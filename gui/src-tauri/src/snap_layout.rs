//! Windows 11 Snap Layout overlay HWND.
//!
//! Creates a transparent child window over the maximize-button region of a
//! borderless Tauri webview. The child's WM_NCHITTEST handler returns
//! HTMAXBUTTON, which the Win11 shell uses as the trigger to display the
//! Snap Layout flyout on hover.
//!
//! Vendored from the §10 "write our own" sketch in
//! `.planning/phases/67-custom-titlebar/67-AUDIT-tauri-plugin-frame.md`
//! after the user opted to vendor rather than depend on a 1-day-old
//! upstream plugin (`clarifei/tauri-plugin-frame`). Mechanism is
//! identical to the audited plugin: HTMAXBUTTON overlay HWND, no Win+Z
//! key simulation.
//!
//! Phase 67 round 2 — hover bridge: the overlay HWND eats the React
//! Maximize button's `:hover`, so we re-emit hover-enter / hover-leave
//! as Tauri global events that the React component subscribes to and
//! mirrors as a synthetic `is-hovered` class.

#![cfg(target_os = "windows")]

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use tauri::{Emitter, Manager, Runtime, WebviewWindow};
use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::Graphics::Gdi::{GetStockObject, HBRUSH, NULL_BRUSH};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::HiDpi::GetDpiForWindow;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    TrackMouseEvent, TME_LEAVE, TME_NONCLIENT, TRACKMOUSEEVENT,
};
use windows_sys::Win32::UI::Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, GetClientRect, RegisterClassExW, SetWindowPos,
    CS_HREDRAW, CS_VREDRAW, HTMAXBUTTON, HWND_TOP, SWP_ASYNCWINDOWPOS, SWP_SHOWWINDOW, WM_CLOSE,
    WM_DPICHANGED, WM_NCHITTEST, WM_NCLBUTTONUP, WM_NCMOUSELEAVE, WM_NCMOUSEMOVE, WM_SIZE,
    WNDCLASSEXW, WS_CHILD, WS_CLIPSIBLINGS, WS_VISIBLE,
};

const CLASS_NAME: &[u16] = &[
    b'S' as u16,
    b'T' as u16,
    b'R' as u16,
    b'E' as u16,
    b'A' as u16,
    b'M' as u16,
    b'S' as u16,
    b'n' as u16,
    b'a' as u16,
    b'p' as u16,
    0,
];
const SUBCLASS_ID: usize = 0x53_54_52_4d; // 'STRM'
const TITLEBAR_PX: u32 = 36;
const BUTTON_PX: u32 = 46;
const RIGHT_INDEX: i32 = 1; // maximize button is 2nd from the right (Close=0, Max=1, Min=2)

// Tauri event names — kebab namespaced. Matches D-style used elsewhere in
// the codebase (e.g. `snap-layout://hover-enter`).
const EVT_HOVER_ENTER: &str = "snap-layout://hover-enter";
const EVT_HOVER_LEAVE: &str = "snap-layout://hover-leave";
// Emitted on WM_NCLBUTTONUP — clicks on the overlay never reach the React
// Maximize button because Windows routes them as non-client clicks to the
// overlay HWND (HTMAXBUTTON area). React subscribes and calls toggleMaximize.
const EVT_CLICK: &str = "snap-layout://click";

// HWND is `*mut c_void`, which is not Send/Sync — but storing the handle in a
// `static` requires Sync. The portable workaround is to keep handles as `isize`
// (their representation as integers) and cast back to HWND at use sites.
// Round-tripping `*mut c_void` ↔ `isize` is safe on Windows for both 32- and
// 64-bit targets (pointer width matches isize on all `cfg(windows)` targets).
static OVERLAYS: OnceLock<Mutex<HashMap<isize, isize>>> = OnceLock::new();

// Per-overlay hover state. WM_MOUSEMOVE fires continuously while the cursor
// is over the window; we only want to emit hover-enter once per visit, so we
// track the boolean here and only emit on the rising edge. WM_MOUSELEAVE
// resets the flag.
static HOVERED: OnceLock<Mutex<HashMap<isize, bool>>> = OnceLock::new();

// Boxed Tauri event emitter — set once in `install()` and read from
// `overlay_proc`. Storing a `Box<dyn Fn>` rather than `AppHandle<R>` lets us
// avoid threading the Runtime generic through static storage.
type Emit = Box<dyn Fn(&str) + Send + Sync>;
static EMITTER: OnceLock<Emit> = OnceLock::new();

