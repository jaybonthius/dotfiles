if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Ensure COLORTERM is set for truecolor support in TUI apps (Emacs, etc.)
# Ghostty supports truecolor but the env var gets lost over SSH hops.
if not set -q COLORTERM
    set -gx COLORTERM truecolor
end

# Keep a stable symlink to the current SSH agent socket so that long-running
# processes (e.g. Emacs daemon) can always find the agent.
if test -n "$SSH_AUTH_SOCK"; and test "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock"
    mkdir -p "$HOME/.ssh"
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
end

# Conversely, when a shell starts without SSH_AUTH_SOCK in its environment (e.g.
# the agent wasn't forwarded into it), fall back to that stable symlink if it
# still points at a live socket, so ssh/git can reach the agent.
if test -z "$SSH_AUTH_SOCK"; and test -S "$HOME/.ssh/ssh_auth_sock"
    set -gx SSH_AUTH_SOCK "$HOME/.ssh/ssh_auth_sock"
end

# Herdr uses libghostty-vt but advertises xterm-256color. Emacs 30's
# COLORTERM fallback aliases exact RGB values 0-7 to ANSI palette colors.
# Use Ghostty's installed terminfo entry so truecolor remains explicit RGB.
if set -q HERDR_ENV; and test "$HERDR_ENV" = "1"; and infocmp xterm-ghostty >/dev/null 2>&1
    set -gx TERM xterm-ghostty
else if test "$TERM" = "xterm-color"; and infocmp xterm-ghostty >/dev/null 2>&1
    set -gx TERM xterm-ghostty
end

# Rex terminals carry no SSH variables and may inherit the server's DISPLAY,
# so Pi would copy to the server's X clipboard instead of the viewing client.
# Make Pi also emit OSC 52, which Rex forwards to the client's clipboard.
if test "$TERM_PROGRAM" = "rex"
    set -gx PI_CLIPBOARD_OSC52 1
end

# greeting
function fish_greeting -d "What's up, fish?"
    set_color $fish_color_autosuggestion
    uname -nmsr

    command -q uptime
    and command uptime

    set_color normal
end

# starship
starship init fish | source

# zoxide
zoxide init --cmd cd fish | source

# fzf
set fzf_preview_dir_cmd eza --all --color=always
functions -q fzf_configure_bindings && fzf_configure_bindings --history=\cr --directory=\cf --git_log=\cg --git_status=\cs --processes=\cp
set fzf_preview_file_cmd cat -n

# Homebrew on Apple Silicon; needed before repo scripts try brew fallbacks.
fish_add_path /opt/homebrew/bin

# rustup-managed Rust toolchains.
fish_add_path $HOME/.cargo/bin

# Go environment (GOPATH/GOBIN set via home.sessionVariables in home.nix)
fish_add_path $GOBIN

# User-installed Gerbil applications
fish_add_path $HOME/.gerbil/bin

# User-installed Racket 9.2 applications
fish_add_path $HOME/.local/share/racket/9.2/bin

# npm global bin (agent-browser CLI and other globally-installed npm tools)
fish_add_path $HOME/.npm-global/bin

# Force pi to use zellij as the subagent multiplexer backend
set -gx PI_SUBAGENT_MUX zellij

# Tell subprocesses and agent extensions that the interactive shell is Fish.
set -gx SHELL (which fish)

# Restore pre-4.1-ish Option/Alt word motions/kills (instead of token-level defaults)
function fish_user_key_bindings
    # Delete previous word
    bind alt-backspace backward-kill-word
    bind \e\x7f backward-kill-word
    bind \e\b backward-kill-word

    # Move/delete by word with Alt
    bind alt-left prevd-or-backward-word
    bind alt-right nextd-or-forward-word
    bind alt-delete kill-word

    # Keep Ctrl variants available for token-level operations
    bind ctrl-backspace backward-kill-token
    bind ctrl-delete kill-token

    # Optional in many terminals; harmless if unsupported
    bind ctrl-left backward-word
    bind ctrl-right forward-word
end
