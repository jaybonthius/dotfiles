#!/bin/bash
# watch-theme.sh
# Watches ~/.local/state/theme and updates application themes.
# Currently handles: Zellij (config rewrite) and tmux (source-file).
#
# Cross-platform: uses inotifywait on Linux, fswatch on macOS.
#
# Also watches the Zellij config directory so that if home-manager (or
# anything else) overwrites config.kdl, the correct theme is re-applied.
#
# If config.kdl is a symlink (e.g. from Nix Home Manager), it is replaced
# with a mutable copy so that sed can edit it in place.

THEME_FILE="$HOME/.local/state/theme"
ZELLIJ_CONFIG="$HOME/.config/zellij/config.kdl"
TMUX_THEMES="$HOME/.config/tmux/themes"

THEME_DIR="$(dirname "$THEME_FILE")"
ZELLIJ_DIR="$(dirname "$ZELLIJ_CONFIG")"
THEME_BASE="$(basename "$THEME_FILE")"
ZELLIJ_BASE="$(basename "$ZELLIJ_CONFIG")"

ensure_mutable_config() {
    if [[ -L "$ZELLIJ_CONFIG" ]]; then
        # Replace symlink with a mutable copy of the target
        local target
        target=$(realpath "$ZELLIJ_CONFIG")
        rm "$ZELLIJ_CONFIG"
        cp "$target" "$ZELLIJ_CONFIG"
        chmod u+w "$ZELLIJ_CONFIG"
    elif [[ -f "$ZELLIJ_CONFIG" ]] && [[ ! -w "$ZELLIJ_CONFIG" ]]; then
        # File exists but is read-only (e.g. Nix Home Manager copied it)
        chmod u+w "$ZELLIJ_CONFIG"
    fi
}

apply_zellij_theme() {
    local mode="$1"
    local theme
    case "$mode" in
        light) theme="modus_operandi_Tinted" ;;
        *)     theme="modus_vivendi_Tinted" ;;
    esac
    if [[ -f "$ZELLIJ_CONFIG" ]] || [[ -L "$ZELLIJ_CONFIG" ]]; then
        ensure_mutable_config
        sed -i "s/^theme .*/theme \"$theme\"/" "$ZELLIJ_CONFIG"
    fi
}

apply_tmux_theme() {
    local mode="$1"
    local variant
    case "$mode" in
        light) variant="operandi" ;;
        *)     variant="vivendi" ;;
    esac
    local theme_file="$TMUX_THEMES/modus_${variant}_tinted.tmux"
    # Only source if tmux server is running and theme file exists
    if [[ -f "$theme_file" ]] && tmux list-sessions &>/dev/null; then
        tmux source-file "$theme_file"
    fi
}

apply_all() {
    local mode
    mode=$(tr -d '[:space:]' < "$THEME_FILE" 2>/dev/null)
    apply_zellij_theme "$mode"
    apply_tmux_theme "$mode"
}

# Ensure theme file exists
mkdir -p "$THEME_DIR"
if [[ ! -f "$THEME_FILE" ]]; then
    echo "dark" > "$THEME_FILE"
fi

# Apply on startup
apply_all

# Watch for changes (platform-specific)
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: watch both the theme state directory and the zellij config
    # directory. This catches theme toggles AND config.kdl being overwritten
    # by home-manager switch. Watching directories (not files) is required
    # because atomic file replacements create new inodes.
    fswatch -0 "$THEME_DIR" "$ZELLIJ_DIR" | while read -d '' changed; do
        base="$(basename "$changed")"
        if [[ "$base" == "$THEME_BASE" || "$base" == "$ZELLIJ_BASE" ]]; then
            apply_all
        fi
    done
else
    # Linux: use inotifywait on both directories
    exec inotifywait -m -e close_write --format '%w%f' "$THEME_DIR" "$ZELLIJ_DIR" 2>/dev/null |
    while read -r path; do
        base="$(basename "$path")"
        if [[ "$base" == "$THEME_BASE" || "$base" == "$ZELLIJ_BASE" ]]; then
            apply_all
        fi
    done
fi
