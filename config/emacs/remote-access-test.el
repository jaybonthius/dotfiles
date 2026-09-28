;;; remote-access-test.el --- TRAMP-RPC smoke tests -*- lexical-binding: t; -*-

;; After install.sh switch:
;; emacs -Q --batch -l config/emacs/remote-access-test.el -f ert-run-tests-batch-and-exit
;; Prefix with TRAMP_RPC_TEST_REMOTE=1 to exercise SSH access to jay@tungo.org.
(require 'ert)
(load (expand-file-name "~/.config/emacs/tramp-rpc-packages.el") nil t)
(load (expand-file-name "remote-access.el" (file-name-directory load-file-name)) nil t)

(ert-deftest jb-remote-access-methods ()
  (should (version<= "2.8.1.4" tramp-version))
  (should (featurep 'tramp-rpc))
  (dolist (entry '(("/jay@tungo.org:/home/jay/" . "rpc")
                   ("/rpc:jay@tungo.org:/home/jay/" . "rpc")
                   ("/ssh:jay@tungo.org:/home/jay/" . "ssh")))
    (should (equal (tramp-file-name-method (tramp-dissect-file-name (car entry)))
                   (cdr entry)))))

(ert-deftest jb-remote-access-managed-server ()
  (with-temp-buffer
    (connection-local-get-variables
     '(:application tramp :protocol "rpc" :user "jay" :machine "tungo.org"))
    (should (eq t (alist-get 'tramp-rpc-deploy-never-deploy connection-local-variables-alist)))
    (should (equal (alist-get 'tramp-rpc-deploy-remote-binary-path connection-local-variables-alist)
                   "/home/jay/.nix-profile/bin/tramp-rpc-server")))
  (with-temp-buffer
    (connection-local-get-variables
     '(:application tramp :protocol "rpc" :user "jay" :machine "another-host"))
    (should-not (assq 'tramp-rpc-deploy-never-deploy connection-local-variables-alist))))

(ert-deftest jb-remote-access-roundtrip ()
  (skip-unless (getenv "TRAMP_RPC_TEST_REMOTE"))
  (let* ((default-directory "/rpc:jay@tungo.org:/home/jay/")
         (directory (make-temp-file (concat default-directory ".tramp-rpc-test-") t))
         (file (concat directory "/roundtrip.txt"))
         (renamed (concat directory "/renamed.txt"))
         (text "TRAMP-RPC roundtrip: λ 日本語\n"))
    (unwind-protect
        (progn
          (write-region text nil file nil 'silent)
          (should (file-exists-p file))
          (should (member "roundtrip.txt" (directory-files directory)))
          (should (file-attributes file))
          (with-temp-buffer
            (insert-file-contents file)
            (should (equal (buffer-string) text)))
          (rename-file file renamed)
          (should-not (file-exists-p file))
          (should (file-exists-p renamed))
          (delete-file renamed)
          (should-not (file-exists-p renamed)))
      (delete-directory directory t))))

(ert-deftest jb-remote-access-processes-and-ssh-fallback ()
  (skip-unless (getenv "TRAMP_RPC_TEST_REMOTE"))
  (let ((default-directory "/rpc:jay@tungo.org:/home/jay/dotfiles/"))
    (with-temp-buffer
      (should (zerop (process-file "git" nil t nil "rev-parse" "--show-toplevel")))
      (should (equal (string-trim (buffer-string)) "/home/jay/dotfiles")))
    (with-temp-buffer
      (let ((process (make-process :name "tramp-rpc-smoke" :buffer (current-buffer)
                                   :command '("printf" "rpc-async-ok")
                                   :connection-type 'pipe :file-handler t :noquery t
                                   :sentinel #'ignore))
            (deadline (+ (float-time) 30)))
        (unwind-protect
            (progn
              (while (and (process-live-p process) (< (float-time) deadline))
                (accept-process-output process 0.1))
              (should-not (process-live-p process))
              (should (zerop (process-exit-status process)))
              (should (equal (buffer-string) "rpc-async-ok")))
          (when (process-live-p process) (delete-process process))))))
  (with-temp-buffer
    (insert-file-contents "/ssh:jay@tungo.org:/home/jay/dotfiles/flake.nix")
    (should (string-match-p "emacs-tramp-rpc" (buffer-string)))))

;;; remote-access-test.el ends here
