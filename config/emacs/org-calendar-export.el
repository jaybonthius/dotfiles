;;; org-calendar-export.el --- Publish Org calendars in a batch process -*- lexical-binding: t; -*-

(require 'org)
(require 'org-agenda)
(require 'ox-icalendar)
(require 'seq)
(require 'subr-x)

(defconst jb-org-calendar-directory
  (expand-file-name "~/.local/share/org-calendar/")
  "Directory containing published iCalendar feeds.")

(defun jb-org-calendar-discover-agenda-files ()
  "Return ~/org/inbox.org and every schedule.org below ~/Code."
  (let ((inbox (expand-file-name "~/org/inbox.org"))
        (code-directory (expand-file-name "~/Code/")))
    (append (when (file-exists-p inbox) (list inbox))
            (when (file-directory-p code-directory)
              (directory-files-recursively
               code-directory "\\`schedule\\.org\\'")))))

(defun jb-org-calendar-discover-names ()
  "Return unique valid CALENDAR property values from agenda entries."
  (let (names)
    (org-map-entries
     (lambda ()
       (when-let ((name (org-entry-get nil "CALENDAR")))
         (unless (and (string-match-p "\\`[a-z0-9_]+\\'" name)
                      (not (string= name "agenda")))
           (user-error
            "CALENDAR must use lowercase letters, numbers, or underscores: %s"
            name))
         (push name names)))
     nil 'agenda 'comment)
    (sort (delete-dups names) #'string<)))

(defun jb-org-calendar-export-feed (name matcher)
  "Export entries matching MATCHER atomically to NAME.ics."
  (let* ((output (expand-file-name (concat name ".ics")
                                   jb-org-calendar-directory))
         (temporary-org-file (make-temp-file "org-calendar-" nil ".org"))
         (temporary-ics-file
          (make-temp-file (expand-file-name (concat "." name "-")
                                            jb-org-calendar-directory)
                          nil ".ics.tmp"))
         (org-agenda-sticky t)
         agenda-buffer)
    (unwind-protect
        (progn
          (org-tags-view nil matcher)
          (setq agenda-buffer (current-buffer))
          (org-agenda-write temporary-org-file)
          (with-temp-buffer
            (let ((buffer-file-name
                   (expand-file-name (concat name ".org")
                                     temporary-file-directory)))
              (insert "#+TITLE: " name "\n")
              (insert-file-contents temporary-org-file)
              (org-mode)
              (org-export-to-file 'icalendar temporary-ics-file)))
          (rename-file temporary-ics-file output t))
      (when (buffer-live-p agenda-buffer)
        (kill-buffer agenda-buffer))
      (when (file-exists-p temporary-org-file)
        (delete-file temporary-org-file))
      (when (file-exists-p temporary-ics-file)
        (delete-file temporary-ics-file)))))

(defun jb-org-calendar-export-all ()
  "Publish mutually exclusive Org calendar feeds."
  (setq org-agenda-files (jb-org-calendar-discover-agenda-files))
  (unless org-agenda-files
    (user-error "No Org calendar source files found"))
  (make-directory jb-org-calendar-directory t)
  (jb-org-calendar-export-feed "agenda" "CALENDAR=\"\"")
  (dolist (name (jb-org-calendar-discover-names))
    (jb-org-calendar-export-feed
     name (format "CALENDAR=\"%s\"" name))))

(setq org-icalendar-store-UID t
      org-icalendar-include-todo nil
      org-icalendar-use-scheduled '(event-if-todo-not-done)
      org-icalendar-scheduled-summary-prefix ""
      org-icalendar-use-deadline '(event-if-todo-not-done)
      org-icalendar-timezone "America/Los_Angeles"
      org-icalendar-alarm-time 15
      org-icalendar-ttl "PT15M"
      org-icalendar-exclude-tags '("nocal"))

(when noninteractive
  (condition-case err
      (jb-org-calendar-export-all)
    (error
     (message "Org calendar export failed: %s" (error-message-string err))
     (kill-emacs 1))))

(provide 'org-calendar-export)
;;; org-calendar-export.el ends here
