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
        .invoke_handler(tauri::generate_handler![greet, is_pid_alive, get_pid])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
