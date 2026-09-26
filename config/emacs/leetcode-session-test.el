;;; leetcode-session-test.el --- Offline LeetCode session tests -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'leetcode)
(require 'url-cookie)
(require 'leetcode-session nil t)

(defvar jb-leetcode-env-file)
(defvar jb-leetcode-test--buffers nil)

(defmacro jb-leetcode-test--with-env (contents &rest body)
  "Run BODY with an isolated cookie file containing CONTENTS."
  (declare (indent 1))
  `(let ((jb-leetcode-env-file (make-temp-file "leetcode-env-"))
         (url-cookie-file (make-temp-file "leetcode-cookie-"))
         (url-cookie-storage nil)
         (url-cookie-secure-storage nil)
         (url-cookies-changed-since-last-save nil)
         (leetcode--user (make-leetcode-user))
         (jb-leetcode-test--buffers nil))
     (unwind-protect
         (progn
           (with-temp-file jb-leetcode-env-file (insert ,contents))
           (cl-letf (((symbol-function 'url-retrieve)
                      (lambda (&rest _) (ert-fail "Real network request blocked")))
                     ((symbol-function 'shell-command-to-string)
                      (lambda (&rest _) (ert-fail "Browser cookie extraction blocked")))
                     ((symbol-function 'leetcode--install-my-cookie)
                      (lambda () (ert-fail "Python helper installation blocked"))))
             ,@body))
       (dolist (buffer jb-leetcode-test--buffers)
         (when (buffer-live-p buffer) (kill-buffer buffer)))
       (delete-file jb-leetcode-env-file)
       (delete-file url-cookie-file))))

(defun jb-leetcode-test--response (status body &optional headers)
  "Return a resolved aio HTTP response for STATUS, BODY and optional HEADERS."
  (let ((buffer (generate-new-buffer " *leetcode-test-response*"))
        (promise (aio-promise)))
    (push buffer jb-leetcode-test--buffers)
    (with-current-buffer buffer
      (insert (format "HTTP/1.1 %d Test\r\nContent-Type: application/json\r\n%s\r\n"
                      status (or headers "")))
      (setq-local url-http-end-of-headers (point-marker)
                  url-http-response-status status)
      (insert body))
    (aio-resolve promise
                 (lambda ()
                   (cons (unless (= status 200) `(:error (error http ,status)))
                         buffer)))
    promise))

