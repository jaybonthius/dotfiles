function ws -d "Open a tmux session with emacs, pi, and a terminal"
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

    # Attach/switch if session already exists
    if tmux has-session -t $name 2>/dev/null
        if set -q TMUX
            tmux switch-client -t $name
        else
            tmux attach-session -t $name
        end
        return
    end

    # Window 1: emacs
    tmux new-session -d -s $name -c $dir -n emacs
    tmux send-keys -t "$name:emacs" 'emacsclient -t' Enter

    # Window 2: pi
    tmux new-window -t $name -c $dir
    tmux send-keys -t $name 'pi' Enter

    # Window 3: empty terminal
    tmux new-window -t $name -c $dir

    # Focus emacs window and attach/switch
    tmux select-window -t "$name:emacs"
    if set -q TMUX
        tmux switch-client -t $name
    else
        tmux attach-session -t $name
    end
end
