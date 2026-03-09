function zlast
    set -l session_file ~/.local/state/zellij-emacs-session
    if test -s $session_file
        set -l session (cat $session_file)
        zellij attach $session; or zellij
    else
        zellij
    end
end
