;;; post-init.el --- Post initialization -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Code:

;;; ============================================================================
;;; Native compilation
;;; ============================================================================

;; compile-angel: ensure all packages are byte-compiled and native-compiled.
;; Must be loaded before all other packages.
(use-package compile-angel
  :ensure t
  :demand t
  :custom
  (compile-angel-verbose nil)
  :config
  (push "/init.el" compile-angel-excluded-files)
  (push "/early-init.el" compile-angel-excluded-files)
  (push "/pre-init.el" compile-angel-excluded-files)
  (push "/post-init.el" compile-angel-excluded-files)
  (push "/pre-early-init.el" compile-angel-excluded-files)
  (push "/post-early-init.el" compile-angel-excluded-files)
  (compile-angel-on-load-mode 1))

;;; ============================================================================
;;; System integration
;;; ============================================================================

;; Inherit environment variables (especially PATH) from the shell on macOS.
;; Without this, GUI Emacs won't find tools like rg, git, node, etc.
;; Only needed on macOS — on Linux the daemon inherits env from systemd.
(use-package exec-path-from-shell
  :ensure t
  :defer t
  :when (eq system-type 'darwin)
  :hook (elpaca-after-init . exec-path-from-shell-initialize))

;; macOS key modifiers: Control=Control, Option=Meta, Command=Super, Fn=Hyper.
(when (eq system-type 'darwin)
  (setq ns-command-modifier 'super
        ns-option-modifier 'meta
        ns-control-modifier 'control
        ns-function-modifier 'hyper))

;; kkp: Kitty Keyboard Protocol support for terminal Emacs.
;; The default query timeout (0.1s) is too short for SSH sessions and
;; can cause KKP negotiation to silently fail.  When that happens,
;; modifyOtherKeys CSI-u sequences arrive but nothing decodes them,
;; producing "u is undefined" errors on Ctrl+Shift combos.
(use-package kkp
  :ensure t
  :custom
  (kkp-terminal-query-timeout 0.5)
  (kkp-super-modifier 'super)
  (kkp-control-modifier 'control)
  :config
  (global-kkp-mode 1))

;; clipetty: send kills to the system clipboard over SSH/tmux via OSC 52.
(use-package clipetty
  :ensure t
  :bind ("M-w" . clipetty-kill-ring-save))

;; browse-url: open URLs via opener-open, which forwards to the local
;; browser through the opener socket (SSH RemoteForward) when available,
;; and falls back to xdg-open/open when running locally with a display.
(setq browse-url-browser-function #'browse-url-generic
      browse-url-generic-program (expand-file-name "~/bin/opener-open"))

(defun jb-parse-git-remote-url (url)
  "Convert a git remote URL to an HTTP URL."
  (let ((base (if (string-match "^http" url)
                  url
                (replace-regexp-in-string
                 "\\(.*\\)@\\(.*\\):\\(.*?\\)\\(\\.git\\)?$"
                 "https://\\2/\\3"
                 url))))
    (replace-regexp-in-string "\\.git$" "" base)))

;; Open the current file on the remote git host at the current line or
;; selection.  Uses `gh browse' for GitHub/GHE, constructs the URL
;; manually for Forgejo/Codeberg.
(defun jb-browse-file-remote ()
  "Open the current file on the remote git host at point or region."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (let* ((root (or (vc-git-root buffer-file-name)
                   (user-error "Not in a git repository")))
         (default-directory root)
         (file (file-relative-name buffer-file-name root))
         (branch (or (ignore-errors
                       (string-trim
                        (shell-command-to-string "git symbolic-ref --short HEAD")))
                     (string-trim
                      (shell-command-to-string "git rev-parse HEAD"))))
         (remote-url (string-trim
                      (shell-command-to-string "git config remote.origin.url")))
         (line (line-number-at-pos (if (use-region-p) (region-beginning) (point))))
         (end-line (when (use-region-p)
                     (line-number-at-pos (1- (region-end)))))
         (process-environment
          (cons (concat "BROWSER=" (expand-file-name "~/bin/opener-open"))
                process-environment))
         (line-spec (if end-line
                        (format "%s:%d-%d" file line end-line)
                      (format "%s:%d" file line)))
         (buf (generate-new-buffer " *gh-output*")))
    (unwind-protect
        (let ((rc (call-process "gh" nil buf nil "browse" line-spec
                                "--branch" branch)))
          (unless (= rc 0)
            (let* ((base-url (jb-parse-git-remote-url remote-url))
                   (anchor (if end-line
                               (format "#L%d-L%d" line end-line)
                             (format "#L%d" line)))
                   (url (format "%s/src/branch/%s/%s%s"
                                base-url branch file anchor)))
              (browse-url url))))
      (kill-buffer buf))))

(global-set-key (kbd "C-c g o") #'jb-browse-file-remote)

;; eat: Emulate A Terminal — fast terminal emulator inside Emacs.
;; Launches Fish by default.  Meow is disabled in eat buffers so
;; terminal keys pass through; press s-m to toggle meow back on.
(use-package eat
  :ensure t
  :commands (eat eat-project)
  :custom
  (eat-shell (executable-find "fish"))
  (eat-term-name "xterm-256color")
  :config
  (add-hook 'eat-mode-hook (lambda () (meow-mode -1))))

;; jb-opencode: launch the OpenCode TUI in an Eat terminal.
;; Defined outside `use-package eat' so the function and keybinding
;; exist at init time (eat's :config is deferred until first use).
;; With prefix arg, uses `consult-dir' to pick the directory first
;; via its public `consult-dir-default-command' extension point.
(defvar consult-dir-default-command)

(defun jb-opencode--in-dir ()
  "Launch OpenCode in `default-directory' via Eat.
Buffer is named *oc:session:dir* when an easysession is active,
or *oc:dir* otherwise.  Intended as a `consult-dir-default-command'
action or direct call."
  (interactive)
  (let* ((dir-name (file-name-nondirectory
                    (directory-file-name default-directory)))
         (session (and (fboundp 'easysession-get-session-name)
                       (easysession-get-session-name)))
         (buf-name (if session
                       (format "*oc:%s:%s*" session dir-name)
                     (format "*oc:%s*" dir-name)))
         (buf (eat "opencode" t)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (rename-buffer buf-name t)))))

(defun jb-opencode (arg)
  "Launch OpenCode TUI in an Eat terminal.
Without prefix ARG, runs in the current directory.
With \\[universal-argument], pick the directory first via `consult-dir'
\(projects, recent dirs, bookmarks, etc.)."
  (interactive "P")
  (if arg
      (let ((consult-dir-default-command #'jb-opencode--in-dir))
        (call-interactively #'consult-dir))
    (jb-opencode--in-dir)))

(global-set-key (kbd "C-c a o") #'jb-opencode)

(defun jb-opencode-home ()
  "Launch OpenCode in the home directory via Eat."
  (interactive)
  (let ((default-directory (expand-file-name "~/")))
    (jb-opencode--in-dir)))

(global-set-key (kbd "C-c a ~") #'jb-opencode-home)

(defun jb-opencode-dir ()
  "Launch OpenCode in a directory chosen via `read-directory-name'."
  (interactive)
  (let ((default-directory (read-directory-name "OpenCode directory: ")))
    (jb-opencode--in-dir)))

(global-set-key (kbd "C-c a d") #'jb-opencode-dir)

;; Terminal mouse support.
(unless (display-graphic-p)
  (xterm-mouse-mode 1))

;; Nix Home Manager: apply dotfiles changes from within Emacs.
(defun jb-home-manager-switch ()
  "Run `home-manager switch' to apply dotfiles changes.
Saves the current easysession first in case the daemon is restarted.
Uses `compile' so output is displayed in a *compilation* buffer
with clickable error locations."
  (interactive)
  (when (easysession-get-session-name)
    (easysession-save))
  (compile (format "systemd-run --user --collect --pipe -E PATH=%s --unit=hm-switch-%s ~/dotfiles/install.sh switch"
                   (shell-quote-argument (getenv "PATH"))
                   (format-time-string "%s"))))

(global-set-key (kbd "C-c g r") #'jb-home-manager-switch)

;; Ask before quitting Emacs.
(setq confirm-kill-emacs 'y-or-n-p)

;;; ============================================================================
;;; Built-in modes
;;; ============================================================================

;; Auto-revert: automatically update buffers to reflect changes on disk.
(use-package autorevert
  :ensure nil
  :commands (auto-revert-mode global-auto-revert-mode)
  :hook (after-init . global-auto-revert-mode)
  :custom
  (auto-revert-interval 3)
  (auto-revert-remote-files nil)
  (auto-revert-use-notify t)
  (auto-revert-avoid-polling t)
  (auto-revert-verbose t))

;; Recentf: maintain a list of recently accessed files.
(use-package recentf
  :ensure nil
  :commands (recentf-mode recentf-cleanup)
  :hook (after-init . recentf-mode)
  :custom
  (recentf-auto-cleanup (if (daemonp) 300 'never))
  (recentf-exclude
   (list "\\.tar$" "\\.tbz2$" "\\.tbz$" "\\.tgz$" "\\.bz2$"
         "\\.bz$" "\\.gz$" "\\.gzip$" "\\.xz$" "\\.zip$"
         "\\.7z$" "\\.rar$"
         "COMMIT_EDITMSG\\'"
         "\\.\\(?:gz\\|gif\\|svg\\|png\\|jpe?g\\|bmp\\|xpm\\)$"
         "-autoloads\\.el$" "autoload\\.el$"))
  :config
  (add-hook 'kill-emacs-hook #'recentf-cleanup -90))

;; Savehist: preserve minibuffer history between sessions.
(use-package savehist
  :ensure nil
  :commands (savehist-mode savehist-save)
  :hook (after-init . savehist-mode)
  :custom
  (savehist-autosave-interval 600)
  (savehist-additional-variables
   '(kill-ring
     register-alist
     mark-ring global-mark-ring
     search-ring regexp-search-ring
     easysession--current-session-name)))

;; Save-place: remember last cursor position in files.
(use-package saveplace
  :ensure nil
  :commands (save-place-mode save-place-local-mode)
  :hook (after-init . save-place-mode)
  :custom
  (save-place-limit 400))

;; which-key: display available keybindings in a popup.
(use-package which-key
  :ensure nil ; builtin since Emacs 30
  :commands which-key-mode
  :hook (after-init . which-key-mode)
  :custom
  (which-key-idle-delay 1.5)
  (which-key-idle-secondary-delay 0.25)
  (which-key-add-column-padding 1)
  (which-key-max-description-length 40))

;;; Autosave

;; Enable auto-save-mode to prevent data loss. Use `recover-file' or
;; `recover-session' to restore unsaved changes.
(setq auto-save-default t)
(setq auto-save-interval 300)
(setq auto-save-timeout 30)

;; auto-save-visited-mode: save file-visiting buffers after idle time.

(auto-save-visited-mode 1)

;;; ============================================================================
;;; UI & appearance
;;; ============================================================================

;;; Font & cursor

(set-face-attribute 'default nil
                    :family "Fira Code"
                    :height 140
                    :weight 'regular)

(set-face-attribute 'fixed-pitch nil :family "Fira Code")

(setq-default cursor-type 'bar)

;;; Tab bar: hidden, with history-based window undo/redo.

(use-package tab-bar
  :ensure nil
  :bind (("C-c <left>" . tab-bar-history-back)
         ("C-c <right>" . tab-bar-history-forward))
  :custom
  (tab-bar-show nil)
  :config
  (tab-bar-history-mode 1))

;;; Themes

;; twilight-bright-theme: a clean light theme (bogdan's fork).
(use-package twilight-bright-theme
  :ensure (:host github :repo "Bogdanp/twilight-bright-theme.el")
  :demand t)

;; twilight-anti-bright-theme: the dark counterpart (bogdan's fork).
(use-package twilight-anti-bright-theme
  :ensure (:host github :repo "Bogdanp/twilight-anti-bright-theme")
  :demand t)

;; gruvbox-theme: retro groove color scheme (dark & light variants).
(use-package gruvbox-theme
  :ensure t
  :demand t)

;; modus-themes: highly accessible themes (WCAG AAA contrast).
;; modus-operandi (light) / modus-vivendi (dark).
(use-package modus-themes
  :ensure t
  :demand t
  :custom
  (modus-themes-italic-constructs nil)
  (modus-themes-bold-constructs t)
  (modus-themes-mixed-fonts t)
  (modus-themes-headings
   '((1 . (1.3))
     (2 . (1.2))
     (3 . (1.1))
     (t . (1.0))))
  (modus-themes-completions '((matches . (bold))
                              (selection . (semibold))))
  (modus-themes-prompts '(bold))
  :config
  (defvar jb-modus-face-overrides
    '((keyword
       :fg fg-main
       :face font-lock-keyword-face
       :bg nil
       :weight bold)

      (builtin
       :fg fg-main
       :face font-lock-builtin-face
       :bg nil
       :weight bold)

      (preprocessor
       :fg fg-main
       :face font-lock-preprocessor-face
       :bg nil
       :weight normal)

      (fnname
       :fg blue-warmer
       :face font-lock-function-name-face
       :bg bg-blue-nuanced
       :weight normal)

      (fnname-call
       :fg fg-main
       :face font-lock-function-call-face
       :bg nil
       :weight normal)

      (type
       :fg fg-main
       :face font-lock-type-face
       :bg nil
       :weight normal)

      (string
       :fg green-warmer
       :face font-lock-string-face
       :bg bg-green-nuanced
       :weight normal)

      (constant
       :fg magenta-warmer
       :face font-lock-constant-face
       :bg bg-magenta-nuanced
       :weight normal)

      (variable
       :fg red-warmer
       :face font-lock-variable-name-face
       :bg bg-red-nuanced
       :weight normal)

      (variable-use
       :fg fg-main
       :face font-lock-variable-use-face
       :bg nil
       :weight normal)

      (property
       :fg fg-main
       :face font-lock-property-name-face
       :bg nil
       :weight normal)

      (property-use
       :fg fg-main
       :face font-lock-property-use-face
       :bg nil
       :weight normal)

      (rx-backslash
       :fg fg-main
       :face font-lock-regexp-grouping-backslash
       :bg nil
       :weight normal)

      (rx-construct
       :fg fg-main
       :face font-lock-regexp-grouping-construct
       :bg nil
       :weight normal)

      (docstring
       :fg yellow-warmer
       :face font-lock-doc-face
       :bg bg-yellow-nuanced
       :weight normal)

      (docmarkup
       :fg yellow-warmer
       :face font-lock-doc-markup-face
       :bg bg-yellow-nuanced
       :weight normal)

      (comment
       :fg yellow-warmer
       :face font-lock-comment-face
       :bg bg-yellow-nuanced
       :weight normal)))

  (setq modus-themes-common-palette-overrides
        (mapcar (lambda (entry) (list (car entry) (plist-get (cdr entry) :fg)))
                jb-modus-face-overrides))

  (defun jb-modus-apply-face-overrides ()
    "Apply background and weight overrides from `jb-modus-face-overrides'."
    (dolist (entry jb-modus-face-overrides)
      (let* ((props (cdr entry))
             (face (plist-get props :face))
             (bg-sym (plist-get props :bg))
             (weight (plist-get props :weight)))
        (when-let* ((bg-val (and bg-sym (modus-themes-get-color-value bg-sym))))
          (set-face-attribute face nil :background bg-val))
        (when weight
          (set-face-attribute face nil :weight weight)))))
  (add-hook 'modus-themes-after-load-theme-hook #'jb-modus-apply-face-overrides)
  (add-hook 'enable-theme-functions (lambda (_theme) (jb-modus-apply-face-overrides))))

;; Auto theme sync: watches ~/.local/state/theme for "dark"/"light" changes
;; written by macOS dark-notify.  Preferred theme per mode is stored in
;; ~/.local/state/emacs-preferred-themes (format: "dark:THEME\nlight:THEME").

(defvar jb-theme-state-file (expand-file-name "~/.local/state/theme")
  "File containing the current mode: \"dark\" or \"light\".
Written by the macOS sync script when system appearance changes.")

(defvar jb-theme-default-dark 'modus-vivendi-tinted
  "Theme to use in dark mode.")

(defvar jb-theme-default-light 'modus-operandi-tinted
  "Theme to use in light mode.")

(defvar jb-theme--watch-descriptor nil
  "File-notify descriptor for the theme state file watcher.")

(defun jb-theme-current-mode ()
  "Return `dark' or `light' based on `jb-theme-state-file' contents.
Falls back to `dark' if the file is missing or unreadable."
  (if (file-exists-p jb-theme-state-file)
      (let ((mode (with-temp-buffer
                    (insert-file-contents jb-theme-state-file)
                    (string-trim (buffer-string)))))
        (if (string= mode "light") 'light 'dark))
    'dark))

(defun jb-theme-apply ()
  "Load the theme for the current mode.
Disables all active themes first, then loads the appropriate one."
  (let* ((mode (jb-theme-current-mode))
         (theme (if (eq mode 'light) jb-theme-default-light jb-theme-default-dark)))
    (mapc #'disable-theme custom-enabled-themes)
    (load-theme theme t)
    (message "Theme: %s (%s mode)" theme mode)))

(defun jb-theme--on-file-change (event)
  "File-notify callback for `jb-theme-state-file' changes.
EVENT is the notification event from `file-notify-add-watch'."
  (let ((action (nth 1 event)))
    (cond
     ((memq action '(changed created renamed))
      ;; Small delay to ensure the file write is complete.
      (run-with-timer 0.1 nil #'jb-theme-apply))
     ((eq action 'deleted)
      ;; File was deleted (e.g. atomic replacement creates a new inode).
      ;; Re-establish the watch once the new file appears.
      (run-with-timer 0.5 nil #'jb-theme--setup-watch)))))

(defun jb-theme--setup-watch ()
  "Set up the file-notify watch for `jb-theme-state-file'.
On kqueue (macOS), watch the file directly since kqueue does not fire
events on a directory for in-place content changes to contained files.
On inotify (Linux), watch the directory since inotify's close_write on
a directory correctly fires when contained files are written.
Also re-applies the current theme."
  ;; Remove any existing watcher.
  (when jb-theme--watch-descriptor
    (ignore-errors (file-notify-rm-watch jb-theme--watch-descriptor))
    (setq jb-theme--watch-descriptor nil))
  (when (file-exists-p jb-theme-state-file)
    (if (eq file-notify--library 'kqueue)
        ;; macOS/kqueue: watch the file directly.
        (setq jb-theme--watch-descriptor
              (file-notify-add-watch
               jb-theme-state-file
               '(change)
               #'jb-theme--on-file-change))
      ;; Linux/inotify: watch the directory, filter for our file.
      (setq jb-theme--watch-descriptor
            (file-notify-add-watch
             (file-name-directory jb-theme-state-file)
             '(change)
             (lambda (event)
               (when (string= (file-name-nondirectory (nth 2 event))
                              (file-name-nondirectory jb-theme-state-file))
                 (jb-theme--on-file-change event))))))
    (jb-theme-apply)))

(defun jb-theme-start-watcher ()
  "Start watching `jb-theme-state-file' and apply the current theme.
Ensures required directories and files exist, sets up file-notify."
  (interactive)
  (let ((dir (file-name-directory jb-theme-state-file)))
    (unless (file-exists-p dir)
      (make-directory dir t)))
  (unless (file-exists-p jb-theme-state-file)
    (with-temp-file jb-theme-state-file
      (insert "dark\n")))
  (jb-theme--setup-watch))

(defun jb-theme-stop-watcher ()
  "Stop watching the theme state file."
  (interactive)
  (when jb-theme--watch-descriptor
    (file-notify-rm-watch jb-theme--watch-descriptor)
    (setq jb-theme--watch-descriptor nil)
    (message "Theme watcher stopped.")))

;; Start the theme watcher after all packages are loaded.
(add-hook 'elpaca-after-init-hook #'jb-theme-start-watcher)

;;; Ligatures

(use-package ligature
  :ensure t
  :config
  (ligature-set-ligatures t '("www"))
  (ligature-set-ligatures 'eww-mode '("ff" "fi" "ffi"))
  (ligature-set-ligatures 'prog-mode
                          '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
                            ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
                            "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
                            "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
                            "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
                            "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
                            "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
                            "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
                            ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
                            "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
                            "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
                            "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "~~" "(*" "*)"
                            "\\\\" "://"))
  (global-ligature-mode t))

;;; Centering

(use-package olivetti
  :ensure t
  :custom
  (olivetti-body-width 100))

(use-package auto-olivetti
  :ensure (:host sourcehut :repo "ashton314/auto-olivetti")
  :custom
  (auto-olivetti-enabled-modes '(prog-mode text-mode fundamental-mode))
  (auto-olivetti-threshold-fraction 1.0)
  :config
  (auto-olivetti-mode))

(dolist (hook '(org-mode-hook markdown-mode-hook))
  (add-hook hook (lambda () (setq-local olivetti-body-width 80))))

;;; Org prettification: terminal-friendly styling.

;; org-superstar: prettify heading bullets and list markers.
;; Unlike org-modern, org-superstar is designed with terminal fallback
;; support and doesn't rely on GUI text properties or fringes.
(use-package org-superstar
  :ensure t
  :hook (org-mode . org-superstar-mode)
  :custom
  (org-superstar-headline-bullets-list '("◉" "○" "●" "○" "●"))
  (org-superstar-prettify-item-bullets t))

;; Built-in Org appearance settings.
(setq org-hide-leading-stars t
      org-pretty-entities t
      org-hide-emphasis-markers t
      org-ellipsis "…"
      org-tags-column 0
      org-auto-align-tags nil)

;;; ============================================================================
;;; Note-taking: Denote and companion packages
;;; ============================================================================

;;; Denote: simple notes with an efficient file-naming scheme.
;; Files follow a predictable naming convention:
;;   ID--TITLE__KEYWORDS.EXT  (e.g. 20260308T142356--my-note__emacs_project.org)
;; No database required; everything is plain text and portable.

(use-package denote
  :ensure t
  :hook
  ((text-mode . denote-fontify-links-mode)
   (dired-mode . denote-dired-mode))
  :bind
  ( :map global-map
    ("C-c n n" . denote)
    ("C-c n d" . denote-dired)
    ("C-c n g" . denote-grep)
    ("C-c n l" . denote-link)
    ("C-c n L" . denote-add-links)
    ("C-c n b" . denote-backlinks)
    ("C-c n q c" . denote-query-contents-link)
    ("C-c n q f" . denote-query-filenames-link)
    ("C-c n r" . denote-rename-file)
    ("C-c n R" . denote-rename-file-using-front-matter)
    :map dired-mode-map
    ("C-c C-d C-i" . denote-dired-link-marked-notes)
    ("C-c C-d C-r" . denote-dired-rename-files)
    ("C-c C-d C-k" . denote-dired-rename-marked-files-with-keywords)
    ("C-c C-d C-R" . denote-dired-rename-marked-files-using-front-matter))
  :config
  (setq denote-directory (expand-file-name "~/org/notes/"))
  (setq denote-save-buffers nil)
  (setq denote-infer-keywords t)
  (setq denote-sort-keywords t)
  (setq denote-prompts '(title keywords))
  (setq denote-date-prompt-use-org-read-date t)
  (setq denote-rename-confirmations '(rewrite-front-matter modify-file-name))

  (denote-rename-buffer-mode 1))

;;; consult-denote: enhanced minibuffer interactions using Consult.
;; Provides live preview, narrowing, and async search for Denote prompts.
;; Integrates naturally with the Vertico + Consult + Marginalia stack.

(use-package consult-denote
  :ensure t
  :after denote
  :config
  (setq consult-denote-grep-command #'consult-ripgrep)
  (consult-denote-mode 1))

;;; denote-journal: dedicated journaling workflow.
;; Creates daily journal entries in a "journal" subdirectory with
;; a "journal" keyword automatically applied.

(use-package denote-journal
  :ensure t
  :after denote
  :bind
  ("C-c n j" . denote-journal-new-entry)
  :config
  (setq denote-journal-directory
        (expand-file-name "journal/" (denote-directory)))
  (setq denote-journal-keyword "journal"))

;;; denote-org: Org dynamic blocks for listing and aggregating notes.
;; Use #+BEGIN: denote-files / denote-links / denote-backlinks blocks
;; inside Org files to dynamically list or aggregate your notes.

(use-package denote-org
  :ensure t
  :after denote)

;;; hl-todo: highlight TODO/FIXME/etc keywords.

(use-package hl-todo
  :ensure t
  :custom
  (hl-todo-keyword-faces
   '(("TODO"   . (:inherit error :weight bold))
     ("FIXME"  . (:inherit error :weight bold))
     ("DEBUG"  . (:inherit warning :weight bold))
     ("GOTCHA" . (:inherit warning :weight bold))
     ("STUB"   . (:inherit font-lock-keyword-face :weight bold))
     ("HACK"   . (:inherit warning :weight bold))
     ("NOTE"   . (:inherit success :weight bold))))
  :bind (:map hl-todo-mode-map
              ("C-c t p" . hl-todo-previous)
              ("C-c t n" . hl-todo-next)
              ("C-c t o" . hl-todo-occur))
  :config
  (global-hl-todo-mode 1))

;;; Page break lines: visual indicators for ^L characters.

(use-package page-break-lines
  :ensure t
  :commands (page-break-lines-mode global-page-break-lines-mode)
  :hook (emacs-lisp-mode . page-break-lines-mode))

;;; Persist text scale across sessions.

(use-package persist-text-scale
  :ensure t
  :commands (persist-text-scale-mode persist-text-scale-restore)
  :hook (after-init . persist-text-scale-mode))

;;; Modeline: doom-modeline

(use-package doom-modeline
  :ensure t
  :hook (elpaca-after-init . doom-modeline-mode)
  :custom
  (doom-modeline-icon nil)
  (doom-modeline-unicode-fallback nil)
  (doom-modeline-modal t)
  (doom-modeline-modal-icon nil)
  (doom-modeline-buffer-encoding 'nondefault)
  (doom-modeline-minor-modes nil)
  (doom-modeline-indent-info nil)
  (doom-modeline-vcs-max-length 20)
  (doom-modeline-check 'auto)
  (doom-modeline-lsp t)
  (doom-modeline-highlight-modified-buffer-name t))

;;; Line numbers: disabled in buffers.

(setq display-line-numbers-type nil)

;;; Tree-sitter: maximum syntax highlighting.

(setq treesit-font-lock-level 4)

;;; Pixel-precise scrolling (not needed on emacs-mac which handles it natively).

(unless (and (eq window-system 'mac)
             (bound-and-true-p mac-carbon-version-string))
  (setq pixel-scroll-precision-use-momentum nil)
  (pixel-scroll-precision-mode 1))

;;; Built-in minor modes enabled after init.

(add-hook 'after-init-hook #'show-paren-mode)
(add-hook 'after-init-hook #'delete-selection-mode)
(add-hook 'after-init-hook #'window-divider-mode)
(add-hook 'after-init-hook #'minibuffer-depth-indicate-mode)

;;; Window splitting: always prefer vertical (side-by-side) splits.

(setq split-height-threshold nil)
(setq split-width-threshold 80)

;;; Uniquify: disambiguate buffer names with path components.

(use-package uniquify
  :ensure nil
  :custom
  (uniquify-buffer-name-style 'reverse)
  (uniquify-separator "•")
  (uniquify-after-kill-buffer-p t))

;;; Prevent accidental zoom via mouse wheel.

(global-unset-key (kbd "C-<wheel-up>"))
(global-unset-key (kbd "C-<wheel-down>"))

;;; Terminal: map F12 as a Control modifier prefix.

(unless (display-graphic-p)
  (define-key key-translation-map (kbd "<f12>") 'event-apply-control-modifier))

;;; ============================================================================
;;; Modal editing: Symex + Meow
;;; ============================================================================

;;; Symex: structural s-expression editing via a Lithium modal interface.
;;; Uses IJKL directional keys to match the Meow layout below.

(use-package symex-core
  :ensure (:host github
                 :repo "drym-org/symex.el"
                 :files ("symex-core/symex*.el")))

(use-package symex
  :after symex-core
  :ensure (:host github
                 :repo "drym-org/symex.el"
                 :files ("symex/symex*.el"
                         "symex/doc/*.texi"
                         "symex/doc/figures"))
  :bind ("s-;" . symex-mode-interface)
  :custom
  (symex-orientation 'inverted)
  :config
  (symex-mode 1)
  (lithium-define-keys symex-editing-mode
                       (;; IJKL movement (matches Meow normal state)
                        ("h" symex-insert-at-beginning :exit)
                        ("i" symex-go-down)
                        ("j" symex-go-backward)
                        ("k" symex-go-up)
                        ("l" symex-go-forward)
                        ;; Branch navigation
                        ("C-i" symex-descend-branch)
                        ("C-k" symex-climb-branch)
                        ("M-i" symex-goto-lowest)
                        ("M-k" symex-goto-highest)
                        ;; Insertion (all exit symex modal UI)
                        ("H" symex-insert-before :exit)
                        ("A" symex-append-after :exit)
                        ("a" symex-append-at-end :exit))))

(use-package symex-ide
  :after symex
  :ensure (:host github
                 :repo "drym-org/symex.el"
                 :files ("symex-ide/symex*.el"))
  :config
  (symex-ide-mode 1))

;;; Meow: modal editing with a custom IJKL directional layout.
;;; i=up, j=left, k=down, l=right.  h=insert (replaces the traditional i).

(use-package meow
  :ensure (:host github :repo "meow-edit/meow")
  :config
  (defun meow-setup ()
    "Configure Meow keybindings with an IJKL directional layout."
    (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)

    ;; Motion state (read-only buffers: Dired, Help, etc.)
    (meow-motion-define-key
     '("i" . meow-prev)
     '("k" . meow-next)
     '("<escape>" . ignore))

    ;; Leader (SPC prefix)
    (meow-leader-define-key
     ;; Digit arguments
     '("1" . meow-digit-argument)
     '("2" . meow-digit-argument)
     '("3" . meow-digit-argument)
     '("4" . meow-digit-argument)
     '("5" . meow-digit-argument)
     '("6" . meow-digit-argument)
     '("7" . meow-digit-argument)
     '("8" . meow-digit-argument)
     '("9" . meow-digit-argument)
     '("0" . meow-digit-argument)
     '("/" . meow-keypad-describe-key)
     '("?" . meow-cheatsheet)
     ;; Code navigation (xref)
     '("." . xref-find-definitions)
     '("," . xref-go-back)
     '("r" . xref-find-references)
     ;; Search & replace
     '("l" . consult-line)
     '(";" . flash-jump)
     '("t" . uflash-treesitter)
     '("s" . query-replace)
     '("S" . query-replace-regexp)
     '("r" . consult-ripgrep)
     '("p" . easysession-switch-to-previous))

    ;; Normal state (main editing)
    (meow-normal-define-key
     ;; Expansion
     '("0" . meow-expand-0)
     '("9" . meow-expand-9)
     '("8" . meow-expand-8)
     '("7" . meow-expand-7)
     '("6" . meow-expand-6)
     '("5" . meow-expand-5)
     '("4" . meow-expand-4)
     '("3" . meow-expand-3)
     '("2" . meow-expand-2)
     '("1" . meow-expand-1)
     '("-" . negative-argument)
     '(";" . meow-reverse)
     '("," . meow-inner-of-thing)
     '("." . meow-bounds-of-thing)
     '("[" . meow-beginning-of-thing)
     '("]" . meow-end-of-thing)
     ;; Movement (IJKL)
     '("i" . meow-prev)
     '("I" . meow-prev-expand)
     '("j" . meow-left)
     '("J" . meow-left-expand)
     '("k" . meow-next)
     '("K" . meow-next-expand)
     '("l" . meow-right)
     '("L" . meow-right-expand)
     ;; Editing
     '("a" . meow-append)
     '("A" . meow-open-below)
     '("b" . meow-back-word)
     '("B" . meow-back-symbol)
     '("c" . meow-change)
     '("d" . meow-delete)
     '("D" . meow-backward-delete)
     '("e" . meow-next-word)
     '("E" . meow-next-symbol)
     '("f" . meow-find)
     '("g" . meow-cancel-selection)
     '("G" . meow-grab)
     '("h" . meow-insert)
     '("H" . meow-open-above)
     '("m" . meow-join)
     '("n" . meow-search)
     '("o" . meow-block)
     '("O" . meow-to-block)
     '("p" . meow-yank)
     '("q" . meow-quit)
     '("Q" . meow-goto-line)
     '("r" . meow-replace)
     '("R" . meow-swap-grab)
     '("s" . meow-kill)
     '("t" . meow-till)
     '("u" . meow-undo)
     '("U" . meow-undo-in-selection)
     '("v" . meow-visit)
     '("w" . meow-mark-word)
     '("W" . meow-mark-symbol)
     '("x" . meow-line)
     '("X" . meow-goto-line)
     '("y" . clipetty-kill-ring-save)
     '("Y" . meow-sync-grab)
     '("z" . meow-pop-selection)
     '("'" . repeat)
     '("<escape>" . ignore)))

  (meow-setup)
  (setq meow-cursor-type-default '(bar . 2))
  (meow-global-mode 1)

  ;; s-m: toggle meow on/off in the current buffer.
  ;; When toggled on, forces normal state (full keymap) so the underlying
  ;; mode's bindings are completely suppressed.
  (defun meow-toggle ()
    "Toggle meow-mode in the current buffer.
When enabling, always enter normal state so that meow's full keymap
takes priority and the underlying mode's keys are suppressed."
    (interactive)
    (if meow-mode
        (progn
          (meow-mode -1)
          (meow--set-cursor-type '(bar . 2)))
      (meow-mode 1)
      (meow--switch-state 'normal)))
  (global-set-key (kbd "s-m") #'meow-toggle))

;;; ============================================================================
;;; Completion (minibuffer): Vertico + Orderless + Marginalia + Consult + Embark
;;; ============================================================================

;; Vertico: vertical completion interface for the minibuffer.
(use-package vertico
  :ensure t
  :custom
  (vertico-count 15)
  (vertico-resize nil)
  :config
  (vertico-mode)
  (vertico-multiform-mode)
  (vertico-buffer-mode)
  (setq vertico-multiform-commands
        '((execute-extended-command (vertico-buffer-mode . -1)))))

;; Orderless: flexible matching for completion candidates.
;; Allows space-separated patterns matched in any order.
(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

;; Marginalia: rich annotations in the minibuffer.
(use-package marginalia
  :ensure t
  :commands (marginalia-mode marginalia-cycle)
  :hook (elpaca-after-init . marginalia-mode))

;; Consult: enhanced search, navigation, and buffer commands.
(use-package consult
  :ensure t
  :bind (;; C-c bindings in `mode-specific-map'
         ("C-c M-x" . consult-mode-command)
         ("C-c h" . consult-history)
         ("C-c k" . consult-kmacro)
         ("C-c m" . consult-man)
         ("C-c i" . consult-info)
         ([remap Info-search] . consult-info)
         ;; C-x bindings in `ctl-x-map'
         ("C-x M-:" . consult-complex-command)
         ("C-x b" . consult-buffer)
         ("C-x 4 b" . consult-buffer-other-window)
         ("C-x 5 b" . consult-buffer-other-frame)
         ("C-x t b" . consult-buffer-other-tab)
         ("C-x r b" . consult-bookmark)
         ("C-x p b" . consult-project-buffer)
         ;; Custom M-# bindings for fast register access
         ("M-#" . consult-register-load)
         ("M-'" . consult-register-store)
         ("C-M-#" . consult-register)
         ;; Other custom bindings
         ("M-y" . consult-yank-pop)
         ;; M-g bindings in `goto-map'
         ("M-g e" . consult-compile-error)
         ("M-g f" . consult-flymake)
         ("M-g g" . consult-goto-line)
         ("M-g M-g" . consult-goto-line)
         ("M-g o" . consult-outline)
         ("M-g m" . consult-mark)
         ("M-g k" . consult-global-mark)
         ("M-g i" . consult-imenu)
         ("M-g I" . consult-imenu-multi)
         ;; M-s bindings in `search-map'
         ("M-s d" . consult-find)
         ("M-s c" . consult-locate)
         ("M-s g" . consult-grep)
         ("M-s G" . consult-git-grep)
         ("M-s r" . consult-ripgrep)
         ("M-s l" . consult-line)
         ("M-s L" . consult-line-multi)
         ("M-s k" . consult-keep-lines)
         ("M-s u" . consult-focus-lines)
         ;; Isearch integration
         ("M-s e" . consult-isearch-history)
         :map isearch-mode-map
         ("M-e" . consult-isearch-history)
         ("M-s e" . consult-isearch-history)
         ("M-s l" . consult-line)
         ("M-s L" . consult-line-multi)
         ;; Minibuffer history
         :map minibuffer-local-map
         ("M-s" . consult-history)
         ("M-r" . consult-history))

  :hook (completion-list-mode . consult-preview-at-point-mode)

  :init
  (setq register-preview-delay 0.5
        register-preview-function #'consult-register-format)
  (advice-add #'register-preview :override #'consult-register-window)
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  :config
  (consult-customize
   consult-theme :preview-key '(:debounce 0.2 any)
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref
   consult-source-bookmark consult-source-file-register
   consult-source-recent-file consult-source-project-recent-file
   :preview-key '(:debounce 0.4 any))
  (setq consult-narrow-key "<"))

;; Embark: context-sensitive actions on completion candidates.
(use-package embark
  :ensure t
  :commands (embark-act
             embark-dwim
             embark-export
             embark-collect
             embark-bindings
             embark-prefix-help-command)
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)
   ("C-h B" . embark-bindings))

  :init
  (setq prefix-help-command #'embark-prefix-help-command)

  :config
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none)))))

;; Embark-consult: integration between Embark and Consult.
(use-package embark-consult
  :ensure t
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

;; consult-project-extra: unified consult interface for project.el
;; (project buffers, project files, and known projects via narrowing).
(use-package consult-project-extra
  :ensure t
  :bind (("C-x p f" . consult-project-extra-find)
         ("C-x p F" . consult-project-extra-find-other-window)))

;; consult-dir: multi-source directory picker for the minibuffer.
;; Provides quick access to current dir, project roots, recent dirs,
;; and bookmarks via consult narrowing.  Also works inside the
;; minibuffer (e.g. during find-file) to switch directories on the fly.
(use-package consult-dir
  :ensure t
  :bind (("C-x C-d" . consult-dir)
         :map vertico-map
         ("C-x C-d" . consult-dir)
         ("C-x C-j" . consult-dir-jump-file)))

;;;; TODO: consult-dir-jump-file doesn't seem to be working...

;;; ============================================================================
;;; Completion (in-buffer): Corfu + Cape
;;; ============================================================================

;; Corfu: compact in-buffer completion popup.
(use-package corfu
  :ensure t
  :commands (corfu-mode global-corfu-mode)

  :hook ((prog-mode . corfu-mode)
         (shell-mode . corfu-mode)
         (eshell-mode . corfu-mode))

  :custom
  (read-extended-command-predicate #'command-completion-default-include-p)
  (text-mode-ispell-word-completion nil)
  (tab-always-indent 'complete)

  :config
  (global-corfu-mode))

;; Cape: Completion At Point Extensions.
;; Provides additional completion backends for corfu.
(use-package cape
  :ensure t
  :commands (cape-dabbrev cape-file cape-elisp-block)
  :bind ("C-c p" . cape-prefix-map)
  :init
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-elisp-block))

;;; ============================================================================
;;; Help & discovery
;;; ============================================================================

;; Helpful: better *help* buffers with more contextual information.
(use-package helpful
  :ensure t
  :commands (helpful-callable
             helpful-variable
             helpful-key
             helpful-command
             helpful-at-point
             helpful-function)
  :bind
  ([remap describe-command] . helpful-command)
  ([remap describe-function] . helpful-callable)
  ([remap describe-key] . helpful-key)
  ([remap describe-symbol] . helpful-symbol)
  ([remap describe-variable] . helpful-variable)
  :custom
  (helpful-max-buffers 7))

;;; ============================================================================
;;; Undo
;;; ============================================================================

;; undo-fu: lightweight undo/redo wrapper.
(use-package undo-fu
  :ensure t
  :commands (undo-fu-only-undo
             undo-fu-only-redo
             undo-fu-only-redo-all
             undo-fu-disable-checkpoint)
  :bind (("C-z" . undo-fu-only-undo)
         ("C-S-z" . undo-fu-only-redo)))

;; undo-fu-session: persist undo history across Emacs sessions.
(use-package undo-fu-session
  :ensure t
  :commands undo-fu-session-global-mode
  :hook (elpaca-after-init . undo-fu-session-global-mode))

;;; ============================================================================
;;; Navigation
;;; ============================================================================

;; Avy: jump to visible text with minimal keystrokes.
(use-package avy
  :ensure t
  :commands (avy-gotochar
             avy-goto-char-2
             avy-next))

(use-package casual-avy
  :ensure t
  :after avy
  :bind ("s-k" . casual-avy-tmenu))

;; Flash: incremental search-based navigation with jump labels.
;; Unlike avy's fixed-length input, flash lets you type an arbitrary
;; search pattern and shows labels alongside results as you type.
(use-package flash
  :ensure (:host github :repo "Prgebish/flash")
  :commands (flash-jump flash-jump-continue flash-treesitter)
  :config
  (setq flash-multi-window t)
  (setq flash-backdrop t)
  (setq flash-rainbow t)
  (setq flash-nohlsearch t)
  (setq flash-search-history t)
  (setq flash-label-position 'overlay)
  (require 'flash-isearch)
  (flash-isearch-mode 1))

;; Switchy-window: MRU-based window switching. Pressing the key in
;; quick succession cycles windows by recency; pausing locks the
;; selection.
(use-package switchy-window
  :ensure t
  :bind ("s-o" . switchy-window)
  :init
  (switchy-window-minor-mode))

;;; ============================================================================
;;; Git
;;; ============================================================================

;; Transient: required by magit. The built-in version is too old,
;; so we install the current version from MELPA via Elpaca.
(use-package transient
  :ensure t)

;; Magit: full-featured git porcelain inside Emacs.
(use-package magit
  :ensure t
  :after transient
  :commands (magit-status
             magit-dispatch
             magit-file-dispatch)
  :bind (("C-x g" . magit-status)
         ("C-x M-g" . magit-dispatch))
  :custom
  (magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1)
  :config
  ;; Disable meow by default in magit buffers so all magit keys work
  ;; natively.  Press s-m to toggle meow on for IJKL movement.
  (add-hook 'magit-mode-hook (lambda () (meow-mode -1)))


  (defun jb-magit-open-repo ()
    "Open the remote origin repo URL in a browser."
    (interactive)
    (if-let ((url (magit-get "remote" "origin" "url")))
        (browse-url (jb-parse-git-remote-url url))
      (user-error "No remote.origin.url configured")))

  (defun jb-magit-open-pr ()
    "Open the PR for the current branch, or create one if none exists.
Uses `gh' for GitHub/GHE remotes, `fj' for Forgejo/Codeberg."
    (interactive)
    (let ((toplevel (magit-toplevel)))
      (unless toplevel
        (user-error "Not in a git repository"))
      (let* ((default-directory toplevel)
             (process-environment
              (cons (concat "BROWSER=" (expand-file-name "~/bin/opener-open"))
                    process-environment))
             (buf (generate-new-buffer " *gh-output*")))
        (unwind-protect
            (let ((rc (call-process "gh" nil buf nil
                                    "pr" "view" "--web")))
              (if (= rc 0)
                  nil
                (let ((output (with-current-buffer buf (buffer-string))))
                  (if (string-match-p "none of the git remotes" output)
                      (call-process "fj" nil nil nil "pr" "create" "--web")
                    (call-process "gh" nil nil nil "pr" "create" "--web")))))
          (kill-buffer buf)))))

  (define-key magit-status-mode-map (kbd "o") #'jb-magit-open-repo)
  (define-key magit-status-mode-map (kbd "O") #'jb-magit-open-pr))

;; difftastic: structural diffs (via difft CLI) inside Emacs.
;; Integrates with magit-diff, magit-blame, and dired.
(use-package difftastic
  :ensure t
  :defer t)

(use-package difftastic-bindings
  :ensure nil
  :after difftastic
  :config (difftastic-bindings-mode))

;; diff-hl: highlight uncommitted changes in the gutter.
(defun jb-diff-hl-highlight-inline (ovl type _shape)
  "Highlight OVL with a colored indicator at the right edge of the left margin.
TYPE is one of `insert', `delete', `change', etc.  The indicator
is placed in the left margin via a `display' spec, but padded
with spaces so it sits at the rightmost column — immediately
adjacent to the buffer text.  This keeps it visually attached to
olivetti-centered text instead of appearing at column 0."
  (let* ((face (intern (format "diff-hl-%s" type)))
         (margin-width (or (car (window-margins)) 0)))
    (when (< margin-width 2)
      (setq margin-width 2))
    (let* ((padding (propertize (make-string (max 0 (- margin-width 2)) ?\s) 'face 'default))
           (gap (propertize " " 'face 'default))
           (indicator (concat padding (propertize "▎" 'face face) gap)))
      (overlay-put ovl 'before-string
                   (propertize " " 'display
                               `((margin left-margin) ,indicator))))))

(defun jb-diff-hl-ensure-margin ()
  "Ensure a minimum 2-column left margin exists for diff-hl indicators.
Olivetti provides large margins when active; this covers the case
when it is not."
  (when (and diff-hl-mode (< (or left-margin-width 0) 2))
    (setq-local left-margin-width 2)
    ;; Force the window to pick up the new margin width.
    (dolist (win (get-buffer-window-list nil nil t))
      (set-window-buffer win (current-buffer)))))

(defun jb-diff-hl-update-on-window-change ()
  "Re-apply diff-hl margins and refresh overlays after a window change.
Ensures the margin indicator padding stays correct when olivetti
recalculates margins for a new window geometry."
  (when (bound-and-true-p diff-hl-mode)
    (jb-diff-hl-ensure-margin)
    (diff-hl-update)))

(defun jb-diff-hl-on-enable ()
  "Register or deregister the window-change hook for diff-hl."
  (if diff-hl-mode
      (add-hook 'window-configuration-change-hook
                #'jb-diff-hl-update-on-window-change nil t)
    (remove-hook 'window-configuration-change-hook
                 #'jb-diff-hl-update-on-window-change t)))

(use-package diff-hl
  :ensure t
  :commands (diff-hl-mode
             global-diff-hl-mode
             diff-hl-flydiff-mode)
  :hook ((prog-mode . diff-hl-mode)
         (magit-post-refresh . diff-hl-magit-post-refresh)
         (diff-hl-mode . jb-diff-hl-ensure-margin)
         (diff-hl-mode . jb-diff-hl-on-enable))
  :init
  (setq diff-hl-flydiff-delay 0.4)
  (setq diff-hl-show-staged-changes nil)
  (setq diff-hl-update-async t)
  (setq diff-hl-global-modes '(not pdf-view-mode image-mode))
  (setq diff-hl-highlight-function #'jb-diff-hl-highlight-inline)
  :config
  (diff-hl-flydiff-mode 1))

;;; ============================================================================
;;; Snippets
;;; ============================================================================

;; yasnippet-snippets: official collection of snippets.
;; Declared before yasnippet so it's available when yas-global-mode loads.
(use-package yasnippet-snippets
  :ensure t
  :after yasnippet)

;; YASnippet: template expansion system.
(use-package yasnippet
  :ensure t
  :commands (yas-minor-mode
             yas-global-mode)
  :hook (elpaca-after-init . yas-global-mode)
  :custom
  (yas-also-auto-indent-first-line t)
  (yas-also-indent-empty-lines t)
  (yas-snippet-revival nil)
  (yas-wrap-around-region nil)
  :init
  (setq yas-verbosity 0))

;;; ============================================================================
;;; Tree-sitter
;;; ============================================================================

;; treesit-auto: keep the package for grammar installation only.
;; `global-treesit-auto-mode' is intentionally disabled because
;; `treesit-auto--ready-p' runs on every `find-file' and takes ~1.8s
;; per call (known issue: treesit-auto#135).  Instead, remap modes
;; manually via `major-mode-remap-alist'.
(use-package treesit-auto
  :ensure t
  :custom
  (treesit-auto-install 'prompt))

(setq major-mode-remap-alist
      '((python-mode    . python-ts-mode)
        (json-mode      . json-ts-mode)
        (sh-mode        . bash-ts-mode)
        (css-mode       . css-ts-mode)
        (yaml-mode      . yaml-ts-mode)
        (toml-mode      . toml-ts-mode)))

;; kdl-mode: major mode for KDL document language files (.kdl).
;; Uses tree-sitter for highlighting (auto-installs grammar), derives from
;; prog-mode so auto-olivetti picks it up.
(use-package kdl-mode
  :ensure t)

;;; ============================================================================
;;; Code navigation
;;; ============================================================================

;; dumb-jump: jump-to-definition using ripgrep/grep heuristics.
;; Falls back gracefully when no LSP is available.
(use-package dumb-jump
  :ensure t
  :commands dumb-jump-xref-activate
  :init
  (add-hook 'xref-backend-functions #'dumb-jump-xref-activate 90)
  (setq dumb-jump-aggressive nil)
  (setq dumb-jump-max-find-time 3)
  (setq dumb-jump-selector 'completing-read)
  (when (executable-find "rg")
    (setq dumb-jump-force-searcher 'rg)
    (setq dumb-jump-prefer-searcher 'rg)))

;;; ============================================================================
;;; Session & buffer management
;;; ============================================================================

;; Kill the current buffer immediately instead of prompting.
(keymap-global-set "C-x k" #'kill-current-buffer)

;; easysession: persist and restore file buffers, indirect buffers/clones,
;; Dired buffers, windows/splits, tab-bar state, and frames across sessions.
;;
;; Forward-declare dynamic variables referenced in `let' bindings below so the
;; byte/native compiler knows they are special *before* easysession is loaded.
(defvar easysession-confirm-new-session t
  "Non-nil prompts the user for confirmation when creating a new session.")
(defvar easysession--current-session-name nil)

(use-package easysession
  :ensure t
  :commands (easysession-switch-to
             easysession-save-mode
             easysession-load
             easysession-load-including-geometry
             easysession-set-current-session-name)

  :custom
  (easysession-mode-line-misc-info t)    ; Display session name in modeline
  (easysession-save-interval (* 10 60))  ; Save every 10 minutes

  :init

  ;; Track previous session for quick toggling
  (defvar easysession-previous-session nil
    "Name of the previously visited easysession.")

  (defun easysession-switch-to-previous ()
    "Switch to the previous easysession."
    (interactive)
    (if easysession-previous-session
        (easysession-switch-to easysession-previous-session)
      (user-error "No previous session")))

  (defun jb-easysession-delete-all (&optional force)
    "Delete all easysession sessions, including the current one.
When FORCE is non-nil, skip the confirmation prompt."
    (interactive)
    ;; Unload saves the current session then clears in-memory state.
    (easysession-unload)
    (let ((sessions (easysession--get-all-names)))
      (unless sessions
        (user-error "No easysession sessions found"))
      (when (or force
                (yes-or-no-p
                 (format "Delete ALL %d easysession sessions? " (length sessions))))
        (easysession-delete sessions)
        (setq easysession-previous-session nil)
        (message "Deleted %d easysession sessions." (length sessions)))))

  (define-advice easysession-switch-to (:before (&rest _) track-previous)
    "Stash current session name before switching."
    (when-let ((name (easysession-get-session-name)))
      (setq easysession-previous-session name)))

  ;; Key mappings (C-c e prefix)
  (global-set-key (kbd "C-c e s") #'easysession-save)
  (global-set-key (kbd "C-c e l") #'easysession-switch-to)
  (global-set-key (kbd "C-c e L") #'easysession-switch-to-and-restore-geometry)
  (global-set-key (kbd "C-c e p") #'easysession-switch-to-previous)
  (global-set-key (kbd "C-c e r") #'easysession-rename)
  (global-set-key (kbd "C-c e R") #'easysession-reset)
  (global-set-key (kbd "C-c e d") #'easysession-delete)
  (global-set-key (kbd "C-c e D") #'jb-easysession-delete-all)

  (defun jb-restart-emacs-daemon ()
    "Save the current easysession and restart the Emacs daemon.
On Linux, restarts via systemd.  On macOS, restarts via launchctl."
    (interactive)
    (when (y-or-n-p "Restart Emacs daemon? All frames will be closed. ")
      (when (easysession-get-session-name)
        (easysession-save))
      (if (eq system-type 'darwin)
          (start-process "restart-emacs" nil "bash" "-c"
                         "launchctl kickstart -k gui/$(id -u)/org.nix-community.home.emacs-daemon")
        (start-process "restart-emacs" nil "systemctl" "--user" "restart" "emacs-daemon"))))

  (global-set-key (kbd "C-c g d") #'jb-restart-emacs-daemon)

  ;; easysession-setup: auto-load last session on startup (or first
  ;; emacsclient frame in daemon mode), and enable periodic saving.
  (add-hook 'elpaca-after-init-hook
            (lambda ()
              (easysession-setup))
            95))

;; easysession-scratch: persist *scratch* buffer contents across sessions.
(use-package easysession-scratch
  :ensure nil
  :after easysession
  :config
  (easysession-scratch-mode 1))

;; buffer-terminator: automatically kill inactive buffers to keep the
;; buffer list clean and reduce resource usage.
(use-package buffer-terminator
  :ensure t
  :custom
  (buffer-terminator-verbose nil)
  (buffer-terminator-inactivity-timeout (* 30 60)) ; 30 minutes
  (buffer-terminator-interval (* 10 60))           ; 10 minutes
  :config
  (buffer-terminator-mode 1))

;;; ============================================================================
;;; Formatting
;;; ============================================================================

;; format-all: auto-format buffers on save using external tools.
;; Used for languages where the LSP server does not provide formatting
;; (Python via basedpyright, Racket, Emacs Lisp).  Languages with LSP
;; formatting (Go, Terraform, Typst) keep using eglot-format-buffer.
(use-package format-all
  :ensure t
  :commands (format-all-mode
             format-all-ensure-formatter
             format-all-buffer)
  :hook ((python-ts-mode . format-all-mode)
         (racket-mode . format-all-mode)
         (emacs-lisp-mode . format-all-mode))
  :config
  (setq-default format-all-formatters
                '(("Python" ruff)
                  ("Racket" raco-fmt)
                  ("Emacs Lisp" emacs-lisp))))

;;; ============================================================================
;;; Languages
;;; ============================================================================

;;; Eglot workspace configuration (global, all languages).
;;; gopls: enable staticcheck linting and auto-complete unimported packages.
;;; basedpyright: default settings (works well out of the box).

(with-eval-after-load 'eglot
  ;; Register basedpyright as the Python LSP server.
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode)
                 . ("basedpyright-langserver" "--stdio")))

  ;; Register terraform-ls as the LSP server for terraform-mode.
  (add-to-list 'eglot-server-programs
               '(terraform-mode . ("terraform-ls" "serve")))

  ;; Register tinymist as the Typst LSP server.
  ;; initializationOptions are required so that formatterMode is set
  ;; before the first workspace/didChangeConfiguration clobbers it.
  (add-to-list 'eglot-server-programs
               '(typst-ts-mode . ("tinymist" "lsp"
                                  :initializationOptions
                                  (:formatterMode "typstyle"
                                                  :formatterPrintWidth 80))))

  ;; Register nixd as the Nix LSP server.
  (add-to-list 'eglot-server-programs
               '(nix-ts-mode . ("nixd")))

  ;; Register sourcekit-lsp as the Swift LSP server.
  (add-to-list 'eglot-server-programs
               '(swift-mode . ("xcrun" "sourcekit-lsp")))

  (add-hook 'eglot-managed-mode-hook (lambda () (eglot-inlay-hints-mode -1)))

  ;; Eldoc: single-line echo area by default; full docs on demand via C-c d.
  ;; Prevents the echo area from resizing and the *eldoc* buffer from
  ;; stealing windows.  Press C-c d to open the full documentation buffer
  ;; when the one-liner isn't enough.
  (setq eldoc-echo-area-use-multiline-p nil)
  (global-set-key (kbd "C-c d") #'eldoc-doc-buffer)

  ;; Pin the *eldoc* buffer to the bottom of the frame so it never
  ;; hijacks an existing code window.
  (add-to-list 'display-buffer-alist
               '("^\\*eldoc for" display-buffer-at-bottom))

  ;; Disable the JSONRPC events buffer to avoid logging overhead.
  (setq eglot-events-buffer-size 0)

  ;; Workspace configuration: dispatched per-server.
  ;; tinymist's workspace/didChangeConfiguration handler calls
  ;; `update_by_map' (not `update'), which does NOT unwrap a
  ;; "tinymist" namespace.  We must therefore send flat keys for
  ;; tinymist while keeping the usual namespaced plist for other
  ;; servers.
  (setq-default eglot-workspace-configuration
                (lambda (server)
                  (let ((modes (mapcar #'car (eglot--languages server))))
                    (cond
                     ((memq 'typst-ts-mode modes)
                      '(:formatterMode "typstyle"
                                       :formatterPrintWidth 80))
                     ((or (memq 'go-ts-mode modes)
                          (memq 'go-mode modes)
                          (memq 'templ-ts-mode modes))
                      '(:gopls (:staticcheck t
                                             :completeUnimported t)))
                     ((or (memq 'python-ts-mode modes)
                          (memq 'python-mode modes))
                      '(:basedpyright.analysis (:typeCheckingMode "basic")))
                     (t nil))))))

;;; Go

;; Teach project.el to find go.mod as project root so Eglot scopes
;; the workspace correctly for Go modules.
(with-eval-after-load 'project
  (defun jb-project-find-go-module (dir)
    "Find the nearest parent directory containing go.mod."
    (when-let ((root (locate-dominating-file dir "go.mod")))
      (cons 'go-module root)))

  (cl-defmethod project-root ((project (head go-module)))
    (cdr project))

  (add-hook 'project-find-functions #'jb-project-find-go-module)

  ;; Project dispatch menu: shown after selecting a project via
  ;; `project-switch-project'.  Wire up consult-based commands so
  ;; the dispatch menu matches our C-x p keybindings.
  (setq project-switch-commands
        '((consult-project-extra-find "Find file" ?f)
          (consult-project-buffer "Buffer" ?b)
          (consult-ripgrep "Ripgrep" ?r)
          (project-find-dir "Find directory" ?d)
          (magit-project-status "Magit" ?m)
          (project-vc-dir "VC-Dir" ?v)
          (project-shell "Shell" ?s)
          (project-eshell "Eshell" ?e))))

;; go-ts-mode: tree-sitter based Go major mode (built-in).
;; Hooks: eglot for LSP, format + organize imports on save.
(use-package go-ts-mode
  :ensure nil
  :defer t
  :mode "\\.go\\'"
  :hook ((go-ts-mode . eglot-ensure))
  :config
  (setq go-ts-mode-indent-offset tab-width)
  (defun jb-go-before-save-hooks ()
    "Set up format-on-save and organize-imports-on-save for Go."
    (add-hook 'before-save-hook #'eglot-format-buffer -10 t)
    (add-hook 'before-save-hook
              (lambda ()
                (when (eglot-managed-p)
                  (call-interactively #'eglot-code-action-organize-imports)))
              nil t))
  (add-hook 'go-ts-mode-hook #'jb-go-before-save-hooks))

;;; Templ (Go HTML templating)

;; templ-ts-mode: tree-sitter based major mode for templ template files.
;; Provides syntax highlighting, indentation, and eglot integration
;; with the templ LSP server (`templ lsp`).  The package automatically
;; registers .templ in auto-mode-alist and eglot-server-programs.
(use-package templ-ts-mode
  :ensure t
  :defer t
  :mode "\\.templ\\'"
  :hook ((templ-ts-mode . eglot-ensure))
  :custom
  (templ-ts-mode-grammar-install 'auto)
  :config
  (defun jb-templ-before-save-hooks ()
    "Set up format-on-save for templ via eglot (templ lsp)."
    (add-hook 'before-save-hook #'eglot-format-buffer -10 t))
  (add-hook 'templ-ts-mode-hook #'jb-templ-before-save-hooks))

;;; Python

;; python-ts-mode: tree-sitter based Python major mode (built-in).
;; Hooks: eglot for LSP (basedpyright), compile-command for M-x compile.
;; Format-on-save via format-all (ruff) — see Formatting section above.
(use-package python
  :ensure nil
  :defer t
  :hook ((python-ts-mode . eglot-ensure))
  :config
  (defun jb-python-compile-command ()
    "Set compile-command to run the current Python file."
    (setq-local compile-command
                (concat "python3 "
                        (when buffer-file-name
                          (shell-quote-argument
                           (file-name-nondirectory buffer-file-name))))))
  (add-hook 'python-ts-mode-hook #'jb-python-compile-command))

;;; JSON

;; json-ts-mode: tree-sitter based JSON major mode (built-in).
;; treesit-auto handles auto-mode-alist and grammar installation.
;; Eglot has built-in server registration for vscode-json-language-server.
(use-package json-ts-mode
  :ensure nil
  :defer t
  :hook ((json-ts-mode . eglot-ensure))
  :custom
  (json-ts-mode-indent-offset 2))

;;; Terraform

;; terraform-mode: major mode for Terraform/HCL configuration files.
;; Provides syntax highlighting, indentation, and imenu.
;; hcl-mode is pulled in automatically as a dependency.
(use-package terraform-mode
  :ensure t
  :defer t
  :hook ((terraform-mode . eglot-ensure))
  :custom
  (terraform-indent-level 2)
  (terraform-format-on-save nil)
  :config
  (defun jb-terraform-before-save-hooks ()
    "Set up format-on-save for Terraform via eglot (terraform-ls)."
    (add-hook 'before-save-hook #'eglot-format-buffer -10 t))
  (add-hook 'terraform-mode-hook #'jb-terraform-before-save-hooks))

;;; Nix

;; nix-ts-mode: tree-sitter based major mode for Nix expressions.
;; Provides syntax highlighting and indentation via tree-sitter-nix.
;; LSP provided by nixd via eglot; formatting via nixfmt (eglot).
(use-package nix-ts-mode
  :ensure t
  :defer t
  :mode "\\.nix\\'"
  :hook ((nix-ts-mode . eglot-ensure))
  :config
  (defun jb-nix-before-save-hooks ()
    "Set up format-on-save for Nix via eglot (nixd/nixfmt)."
    (add-hook 'before-save-hook #'eglot-format-buffer -10 t))
  (add-hook 'nix-ts-mode-hook #'jb-nix-before-save-hooks))

;;; Swift

;; swift-mode: major mode for Swift source files.
;; Provides syntax highlighting, indentation, imenu, and REPL support.
;; LSP provided by sourcekit-lsp via eglot; formatting on save via eglot.
(use-package swift-mode
  :ensure t
  :defer t
  :mode "\\.swift\\'"
  :hook ((swift-mode . eglot-ensure))
  :config
  (defun jb-swift-before-save-hooks ()
    "Set up format-on-save for Swift via eglot (sourcekit-lsp)."
    (add-hook 'before-save-hook #'eglot-format-buffer -10 t))
  (add-hook 'swift-mode-hook #'jb-swift-before-save-hooks))

;;; Markdown

;; markdown-mode: syntax highlighting, editing commands, and preview for
;; Markdown documents.  Also provides faces used by punct highlighting.
(use-package markdown-mode
  :ensure t
  :commands (gfm-mode
             gfm-view-mode
             markdown-mode
             markdown-view-mode)
  :mode (("\\.markdown\\'" . markdown-mode)
         ("\\.md\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :bind
  (:map markdown-mode-map
        ("C-c C-e" . markdown-do)))

;;; Racket

;; Helper functions defined before use-package forms so they are
;; available immediately at init time, avoiding Elpaca's deferred
;; evaluation race condition where hooks fire before the use-package
;; body has been evaluated.

(defun jb-insert-lisp-section (section)
  "Insert a Lisp section header comment for SECTION at point.
Produces a line like: ;; Foo ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;"
  (interactive "sSection: ")
  (let ((suffix (make-string (max 0 (- 72 (length section) 4)) ?\;)))
    (insert (format ";; %s %s\n" section suffix))))

(defun jb-racket-mode-hook ()
  "Set up Flymake with the raco-review backend for Racket buffers."
  (add-hook 'flymake-diagnostic-functions #'jb-flymake-racket-review nil t)
  (flymake-mode 1))

;; Register hooks immediately — these run at init time, before Elpaca
;; processes its queue, so they're in place when racket-mode activates.
(add-hook 'racket-mode-hook #'jb-racket-mode-hook)
(add-hook 'racket-mode-hook #'racket-xp-mode)
(add-hook 'racket-hash-lang-mode-hook #'racket-xp-mode)


;; Punct (.punct) markdown highlighting for racket-hash-lang-mode.
;;
;; Punct files are CommonMark markdown with inline Racket via #lang punct.
;; racket-hash-lang-mode provides Racket back-end integration but its
;; color-lexer treats prose as undifferentiated text.  We layer markdown
;; font-lock keywords on top so headings, bold, italic, links, etc. are
;; visually highlighted while keeping full Racket tooling.
;;
;; This works because racket-hash-lang-mode explicitly supports
;; font-lock-add-keywords: it applies back-end token faces first (setting
;; syntax-table properties for comments/strings), then runs
;; font-lock-fontify-keywords-region for any added keyword rules.

(defvar jb-punct-markdown-keywords
  '(;; YAML front matter: --- delimiters and key: value pairs
    ("^---$" 0 'markdown-markup-face prepend)
    ("^\\([[:alpha:]][[:alnum:]_-]*\\):\\s-+\\(.*\\)$"
     (1 'markdown-metadata-key-face prepend)
     (2 'markdown-metadata-value-face prepend))

    ;; ATX headings: # through ######
    ;; Ordered long-to-short so ###### matches before #.
    ("^\\(######\\)\\s-+\\(.*\\)$"
     (1 'markdown-header-delimiter-face prepend)
     (2 'markdown-header-face-6 prepend))
    ("^\\(#####\\)\\s-+\\(.*\\)$"
     (1 'markdown-header-delimiter-face prepend)
     (2 'markdown-header-face-5 prepend))
    ("^\\(####\\)\\s-+\\(.*\\)$"
     (1 'markdown-header-delimiter-face prepend)
     (2 'markdown-header-face-4 prepend))
    ("^\\(###\\)\\s-+\\(.*\\)$"
     (1 'markdown-header-delimiter-face prepend)
     (2 'markdown-header-face-3 prepend))
    ("^\\(##\\)\\s-+\\(.*\\)$"
     (1 'markdown-header-delimiter-face prepend)
     (2 'markdown-header-face-2 prepend))
    ("^\\(#\\)\\s-+\\(.*\\)$"
     (1 'markdown-header-delimiter-face prepend)
     (2 'markdown-header-face-1 prepend))

    ;; Horizontal rules: three or more -, *, or _ (possibly spaced)
    ("^\\s-*\\([-*_]\\s-*\\)\\{3,\\}$" 0 'markdown-hr-face prepend)

    ;; Blockquotes: > at start of line
    ("^\\s-*\\(>\\)\\s-?\\(.*\\)$"
     (1 'markdown-markup-face prepend)
     (2 'markdown-blockquote-face prepend))

    ;; Unordered list markers: -, *, + at start of line
    ("^\\s-*\\([-*+]\\)\\s-+" 1 'markdown-list-face prepend)
    ;; Ordered list markers: 1. 2. etc.
    ("^\\s-*\\([0-9]+\\.\\)\\s-+" 1 'markdown-list-face prepend)

    ;; Fenced code block delimiters: ``` or ~~~
    ;; Captures optional language identifier separately.
    ("^\\s-*\\(```\\|~~~\\)\\([[:alpha:]][[:alnum:]_+-]*\\)?\\s-*$"
     (1 'markdown-markup-face prepend)
     (2 'markdown-language-keyword-face prepend t))

    ;; Inline code: `code`
    ("\\(`\\)\\([^`\n]+?\\)\\(`\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-inline-code-face prepend)
     (3 'markdown-markup-face prepend))

    ;; Bold: **text** or __text__
    ("\\(\\*\\*\\)\\([^*\n]+?\\)\\(\\*\\*\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-bold-face prepend)
     (3 'markdown-markup-face prepend))
    ("\\(__\\)\\([^_\n]+?\\)\\(__\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-bold-face prepend)
     (3 'markdown-markup-face prepend))

    ;; Italic: *text* or _text_ (but not ** or __)
    ("\\(?:^\\|[^*]\\)\\(\\*\\)\\([^*\n]+?\\)\\(\\*\\)\\(?:[^*]\\|$\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-italic-face prepend)
     (3 'markdown-markup-face prepend))
    ("\\(?:^\\|[^_]\\)\\(_\\)\\([^_\n]+?\\)\\(_\\)\\(?:[^_]\\|$\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-italic-face prepend)
     (3 'markdown-markup-face prepend))

    ;; Strikethrough: ~~text~~
    ("\\(~~\\)\\([^~\n]+?\\)\\(~~\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-strike-through-face prepend)
     (3 'markdown-markup-face prepend))

    ;; Links: [text](url) with optional "title"
    ("\\(\\[\\)\\([^]\n]*\\)\\(\\]\\)(\\([^)\" \t\n]*\\)\\(?:\\s-+\"\\([^\"]*\\)\"\\)?)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-link-face prepend)
     (3 'markdown-markup-face prepend)
     (4 'markdown-url-face prepend)
     (5 'markdown-link-title-face prepend t))

    ;; Images: ![alt](url) with optional "title"
    ("\\(!\\[\\)\\([^]\n]*\\)\\(\\]\\)(\\([^)\" \t\n]*\\)\\(?:\\s-+\"\\([^\"]*\\)\"\\)?)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-link-face prepend)
     (3 'markdown-markup-face prepend)
     (4 'markdown-url-face prepend)
     (5 'markdown-link-title-face prepend t))

    ;; Reference links: [text][ref]
    ("\\(\\[\\)\\([^]\n]*\\)\\(\\]\\)\\(\\[\\)\\([^]\n]*\\)\\(\\]\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-link-face prepend)
     (3 'markdown-markup-face prepend)
     (4 'markdown-markup-face prepend)
     (5 'markdown-reference-face prepend)
     (6 'markdown-markup-face prepend))

    ;; Reference definitions: [ref]: url "title"
    ("^\\s-*\\(\\[\\)\\([^]\n]+\\)\\(\\]\\):\\s-+\\(\\S-+\\)\\(?:\\s-+\"\\([^\"]*\\)\"\\)?$"
     (1 'markdown-markup-face prepend)
     (2 'markdown-reference-face prepend)
     (3 'markdown-markup-face prepend)
     (4 'markdown-url-face prepend)
     (5 'markdown-link-title-face prepend t))

    ;; Footnote markers: [^label]
    ("\\(\\[\\^\\)\\([^]\n]+\\)\\(\\]\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-footnote-marker-face prepend)
     (3 'markdown-markup-face prepend))

    ;; GFM tables: lines with | delimiters
    ("^\\s-*|.*|\\s-*$" 0 'markdown-table-face prepend)

    ;; HTML comments: <!-- ... -->
    ("\\(<!--\\)\\(\\(?:.\\|\n\\)*?\\)\\(-->\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-comment-face prepend)
     (3 'markdown-markup-face prepend))

    ;; Angle-bracket URLs: <http://...>
    ("\\(<\\)\\(https?://[^>\n]+\\)\\(>\\)"
     (1 'markdown-markup-face prepend)
     (2 'markdown-plain-url-face prepend)
     (3 'markdown-markup-face prepend))

    ;; Backslash escapes: \* \[ \] etc.
    ("\\(\\\\\\)[\\\\`*_{}\\[\\]()#+.!~|>-]"
     1 'markdown-markup-face prepend)

    ;; Task list checkboxes: - [ ] or - [x] or - [X]
    ("^\\s-*[-*+]\\s-+\\(\\[[ xX]\\]\\)"
     1 'markdown-gfm-checkbox-face prepend)

    ;; Punct inline Racket: •(...) — highlight the bullet marker
    ("\\(•\\)" 1 'markdown-markup-face prepend))
  "Font-lock keywords for CommonMark constructs in Punct files.
Uses `prepend' so markdown faces override the back-end's `text' token
face while respecting syntax-table properties that prevent matches
inside comments and strings.")

(defun jb-punct-hash-lang-hook (module-language)
  "Add or remove markdown font-lock keywords based on MODULE-LANGUAGE.
When the hash-lang is punct, layer CommonMark highlighting on top of
racket-hash-lang-mode's token-based fontification."
  (if (or (and (stringp module-language)
               (string-match-p "punct" module-language))
          ;; Fallback: detect via buffer file extension when the lang
          ;; doesn't supply module-language info.
          (and (null module-language)
               buffer-file-name
               (string-match-p "\\.punct\\'" buffer-file-name)))
      (progn
        (require 'markdown-mode)
        (font-lock-add-keywords nil jb-punct-markdown-keywords 'append)
        (font-lock-flush))
    ;; Non-punct lang: remove markdown keywords if present.
    (font-lock-remove-keywords nil jb-punct-markdown-keywords)
    (font-lock-flush)))

(add-hook 'racket-hash-lang-module-language-hook #'jb-punct-hash-lang-hook)

;; rainbow-delimiters: colorize nested delimiters for visual depth cues.
(use-package rainbow-delimiters
  :ensure t
  :hook ((racket-mode racket-hash-lang-mode emacs-lisp-mode) . rainbow-delimiters-mode))

;; Flymake backend for raco review: lint Racket source files.
(defvar-local jb-flymake-racket-review--proc nil
  "The running raco-review process for the current buffer, if any.")

(defun jb-flymake-racket-review (report-fn &rest _args)
  "Flymake backend that runs `raco review' on the current file.
REPORT-FN is the Flymake callback for reporting diagnostics."
  (unless (executable-find "raco")
    (error "Cannot find `raco' on exec-path"))
  (let ((source (current-buffer))
        (filename (buffer-file-name)))
    (when filename
      ;; Kill any previous running process.
      (when (process-live-p jb-flymake-racket-review--proc)
        (kill-process jb-flymake-racket-review--proc))
      (setq jb-flymake-racket-review--proc
            (make-process
             :name "flymake-racket-review"
             :noquery t
             :connection-type 'pipe
             :buffer (generate-new-buffer " *flymake-racket-review*")
             :command (list "raco" "review" filename)
             :sentinel
             (lambda (proc _event)
               (when (memq (process-status proc) '(exit signal))
                 (unwind-protect
                     (if (with-current-buffer source
                           (eq proc jb-flymake-racket-review--proc))
                         (with-current-buffer (process-buffer proc)
                           (goto-char (point-min))
                           (let ((diags nil))
                             (while (search-forward-regexp
                                     "^.+?:\\([0-9]+\\):\\([0-9]+\\):\\(error\\|warning\\):\\(.*\\)$"
                                     nil t)
                               (let* ((line (string-to-number (match-string 1)))
                                      (col (string-to-number (match-string 2)))
                                      (severity (match-string 3))
                                      (msg (string-trim (match-string 4)))
                                      (type (if (string= severity "error") :error :warning))
                                      (region (flymake-diag-region source line col)))
                                 (when region
                                   (push (flymake-make-diagnostic
                                          source (car region) (cdr region) type msg)
                                         diags))))
                             ;; Non-zero exit with no diagnostics: tool error.
                             (when (and (not diags)
                                        (not (zerop (process-exit-status proc)))
                                        (not (eq (process-status proc) 'signal)))
                               (goto-char (point-min))
                               (funcall report-fn :panic
                                        :explanation
                                        (buffer-substring
                                         (point-min)
                                         (min (point-max)
                                              (line-end-position)))))
                             (unless (eq (process-status proc) 'signal)
                               (funcall report-fn diags))))
                       (flymake-log :warning "Canceling obsolete raco review check %s" proc))
                   (kill-buffer (process-buffer proc))))))))))

;; racket-hash-lang: major mode for Racket hash-lang files (.rhm, .scrbl, .punct).
(use-package racket-hash-lang
  :ensure (racket-mode :host github :repo "greghendershott/racket-mode")
  :defer t
  :mode (("\\.rhm\\'" . racket-hash-lang-mode)
         ("\\.scrbl\\'" . racket-hash-lang-mode)
         ("\\.punct\\'" . racket-hash-lang-mode))
  :bind (:map racket-hash-lang-mode-map
              ("C-c C-d" . racket-xp-describe)
              ("C-c C-r" . racket-xp-rename)
              ("C-c ."   . xref-find-definitions)
              ("C-c ,"   . xref-go-back)))

;; racket-mode: major mode for Racket source files.
(use-package racket-mode
  :ensure nil
  :defer t
  :mode (("\\.rkt\\'" . racket-mode))
  :config
  (setq racket-repl-buffer-name-function #'racket-repl-buffer-name-project
        racket-show-functions '(racket-show-echo-area))
  :bind (:map racket-mode-map
              ("C-c C-d" . racket-xp-describe)
              ("C-c C-r" . racket-xp-rename)
              ("C-c C-s" . jb-insert-lisp-section)
              ("C-c r t" . racket-tidy-requires)
              ("C-c r i" . racket-add-require-for-identifier)
              ("C-c ."   . xref-find-definitions)
              ("C-c ,"   . xref-go-back)))

;; racket-xp-mode: cross-reference and analysis annotations.
;; Hooks registered above via standalone add-hook calls.
(use-package racket-xp
  :ensure nil
  :defer t)

;;; Typst

;; typst-ts-mode: tree-sitter based major mode for Typst documents.
;; Provides syntax highlighting, indentation, imenu, and raw block
;; highlighting.  LSP provided by tinymist via eglot.
(use-package typst-ts-mode
  :ensure (:host codeberg :repo "meow_king/typst-ts-mode")
  :defer t
  :mode "\\.typ\\'"
  :hook ((typst-ts-mode . eglot-ensure))
  :custom
  (typst-ts-mode-enable-raw-blocks-highlight t)
  :config
  (defun jb-typst-before-save-hooks ()
    "Set up format-on-save for Typst via eglot (tinymist/typstyle)."
    (add-hook 'before-save-hook #'eglot-format-buffer -10 t))
  (add-hook 'typst-ts-mode-hook #'jb-typst-before-save-hooks))

;; typst-preview: live preview of Typst documents via tinymist.
;; Fixed ports allow SSH port forwarding so the preview can be viewed
;; in a local browser while editing remotely in terminal Emacs.
;; Forward the data-plane port: ssh -L 23625:127.0.0.1:23625 remote-host
;; Then open http://localhost:23625 in your local browser.
(use-package typst-preview
  :ensure t
  :custom
  (typst-preview-open-browser-automatically nil)
  :init
  ;; The upstream package hardcodes random ports (127.0.0.1:0) for the
  ;; --host, --data-plane-host, and --control-plane-host flags, and
  ;; tinymist rejects duplicate flags.  This advice rewrites the
  ;; hardcoded values to fixed ports so we can set up SSH port
  ;; forwarding in advance.  Placed in :init so the advice is active
  ;; before typst-preview-start is ever called.
  (defvar jb-typst-preview-data-plane-host "127.0.0.1:23625"
    "Fixed data-plane host:port for typst-preview SSH forwarding.")
  (defvar jb-typst-preview-control-plane-host "127.0.0.1:23626"
    "Fixed control-plane host:port for typst-preview SSH forwarding.")

  (define-advice start-process (:filter-args (args) jb-typst-preview-fixed-ports)
    "Rewrite typst-preview process args to use fixed ports.
Also remove the deprecated --host flag so tinymist does not start a
redundant static file server on a random port."
    (when (string= (car args) "typst-preview-proc")
      (let ((result nil)
            (rest (cddr args)))
        ;; Walk the CLI args, dropping --host and its value, rewriting
        ;; --data-plane-host and --control-plane-host values.
        (while rest
          (cond
           ((string= (car rest) "--host")
            (setq rest (cddr rest)))           ; skip flag + value
           ((string= (car rest) "--data-plane-host")
            (push (pop rest) result)           ; keep flag
            (push jb-typst-preview-data-plane-host result) ; replace value
            (pop rest))                        ; skip original value
           ((string= (car rest) "--control-plane-host")
            (push (pop rest) result)           ; keep flag
            (push jb-typst-preview-control-plane-host result)
            (pop rest))
           (t
            (push (pop rest) result))))
        (setq args (append (list (car args) (cadr args)) (nreverse result)))))
    args))

;;; Org-mode live preview: impatient-mode + simple-httpd.
;; M-x jb-org-preview-start, then http://localhost:8080/imp/live/<buffer>/
;; SSH forwarding: ssh -L 8080:127.0.0.1:8080 remote-host

(use-package simple-httpd
  :ensure t
  :defer t
  :custom
  (httpd-port 8080)
  (httpd-host 'local))

(use-package htmlize
  :ensure t
  :defer t)

(use-package impatient-mode
  :ensure t
  :defer t
  :init
  (defun jb-org-impatient-filter (buffer)
    "Export BUFFER as Org HTML for impatient-mode browser preview."
    (let ((html (with-current-buffer buffer
                  (org-export-as 'html nil nil t))))
      (princ html (current-buffer))))

  (defun jb-org-preview-start ()
    "Start a live HTML preview of the current Org buffer in a browser."
    (interactive)
    (unless (derived-mode-p 'org-mode)
      (user-error "Not an Org buffer"))
    (httpd-start)
    (impatient-mode 1)
    (setq-local impatient-mode-delay 1)
    (imp-set-user-filter #'jb-org-impatient-filter)
    (message "Org preview: http://localhost:%d/imp/live/%s/"
             httpd-port (url-hexify-string (buffer-name))))

  (defun jb-org-preview-stop ()
    "Stop the live HTML preview for the current Org buffer."
    (interactive)
    (impatient-mode -1)
    (message "Org preview stopped.")))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-v h") #'jb-org-preview-start))

;;; ============================================================================
;;; AI: OpenCode agent interface
;;; ============================================================================

;; agent-shell: native Emacs buffer to interact with LLM agents via ACP.
;; Used here with the OpenCode agent (`opencode acp`).
;; Dependencies (shell-maker, acp) are pulled automatically from MELPA.
(use-package agent-shell
  :ensure t
  :ensure-system-package
  (claude-agent-acp . "npm install -g @zed-industries/claude-agent-acp")
  :commands (agent-shell
             agent-shell-opencode-start-agent
             agent-shell-anthropic-start-agent
             agent-shell-send-region
             agent-shell-send-current-file)
  :bind (("C-c a a" . agent-shell)
         ("C-c a c" . agent-shell-opencode-start-agent)
         ("C-c a A" . agent-shell-anthropic-start-agent))
  :custom
  (agent-shell-opencode-authentication
   (agent-shell-opencode-make-authentication :none t))
  (agent-shell-anthropic-authentication
   (agent-shell-anthropic-make-authentication :login t))
  (agent-shell-anthropic-default-model-id "claude-opus-4-6")
  (agent-shell-preferred-agent-config
   (agent-shell-anthropic-make-claude-code-config))
  :config
  (defun my/agent-shell-send-file-fallback (orig-fn &optional prompt-for-file pick-shell)
    "Fall back to `read-file-name' when no project files are available."
    (if (and (or (derived-mode-p 'agent-shell-mode) prompt-for-file)
             (not (agent-shell--project-files)))
        (let* ((file (read-file-name "Send file: "))
               (shell-buffer (when pick-shell
                               (completing-read "Send file to shell: "
                                                (mapcar #'buffer-name
                                                        (or (agent-shell-buffers)
                                                            (user-error "No shells available")))
                                                nil t))))
          (agent-shell-insert :text (agent-shell--get-files-context :files (list file))
                              :shell-buffer shell-buffer))
      (funcall orig-fn prompt-for-file pick-shell)))
  (advice-add 'agent-shell-send-file :around #'my/agent-shell-send-file-fallback))

;;; gptel: LLM client for Emacs — chat, rewrite, and query from any buffer.
;; Uses GitHub Copilot as the backend, providing access to Claude, GPT,
;; Gemini, and other models via your Copilot subscription.
;; First-time setup: M-x gptel-gh-login (authorizes via GitHub device flow).
(use-package gptel
  :ensure t
  :commands (gptel gptel-send gptel-menu gptel-rewrite gptel-gh-login)
  :bind (("C-c g g" . gptel)
         ("C-c g s" . gptel-send)
         ("C-c g m" . gptel-menu)
         ("C-c g w" . gptel-rewrite))
  :config
  (setq gptel-backend (gptel-make-gh-copilot "Copilot")
        gptel-model 'claude-opus-4.6
        gptel-stream t
        gptel-default-mode 'org-mode)

  ;; Auto-scroll the buffer as the LLM streams its response.
  (add-hook 'gptel-post-stream-hook 'gptel-auto-scroll)
  ;; Move cursor to the next prompt position after the response finishes.
  (add-hook 'gptel-post-response-functions 'gptel-end-of-response)
  ;; Org branching: each outline path is a separate conversation fork.
  (setq gptel-org-branching-context t))

;; gptel-agent: agentic tools and sub-agents for gptel.
;; Provides file read/write/edit, web search, Bash, and Emacs
;; introspection tools.  Use M-x gptel-agent for a dedicated session,
;; or include @gptel-agent in any prompt for one-shot agent capabilities.
;; Includes plan vs agent presets: gptel-plan (read-only, planning) and
;; gptel-agent (full read/write agent).  Switch via gptel's menu.
(use-package gptel-agent
  :ensure t
  :after gptel
  :commands (gptel-agent)
  :bind ("C-c g A" . gptel-agent)
  :config
  (gptel-agent-update))

;; plz: HTTP library required by opencode.el and its dependencies.
(use-package plz
  :ensure t)

;; opencode: native Emacs UI for the OpenCode AI coding agent.
;; Provides a comint-based chat interface, session management, project
;; scoping, diff review, and notification support — all inside Emacs
;; buffers rather than a TUI.  Connects to an opencode server via HTTP.
;; Dependencies (plz-media-type, plz-event-source) are pulled transitively.
(use-package opencode
  :ensure (:host codeberg :repo "sczi/opencode.el")
  :commands (opencode
             opencode-connect
             opencode-select-project
             opencode-new-session
             opencode-new-worktree
             opencode-select-idle
             opencode-visit-last-idle)
  :bind (("C-c a O" . opencode)
         ("C-c a P" . opencode-select-project)))

(with-eval-after-load 'gptel-agent-tools
  (defun gptel-agent--glob (pattern &optional path depth)
    "Find files matching PATTERN using the `tree' command.
Fixed version that includes --matchdirs so directories appear in results."
    (when (string-empty-p pattern)
      (error "Error: pattern must not be empty"))
    (if path
        (unless (and (file-readable-p path) (file-directory-p path))
          (error "Error: path %s is not readable" path))
      (setq path "."))
    (unless (executable-find "tree")
      (error "Error: Executable `tree` not found.  This tool cannot be used"))
    (let ((full-path (expand-file-name path)))
      (with-temp-buffer
        (let* ((args (list "-l" "-f" "-i" "-I" ".git"
                           "--sort=mtime" "--ignore-case"
                           "--prune" "--matchdirs" "-P" pattern full-path))
               (args (if (natnump depth)
                         (nconc args (list "-L" (number-to-string depth)))
                       args))
               (exit-code (apply #'call-process "tree" nil t nil args)))
          (when (/= exit-code 0)
            (goto-char (point-min))
            (insert (format "Glob failed with exit code %d\n.STDOUT:\n\n"
                            exit-code))))
        (when (> (buffer-size) 20000)
          (let* ((temp-dir (expand-file-name "gptel-agent-temp"
                                             (temporary-file-directory)))
                 (temp-file (expand-file-name
                             (format "glob-%s-%s.txt"
                                     (format-time-string "%Y%m%d-%H%M%S")
                                     (random 10000))
                             temp-dir)))
            (unless (file-directory-p temp-dir) (make-directory temp-dir t))
            (write-region nil nil temp-file)
            (let ((max-lines 50)
                  (orig-size (buffer-size))
                  (orig-lines (line-number-at-pos (point-max))))
              (goto-char (point-min))
              (insert (format "Glob results too large (%d chars, %d lines)\
 for context window.\nStored in: %s\n\nFirst %d lines:\n\n"
                              orig-size orig-lines temp-file max-lines))
              (forward-line max-lines)
              (delete-region (point) (point-max))
              (goto-char (point-max))
              (insert (format "\n\n[Use Read tool with file_path=\"%s\" to view full results]"
                              temp-file)))))
        (buffer-string)))))

;;; ============================================================================
;;; Load custom.el
;;; ============================================================================

;; Load custom.el after Elpaca has activated all packages.
(add-hook 'elpaca-after-init-hook
          (lambda () (load custom-file 'noerror 'no-message)))

;;; post-init.el ends here
