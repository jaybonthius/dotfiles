;;; gui-presentation.el --- GUI polish without changing TTY presentation -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'face-remap)
(require 'pixel-scroll)

(declare-function markdown-mode "markdown-mode" ())
(declare-function gfm-mode "markdown-mode" ())
(declare-function markdown-modern-mode "markdown-modern" ())
(declare-function org-superstar-mode "org-superstar" (&optional arg))
(declare-function org-modern-mode "org-modern" (&optional arg))
(declare-function org-modern-agenda "org-modern" ())
(declare-function org-agenda-redo-all "org-agenda" (&optional exhaustive))
(defvar org-modern-mode)
(defvar org-superstar-mode)

(defvar jb-gui-presentation-active nil)
(defvar-local jb-org-gui--remappings nil)
(defvar-local jb-org-gui--spacing nil)

(defun jb-gui-presentation-eligible-p (&optional departing-frame)
  "Use GUI styling only when live visible frames are exclusively graphical.
Ignore DEPARTING-FRAME during deletion.  Org properties are buffer-wide, so
TTY presentation takes precedence in a mixed GUI/TTY process.  A daemon's
invisible startup frame does not prevent graphical client presentation."
  (let ((frames (cl-remove-if
                 (lambda (frame)
                   (or (eq frame departing-frame)
                       (not (frame-visible-p frame))))
                 (frame-list))))
    (and frames (cl-every #'display-graphic-p frames))))

(define-minor-mode jb-org-gui-typography-mode
  "Give this Org buffer proportional prose and fixed-pitch technical text."
  :lighter nil
  (if jb-org-gui-typography-mode
      (unless jb-org-gui--remappings
        (setq jb-org-gui--spacing (cons (local-variable-p 'line-spacing) line-spacing))
        (setq-local line-spacing 0.15)
        ;; Reuse the platform's variable-pitch face; keep the owner's Fira Code
        ;; fixed-pitch face.  No new fonts or global face changes are needed.
        (push (face-remap-add-relative 'default 'variable-pitch) jb-org-gui--remappings)
        (dolist (face '(org-block org-code org-verbatim org-table org-formula
                       org-meta-line org-special-keyword org-property-value
                       org-drawer org-indent))
          (push (face-remap-add-relative face 'fixed-pitch) jb-org-gui--remappings)))
    (when jb-org-gui--remappings
      (mapc #'face-remap-remove-relative jb-org-gui--remappings)
      (setq jb-org-gui--remappings nil)
      (when (equal line-spacing 0.15)
        (if (car jb-org-gui--spacing)
            (setq-local line-spacing (cdr jb-org-gui--spacing))
          (kill-local-variable 'line-spacing)))
      (setq jb-org-gui--spacing nil))))

(defun jb-org-apply-presentation ()
  "Select exactly one Org prettifier without altering terminal preferences."
  (when (derived-mode-p 'org-mode)
    (if jb-gui-presentation-active
        (progn
          (when (bound-and-true-p org-superstar-mode) (org-superstar-mode -1))
          (unless (bound-and-true-p org-modern-mode) (org-modern-mode 1))
          (unless jb-org-gui-typography-mode (jb-org-gui-typography-mode 1)))
      (when (bound-and-true-p org-modern-mode) (org-modern-mode -1))
      (when jb-org-gui-typography-mode (jb-org-gui-typography-mode -1))
      (unless (bound-and-true-p org-superstar-mode) (org-superstar-mode 1)))))

(defun jb-markdown-register-mode ()
  "Put the frame-aware Markdown selector ahead of package autoloads."
  (let ((entry '("\\.\\(md\\|markdown\\)\\'" . jb-markdown-select-mode)))
    (setq auto-mode-alist (cons entry (delete entry auto-mode-alist)))))

(defun jb-markdown-select-mode ()
  "Choose a Markdown major mode for the current frame configuration."
  (interactive)
  (cond ((jb-gui-presentation-eligible-p) (markdown-modern-mode))
        ((and buffer-file-name (string-match-p "README\\.md\\'" buffer-file-name))
         (gfm-mode))
        (t (markdown-mode))))

(defun jb-markdown-apply-presentation ()
  "Keep visiting Markdown buffers in the mode appropriate for current frames."
  (when (and buffer-file-name
             (string-match-p "\\.\\(md\\|markdown\\)\\'" buffer-file-name)
             (memq major-mode '(markdown-mode gfm-mode markdown-modern-mode))
             (not (eq (eq major-mode 'markdown-modern-mode)
                      jb-gui-presentation-active)))
    (jb-markdown-select-mode)))

(defun jb-org-agenda-apply-presentation ()
  "Style new agenda output only in a GUI-only process."
  (when jb-gui-presentation-active (org-modern-agenda)))

(defun jb-refresh-gui-presentation (&optional departing-frame)
  "Update presentation after frame creation or before DEPARTING-FRAME deletion."
  (let* ((gui (and (jb-gui-presentation-eligible-p departing-frame) t))
         (changed (not (eq gui jb-gui-presentation-active))))
    (setq jb-gui-presentation-active gui)
    (unless (eq (and pixel-scroll-precision-mode t) gui)
      (pixel-scroll-precision-mode (if gui 1 -1)))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (jb-org-apply-presentation)
        (when changed (jb-markdown-apply-presentation))))
    ;; Agenda styling also writes text properties: regenerate instead of
    ;; leaving a previously GUI-styled agenda visible to a new TTY client.
    (when (and changed (fboundp 'org-agenda-redo-all))
      (save-window-excursion (org-agenda-redo-all t)))))

(defun jb-gui-presentation-frame-created (_frame)
  "Reconsider presentation when a client frame is created."
  (jb-refresh-gui-presentation))

(defun jb-gui-presentation-start ()
  "Install presentation hooks after Elpaca has provided both Org packages."
  (add-hook 'org-mode-hook #'jb-org-apply-presentation)
  (add-hook 'org-agenda-finalize-hook #'jb-org-agenda-apply-presentation)
  (add-hook 'after-make-frame-functions #'jb-gui-presentation-frame-created)
  (add-hook 'delete-frame-functions #'jb-refresh-gui-presentation)
  (jb-refresh-gui-presentation))

(provide 'jb-gui-presentation)
;;; gui-presentation.el ends here
