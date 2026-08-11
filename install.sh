#!/usr/bin/env bash
# install.sh — Bootstrap a fresh machine with Nix + Home Manager.
#
# Usage:
#   ~/dotfiles/install.sh              # Run all steps
#   ~/dotfiles/install.sh install-nix  # Run a single step
#   ~/dotfiles/install.sh switch       # Apply home-manager config
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
fail()  { printf '\033[1;31m[fail]\033[0m  %s\n' "$*"; exit 1; }

# ── Steps ─────────────────────────────────────────────────────────────

setup_swap() {
    # Ubuntu EC2/Lima instances often have no swap.  Without swap,
    # memory overcommit causes kernel hard-freezes instead of OOM kills.
    info "Setting up swap..."
    if swapon --show | grep -q .; then
        ok "Swap already configured"
        return
    fi
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    ok "4G swapfile created and enabled"
}

install_nix() {
    info "Installing Nix..."
    if command -v nix >/dev/null 2>&1 || [ -e /nix/var/nix/profiles/default/bin/nix ]; then
        # Source profile so subsequent steps have nix on PATH
        if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
            . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        fi
        ok "Nix already installed: $(nix --version)"
        return
    fi
    curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
    ok "Nix installed. Sourcing daemon profile..."

    # Source nix-daemon for the current shell
    if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
}

enable_flakes() {
    info "Enabling Nix flakes..."
    mkdir -p ~/.config/nix
    if grep -q 'experimental-features' ~/.config/nix/nix.conf 2>/dev/null; then
        ok "Flakes already enabled"
        return
    fi
    echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
    ok "Flakes enabled in ~/.config/nix/nix.conf"
}

switch() {
    info "Running home-manager switch..."

    # Determine config name (matches flake.nix homeConfigurations keys)
    local config
    case "$(uname -s)-$(uname -m)" in
        Linux-aarch64)   config="aarch64-linux" ;;
        Linux-x86_64)    config="x86_64-linux" ;;
        Darwin-arm64)    config="aarch64-darwin" ;;
        *)               fail "Unsupported platform: $(uname -s)-$(uname -m)" ;;
    esac

    info "Using configuration: $config"

    # --impure allows home.nix to read $USER/$HOME via builtins.getEnv
    if ! command -v home-manager >/dev/null 2>&1; then
        info "Bootstrapping home-manager..."
        nix run home-manager/master -- switch --impure --flake "$DOTFILES_DIR#$config"
    else
        home-manager switch --impure --flake "$DOTFILES_DIR#$config"
    fi

    ok "home-manager switch complete"
}

compile_terminfo() {
    info "Compiling custom terminfo entries..."
    local ti_file="$DOTFILES_DIR/config/terminfo/xterm-ghostty.ti"
    if [ -f "$ti_file" ]; then
        tic -x -o "$HOME/.terminfo" "$ti_file"
        ok "Terminfo compiled"
    else
        warn "Terminfo file not found: $ti_file"
    fi
}

default_shell() {
    # home-manager can't set the login shell (needs root), so do it here.
    local fish="$HOME/.nix-profile/bin/fish"
    info "Setting fish as the default shell..."
    grep -qxF "$fish" /etc/shells || echo "$fish" | sudo tee -a /etc/shells >/dev/null
    sudo chsh -s "$fish" "$(id -un)"
    ok "Default shell set to fish (effective next login)"
}

fish_plugins() {
    info "Installing Fish plugins via Fisher..."
    if ! command -v fish >/dev/null 2>&1; then
        warn "Fish not found in PATH — run 'switch' first"
        return
    fi
    fish -c 'fisher update 2>/dev/null; or fisher install (cat ~/.config/fish/fish_plugins)'
    ok "Fish plugins installed"
}

post_setup_notes() {
    info "Post-setup reminders:"
    echo ""
    echo "  0. Remove pre-existing config dirs (first run only):"
    echo "     rm -rf ~/.config/emacs ~/.config/fish ~/.config/zellij"
    echo ""
    echo "  1. SSH key setup:"
    echo "     ssh-keygen -t ed25519 -C \"jaybonthius@gmail.com\" -N \"\""
    echo "     cat ~/.ssh/id_ed25519.pub"
    echo "     # Add to: https://github.com/settings/ssh/new"
    echo ""
    echo "  2. Install Python LSP:"
    if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "aarch64" ]; then
        echo "     uv tool install basedpyright"
    else
        echo "     (skipped: uv is only installed on Linux aarch64)"
    fi
    echo ""
    echo "  3. Start Emacs daemon (first run only):"
    if [ "$(uname -s)" = "Darwin" ]; then
        echo "     # launchd agent is installed — just log out and back in,"
        echo "     # or start it now with:"
        echo "     launchctl load ~/Library/LaunchAgents/org.nix-community.home.emacs-daemon.plist"
    else
        echo "     systemctl --user start emacs-daemon"
    fi
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────

run_all() {
    if [ "$(uname -s)" = "Linux" ]; then
        setup_swap
    fi
    install_nix
    enable_flakes
    switch
    compile_terminfo
    default_shell
    fish_plugins
    post_setup_notes
}

if [ $# -eq 0 ]; then
    run_all
else
    for step in "$@"; do
        case "$step" in
            setup-swap)      setup_swap ;;
            install-nix)     install_nix ;;
            enable-flakes)   enable_flakes ;;
            switch)          switch ;;
            compile-terminfo) compile_terminfo ;;
            default-shell)   default_shell ;;
            fish-plugins)    fish_plugins ;;
            notes)           post_setup_notes ;;
            *)               fail "Unknown step: $step" ;;
        esac
    done
fi
