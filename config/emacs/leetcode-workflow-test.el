;;; leetcode-workflow-test.el --- Offline practice workflow tests -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'leetcode)
(require 'org)
(require 'leetcode-workflow)

(defvar jb-leetcode-notes-file)

(defconst jb-leetcode-workflow-test--template
  "class Solution:\n    def twoSum(self, nums, target):\n        pass\n")

(defmacro jb-leetcode-workflow-test--with-practice (&rest body)
  "Run BODY against real problem commands with isolated files and no network."
  (declare (indent 0))
  `(let* ((root (make-temp-file "leetcode-practice-" t))
          (leetcode-directory (expand-file-name "solutions/" root))
          (jb-leetcode-notes-file (expand-file-name "org/leetcode.org" root))
          (leetcode-prefer-language "python3")
          (leetcode-save-solutions t)
          (leetcode--lang "python3")
          (leetcode--problem-titles nil)
          (problem (make-leetcode-problem
                    :id "1" :backend-id "1" :title "Two Sum" :title-slug "two-sum"
                    :difficulty "Easy" :likes 1 :dislikes 0
                    :content "<p>Return the indices of two numbers.</p>"
                    :testcases '("[2,7,11,15]" "9")
                    :snippets (list (make-leetcode-snippet
                                     :lang "Python3" :lang-slug "python3"
                                     :code jb-leetcode-workflow-test--template))))
          (leetcode--problems (make-leetcode-problems :problems (list problem)))
          (existing-buffers (buffer-list))
          (create-lockfiles nil)
          (make-backup-files nil))
     (unwind-protect
         (save-window-excursion
           (cl-letf (((symbol-function 'url-retrieve)
                      (lambda (&rest _) (ert-fail "Real network request blocked"))))
             ,@body))
       (dolist (buffer (buffer-list))
         (unless (memq buffer existing-buffers)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory root t))))

(defun jb-leetcode-workflow-test--open ()
  "Open the fixture through the package's problem-solving command."
  (aio-wait-for (leetcode-solve-problem "1"))
  (find-buffer-visiting (expand-file-name "1_two-sum.py" leetcode-directory)))

(defun jb-leetcode-workflow-test--read (file)
  "Read FILE's contents."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(ert-deftest jb-leetcode-workflow-opening-problem-creates-file-and-org-entry ()
  (jb-leetcode-workflow-test--with-practice
    (let ((code (jb-leetcode-workflow-test--open)))
      (should (buffer-live-p code))
      (with-current-buffer code
        (should (equal (buffer-name) "1_two-sum.py"))
        (should leetcode-solution-mode)
        (should (file-exists-p buffer-file-name))
        (should (equal (jb-leetcode-workflow-test--read buffer-file-name)
                       jb-leetcode-workflow-test--template)))
      (let ((notes (jb-leetcode-workflow-test--read jb-leetcode-notes-file)))
        (should (string-match-p "^\\* TODO 1\\. Two Sum" notes))
        (should (string-match-p ":LEETCODE_SLUG: two-sum" notes))
        (should (string-match-p "https://leetcode.com/problems/two-sum/" notes))
        (should (string-match-p "1_two-sum.py" notes))))))

(ert-deftest jb-leetcode-workflow-new-attempt-keeps-unsaved-code-and-numbers-after-reopen ()
  (jb-leetcode-workflow-test--with-practice
    (let* ((file (expand-file-name "1_two-sum.py" leetcode-directory))
           (first (expand-file-name "attempts/1_two-sum/001.py" leetcode-directory))
           (second (expand-file-name "attempts/1_two-sum/002.py" leetcode-directory))
           (code (jb-leetcode-workflow-test--open)))
      (with-current-buffer code
        (erase-buffer)
        (insert "# first attempt, not yet saved\n")
        (jb-leetcode-new-attempt)
        (should (equal buffer-file-name file))
        (should (equal (buffer-name) "1_two-sum.py"))
        (should leetcode-solution-mode)
        (should (equal (buffer-string) jb-leetcode-workflow-test--template))
        (should (equal (jb-leetcode-workflow-test--read file)
                       jb-leetcode-workflow-test--template))
        ;; Upstream can still resolve the problem and restore its normal layout.
        (aio-wait-for (leetcode-restore-layout)))
      (kill-buffer code)
      (with-current-buffer (jb-leetcode-workflow-test--open)
        (erase-buffer)
        (insert "# second attempt\n")
        (jb-leetcode-new-attempt))
      (should (equal (jb-leetcode-workflow-test--read first)
                     "# first attempt, not yet saved\n"))
      (should (equal (jb-leetcode-workflow-test--read second) "# second attempt\n"))
      (let ((notes (jb-leetcode-workflow-test--read jb-leetcode-notes-file)))
        (should (string-match-p "^\\*\\* Attempt 001" notes))
        (should (string-match-p "^\\*\\* Attempt 002" notes))
        (should (string-match-p "001.py" notes))
        (should (string-match-p "002.py" notes))))))

(ert-deftest jb-leetcode-workflow-view-attempt-opens-a-read-only-snapshot ()
  (jb-leetcode-workflow-test--with-practice
    (let ((code (jb-leetcode-workflow-test--open)))
      (with-current-buffer code
        (erase-buffer)
        (insert "# archived attempt\n")
        (jb-leetcode-new-attempt)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt choices &rest _)
                     (should (member "001.py" choices))
                     "001.py")))
          (jb-leetcode-view-attempts)
          (should buffer-read-only)
          (should (equal (buffer-string) "# archived attempt\n"))
          (should-not leetcode-solution-mode))))))

(ert-deftest jb-leetcode-workflow-reopening-preserves-notes-status-and-unsaved-code ()
  (jb-leetcode-workflow-test--with-practice
    (let ((code (jb-leetcode-workflow-test--open)))
      (with-current-buffer code
        (erase-buffer)
        (insert "# keep my unsaved work\n"))
      (with-current-buffer (find-buffer-visiting jb-leetcode-notes-file)
        (goto-char (org-find-property "LEETCODE_SLUG" "two-sum"))
        (org-todo 'done)
        (org-end-of-subtree t t)
        (insert "My reasoning must survive reopening.\n")
        (save-buffer))
      (jb-leetcode-workflow-test--open)
      (with-current-buffer code
        (should (equal (buffer-string) "# keep my unsaved work\n"))
        (should (buffer-modified-p))
        (jb-leetcode-open-notes)
        (should (derived-mode-p 'org-mode))
        (should (equal (org-entry-get nil "LEETCODE_SLUG") "two-sum"))
        (should (equal (org-get-todo-state) "DONE"))
        (should (string-match-p "My reasoning must survive reopening" (buffer-string))))
      (with-current-buffer (find-buffer-visiting jb-leetcode-notes-file)
        (should (= (length (org-map-entries (lambda () t) "LEETCODE_SLUG=\"two-sum\"")) 1))))))

(ert-deftest jb-leetcode-workflow-cannot-reset-code-when-tracker-is-read-only ()
  (jb-leetcode-workflow-test--with-practice
    (let ((code (jb-leetcode-workflow-test--open)))
      (with-current-buffer (find-buffer-visiting jb-leetcode-notes-file)
        (setq buffer-read-only t))
      (with-current-buffer code
        (erase-buffer)
        (insert "# valuable unsaved work\n")
        (should-error (jb-leetcode-new-attempt) :type 'buffer-read-only)
        (should (equal (buffer-string) "# valuable unsaved work\n"))
        (should (equal (jb-leetcode-workflow-test--read buffer-file-name)
                       "# valuable unsaved work\n"))
        (should (equal (jb-leetcode-workflow-test--read
                        (expand-file-name "attempts/1_two-sum/001.py" leetcode-directory))
                       "# valuable unsaved work\n"))))))

(ert-deftest jb-leetcode-workflow-never-overwrites-a-concurrent-snapshot ()
  (jb-leetcode-workflow-test--with-practice
    (with-current-buffer (jb-leetcode-workflow-test--open)
      (erase-buffer)
      (insert "# keep this current attempt\n")
      (let ((original-copy (symbol-function 'copy-file)))
        (cl-letf (((symbol-function 'copy-file)
                   (lambda (source destination &rest args)
                     (with-temp-file destination (insert "# other Emacs's snapshot\n"))
                     (apply original-copy source destination args))))
          (should-error (jb-leetcode-new-attempt) :type 'file-already-exists)))
      (should (equal (buffer-string) "# keep this current attempt\n"))
      (should (equal (jb-leetcode-workflow-test--read
                      (expand-file-name "attempts/1_two-sum/001.py" leetcode-directory))
                     "# other Emacs's snapshot\n")))))

(ert-deftest jb-leetcode-workflow-refuses-unrelated-and-renamed-buffers ()
  (jb-leetcode-workflow-test--with-practice
    (with-temp-buffer
      (insert "Do not touch this buffer")
      (should-error (jb-leetcode-new-attempt) :type 'user-error)
      (should (equal (buffer-string) "Do not touch this buffer")))
    (with-current-buffer (jb-leetcode-workflow-test--open)
      (let ((buffer-file-name (expand-file-name "unrelated.py" root)))
        (should-error (jb-leetcode-new-attempt) :type 'user-error)))))

(ert-deftest jb-leetcode-workflow-view-with-no-attempts-is-an-error-not-a-prompt ()
  (jb-leetcode-workflow-test--with-practice
    (with-current-buffer (jb-leetcode-workflow-test--open)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (ert-fail "Must not prompt without snapshots"))))
        (should-error (jb-leetcode-view-attempts) :type 'user-error)))))

(ert-deftest jb-leetcode-workflow-compare-uses-snapshot-and-current-file ()
  (jb-leetcode-workflow-test--with-practice
    (with-current-buffer (jb-leetcode-workflow-test--open)
      (jb-leetcode-new-attempt)
      (let (comparison)
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "001.py"))
                  ((symbol-function 'ediff-files)
                   (lambda (a b &rest _) (setq comparison (list a b)))))
          (jb-leetcode-view-attempts t))
        (should (equal comparison
                       (list (expand-file-name "attempts/1_two-sum/001.py" leetcode-directory)
                             (expand-file-name "1_two-sum.py" leetcode-directory))))))))

(ert-deftest jb-leetcode-workflow-read-only-working-file-does-not-create-an-attempt ()
  (jb-leetcode-workflow-test--with-practice
    (with-current-buffer (jb-leetcode-workflow-test--open)
      (setq buffer-read-only t)
      (should-error (jb-leetcode-new-attempt) :type 'buffer-read-only)
      (should-not (file-exists-p (expand-file-name "attempts" leetcode-directory))))))

;;; leetcode-workflow-test.el ends here
