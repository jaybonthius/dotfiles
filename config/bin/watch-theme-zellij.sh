#!/bin/bash
# watch-theme-zellij.sh
# Watches ~/.local/state/theme and updates Zellij's config.kdl theme line.
# Zellij hot-reloads config changes automatically.
#
# If config.kdl is a symlink (e.g. from Nix Home Manager), it is replaced
# with a mutable copy so that sed can edit it in place.

THEME_FILE="$HOME/.local/state/theme"
ZELLIJ_CONFIG="$HOME/.config/zellij/config.kdl"

ensure_mutable_config() {
    if [[ -L "$ZELLIJ_CONFIG" ]]; then
        local target
        target=$(readlink -f "$ZELLIJ_CONFIG")
        rm "$ZELLIJ_CONFIG"
        cp "$target" "$ZELLIJ_CONFIG"
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
        sed -i "s/^theme .*/theme \"$theme\"/" "$ZELLIJ_CONFIG"
    fi
}

# Ensure theme file exists
mkdir -p "$(dirname "$THEME_FILE")"
if [[ ! -f "$THEME_FILE" ]]; then
    echo "dark" > "$THEME_FILE"
fi

# Apply on startup
apply_theme

# Watch for changes
exec inotifywait -m -e close_write --format '%f' "$(dirname "$THEME_FILE")" 2>/dev/null |
while read -r file; do
    if [[ "$file" == "$(basename "$THEME_FILE")" ]]; then
        apply_theme
    fi
done
