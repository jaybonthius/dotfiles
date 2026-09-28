;;; persp-mode-test.el --- Workspace smoke tests -*- no-byte-compile: t; lexical-binding: t; -*-

;; Run in a separate GUI/TTY Emacs (not --batch: saving needs a live frame).
;; emacs -Q -L ~/.config/emacs/var/elpaca/builds/persp-mode \
;;   -l config/emacs/persp-mode-test.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'use-package)
(require 'use-package-ensure)

(defvar jb-persp-test-directory (make-temp-file "persp-config-test-" t))
(setq user-emacs-directory (file-name-as-directory jb-persp-test-directory))

;; Exercise the actual declaration, without installing anything in the test.
(with-temp-buffer
  (insert-file-contents
   (expand-file-name "post-init.el" (file-name-directory load-file-name)))
  (goto-char (point-min))
  (let ((use-package-ensure-function (lambda (&rest _) nil))
        form)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (when (and (eq (car-safe form) 'use-package) (eq (cadr form) 'persp-mode))
        ;; Elpaca's recipe syntax is not understood by stock use-package.
        (setcdr (cdr form) (plist-put (cddr form) :ensure nil))
        (eval form t)))))

(ert-deftest jb-persp-configuration ()
  (should persp-mode)
  (should (equal persp-keymap-prefix (kbd "C-c e")))
  (should (= persp-auto-save-opt 3))
  (should (> persp-auto-resume-time 0))
  (should-not persp-autokill-buffer-on-remove)
  (should (eq (key-binding (kbd "C-c e s")) 'persp-frame-switch))
  (should (eq (key-binding (kbd "C-c e b")) 'persp-switch-to-buffer))
  (should (eq (key-binding (kbd "C-c e w")) 'persp-save-state-to-file)))

(ert-deftest jb-persp-switch-and-restore ()
  (let* ((file (expand-file-name "workspace.txt" jb-persp-test-directory))
         (state (expand-file-name "workspaces" jb-persp-test-directory))
         buffer)
    (with-temp-file file (insert "workspace fixture\n"))
    (unwind-protect
        (progn
          (persp-switch "one")
          (setq buffer (find-file-noselect file))
          (switch-to-buffer buffer)
          (should (memq buffer (persp-buffers (persp-get-by-name "one"))))
          (persp-switch "two")
          (should-not (memq buffer (persp-buffers (persp-get-by-name "two"))))
          (persp-switch "one")
          (should (eq (window-buffer) buffer))
          (should (persp-save-state-to-file state))
          (let ((persp-auto-save-opt 0)) (persp-mode -1))
          (persp-mode 1)
          (should (persp-load-state-from-file state))
          (should (persp-get-by-name "one"))
          (should (persp-get-by-name "two"))
          (persp-switch "one")
          (should (memq buffer (persp-buffers (get-current-persp))))
          (persp-remove-buffer buffer)
          (should (buffer-live-p buffer)))
      (let ((persp-auto-save-opt 0)) (persp-mode -1))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

;; All persistence stays in the temporary directory, including on test failure.
(add-hook 'kill-emacs-hook
          (lambda ()
            (setq persp-auto-save-opt 0)
            (when (bound-and-true-p persp-mode) (persp-mode -1))
            (delete-directory jb-persp-test-directory t))
          -100)

;;; persp-mode-test.el ends here
