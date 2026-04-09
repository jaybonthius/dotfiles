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

# Force pi to use zellij as the subagent multiplexer backend
set -gx PI_SUBAGENT_MUX zellij

# Tell subagent extension we're fish (SHELL may say /bin/bash due to tmux default-shell)
set -gx SHELL (which fish)
