use std::collections::BTreeMap;
use std::path::PathBuf;
use zellij_tile::prelude::*;

/// A session switcher that remembers which tab was focused per session.
///
/// When a pipe message asks us to switch sessions, we:
///   1. Save the current tab position (tracked via TabUpdate) to a state file
///   2. Load the saved tab for the target session
///   3. Call switch_session_with_focus to restore the right tab
///
/// State is persisted to /tmp/zellij-tab-state/<session_name>.
///
/// Since pipe() may fire before ModeUpdate/TabUpdate deliver session state,
/// we use a deferred switch: stash the request and execute once both the
/// session name and active tab position are known.

const STATE_DIR: &str = "/tmp/zellij-tab-state";

struct SwitchRequest {
    target_session: String,
    cwd: Option<PathBuf>,
    layout: Option<String>,
}

#[derive(Default)]
struct State {
    session_name: Option<String>,
    active_tab_position: Option<usize>,
    pending_switch: Option<SwitchRequest>,
}

register_plugin!(State);

fn save_tab_state(session: &str, tab_position: usize) {
    let _ = std::fs::create_dir_all(STATE_DIR);
    let path = format!("{}/{}", STATE_DIR, session);
    let _ = std::fs::write(&path, tab_position.to_string());
}

fn load_tab_state(session_name: &str) -> Option<usize> {
    let path = format!("{}/{}", STATE_DIR, session_name);
    std::fs::read_to_string(&path).ok()?.trim().parse().ok()
}

/// Parse a pipe payload like "--session my-project --cwd /home/user/project --layout default"
fn parse_pipe_payload(payload: &str) -> (Option<String>, Option<PathBuf>, Option<String>) {
    let mut session: Option<String> = None;
    let mut cwd: Option<PathBuf> = None;
    let mut layout: Option<String> = None;

    let parts: Vec<&str> = payload.split_whitespace().collect();
    let mut i = 0;
    while i < parts.len() {
        match parts[i] {
            "-s" | "--session" => {
                if i + 1 < parts.len() {
                    i += 1;
                    session = Some(parts[i].to_string());
                }
            }
            "-c" | "--cwd" => {
                if i + 1 < parts.len() {
                    i += 1;
                    cwd = Some(PathBuf::from(parts[i]));
                }
            }
            "-l" | "--layout" => {
                if i + 1 < parts.len() {
                    i += 1;
                    layout = Some(parts[i].to_string());
                }
            }
            _ => {}
        }
        i += 1;
    }

    (session, cwd, layout)
}

impl State {
    fn ready_to_switch(&self) -> bool {
        self.pending_switch.is_some()
            && self.session_name.is_some()
            && self.active_tab_position.is_some()
    }

    fn try_switch(&mut self) {
        if !self.ready_to_switch() {
            return;
        }

        let request = match self.pending_switch.take() {
            Some(r) => r,
            None => return,
        };

        // Save current session's focused tab before leaving
        if let (Some(ref current_session), Some(tab_pos)) =
            (&self.session_name, self.active_tab_position)
        {
            save_tab_state(current_session, tab_pos);
        }

        // Load saved tab for target session
        let saved_tab = load_tab_state(&request.target_session);

        if let Some(tab_position) = saved_tab {
            // Switch with focus restoration
            switch_session_with_focus(&request.target_session, Some(tab_position), None);
        } else if request.layout.is_some() || request.cwd.is_some() {
            // New session — use layout/cwd if provided
            let layout_info = request
                .layout
                .map(|l| LayoutInfo::File(format!("{}.kdl", l)))
                .unwrap_or_else(|| LayoutInfo::File("default".to_string()));
            switch_session_with_layout(Some(&request.target_session), layout_info, request.cwd);
        } else {
            // Just switch, no saved tab, no layout
            switch_session_with_focus(&request.target_session, None, None);
        }

        close_self();
    }
}

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[EventType::ModeUpdate, EventType::TabUpdate]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::ModeUpdate(mode_info) => {
                self.session_name = mode_info.session_name;
                self.try_switch();
                false
            }
            Event::TabUpdate(tabs) => {
                if let Some(active) = tabs.iter().find(|t| t.active) {
                    self.active_tab_position = Some(active.position);
                }
                self.try_switch();
                false
            }
            _ => false,
        }
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        let payload = match pipe_message.payload {
            Some(p) => p,
            None => return false,
        };

        let (session, cwd, layout) = parse_pipe_payload(&payload);

        let target_session = match session {
            Some(s) => s,
            None => return false,
        };

        self.pending_switch = Some(SwitchRequest {
            target_session,
            cwd,
            layout,
        });

        // If we already have all state, switch immediately.
        // Otherwise, wait for ModeUpdate/TabUpdate to deliver it.
        self.try_switch();

        true
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // Invisible plugin — no UI needed
    }
}
