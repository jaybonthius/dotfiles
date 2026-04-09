function ws -d "Open a zellij session with emacs, pi, and a terminal"
    if test (count $argv) -lt 1
        echo "Usage: ws <directory> [session-name]"
        return 1
    end

    set -l dir (realpath $argv[1])
    if not test -d $dir
        echo "ws: not a directory: $dir"
        return 1
    end

    set -l name (test (count $argv) -ge 2; and echo $argv[2]; or basename $dir)

    # Attach if session exists, otherwise create with project layout
    if zellij list-sessions --short 2>/dev/null | string match -q $name
        zellij attach $name
    else
        zellij -l project options --session-name $name --default-cwd $dir
    end
end