pub fn install<R: Runtime>(window: &WebviewWindow<R>) -> Result<(), String> {
    let handle = window.window_handle().map_err(|e| e.to_string())?;
    let RawWindowHandle::Win32(h) = handle.as_raw() else {
        return Ok(()); // non-Win32 — no-op
    };
    let hwnd_isize = h.hwnd.get();

    // Capture an AppHandle clone so the overlay WndProc can emit events
    // without holding a borrow of `window`. `get_or_init` is idempotent —
    // multiple `install()` calls (e.g. plugin re-init) are safe.
    let app = window.app_handle().clone();
    EMITTER.get_or_init(|| {
        Box::new(move |evt: &str| {
            let _ = app.emit(evt, ());
        })
    });

    window
        .run_on_main_thread(move || unsafe {
            install_native(hwnd_isize as HWND);
        })
        .map_err(|e| e.to_string())?;
    Ok(())
}

unsafe fn install_native(hwnd: HWND) {
    register_class_once();
    let overlay = CreateWindowExW(
        0,
        CLASS_NAME.as_ptr(),
        CLASS_NAME.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        0,
        0,
        0,
        0,
        hwnd,
        std::ptr::null_mut(),
        GetModuleHandleW(std::ptr::null()),
        std::ptr::null_mut(),
    );
    if overlay.is_null() {
        return;
    }
    let map = OVERLAYS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut g = map.lock().unwrap();
    if let Some(old) = g.insert(hwnd as isize, overlay as isize) {
        DestroyWindow(old as HWND);
    }
    drop(g);
    SetWindowSubclass(hwnd, Some(parent_proc), SUBCLASS_ID, 0);
    reposition(hwnd);
}

unsafe fn register_class_once() {
    static REGISTERED: OnceLock<()> = OnceLock::new();
    REGISTERED.get_or_init(|| {
        let class = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            style: CS_HREDRAW | CS_VREDRAW,
            lpfnWndProc: Some(overlay_proc),
            cbClsExtra: 0,
            cbWndExtra: 0,
            hInstance: GetModuleHandleW(std::ptr::null()),
            hIcon: std::ptr::null_mut(),
            hCursor: std::ptr::null_mut(),
            hbrBackground: GetStockObject(NULL_BRUSH as i32) as HBRUSH,
            lpszMenuName: std::ptr::null(),
            lpszClassName: CLASS_NAME.as_ptr(),
            hIconSm: std::ptr::null_mut(),
        };
        RegisterClassExW(&class);
    });
}

unsafe fn reposition(hwnd: HWND) {
    let map = OVERLAYS.get_or_init(|| Mutex::new(HashMap::new()));
    let g = map.lock().unwrap();
    let Some(&overlay_isize) = g.get(&(hwnd as isize)) else {
        return;
    };
    drop(g);
    let overlay = overlay_isize as HWND;
    let mut rect = std::mem::zeroed();
    if GetClientRect(hwnd, &mut rect) == 0 {
        return;
    }
    let dpi = GetDpiForWindow(hwnd) as i32;
    let (x, y, w, h) = compute_overlay_rect(rect.right, dpi);
    SetWindowPos(
        overlay,
        HWND_TOP,
        x,
        y,
        w,
        h,
        SWP_ASYNCWINDOWPOS | SWP_SHOWWINDOW,
    );
}

/// Compute the overlay rectangle (x, y, width, height) in client-space pixels.
/// Pure function — unit-testable without any Win32 / DPI scaling.
fn compute_overlay_rect(client_right: i32, dpi: i32) -> (i32, i32, i32, i32) {
    let bw = (BUTTON_PX as i32 * dpi + 48) / 96;
    let th = (TITLEBAR_PX as i32 * dpi + 48) / 96;
    let x = client_right - bw * (RIGHT_INDEX + 1);
    (x, 0, bw, th)
}

