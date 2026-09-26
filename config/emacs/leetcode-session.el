;;; leetcode-session.el --- Cookie-file login for headless Emacs -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Read only the two LeetCode cookies from ~/dotfiles/.env; never evaluate the
;; file as shell or Lisp.  Values are reread at login, not copied into config.
;; Upstream's failed run path returns nil but still tries to check its result.
;; Keep the original HTTP error visible and stop that follow-up request.

;;; Code:

(require 'leetcode)

(defvar jb-leetcode-env-file (expand-file-name "~/dotfiles/.env")
  "Local file containing LEETCODE_SESSION and LEETCODE_CSRFTOKEN.
Supports unquoted, single-quoted, or double-quoted values, optional
export prefixes, and trailing comments.  No variable expansion occurs.")

(defun jb-leetcode--error (format-string &rest args)
  "Report and signal a cookie/login error using FORMAT-STRING and ARGS.
Aio captures errors in promises, so also show the message explicitly.
Callers must not include cookie values in error messages."
  (let ((text (apply #'format format-string args)))
    (message "%s" text)
    (user-error "%s" text)))

(defun jb-leetcode--cookie-value (raw name)
  "Parse a cookie value from RAW, using only NAME in error messages."
  (let* ((raw (string-trim raw))
         (value
          (cond
           ((string-match "\\`\\(['\"]\\)\\([^'\"]*\\)\\1\\(?:[ \t]+#.*\\)?\\'" raw)
            (match-string 2 raw))
           (t (string-trim (replace-regexp-in-string "[ \t]+#.*\\'" "" raw))))))
    (when (or (string-empty-p value)
              (string-match-p "[[:space:][:cntrl:]\"';,\\\\]" value))
      (jb-leetcode--error "Invalid %s in %s; use a single cookie value" name jb-leetcode-env-file))
    value))

(defun jb-leetcode--env-cookies ()
  "Read the current LeetCode cookies without executing or displaying them."
  (unless (and (file-regular-p jb-leetcode-env-file)
               (file-readable-p jb-leetcode-env-file))
    (jb-leetcode--error "Cannot read LeetCode cookies from %s" jb-leetcode-env-file))
  (let (values)
    (with-temp-buffer
      (insert-file-contents jb-leetcode-env-file)
      (goto-char (point-min))
      (while (re-search-forward
              "^[ \t]*\\(?:export[ \t]+\\)?\\(LEETCODE_SESSION\\|LEETCODE_CSRFTOKEN\\)[ \t]*=[ \t]*\\(.*\\)$"
              nil t)
        (let ((name (match-string-no-properties 1))
              (raw (match-string-no-properties 2)))
          ;; Like ordinary dotenv files, the last assignment wins.
          (setf (alist-get name values nil nil #'equal)
                (jb-leetcode--cookie-value raw name)))))
    (mapcar
     (lambda (entry)
       (let ((value (cdr (assoc (car entry) values))))
         (unless value
           (jb-leetcode--error "Missing %s in %s" (car entry) jb-leetcode-env-file))
         (list (cdr entry) value)))
     '(("LEETCODE_SESSION" . "LEETCODE_SESSION")
       ("LEETCODE_CSRFTOKEN" . "csrftoken")))))

(defun jb-leetcode--check-cookies ()
  "Check the cookie file instead of looking for a browser/Python helper."
  (jb-leetcode--env-cookies)
  t)

(aio-defun jb-leetcode--checked-login (login &rest args)
  "Call LOGIN with ARGS, clearing cached identity and stopping HTTP errors."
  (setf (leetcode-user-username leetcode--user) nil
        (leetcode-user-id leetcode--user) nil
        (leetcode-user-is-premium leetcode--user) nil)
  (let ((result (aio-await (apply login args))))
    ;; Upstream returns the displayed response buffer on an HTTP error.
    ;; A successful HTTP response may still be signed out on the first pass:
    ;; `leetcode--ensure-login' deliberately performs two login passes.
    (when (bufferp result)
      (with-current-buffer result
        (let ((case-fold-search t))
          (jb-leetcode--error
           "LeetCode login failed (HTTP %s%s); no run/submission was sent"
           (or url-http-response-status "unknown")
           (if (save-excursion
                 (goto-char (point-min))
                 (re-search-forward "^cf-mitigated:[ \t]*challenge[ \t]*\r?$"
                                    url-http-end-of-headers t))
               ", Cloudflare challenge"
             "")))))
    result))

(aio-defun jb-leetcode--checked-ensure-login (ensure-login &rest args)
  "Call ENSURE-LOGIN with ARGS before checking the final signed-in state."
  (let ((result (aio-await (apply ensure-login args))))
    (unless (leetcode--login-p)
      (jb-leetcode--error
       "LeetCode did not recognize the session cookies after both login passes; no run/submission was sent"))
    result))

(defun jb-leetcode--require-result-id (request-id &rest _)
  "Do not ask LeetCode for results without a valid REQUEST-ID."
  (unless (or (and (integerp request-id) (> request-id 0))
              (and (stringp request-id)
                   (not (member (string-trim request-id) '("" "nil" "null")))))
    (jb-leetcode--error
     "LeetCode run/submission failed; see the HTTP response. No result request was sent")))

(advice-add 'leetcode--cookie-get-all :override #'jb-leetcode--env-cookies)
(advice-add 'leetcode--check-deps :override #'jb-leetcode--check-cookies)
(advice-add 'leetcode--login :around #'jb-leetcode--checked-login)
(advice-add 'leetcode--ensure-login :around #'jb-leetcode--checked-ensure-login)
(advice-add 'leetcode--api-check-submission :before #'jb-leetcode--require-result-id)

(provide 'leetcode-session)
;;; leetcode-session.el ends here
