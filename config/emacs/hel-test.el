;;; hel-test.el --- Hel migration regression tests -*- lexical-binding: t; -*-

;; Run with Hel, hel-leader, and their dependencies on load-path:
;; emacs -Q --batch -L ... -l config/emacs/hel-test.el \
;;   -f ert-run-tests-batch-and-exit
;; Existing Elpaca builds can supply the remaining configured packages.
(require 'ert)
(require 'use-package)
(require 'use-package-ensure)

(defvar jb-hel-test-directory (make-temp-file "hel-config-test-" t))
(setq user-emacs-directory (file-name-as-directory jb-hel-test-directory))

;; Read the real declarations without installing packages or loading unrelated
;; startup side effects (calendar publishing, sessions, shells, theme watchers).
(with-temp-buffer
  (insert-file-contents
   (expand-file-name "post-init.el" (file-name-directory load-file-name)))
  (goto-char (point-min))
  (let ((use-package-ensure-function (lambda (&rest _) nil))
        form)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (cond
       ((and (eq (car-safe form) 'use-package)
             (memq (cadr form) '(which-key clipetty symex-core symex hel hel-leader
                                doom-modeline cape)))
        ;; Stock use-package does not accept Elpaca's recipe syntax.
        (setcdr (cdr form) (plist-put (cddr form) :ensure nil))
        (eval form t))
       ((and (eq (car-safe form) 'defvar-keymap)
             (eq (cadr form) 'jb-language-tools-map))
        (eval form t))
       ((equal form '(keymap-global-set "C-c l" jb-language-tools-map))
        (eval form t))))))

(which-key-mode 1)
(transient-mark-mode 1)
(require 'consult)
(require 'flash)
(require 'doom-modeline)
(require 'eglot)

;; Stand-ins exercise the same major-mode hook lifecycle without starting a
;; terminal module, Git process, or AI agent. Names match the actual hooks.
(define-derived-mode ghostel-mode fundamental-mode "Ghostel-test")
(define-derived-mode magit-mode special-mode "Magit-test")
(define-derived-mode jb-hel-test-magit-status-mode magit-mode "Magit-status-test")
(define-derived-mode pilish-chat-mode text-mode "Pilish-chat-test")
(define-derived-mode pilish-input-mode text-mode "Pilish-input-test")

(defmacro jb-hel-test-with-buffer (&rest body)
  "Run BODY in a displayed temporary editing buffer."
  (declare (indent 0))
  `(save-window-excursion
     ;; ERT's debugger installs an overriding map on failed assertions.
     ;; Keep that map and Lithium's promotion bookkeeping out of fixtures.
     (let ((overriding-terminal-local-map nil)
           (lithium-promoted-map nil))
       (with-temp-buffer
         (switch-to-buffer (current-buffer))
         (text-mode)
         (hel-local-mode 1)
         ,@body))))

(defun jb-hel-test-leader-command (keys)
  "Resolve KEYS after Space using the real leader input loop."
  (let ((unread-command-events (append (kbd keys) nil))
        (hel-leader-echo nil)
        (which-key-idle-delay 0))
    (hel-leader-start)))

(ert-deftest jb-hel-loads-without-meow ()
  (should hel-mode)
  (should (featurep 'hel))
  (should (featurep 'hel-leader))
  (should-not (featurep 'meow))
  (should-not (fboundp 'meow-toggle))
  (should-not hel-want-minibuffer)
  (should-not hel-want-C-hjkl-keys)
  (should (eq (key-binding (kbd "s-m")) 'jb-hel-toggle)))

(ert-deftest jb-hel-ijkl-insert-and-extend ()
  (jb-hel-test-with-buffer
    (insert "one\ntwo\nthree\n")
    (goto-char 6)
    (should (eq (key-binding (kbd "i")) 'hel-previous-line))
    (should (eq (key-binding (kbd "j")) 'hel-backward-char))
    (should (eq (key-binding (kbd "k")) 'hel-next-line))
    (should (eq (key-binding (kbd "l")) 'hel-forward-char))
    (should (eq (key-binding (kbd "h")) 'hel-insert))
    (should (eq (key-binding (kbd "H")) 'hel-insert-line))
    (should (eq (key-binding (kbd "g i")) 'hel-avy-previous-line))
    (should (eq (key-binding (kbd "g k")) 'hel-avy-next-line))
    (call-interactively (key-binding (kbd "i")))
    (should (= (line-number-at-pos) 1))
    (hel-extend-selection 1)
    (let ((anchor (mark)))
      (call-interactively (key-binding (kbd "k")))
      (should (= (mark) anchor))
      (should (= (line-number-at-pos) 2)))
    (call-interactively (key-binding (kbd "h")))
    (should (eq hel-state 'insert))
    (should (eq (key-binding (kbd "SPC")) 'self-insert-command))
    (call-interactively (key-binding (kbd "<escape>")))
    (should (eq hel-state 'normal))
    (should (eq (key-binding (kbd "SPC")) 'hel-leader))))

(ert-deftest jb-hel-window-directions ()
  (jb-hel-test-with-buffer
    (dolist (entry '(("i" . windmove-up) ("j" . windmove-left)
                     ("k" . windmove-down) ("l" . windmove-right)))
      (should (eq (key-binding (kbd (concat "C-w " (car entry)))) (cdr entry)))
      (should (eq (jb-hel-test-leader-command (concat "w " (car entry))) (cdr entry))))))

(ert-deftest jb-hel-excluded-modes-stay-native ()
  (dolist (mode '(ghostel-mode jb-hel-test-magit-status-mode
                  pilish-chat-mode pilish-input-mode))
    (jb-hel-test-with-buffer
      (funcall mode)
      (should-not hel-local-mode)
      (should-not hel-state)
      (should (eq cursor-type 'bar))
      (let ((native-space (key-binding (kbd "SPC"))))
        (jb-hel-toggle)
        (should hel-local-mode)
        (should (eq hel-state 'normal))
        (should (eq (key-binding (kbd "i")) 'hel-previous-line))
        (should (eq (key-binding (kbd "SPC")) 'hel-leader))
        (jb-hel-toggle)
        (should-not hel-local-mode)
        (should (eq (key-binding (kbd "SPC")) native-space))))))

(ert-deftest jb-hel-leader-keeps-existing-prefixes ()
  (jb-hel-test-with-buffer
    ;; A lowercase g must not be swallowed as Hel's C-M modifier.
    (keymap-local-set "C-c g o" #'ignore)
    (keymap-local-set "C-c e s" #'ignore)
    (should (eq (jb-hel-test-leader-command "g o") 'ignore))
    (should (eq (jb-hel-test-leader-command "e s") 'ignore))
    (should (eq (jb-hel-test-leader-command "p f")
                (key-binding (kbd "C-c p f"))))
    (should (eq (jb-hel-test-leader-command "l a") 'eglot-code-actions))
    (should (eq (jb-hel-test-leader-command "M x") 'execute-extended-command))
    (should (eq (jb-hel-test-leader-command "x x s") 'save-buffer))))

(ert-deftest jb-hel-leader-search-navigation-and-help ()
  (jb-hel-test-with-buffer
    (dolist (entry '(("/" . consult-ripgrep) (";" . flash-jump)
                     ("." . xref-find-definitions) ("," . xref-go-back)
                     ("s l" . consult-line) ("s r" . query-replace)
                     ("s R" . query-replace-regexp) ("s t" . flash-treesitter)
                     ("s x" . xref-find-references) ("?" . describe-bindings)
                     ("f f" . find-file) ("b b" . consult-buffer)))
      (should (commandp (cdr entry)))
      (should (eq (jb-hel-test-leader-command (car entry)) (cdr entry))))
    (should-not (jb-hel-test-leader-command "<escape>"))
    (should-not hel-leader--preview-is-active)))

(ert-deftest jb-hel-which-key-preview-shows-command-groups ()
  (jb-hel-test-with-buffer
    (let ((hel-leader--keys nil)
          (hel-leader--pending-modifier nil))
      (let ((preview (prin1-to-string (hel-leader--which-key-get-bindings))))
        (dolist (label '("files" "buffers" "search" "language" "completion"))
          (should (string-match-p label preview))))
      (setq hel-leader--keys '("C-c" "s"))
      (let ((preview (prin1-to-string (hel-leader--which-key-get-bindings))))
        (should (string-match-p "consult-line" preview))
        (should (string-match-p "query-replace" preview)))
      (unwind-protect
          (progn
            (hel-leader--which-key-show)
            (should which-key--pages-obj)
            (should (buffer-live-p (get-buffer which-key-buffer-name))))
        (which-key--hide-popup)))))

(ert-deftest jb-hel-symex-returns-to-correct-state ()
  (jb-hel-test-with-buffer
    (emacs-lisp-mode)
    (insert "(one two)\n")
    (goto-char (point-min))
    (symex-mode-interface)
    ;; Direct calls do not run the command loop's keymap promotion hook.
    (lithium-evaluate-overriding-map)
    (should symex-editing-mode)
    (should (eq (key-binding (kbd "j"))
                (lookup-key symex-editing-mode-map (kbd "j"))))
    (symex-escape-higher)
    (should-not symex-editing-mode)
    (should (eq hel-state 'normal))
    (symex-mode-interface)
    (symex-insert-at-beginning)
    (should-not symex-editing-mode)
    (should (eq hel-state 'insert))
    (should (eq (key-binding (kbd "a")) 'self-insert-command))
    (hel-normal-state)
    (symex-mode-interface)
    (symex-enter-lower)
    (should (eq hel-state 'insert))))

(ert-deftest jb-hel-copy-exports-only-on-explicit-copy ()
  (jb-hel-test-with-buffer
    (insert "copy me\n")
    (hel-set-region 1 8)
    (let ((exports nil)
          (interprogram-cut-function #'ignore))
      (cl-letf (((symbol-function 'clipetty--emit)
                 (lambda (text) (push text exports))))
        (call-interactively (key-binding (kbd "y")))
        (should (equal (car kill-ring) "copy me"))
        (should exports)
        (should-not clipetty-mode)
        (setq exports nil)
        (hel-set-region 1 8)
        (hel-cut 1)
        (should-not exports)))))

(ert-deftest jb-hel-multiple-cursor-copy-and-undo ()
  (jb-hel-test-with-buffer
    (buffer-enable-undo)
    (insert "one\ntwo\nthree\n")
    (goto-char 1)
    (setq buffer-undo-list nil)
    (execute-kbd-macro (kbd "e C"))
    (should hel-multiple-cursors-mode)
    (should (= (length (hel-all-fake-cursors)) 1))
    (setq-local interprogram-cut-function #'ignore)
    (cl-letf (((symbol-function 'clipetty--emit) #'ignore))
      (execute-kbd-macro (kbd "y")))
    (should (equal killed-rectangle '("one" "two")))
    (should-not clipetty-mode)
    (execute-kbd-macro (kbd "c Z <escape>"))
    (should (equal (buffer-string) "Z\nZ\nthree\n"))
    ;; Hel's default fine undo separates deletion from inserted text.
    (execute-kbd-macro (kbd "u u"))
    (should (equal (buffer-string) "one\ntwo\nthree\n"))
    (execute-kbd-macro (kbd "U U"))
    (should (equal (buffer-string) "Z\nZ\nthree\n"))))

(ert-deftest jb-hel-modeline-displays-state ()
  (jb-hel-test-with-buffer
    (should (string-match-p "Normal"
                            (substring-no-properties (doom-modeline-segment--modals))))
    (hel-insert-state)
    (should (string-match-p "Insert"
                            (substring-no-properties (doom-modeline-segment--modals))))
    (jb-hel-disable)
    (should-not (string-match-p "Normal\\|Insert"
                               (or (doom-modeline-segment--modals) "")))))

(add-hook 'kill-emacs-hook
          (lambda () (delete-directory jb-hel-test-directory t)))

;;; hel-test.el ends here