unsafe extern "system" fn parent_proc(
    hwnd: HWND,
    msg: u32,
    wp: WPARAM,
    lp: LPARAM,
    _id: usize,
    _data: usize,
) -> LRESULT {
    match msg {
        WM_SIZE | WM_DPICHANGED => reposition(hwnd),
        WM_CLOSE => {
            RemoveWindowSubclass(hwnd, Some(parent_proc), SUBCLASS_ID);
            let map = OVERLAYS.get_or_init(|| Mutex::new(HashMap::new()));
            if let Some(overlay_isize) = map.lock().unwrap().remove(&(hwnd as isize)) {
                DestroyWindow(overlay_isize as HWND);
            }
        }
        _ => {}
    }
    DefSubclassProc(hwnd, msg, wp, lp)
}

unsafe extern "system" fn overlay_proc(
    hwnd: HWND,
    msg: u32,
    wp: WPARAM,
    lp: LPARAM,
) -> LRESULT {
    match msg {
        WM_NCHITTEST => return HTMAXBUTTON as LRESULT,
        // Because WM_NCHITTEST returns HTMAXBUTTON, Windows treats this area
        // as the non-client maximize button. Mouse events arrive as the NC
        // variants — WM_NCMOUSEMOVE / WM_NCMOUSELEAVE — not the regular ones.
        // TrackMouseEvent must be armed with TME_NONCLIENT | TME_LEAVE to
        // receive the NC leave notification.
        WM_NCMOUSEMOVE => {
            // Rising-edge detection — only emit hover-enter once per visit.
            // Subsequent WM_NCMOUSEMOVEs while still hovered are no-ops. We
            // also (re-)arm TrackMouseEvent so WM_NCMOUSELEAVE will be sent
            // when the cursor exits the overlay.
            let map = HOVERED.get_or_init(|| Mutex::new(HashMap::new()));
            let mut g = map.lock().unwrap();
            let was = g.get(&(hwnd as isize)).copied().unwrap_or(false);
            if !was {
                g.insert(hwnd as isize, true);
                drop(g);
                let mut tme = TRACKMOUSEEVENT {
                    cbSize: std::mem::size_of::<TRACKMOUSEEVENT>() as u32,
                    dwFlags: TME_LEAVE | TME_NONCLIENT,
                    hwndTrack: hwnd,
                    dwHoverTime: 0,
                };
                TrackMouseEvent(&mut tme);
                if let Some(emit) = EMITTER.get() {
                    emit(EVT_HOVER_ENTER);
                }
            }
        }
        WM_NCMOUSELEAVE => {
            let map = HOVERED.get_or_init(|| Mutex::new(HashMap::new()));
            let mut g = map.lock().unwrap();
            g.insert(hwnd as isize, false);
            drop(g);
            if let Some(emit) = EMITTER.get() {
                emit(EVT_HOVER_LEAVE);
            }
        }
        // Clicks on the overlay arrive as WM_NCLBUTTONUP because the
        // WM_NCHITTEST return value (HTMAXBUTTON) put the entire overlay
        // area into the non-client space. The overlay's DefWindowProcW
        // would react to this by trying to system-maximize itself — a
        // child window — which is a no-op. Emit our event and return 0
        // (consumed); React's onClick handler on the Maximize button
        // listens and calls getCurrentWindow().toggleMaximize() on the
        // parent webview.
        WM_NCLBUTTONUP => {
            if let Some(emit) = EMITTER.get() {
                emit(EVT_CLICK);
            }
            return 0;
        }
        _ => {}
    }
    DefWindowProcW(hwnd, msg, wp, lp)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlay_rect_96dpi() {
        // At 96 dpi, button=46px, titlebar=36px, anchored to right with RIGHT_INDEX=1.
        // Client right=1000 → overlay x = 1000 - 46*2 = 908.
        let (x, y, w, h) = compute_overlay_rect(1000, 96);
        assert_eq!((x, y, w, h), (908, 0, 46, 36));
    }

    #[test]
    fn overlay_rect_192dpi() {
        // At 192 dpi (200% scaling), button=92px, titlebar=72px.
        // Client right=2000 → overlay x = 2000 - 92*2 = 1816.
        let (x, y, w, h) = compute_overlay_rect(2000, 192);
        assert_eq!((x, y, w, h), (1816, 0, 92, 72));
    }

    #[test]
    fn overlay_rect_150dpi_rounds() {
        // At 150 dpi (156.25% scaling), button = (46*150 + 48)/96 = 6948/96 = 72 (truncated).
        let (_, _, w, h) = compute_overlay_rect(1500, 150);
        assert_eq!(w, 72);
        assert_eq!(h, (36 * 150 + 48) / 96);
    }
}
