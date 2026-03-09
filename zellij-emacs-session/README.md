# zellij-emacs-session

Zellij WASM plugin that coordinates a single Emacs daemon across multiple
Zellij sessions using [easysession](https://github.com/jamescherti/easysession.el).

When you switch Zellij sessions, the plugin saves the current easysession,
kills all emacsclient frames, and opens a gate file so only the target
session's editor pane can reconnect.

## How it works

A single Emacs daemon serves all Zellij sessions.  Each session's layout has
an editor pane running a gated while-loop that polls a **gate file**
(`~/.local/state/zellij-emacs-session`) and only launches `emacsclient` when
the file contains that session's name.

On session switch the plugin runs three steps sequentially in one bash
invocation:

1. **Write `NONE`** to the gate file -- immediately blocks every session's
   while-loop from passing the gate check.
2. **`emacsclient --eval '(jb-zellij-save-and-kill-clients)'`** -- saves the
   current easysession and kills all client frames.
3. **Write the new session name** to the gate file -- only the matching
   session's loop proceeds and launches `emacsclient`.

The new `emacsclient` frame carries a `zellij-session` frame parameter (set
via `-F`).  On connect, `jb-zellij-initial-session-setup` (on
`server-after-make-frame-hook`) reads that parameter and loads / switches to
the corresponding easysession.

### Known limitations

- Each Zellij session runs its own WASM plugin instance with independent
  state.  The plugin deduplicates `SessionUpdate` events using an in-memory
  `current_session` field, but this resets if Zellij restarts the plugin.
  When that happens the plugin runs a redundant save-kill-gate cycle that
  causes a brief emacsclient reconnect flicker but no data loss.
- Inactive sessions' editor panes poll the gate file every 100 ms.  This is
  cheap but not zero-cost.

## Prerequisites

- **Rust toolchain** with the `wasm32-wasip1` target:
  ```sh
  rustup target add wasm32-wasip1
  ```
- **C compiler** (needed by some Rust dependencies):
  ```sh
  # Nix
  nix shell nixpkgs#gcc
  # or ensure gcc is on PATH (installed by home.nix)
  ```

## Building

The default build target is set in `.cargo/config.toml`, so a plain
`cargo build --release` produces the WASM binary:

```sh
cargo build --release
```

The output is at `target/wasm32-wasip1/release/zellij-emacs-session.wasm`.

## Updating the committed binary

After rebuilding, copy the new binary to the project root so it is tracked
by git and referenced by `home.nix`:

```sh
cp target/wasm32-wasip1/release/zellij-emacs-session.wasm .
```

## Deploying

Run Home Manager to symlink the plugin into the Zellij config directory:

```sh
home-manager switch --impure --flake ~/dotfiles
```

Then kill and restart your Zellij sessions so the updated plugin loads.
You may also need to clear the Zellij plugin cache if it serves a stale
copy:

```sh
rm -rf ~/.cache/zellij/
```
