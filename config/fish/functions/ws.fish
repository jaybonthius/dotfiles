function ws -d "Open or switch a zellij project session"
    set -l fresh_flag
    set -l args $argv

    if test (count $args) -ge 1
        switch $args[1]
            case --fresh -f
                set fresh_flag --fresh
                set -e args[1]
        end
    end

    if test (count $args) -lt 1
        echo "Usage: ws [--fresh] <directory> [session-name]"
        return 1
    end

    set -l dir (realpath $args[1])
    if not test -d $dir
        echo "ws: not a directory: $dir"
        return 1
    end

    set -l name (test (count $args) -ge 2; and echo $args[2]; or basename $dir)

    if not command -v zellij-session-open >/dev/null 2>&1
        echo "ws: zellij-session-open not found in PATH" >&2
        return 1
    end

    zellij-session-open --name "$name" --dir "$dir" $fresh_flag
end
