use std::collections::BTreeMap;
use zellij_tile::prelude::*;

/// Zellij plugin that coordinates a single Emacs daemon across multiple
/// Zellij sessions, each with its own easysession.
///
/// Each Zellij session's layout has a gated while-loop that polls a gate
/// file (`~/.local/state/zellij-emacs-session`) and only launches
/// `emacsclient` when the file contains that session's name.
///
/// On session switch this plugin:
/// 1. Writes "NONE" to the gate file (blocks all loops immediately).
/// 2. Calls `emacsclient --eval '(jb-zellij-save-and-kill-clients)'`
///    to save the current easysession and kill all client frames.
/// 3. Writes the new session name to the gate file so only the target
///    session's loop proceeds.
///
/// Ignores redundant `SessionUpdate` events for the already-active session.
/// Runs as a non-selectable background plugin (no UI).
#[derive(Default)]
struct EmacsSessionSwitcher {
    /// Tracks the last session name we acted on, to avoid redundant
    /// switches when `SessionUpdate` fires without an actual session change.
    current_session: Option<String>,
}

register_plugin!(EmacsSessionSwitcher);

const GATE_FILE: &str = "~/.local/state/zellij-emacs-session";

impl ZellijPlugin for EmacsSessionSwitcher {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::RunCommands,
            PermissionType::ReadApplicationState,
        ]);
        subscribe(&[EventType::SessionUpdate]);
        set_selectable(false);
    }

    fn update(&mut self, event: Event) -> bool {
        if let Event::SessionUpdate(sessions, _resurrectable) = event {
            if let Some(current) = sessions.iter().find(|s| s.is_current_session) {
                let new_name = &current.name;
                let already_active = self
                    .current_session
                    .as_ref()
                    .map_or(false, |old| old == new_name);

                if !already_active {
                    switch_emacs_session(new_name);
                    self.current_session = Some(new_name.clone());
                }
            }
        }
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {}
}

/// Save the current easysession, kill all client frames, then open the
/// gate for the new session.  All steps run sequentially in a single bash
/// invocation to guarantee ordering.
///
/// The command is idempotent: if the gate file already contains the target
/// session name, it exits immediately without killing anything.  This
/// avoids a redundant kill+reconnect cycle when a fresh plugin instance
/// fires for a session that is already active (each Zellij session runs
/// its own plugin instance with independent in-memory state).
fn switch_emacs_session(new_session_name: &str) {
    let new_esc = new_session_name.replace('\'', "'\\''");
    let cmd = format!(
        "current=$(cat {GATE} 2>/dev/null) && \
         [ \"$current\" = '{NAME}' ] && exit 0; \
         mkdir -p ~/.local/state && \
         printf '%s' 'NONE' > {GATE} && \
         emacsclient --eval '(jb-zellij-save-and-kill-clients)' >/dev/null 2>&1 && \
         printf '%s' '{NAME}' > {GATE}",
        GATE = GATE_FILE,
        NAME = new_esc
    );
    run_command(&["bash", "-c", &cmd], BTreeMap::new());
}
