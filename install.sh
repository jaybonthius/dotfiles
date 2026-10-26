#!/usr/bin/env bash
# install.sh — Bootstrap a fresh machine with Nix + Home Manager.
#
# Usage:
#   ~/dotfiles/install.sh              # Run all steps
#   ~/dotfiles/install.sh install-nix  # Run a single step
#   ~/dotfiles/install.sh switch       # Apply home-manager config
#   ~/dotfiles/install.sh opener-ssh-forward # Repair stale remote opener sockets
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

    # These macOS tools always follow main; leave other inputs untouched.
    if [ "$config" = "aarch64-darwin" ]; then
        info "Updating scrollkey and meizure from main..."
        nix flake update scrollkey meizure --flake "$DOTFILES_DIR"
    fi

    # --impure allows home.nix to read $USER/$HOME via builtins.getEnv
    if ! command -v home-manager >/dev/null 2>&1; then
        info "Bootstrapping home-manager..."
        nix run --inputs-from "$DOTFILES_DIR" home-manager -- switch --impure --flake "$DOTFILES_DIR#$config"
    else
        home-manager switch --impure --flake "$DOTFILES_DIR#$config"
    fi

    ok "home-manager switch complete"
}

opener_ssh_forward() {
    # Home Manager cannot configure the system SSH server; install its
    # root-owned drop-in explicitly rather than running sudo on every switch.
    [ "$(uname -s)" = "Linux" ] || fail "opener-ssh-forward requires a Linux SSH server"
    local source="$DOTFILES_DIR/config/ssh/sshd_config.d/60-opener-forward.conf"
    local target="/etc/ssh/sshd_config.d/60-opener-forward.conf"
    local installed=false
    local settings

    grep -Fqx 'Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config ||
        fail "sshd does not include /etc/ssh/sshd_config.d/*.conf"
    if sudo test -e "$target" || sudo test -L "$target"; then
        sudo test -f "$target" && ! sudo test -L "$target" && sudo cmp -s "$source" "$target" ||
            fail "Refusing to overwrite existing $target"
    else
        sudo install -D -o root -g root -m 0644 "$source" "$target"
        installed=true
    fi

    if ! sudo /usr/sbin/sshd -t ||
       ! settings="$(sudo /usr/sbin/sshd -T)" ||
       ! grep -Fxq 'streamlocalbindunlink yes' <<< "$settings"; then
        if "$installed"; then sudo rm -- "$target"; fi
        fail "sshd rejected the opener setting (new drop-in removed if installed)"
    fi
    if ! sudo systemctl reload ssh; then
        if "$installed"; then sudo rm -- "$target"; fi
        fail "Could not reload sshd (new drop-in removed if installed)"
    fi
    ok "sshd will replace stale remote opener sockets on new SSH connections"
}

compile_terminfo() {
    info "Compiling custom terminfo entries..."
    local ti_file
    for ti_file in "$DOTFILES_DIR"/config/terminfo/*.ti; do
        if [ -f "$ti_file" ]; then
            tic -x -o "$HOME/.terminfo" "$ti_file"
            ok "Terminfo compiled: $(basename "$ti_file")"
        else
            warn "No terminfo files in $DOTFILES_DIR/config/terminfo"
        fi
    done
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
    echo "     ssh-keygen -t ed25519 -C \"jaybonthius@gmail.com\""
    if [ "$(uname -s)" = "Darwin" ]; then
        echo "     /usr/bin/ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
        echo "     # In ~/.ssh/config, set AddKeysToAgent yes, UseKeychain yes,"
        echo "     # and IdentityFile ~/.ssh/id_ed25519 for Host github.com."
    fi
    echo "     cat ~/.ssh/id_ed25519.pub"
    echo "     # Add to: https://github.com/settings/ssh/new"
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
            opener-ssh-forward) opener_ssh_forward ;;
            compile-terminfo) compile_terminfo ;;
            default-shell)   default_shell ;;
            fish-plugins)    fish_plugins ;;
            notes)           post_setup_notes ;;
            *)               fail "Unknown step: $step" ;;
        esac
    done
fi
