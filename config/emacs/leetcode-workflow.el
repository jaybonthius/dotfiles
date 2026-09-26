;;; leetcode-workflow.el --- Local LeetCode practice tools -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Keep upstream's working filenames and run/submit commands unchanged.
;; Add a local Org index and explicitly numbered snapshots without a fork.

;;; Code:

(require 'cl-lib)
(require 'org)

;; These are special variables even when this file is autoloaded before LeetCode.
(defvar leetcode-directory)
(defvar leetcode-save-solutions)
(defvar leetcode--lang)
(defvar leetcode-solution-mode-map)

(defvar jb-leetcode-notes-file (expand-file-name "~/org/leetcode.org")
  "Org file containing problem notes and links to saved attempts.")

(defvar-local jb-leetcode--practice-problem nil
  "Problem belonging to this working solution buffer.")
(defvar-local jb-leetcode--practice-file nil
  "Original working filename; snapshots must never replace this buffer's file.")
(defvar-local jb-leetcode--practice-template nil
  "Starter code for a new attempt in this buffer's language.")

(defun jb-leetcode--notes-buffer ()
  "Visit the practice tracker without selecting its buffer."
  (make-directory (file-name-directory (expand-file-name jb-leetcode-notes-file)) t)
  (let ((buffer (find-file-noselect jb-leetcode-notes-file)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'org-mode) (org-mode))
      (when (= (buffer-size) 0)
        (insert "#+title: LeetCode\n\n")))
    buffer))

(defun jb-leetcode--notes-entry (problem solution-file)
  "Ensure PROBLEM has a tracker entry linking to SOLUTION-FILE.
Return a marker at its heading.  Existing notes and TODO states are preserved."
  (with-current-buffer (jb-leetcode--notes-buffer)
    (save-excursion
      (save-restriction
        (widen)
        (let* ((slug (leetcode-problem-title-slug problem))
               (position (org-find-property "LEETCODE_SLUG" slug)))
          (unless position
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (setq position (point))
            (insert (format "* TODO %s. %s :leetcode:\n"
                            (leetcode-problem-id problem)
                            (replace-regexp-in-string "[\r\n]+" " "
                                                      (leetcode-problem-title problem))))
            (goto-char position)
            (org-entry-put nil "LEETCODE_ID" (leetcode-problem-id problem))
            (org-entry-put nil "LEETCODE_SLUG" slug)
            (org-entry-put nil "DIFFICULTY" (leetcode-problem-difficulty problem))
            (org-end-of-subtree t t)
            (insert (org-link-make-string
                     (format "https://leetcode.com/problems/%s/" slug) "Problem")
                    "\n"
                    (org-link-make-string
                     (concat "file:" (abbreviate-file-name solution-file)) "Current solution")
                    "\n\n"))
          (when (buffer-modified-p) (save-buffer))
          (copy-marker position))))))

(defun jb-leetcode--track-problem (problem)
  "Attach practice tools to the working buffer opened for PROBLEM."
  (when leetcode-save-solutions
    (let* ((filename (expand-file-name
                      (leetcode--get-code-buffer-name (leetcode-problem-title problem))
                      leetcode-directory))
           (buffer (find-buffer-visiting filename))
           (snippet (seq-find
                     (lambda (item) (equal (leetcode-snippet-lang-slug item) leetcode--lang))
                     (leetcode-problem-snippets problem)))
           (template
            (when snippet
              (with-temp-buffer
                (leetcode--insert-code-start-marker)
                (insert (leetcode-snippet-code snippet))
                (leetcode--insert-code-end-marker)
                (replace-regexp-in-string "\r" "" (buffer-string))))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (setq jb-leetcode--practice-problem problem
                jb-leetcode--practice-file filename
                jb-leetcode--practice-template template)
          ;; Create the starter file once.  Later edits use ordinary C-x C-s.
          (unless (file-exists-p filename) (save-buffer))
          (jb-leetcode--notes-entry problem filename))))))

(defun jb-leetcode--require-working-buffer ()
  "Refuse to reset anything except a recognized working solution."
  (unless (and (bound-and-true-p leetcode-solution-mode)
               jb-leetcode--practice-problem
               jb-leetcode--practice-file
               buffer-file-name
               (equal (expand-file-name buffer-file-name) jb-leetcode--practice-file))
    (user-error "Open the working solution through M-x leetcode first")))

(defun jb-leetcode--attempt-directory ()
  "Return the snapshot directory for the current working file."
  (expand-file-name
   (concat "attempts/" (file-name-base jb-leetcode--practice-file) "/")
   (file-name-directory jb-leetcode--practice-file)))

(defun jb-leetcode--record-attempt (archive)
  "Add a link to ARCHIVE under the current problem's Org heading."
  (let ((entry (jb-leetcode--notes-entry jb-leetcode--practice-problem
                                         jb-leetcode--practice-file)))
    (unwind-protect
        (with-current-buffer (marker-buffer entry)
          (save-excursion
            (save-restriction
              (widen)
              (goto-char entry)
              (let ((stars (make-string (1+ (org-outline-level)) ?*)))
                (org-end-of-subtree t t)
                (unless (bolp) (insert "\n"))
                (insert (format "%s Attempt %s\n:PROPERTIES:\n:CREATED: %s\n:END:\n%s\n\n"
                                stars (file-name-base archive)
                                (format-time-string "[%Y-%m-%d %a %H:%M]")
                                (org-link-make-string
                                 (concat "file:" (abbreviate-file-name archive)) "Code"))))
              (save-buffer))))
      (set-marker entry nil))))

;;;###autoload
(defun jb-leetcode-new-attempt ()
  "Archive the current solution under the next number and restore starter code.
Unsaved edits are saved first.  Existing snapshots are never overwritten.
The working filename stays unchanged, so upstream run/submit commands still work."
  (interactive)
  (jb-leetcode--require-working-buffer)
  (barf-if-buffer-read-only)
  (unless (stringp jb-leetcode--practice-template)
    (user-error "No starter code is available; reopen the problem through LeetCode"))
  (let* ((directory (jb-leetcode--attempt-directory))
         (next 1)
         archive)
    (make-directory directory t)
    (dolist (name (directory-files directory nil "\\`[0-9]+\\.[[:alnum:]]+\\'"))
      (setq next (max next (1+ (string-to-number name)))))
    (setq archive (expand-file-name
                   (format "%03d%s" next (file-name-extension buffer-file-name t))
                   directory))
    (save-buffer)
    ;; Refuse collisions, including another Emacs creating this number first.
    (copy-file buffer-file-name archive nil)
    (jb-leetcode--record-attempt archive)
    ;; Do not clear the code until both the snapshot and its Org link are saved.
    (atomic-change-group
      (erase-buffer)
      (insert jb-leetcode--practice-template)
      (goto-char (point-min))
      (save-buffer))
    (message "Saved attempt %03d; started a fresh solution" next)
    archive))

;;;###autoload
(defun jb-leetcode-view-attempts (&optional compare)
  "Choose a numbered snapshot to view read-only.
With prefix argument COMPARE, compare it with the working file using Ediff."
  (interactive "P")
  (jb-leetcode--require-working-buffer)
  (let* ((directory (jb-leetcode--attempt-directory))
         (files (when (file-directory-p directory)
                  (directory-files directory nil "\\`[0-9]+\\.[[:alnum:]]+\\'"))))
    (unless files
      (user-error "No saved attempts yet; use C-c C-n to archive one"))
    (let ((archive (expand-file-name
                    (completing-read "Attempt: " files nil t) directory)))
      (if compare
          (ediff-files archive jb-leetcode--practice-file)
        (view-file archive)))))

;;;###autoload
(defun jb-leetcode-open-notes ()
  "Open the practice tracker, at the current problem when available."
  (interactive)
  (let ((entry (when jb-leetcode--practice-problem
                 (jb-leetcode--notes-entry jb-leetcode--practice-problem
                                          jb-leetcode--practice-file))))
    (pop-to-buffer (jb-leetcode--notes-buffer))
    (when entry
      (widen)
      (goto-char entry)
      (org-fold-show-context)
      (org-fold-show-subtree)
      (set-marker entry nil))))

(with-eval-after-load 'leetcode
  (advice-add 'leetcode--start-coding :after #'jb-leetcode--track-problem)
  (define-key leetcode-solution-mode-map (kbd "C-c C-n") #'jb-leetcode-new-attempt)
  (define-key leetcode-solution-mode-map (kbd "C-c C-a") #'jb-leetcode-view-attempts)
  (define-key leetcode-solution-mode-map (kbd "C-c C-o") #'jb-leetcode-open-notes))

(provide 'leetcode-workflow)
;;; leetcode-workflow.el ends here
