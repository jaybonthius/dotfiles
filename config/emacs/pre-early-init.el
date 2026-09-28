;;; pre-early-init.el --- Pre-early initialization -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Code:

;; Only enable the debugger when Emacs is started with --debug-init.
(setq debug-on-error init-file-debug)

;; Ensure ~/.local/bin is on PATH (systemd-started daemon doesn't have it).
(add-to-list 'exec-path (expand-file-name "~/.local/bin"))
(setenv "PATH" (concat (expand-file-name "~/.local/bin") ":" (getenv "PATH")))

;; The signed macOS Emacs bundles GCC/libgccjit, but Nix's ld on PATH breaks
;; native compilation (missing libSystem). Select Apple's assembler/linker
;; without changing PATH for ordinary subprocesses or disabling native code.
(when (eq system-type 'darwin)
  (with-eval-after-load 'comp
    (add-to-list 'native-comp-driver-options "-B/usr/bin/")))

;; Disable package.el initialization since Elpaca replaces it.
(setq minimal-emacs-package-initialize-and-refresh nil)

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
