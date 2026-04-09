use std::collections::BTreeMap;
use std::path::PathBuf;
use zellij_tile::prelude::*;

/// A session switcher that remembers focused location per session.
///
/// We persist:
/// - focused tab position
/// - focused pane id (when available)
///
/// On switch we:
///   1. Save current focus for current session
///   2. Load saved focus for target session
///   3. Switch sessions and restore focus
const STATE_SUBDIR: &str = "zellij-tab-state";
const EMERGENCY_STATE_DIR: &str = "/tmp/zellij-tab-state";

#[derive(Debug, Clone, Copy)]
struct SavedFocus {
    tab_position: usize,
    pane_id: Option<(u32, bool)>, // (id, is_plugin)
}

struct SwitchRequest {
    target_session: String,
    cwd: Option<PathBuf>,
    layout: Option<String>,
    target_exists: Option<bool>,
    state_dir: Option<String>,
}

#[derive(Default)]
struct State {
    session_name: Option<String>,
    active_tab_position: Option<usize>,
    pending_switch: Option<SwitchRequest>,
}

register_plugin!(State);

fn pane_id_to_tuple(pane_id: PaneId) -> (u32, bool) {
    match pane_id {
        PaneId::Terminal(id) => (id, false),
        PaneId::Plugin(id) => (id, true),
    }
}

fn parse_pane_token(token: &str) -> Option<(u32, bool)> {
    if let Some(id) = token.strip_prefix("terminal:") {
        return id.parse::<u32>().ok().map(|pane_id| (pane_id, false));
    }

    if let Some(id) = token.strip_prefix("plugin:") {
        return id.parse::<u32>().ok().map(|pane_id| (pane_id, true));
    }

    None
}

fn parse_bool(value: &str) -> Option<bool> {
    match value {
        "1" | "true" | "True" | "TRUE" => Some(true),
        "0" | "false" | "False" | "FALSE" => Some(false),
        _ => None,
    }
}

fn default_state_dir() -> String {
    let env = get_session_environment_variables();

    if let Some(state_dir) = env
        .get("ZELLIJ_SESSIONIZER_STATE_DIR")
        .map(String::as_str)
        .filter(|v| !v.trim().is_empty())
    {
        return state_dir.to_string();
    }

    if let Some(xdg_state_home) = env
        .get("XDG_STATE_HOME")
        .map(String::as_str)
        .filter(|v| !v.trim().is_empty())
    {
        return format!("{}/{}", xdg_state_home.trim_end_matches('/'), STATE_SUBDIR);
    }

    if let Some(home) = env
        .get("HOME")
        .map(String::as_str)
        .filter(|v| !v.trim().is_empty())
    {
        return format!(
            "{}/.local/state/{}",
            home.trim_end_matches('/'),
            STATE_SUBDIR
        );
    }

    EMERGENCY_STATE_DIR.to_string()
}

fn save_focus_state(state_dir: &str, session: &str, focus: SavedFocus) {
    let _ = std::fs::create_dir_all(state_dir);

    let path = format!("{}/{}", state_dir, session);
    let mut content = format!("tab={}\n", focus.tab_position);

    if let Some((pane_id, is_plugin)) = focus.pane_id {
        let pane_kind = if is_plugin { "plugin" } else { "terminal" };
        content.push_str(&format!("pane={}:{}\n", pane_kind, pane_id));
    }

    let _ = std::fs::write(&path, content);
}

fn load_focus_state(state_dir: &str, session_name: &str) -> Option<SavedFocus> {
    let path = format!("{}/{}", state_dir, session_name);
    let content = std::fs::read_to_string(&path).ok()?;

    let mut tab_position: Option<usize> = None;
    let mut pane_id: Option<(u32, bool)> = None;

    for line in content.lines() {
        let Some((raw_key, raw_value)) = line.split_once('=') else {
            continue;
        };
        let key = raw_key.trim();
        let value = raw_value.trim();

        match key {
            "tab" => {
                tab_position = value.parse::<usize>().ok();
            }
            "pane" => {
                pane_id = parse_pane_token(value);
            }
            _ => {}
        }
    }

    tab_position.map(|tab_position| SavedFocus {
        tab_position,
        pane_id,
    })
}

