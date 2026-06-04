mod snap_layout;

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[tauri::command]
fn is_pid_alive(pid: u32) -> bool {
    use sysinfo::{System, Pid};
    let mut sys = System::new();
    sys.refresh_processes();
    sys.process(Pid::from_u32(pid)).is_some()
}

#[tauri::command]
fn get_pid() -> u32 {
    std::process::id()
}

// Reveal a file in the OS file manager. On WSL2 specifically — where Tauri's
// stock `revealItemInDir` fails because there's no dbus FileManager1 service
// and `xdg-open` has no GUI handler unless `wslu` is installed — translate
// the Linux path to a `\\wsl.localhost\…` UNC path via `wslpath -w` and hand
// it to `explorer.exe /select,<winpath>`. On non-WSL Linux (and on macOS /
// Windows native), this command returns an error so the JS caller can fall
// back to the regular plugin path.
//
// Detection: `/proc/version` contains "microsoft" on every WSL kernel build.
#[tauri::command]
fn reveal_in_wsl_explorer(path: String) -> Result<(), String> {
    use std::process::Command;

    let is_wsl = std::fs::read_to_string("/proc/version")
        .map(|v| v.to_lowercase().contains("microsoft"))
        .unwrap_or(false);

    if !is_wsl {
        return Err("not running under WSL — caller should use the standard reveal path".into());
    }

    let win_out = Command::new("wslpath")
        .args(["-w", &path])
        .output()
        .map_err(|e| format!("wslpath spawn failed: {e}"))?;
    if !win_out.status.success() {
        return Err(format!(
            "wslpath exited {}: {}",
            win_out.status,
            String::from_utf8_lossy(&win_out.stderr).trim()
        ));
    }
    let win_path = String::from_utf8_lossy(&win_out.stdout).trim().to_string();
    if win_path.is_empty() {
        return Err("wslpath returned empty string".into());
    }

    // explorer.exe expects `/select,` and the Windows path joined as one arg.
    let select_arg = format!("/select,{win_path}");
    Command::new("explorer.exe")
        .arg(select_arg)
        .spawn()
        .map_err(|e| format!("explorer.exe spawn failed: {e}"))?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_os::init())
        .setup(|app| {
            // Win11 Snap Layout overlay — see src/snap_layout.rs.
            // Module is target_os = "windows" gated; no-ops on other platforms.
            #[cfg(target_os = "windows")]
            {
                use tauri::Manager;
                if let Some(main) = app.get_webview_window("main") {
                    if let Err(e) = snap_layout::install(&main) {
                        eprintln!("snap_layout: install failed: {e}");
                    }
                }
            }
            #[cfg(not(target_os = "windows"))]
            {
                let _ = app; // unused on non-Windows
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            greet,
            is_pid_alive,
            get_pid,
            reveal_in_wsl_explorer
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
