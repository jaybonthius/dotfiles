;;; pre-init.el --- Pre-initialization -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Code:

;;;; Elpaca bootstrap

(defvar elpaca-installer-version 0.11)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-repos-directory (expand-file-name "repos/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca--activate-package)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-repos-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;;;; use-package integration

;; Enable Elpaca support for use-package's :ensure keyword.
(elpaca elpaca-use-package
  (elpaca-use-package-mode))

;;;; Lock file
;; Pin package versions for reproducibility.
;; elpaca-menu-lock-file is already first in elpaca-menu-functions by default,
;; so setting elpaca-lock-file is all that's needed for Elpaca to use it.
;; Patterns below follow jimeh/.emacs.d (author of Elpaca PR #504).

(setq elpaca-lock-file (expand-file-name "~/dotfiles/config/emacs/elpaca-lock.el"))

;; Auto-write lock file after all packages are installed on startup.
;; Keeps the lock file in sync without manual intervention.
(add-hook 'elpaca-after-init-hook
          (lambda ()
            (when (and elpaca-lock-file (elpaca--queued))
              (elpaca-write-lock-file elpaca-lock-file)))
          95)

;; elpaca-write-lock-file always prompts for a path (hardcoded interactive spec).
;; This wrapper writes to the configured path without prompting.
(defun elpaca-write-lock-file-default ()
  "Write lock file to `elpaca-lock-file' without prompting."
  (interactive)
  (if elpaca-lock-file
      (elpaca-write-lock-file elpaca-lock-file)
    (call-interactively #'elpaca-write-lock-file)))

;; Force-update: temporarily bypass lock file pinning for a package.
;; The lock file pins via :ref (detached HEAD), which prevents normal
;; elpaca-update from working. These commands advise elpaca-pinned-p
;; to allow updates while locked.
(defvar elpaca-force-update--packages nil
  "List of package IDs temporarily exempt from lock file pinning.")

(advice-add 'elpaca-pinned-p :around
            (lambda (orig e)
              (if (and elpaca-force-update--packages
                       (memq (elpaca<-id e) elpaca-force-update--packages))
                  nil
                (funcall orig e))))

(add-hook 'elpaca-post-queue-hook
          (lambda () (setq elpaca-force-update--packages nil)))

(defun elpaca-force-update (id)
  "Force update package ID, bypassing lock file pin."
  (interactive (list (elpaca--read-queued "Force update: ")))
  (setq elpaca-force-update--packages (list id))
  (elpaca-update id t))

(defun elpaca-force-update-all ()
  "Force update all packages, bypassing lock file pins."
  (interactive)
  (setq elpaca-force-update--packages (mapcar #'car (elpaca--queued)))
  (elpaca-update-all t))

;;; pre-init.el ends here
