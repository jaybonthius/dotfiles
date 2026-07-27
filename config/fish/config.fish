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

# Ensure TERM uses the xterm-ghostty terminfo entry when it gets stripped to the
# generic xterm-color (e.g. Lima's sshd doesn't AcceptEnv TERM by default).
# Only activates when the compiled entry actually exists.
if test "$TERM" = "xterm-color" && infocmp xterm-ghostty >/dev/null 2>&1
    set -gx TERM xterm-ghostty
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

# Go environment (GOPATH/GOBIN set via home.sessionVariables in home.nix)
fish_add_path $GOBIN

# npm global bin (agent-browser CLI and other globally-installed npm tools)
fish_add_path $HOME/.npm-global/bin

# Force pi to use zellij as the subagent multiplexer backend
set -gx PI_SUBAGENT_MUX zellij

# Tell subagent extension we're fish (SHELL may say /bin/bash due to tmux default-shell)
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
