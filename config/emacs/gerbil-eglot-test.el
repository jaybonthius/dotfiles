;;; gerbil-eglot-test.el --- Gerbil server registration tests -*- lexical-binding: t; -*-

;; emacs -Q --batch -L ~/.config/emacs/var/elpaca/builds/gerbil-mode \
;;   -l config/emacs/gerbil-eglot-test.el -f ert-run-tests-batch-and-exit
;; Set GERBIL_EGLOT_TEST_LIVE=1 to exercise the built native server as well.
(require 'ert)
(require 'eglot)
(require 'gerbil-mode)

;; Load the actual Eglot declaration, not the full package/startup machinery.
(with-temp-buffer
  (insert-file-contents
   (expand-file-name "post-init.el" (file-name-directory load-file-name)))
  (emacs-lisp-mode)
  (check-parens)
  (goto-char (point-min))
  (let (form found)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (when (and (eq (car-safe form) 'with-eval-after-load)
                 (equal (cadr form) '(quote eglot)))
        (setq found t)
        (eval form t)))
    (unless found (error "No Eglot declaration found in post-init.el"))))

(ert-deftest jb-gerbil-eglot-selects-native-server ()
  (with-temp-buffer
    (setq-local buffer-file-name (expand-file-name "gerbil-eglot-mode-test.ss"
                                                 temporary-file-directory))
    (gerbil-mode)
    (let ((contact (eglot--guess-contact)))
      (should (equal (nth 0 contact) '(gerbil-mode)))
      (should (equal (nth 3 contact)
                     (list (expand-file-name
                            "~/Code/workbench-gerbil/gerbil__v0.19-lsp/run.sh")
                           "gxlsp" "--stdio")))
      (should (equal (nth 4 contact) '("gerbil"))))
    (should-not (eglot-managed-p))
    (should-not (memq #'eglot-ensure gerbil-mode-hook))))

(ert-deftest jb-gerbil-eglot-preserves-chez-registration ()
  (should (equal (cdr (assq 'scheme-mode eglot-server-programs))
                 '("scheme-langserver" "-m" "enable" "-t" "disable"))))

(ert-deftest jb-gerbil-eglot-live-unsaved-native-features ()
  (skip-unless (getenv "GERBIL_EGLOT_TEST_LIVE"))
  (let* ((directory (make-temp-file "gerbil-eglot-" t))
         (file (expand-file-name "root.ss" directory))
         (eglot-sync-connect t)
         (eglot-connect-timeout 15)
         (eglot-autoshutdown nil)
         (eglot-events-buffer-config '(:size 100000 :format full))
         (create-lockfiles nil)
         buffer server completed)
    (unwind-protect
        (progn
          (with-temp-file file (insert "(def stale-disk-value 0)\n"))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (gerbil-mode)
            (erase-buffer)
            (insert "(def (greet name)    (string-append \"hello \" name))\n"
                    "(greet \"Eglot\")\n(error \"ROOT RAN\")\n")
            (apply #'eglot (eglot--guess-contact))
            (setq server (eglot-current-server))
            (should (eglot-managed-p))
            (goto-char (point-min))
            (forward-line 1)
            (forward-char 2)
            (let* ((params (eglot--TextDocumentPositionParams))
                   (hover (jsonrpc-request server :textDocument/hover params :timeout 45))
                   (definition (jsonrpc-request server :textDocument/definition params :timeout 10)))
              (should (string-match-p "greet" (plist-get (plist-get hover :contents) :value)))
              (should (equal (plist-get definition :uri) (concat "file://" file)))
              (let ((start (plist-get (plist-get definition :range) :start)))
                (should (= (plist-get start :line) 0))
                (should (= (plist-get start :character) 6))))
            (eglot-format-buffer)
            (should (string-match-p
                     (regexp-quote "(def (greet name) (string-append") (buffer-string)))
            (should (buffer-modified-p)))
          (with-current-buffer buffer (eglot-shutdown server nil 5 t))
          (should-not (jsonrpc-running-p server))
          (setq completed t))
      (when (and server (not completed))
        (with-current-buffer (jsonrpc-events-buffer server)
          (princ (buffer-string))))
      (when (and server (jsonrpc-running-p server))
        (ignore-errors
          (with-current-buffer buffer (eglot-shutdown server nil 5))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory directory t))))

;;; gerbil-eglot-test.el ends here
