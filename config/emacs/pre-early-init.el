;;; pre-early-init.el --- Pre-early initialization -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Code:

;; Only enable the debugger when Emacs is started with --debug-init.
(setq debug-on-error init-file-debug)

;; Ensure ~/.local/bin is on PATH (systemd-started daemon doesn't have it).
(add-to-list 'exec-path (expand-file-name "~/.local/bin"))
(setenv "PATH" (concat (expand-file-name "~/.local/bin") ":" (getenv "PATH")))

;; Disable package.el initialization since Elpaca replaces it.
(setq minimal-emacs-package-initialize-and-refresh nil)

;; Fix native compilation on macOS with Homebrew gcc.
;; libgccjit needs LIBRARY_PATH to find libemutls_w.a.
(when (and (eq system-type 'darwin)
           (native-comp-available-p))
  (let ((gcc-lib-dir (car (file-expand-wildcards
                           "/opt/homebrew/lib/gcc/current/gcc/*/*/"))))
    (when (and gcc-lib-dir (file-directory-p gcc-lib-dir))
      (setenv "LIBRARY_PATH"
              (string-join
               (seq-uniq (cons gcc-lib-dir
                               (split-string (or (getenv "LIBRARY_PATH") "") ":" t)))
               ":")))))

;; Remove title bar and window decorations (including stoplight buttons).
(add-to-list 'default-frame-alist '(undecorated . t))

;; Reduce clutter in ~/.config/emacs by redirecting files to var/.
(setq user-emacs-directory (expand-file-name "var/" minimal-emacs-user-directory))
(setq package-user-dir (expand-file-name "elpa" user-emacs-directory))

;; Enable 24-bit (truecolor) support in terminal Emacs.
;; Ghostty supports truecolor but the xterm-ghostty terminfo only
;; advertises 256 colors.  Tell Emacs to use direct-color sequences
;; when we know the terminal supports them.
(unless (display-graphic-p)
  (when (or (string= (getenv "COLORTERM") "truecolor")
            (string= (getenv "COLORTERM") "24bit")
            (string-prefix-p "xterm-ghostty" (or (getenv "TERM") "")))
    (add-to-list 'term-file-aliases '("xterm-ghostty" . "xterm-direct"))
    (add-to-list 'term-file-aliases '("xterm-256color" . "xterm-direct"))))

;;; pre-early-init.el ends here