(defun jb-leetcode-test--run (login-status run-status &optional submit)
  "Exercise the real run or SUBMIT flow with mocked HTTP."
  (let ((problem (make-leetcode-problem :id "1" :backend-id "1" :title-slug "two-sum"))
        requests result-shown failure)
    (cl-letf (((symbol-function 'leetcode-restore-layout) #'ignore)
              ((symbol-function 'leetcode--get-slug-title) (lambda (&rest _) "two-sum"))
              ((symbol-function 'leetcode--get-problem) (lambda (&rest _) problem))
              ((symbol-function 'leetcode--testcase-buffer-data) (lambda (&rest _) "[]"))
              ((symbol-function 'leetcode--code-buffer-data) (lambda () "pass"))
              ;; Keep the HTTP regression reproducible before the adapter exists.
              ;; Cookie-file parsing and the dependency check are tested separately.
              ((symbol-function 'leetcode--cookie-get-all)
               (lambda () '(("LEETCODE_SESSION" "session-fixture") ("csrftoken" "csrf-fixture"))))
              ((symbol-function 'leetcode--show-testcases-result)
               (lambda (&rest _) (setq result-shown t)))
              ((symbol-function 'leetcode--show-submission-result)
               (lambda (&rest _) (setq result-shown t)))
              ((symbol-function 'aio-url-retrieve)
               (lambda (url &rest _)
                 (push url requests)
                 (cond
                  ((equal url leetcode--url-graphql)
                   (jb-leetcode-test--response
                    login-status
                    (if (= login-status 200)
                        "{\"data\":{\"userStatus\":{\"userId\":\"123\",\"username\":\"fixture\",\"isPremium\":false,\"isSignedIn\":true}}}"
                      "{\"error\":\"User is not authenticated\"}")))
                  ((string-suffix-p "/interpret_solution/" url)
                   (jb-leetcode-test--response
                    run-status
                    (if (= run-status 200)
                        "{\"interpret_id\":\"runcode_fixture\"}"
                      "{\"error\":\"User is not authenticated\"}")))
                  ((string-suffix-p "/submit/" url)
                   (jb-leetcode-test--response
                    run-status
                    (if (= run-status 200)
                        "{\"submission_id\":12345}"
                      "{\"error\":\"User is not authenticated\"}")))
                  ((string-match-p "/submissions/detail/" url)
                   (jb-leetcode-test--response 200 "{\"state\":\"SUCCESS\"}"))
                  (t (ert-fail "Unexpected HTTP endpoint"))))))
      (condition-case err
          (with-timeout (5 (ert-fail "Offline promise timed out"))
            (aio-wait-for (if submit (leetcode-submit) (leetcode-try))))
        (user-error (setq failure err))))
    (list :requests (nreverse requests) :result-shown result-shown :failure failure)))

(ert-deftest jb-leetcode-session-parses-only-cookie-values ()
  (jb-leetcode-test--with-env
      "# Unrelated credentials are not evaluated\nLEETCODE_PASSWORD=$(not-a-command)\nexport LEETCODE_SESSION = 'session-fixture' # comment\nLEETCODE_CSRFTOKEN=\"csrf-fixture\"\r\n"
    (should (equal (jb-leetcode--env-cookies)
                   '(("LEETCODE_SESSION" "session-fixture") ("csrftoken" "csrf-fixture"))))))

(ert-deftest jb-leetcode-session-rereads-updated-cookie-file ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=old\nLEETCODE_CSRFTOKEN=csrf\n"
    (should (equal (cadar (jb-leetcode--env-cookies)) "old"))
    (with-temp-file jb-leetcode-env-file
      (insert "LEETCODE_SESSION=old\nLEETCODE_SESSION=new\nLEETCODE_CSRFTOKEN=csrf\n"))
    (should (equal (cadar (jb-leetcode--env-cookies)) "new"))))

(ert-deftest jb-leetcode-session-does-not-expand-shell-expressions ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION='$(id)'\nLEETCODE_CSRFTOKEN=csrf\n"
    (should (equal (cadar (jb-leetcode--env-cookies)) "$(id)"))))

(ert-deftest jb-leetcode-session-rejects-missing-cookie-without-exposing-values ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=secret-fixture\n"
    (let ((err (should-error (jb-leetcode--env-cookies) :type 'user-error)))
      (should-not (string-match-p "secret-fixture" (error-message-string err))))))

(ert-deftest jb-leetcode-session-rejects-unsafe-or-malformed-values ()
  (dolist (value '("''" "'unterminated" "\"mismatched'" "'cookie; injected'" "'line\rbreak'"))
    (jb-leetcode-test--with-env
        (concat "LEETCODE_SESSION=" value "\nLEETCODE_CSRFTOKEN=csrf\n")
      (should-error (jb-leetcode--env-cookies) :type 'user-error))))

(ert-deftest jb-leetcode-session-reports-unreadable-file ()
  (jb-leetcode-test--with-env ""
    (let ((jb-leetcode-env-file (concat jb-leetcode-env-file ".missing")))
      (should-error (jb-leetcode--env-cookies) :type 'user-error))))

(ert-deftest jb-leetcode-session-never-installs-browser-cookie-helper ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=session\nLEETCODE_CSRFTOKEN=csrf\n"
    (should (eq (leetcode--check-deps) t))
    (should (equal (leetcode--cookie-get-all)
                   '(("LEETCODE_SESSION" "session") ("csrftoken" "csrf"))))))

(ert-deftest jb-leetcode-session-failed-run-never-checks-a-nil-id ()
  (dolist (status '(403 429))
    (jb-leetcode-test--with-env ""
      (let* ((result (jb-leetcode-test--run 200 status))
             (requests (plist-get result :requests)))
        (should (plist-get result :failure))
        (should (= (length requests) 3))
        (should-not (seq-some (lambda (url) (string-match-p "/submissions/detail/" url)) requests))
        (should-not (plist-get result :result-shown))))))

(ert-deftest jb-leetcode-session-failed-login-clears-state-and-stops-immediately ()
  (dolist (status '(403 429))
    (jb-leetcode-test--with-env ""
      (setf (leetcode-user-username leetcode--user) "cached-user"
            (leetcode-user-id leetcode--user) "cached-id")
      (let* ((result (jb-leetcode-test--run status 200))
             (requests (plist-get result :requests)))
        (should (plist-get result :failure))
        (should (string-match-p (format "HTTP %d" status)
                                (error-message-string (plist-get result :failure))))
        (should (equal requests (list leetcode--url-graphql)))
        (should-not (leetcode--login-p))
        (should-not (leetcode-user-id leetcode--user))))))

(ert-deftest jb-leetcode-session-successful-run-keeps-valid-result-check ()
  (jb-leetcode-test--with-env ""
    (let ((result (jb-leetcode-test--run 200 200)))
      (should-not (plist-get result :failure))
      (should (plist-get result :result-shown))
      (should (= (length (plist-get result :requests)) 4))
      (should (member "https://leetcode.com/submissions/detail/runcode_fixture/check/"
                      (plist-get result :requests))))))

(ert-deftest jb-leetcode-session-env-cookies-work-through-real-login ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=session-fixture\nLEETCODE_CSRFTOKEN=csrf-fixture\n"
    (let ((requests 0))
      (cl-letf (((symbol-function 'aio-url-retrieve)
                 (lambda (url &rest _)
                   (should (equal url leetcode--url-graphql))
                   (should (equal (leetcode--maybe-session) "session-fixture"))
                   (should (equal (leetcode--maybe-csrf-token) "csrf-fixture"))
                   (cl-incf requests)
                   (jb-leetcode-test--response
                    200 "{\"data\":{\"userStatus\":{\"userId\":\"123\",\"username\":\"fixture\",\"isPremium\":false,\"isSignedIn\":true}}}"))))
        (aio-wait-for (leetcode--ensure-login t)))
      (should (= requests 2))
      (should (leetcode--login-p)))))

(ert-deftest jb-leetcode-session-allows-upstream-two-pass-login ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=session-fixture\nLEETCODE_CSRFTOKEN=csrf-fixture\n"
    (let ((requests 0))
      (cl-letf (((symbol-function 'aio-url-retrieve)
                 (lambda (_url &rest _)
                   (cl-incf requests)
                   (jb-leetcode-test--response
                    200
                    (if (= requests 1)
                        "{\"data\":{\"userStatus\":{\"userId\":null,\"username\":null,\"isPremium\":false,\"isSignedIn\":false}}}"
                      "{\"data\":{\"userStatus\":{\"userId\":\"123\",\"username\":\"fixture\",\"isPremium\":false,\"isSignedIn\":true}}}")))))
        (aio-wait-for (leetcode--ensure-login t)))
      (should (= requests 2))
      (should (leetcode--login-p)))))

(ert-deftest jb-leetcode-session-signed-out-json-does-not-keep-cached-identity ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=session-fixture\nLEETCODE_CSRFTOKEN=csrf-fixture\n"
    (setf (leetcode-user-username leetcode--user) "cached-user")
    (let ((requests 0))
      (cl-letf (((symbol-function 'aio-url-retrieve)
                 (lambda (_url &rest _)
                   (cl-incf requests)
                   (jb-leetcode-test--response
                    200 "{\"data\":{\"userStatus\":{\"userId\":null,\"username\":null,\"isPremium\":false,\"isSignedIn\":false}}}"))))
        (should-error (aio-wait-for (leetcode--ensure-login t)) :type 'user-error))
      (should (= requests 2))
      (should-not (leetcode--login-p)))))

(ert-deftest jb-leetcode-session-reports-cloudflare-challenge-without-retrying ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=session-fixture\nLEETCODE_CSRFTOKEN=csrf-fixture\n"
    (let ((requests 0))
      (cl-letf (((symbol-function 'aio-url-retrieve)
                 (lambda (_url &rest _)
                   (cl-incf requests)
                   (jb-leetcode-test--response
                    429 "<html>challenge fixture</html>" "Cf-Mitigated: challenge\r\n"))))
        (let ((err (should-error (aio-wait-for (leetcode--ensure-login t)) :type 'user-error)))
          (should (string-match-p "HTTP 429, Cloudflare challenge" (error-message-string err)))
          (should-not (string-match-p "session-fixture\\|csrf-fixture" (error-message-string err)))))
      (should (= requests 1))
      (should-not (leetcode--login-p)))))

(ert-deftest jb-leetcode-session-second-pass-http-error-clears-first-pass-identity ()
  (jb-leetcode-test--with-env "LEETCODE_SESSION=session-fixture\nLEETCODE_CSRFTOKEN=csrf-fixture\n"
    (let ((requests 0))
      (cl-letf (((symbol-function 'aio-url-retrieve)
                 (lambda (_url &rest _)
                   (cl-incf requests)
                   (if (= requests 1)
                       (jb-leetcode-test--response
                        200 "{\"data\":{\"userStatus\":{\"userId\":\"123\",\"username\":\"fixture\",\"isPremium\":false,\"isSignedIn\":true}}}")
                     (jb-leetcode-test--response 403 "{\"error\":\"User is not authenticated\"}")))))
        (should-error (aio-wait-for (leetcode--ensure-login t)) :type 'user-error))
      (should (= requests 2))
      (should-not (leetcode--login-p))
      (should-not (leetcode-user-id leetcode--user)))))

(ert-deftest jb-leetcode-session-successful-submission-keeps-valid-result-check ()
  (jb-leetcode-test--with-env ""
    (let ((result (jb-leetcode-test--run 200 200 t)))
      (should-not (plist-get result :failure))
      (should (plist-get result :result-shown))
      (should (= (length (plist-get result :requests)) 4))
      (should (member "https://leetcode.com/submissions/detail/12345/check/"
                      (plist-get result :requests))))))

(ert-deftest jb-leetcode-session-failed-submission-still-stops-before-result-check ()
  (dolist (status '(403 429))
    (jb-leetcode-test--with-env ""
      (let* ((result (jb-leetcode-test--run 200 status t))
             (requests (plist-get result :requests)))
        (should (= (length requests) 3))
        (should-not (plist-get result :result-shown))
        (should-not (seq-some (lambda (url) (string-match-p "/submissions/detail/" url)) requests))))))

(ert-deftest jb-leetcode-session-rejects-missing-result-ids ()
  (dolist (id '(nil "" "  " "nil" "null" 0))
    (should-error (jb-leetcode--require-result-id id) :type 'user-error))
  (dolist (id '(123 "123" "runcode_123.456_fixture"))
    (jb-leetcode--require-result-id id)))

;;; leetcode-session-test.el ends here