/// Parse key/value payloads like:
///   session=my-session
///   cwd=/home/user/my project
///   layout=project
///   exists=1
///   state_dir=/home/user/.local/state/zellij-tab-state
fn parse_pipe_payload(
    payload: &str,
) -> (
    Option<String>,
    Option<PathBuf>,
    Option<String>,
    Option<bool>,
    Option<String>,
) {
    let mut session: Option<String> = None;
    let mut cwd: Option<PathBuf> = None;
    let mut layout: Option<String> = None;
    let mut target_exists: Option<bool> = None;
    let mut state_dir: Option<String> = None;

    for line in payload.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let value = value.trim();

        match key.trim() {
            "session" => {
                if !value.is_empty() {
                    session = Some(value.to_string());
                }
            }
            "cwd" => {
                if !value.is_empty() {
                    cwd = Some(PathBuf::from(value));
                }
            }
            "layout" => {
                if !value.is_empty() {
                    layout = Some(value.to_string());
                }
            }
            "exists" => {
                target_exists = parse_bool(value);
            }
            "state_dir" => {
                if !value.is_empty() {
                    state_dir = Some(value.to_string());
                }
            }
            _ => {}
        }
    }

    (session, cwd, layout, target_exists, state_dir)
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

        let SwitchRequest {
            target_session,
            cwd,
            layout,
            target_exists,
            state_dir,
        } = request;

        let state_dir = state_dir.unwrap_or_else(default_state_dir);

        // Save current session focus before leaving.
        if let Some(ref current_session) = self.session_name {
            let pane_focus = get_focused_pane_info()
                .ok()
                .map(|(tab_position, pane_id)| (tab_position, pane_id_to_tuple(pane_id)));

            let tab_position = self
                .active_tab_position
                .or_else(|| pane_focus.map(|(tab_position, _)| tab_position));

            let pane_id = pane_focus.map(|(_, pane_tuple)| pane_tuple);

            if let Some(tab_position) = tab_position {
                save_focus_state(
                    &state_dir,
                    current_session,
                    SavedFocus {
                        tab_position,
                        pane_id,
                    },
                );
            }
        }

        let saved_focus = load_focus_state(&state_dir, &target_session);

        // Prefer explicit existence info from caller.
        // Fallback to prior behavior when caller omitted it.
        let target_exists = target_exists.unwrap_or(saved_focus.is_some());

        if target_exists {
            // Existing session — restore pane when known (falls back to tab otherwise).
            let tab_position = saved_focus.as_ref().map(|focus| focus.tab_position);
            let pane_id = saved_focus.and_then(|focus| focus.pane_id);
            switch_session_with_focus(&target_session, tab_position, pane_id);
        } else if let Some(layout_name) = layout {
            let layout_info =
                LayoutInfo::File(format!("{}.kdl", layout_name), LayoutMetadata::default());
            switch_session_with_layout(Some(&target_session), layout_info, cwd);
        } else if cwd.is_some() {
            switch_session_with_cwd(Some(&target_session), cwd);
        } else {
            switch_session_with_focus(&target_session, None, None);
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
            Some(payload) => payload,
            None => return false,
        };

        let (session, cwd, layout, target_exists, state_dir) = parse_pipe_payload(&payload);

        let target_session = match session {
            Some(session) => session,
            None => return false,
        };

        self.pending_switch = Some(SwitchRequest {
            target_session,
            cwd,
            layout,
            target_exists,
            state_dir,
        });

        self.try_switch();
        true
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // Invisible plugin — no UI needed
    }
}
