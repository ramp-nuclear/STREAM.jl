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

#![cfg(target_os = "windows")]

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use tauri::{Runtime, WebviewWindow};
use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::Graphics::Gdi::{GetStockObject, HBRUSH, NULL_BRUSH};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::HiDpi::GetDpiForWindow;
use windows_sys::Win32::UI::Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, GetClientRect, RegisterClassExW, SetWindowPos,
    CS_HREDRAW, CS_VREDRAW, HTMAXBUTTON, HWND_TOP, SWP_ASYNCWINDOWPOS, SWP_SHOWWINDOW, WM_CLOSE,
    WM_DPICHANGED, WM_NCHITTEST, WM_SIZE, WNDCLASSEXW, WS_CHILD, WS_CLIPSIBLINGS, WS_VISIBLE,
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

static OVERLAYS: OnceLock<Mutex<HashMap<isize, HWND>>> = OnceLock::new();

pub fn install<R: Runtime>(window: &WebviewWindow<R>) -> Result<(), String> {
    let handle = window.window_handle().map_err(|e| e.to_string())?;
    let RawWindowHandle::Win32(h) = handle.as_raw() else {
        return Ok(()); // non-Win32 — no-op
    };
    let hwnd_isize = h.hwnd.get();
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
    if let Some(old) = g.insert(hwnd as isize, overlay) {
        DestroyWindow(old);
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
    let Some(&overlay) = g.get(&(hwnd as isize)) else {
        return;
    };
    drop(g);
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
            if let Some(overlay) = map.lock().unwrap().remove(&(hwnd as isize)) {
                DestroyWindow(overlay);
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
    if msg == WM_NCHITTEST {
        return HTMAXBUTTON as LRESULT;
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
