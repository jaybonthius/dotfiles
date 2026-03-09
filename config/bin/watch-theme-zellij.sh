#!/bin/bash
# watch-theme-zellij.sh
# Watches ~/.local/state/theme and updates Zellij's config.kdl theme line.
# Zellij hot-reloads config changes automatically.
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

apply_theme() {
    local mode
    mode=$(tr -d '[:space:]' < "$THEME_FILE" 2>/dev/null)
    local theme
    case "$mode" in
        light) theme="modus_operandi_Tinted" ;;
        *)     theme="modus_vivendi_Tinted" ;;
    esac
    if [[ -f "$ZELLIJ_CONFIG" ]] || [[ -L "$ZELLIJ_CONFIG" ]]; then
        ensure_mutable_config
        # Use sed -i (GNU) syntax unconditionally. The launchd agent on macOS
        # has GNU sed from Nix in PATH, so BSD sed -i '' would break.
        # GNU sed -i without a suffix argument works on both platforms when
        # GNU sed is available (guaranteed here via Nix PATH on both OS).
        sed -i "s/^theme .*/theme \"$theme\"/" "$ZELLIJ_CONFIG"
    fi
}

# Ensure theme file exists
mkdir -p "$THEME_DIR"
if [[ ! -f "$THEME_FILE" ]]; then
    echo "dark" > "$THEME_FILE"
fi

# Apply on startup
apply_theme

# Watch for changes (platform-specific)
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: watch both the theme state directory and the zellij config
    # directory. This catches theme toggles AND config.kdl being overwritten
    # by home-manager switch. Watching directories (not files) is required
    # because atomic file replacements create new inodes.
    fswatch -0 "$THEME_DIR" "$ZELLIJ_DIR" | while read -d '' changed; do
        base="$(basename "$changed")"
        if [[ "$base" == "$THEME_BASE" || "$base" == "$ZELLIJ_BASE" ]]; then
            apply_theme
        fi
    done
else
    # Linux: use inotifywait on both directories
    exec inotifywait -m -e close_write --format '%w%f' "$THEME_DIR" "$ZELLIJ_DIR" 2>/dev/null |
    while read -r path; do
        base="$(basename "$path")"
        if [[ "$base" == "$THEME_BASE" || "$base" == "$ZELLIJ_BASE" ]]; then
            apply_theme
        fi
    done
fi
