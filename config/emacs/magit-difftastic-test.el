;;; magit-difftastic-test.el --- Hunk focus regression tests -*- lexical-binding: t; -*-

;; Run with the configured Elpaca builds on load-path:
;; emacs -Q --batch -L ... -l config/emacs/magit-difftastic-test.el \
;;   -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'magit-diff)

;; Load only the highlighting method from the real configuration, without
;; installing packages, enabling Difftastic, or running startup side effects.
(with-temp-buffer
  (insert-file-contents
   (expand-file-name "post-init.el" (file-name-directory load-file-name)))
  (goto-char (point-min))
  (let (form)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (when (and (eq (car-safe form) 'use-package)
                 (eq (cadr form) 'magit-difftastic))
        (dolist (entry (cddr form))
          (when (and (eq (car-safe entry) 'cl-defmethod)
                     (eq (cadr entry) 'magit-section-highlight))
            (eval entry t)))))))

(defmacro jb-magit-test-with-sections (&rest body)
  "Run BODY with a file containing a Difftastic hunk and red/green text."
  (declare (indent 0))
  `(with-temp-buffer
     (magit-section-mode)
     (let ((inhibit-read-only t)
           file hunk added removed)
       (magit-insert-section (root)
         (setq file
               (magit-insert-section (file "example.el")
                 (magit-insert-heading "example.el")
                 (setq hunk
                       (magit-insert-section
                           (magit-difftastic-hunk nil nil
                            :heading-highlight-face 'magit-diff-hunk-heading-highlight
                            :heading-selection-face 'magit-diff-hunk-heading-selection)
                         (magit-insert-heading "@@ line 1 @@")
                         (setq removed (point))
                         (insert (propertize "old\n" 'font-lock-face
                                             '(:background "#ffe9e5")))
                         (setq added (point))
                         (insert (propertize "new\n" 'font-lock-face
                                             '(:background "#dcf8d1"))))))))
       ,@body)))

(ert-deftest jb-magit-difftastic-focus-preserves-change-backgrounds ()
  (jb-magit-test-with-sections
    (goto-char added)
    (magit-section-update-highlight t)
    (dolist (position (list removed added))
      (should-not (seq-some (lambda (ov) (overlay-get ov 'font-lock-face))
                            (overlays-at position))))
    (should (equal (get-text-property removed 'font-lock-face)
                   '(:background "#ffe9e5")))
    (should (equal (get-text-property added 'font-lock-face)
                   '(:background "#dcf8d1")))
    (should (seq-some (lambda (ov)
                       (eq (overlay-get ov 'font-lock-face)
                           'magit-diff-hunk-heading-highlight))
                     (overlays-at (oref hunk start))))))

(ert-deftest jb-magit-difftastic-file-focus-preserves-change-backgrounds ()
  (jb-magit-test-with-sections
    (goto-char (oref file start))
    (magit-section-update-highlight t)
    (should-not (seq-some (lambda (ov) (overlay-get ov 'font-lock-face))
                          (overlays-at added)))
    (magit-section-highlight-selection (list hunk))
    (should (seq-some (lambda (ov)
                       (eq (overlay-get ov 'font-lock-face)
                           'magit-diff-hunk-heading-selection))
                     (overlays-at (oref hunk start))))))

(ert-deftest jb-magit-ordinary-section-focus-is-unchanged ()
  (with-temp-buffer
    (magit-section-mode)
    (let ((inhibit-read-only t))
      (magit-insert-section (root)
        (magit-insert-section (ordinary)
          (magit-insert-heading "Heading")
          (insert "Body\n")))
      (goto-char (1- (point-max)))
      (magit-section-update-highlight t)
      (should (seq-some (lambda (ov)
                         (eq (overlay-get ov 'font-lock-face)
                             'magit-section-highlight))
                       (overlays-at (point)))))))

(provide 'magit-difftastic-test)
;;; magit-difftastic-test.el ends here
