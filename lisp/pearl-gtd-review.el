;;; pearl-gtd-review.el --- Review phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file handles the "Review" phase of GTD, including delegation tracking and reminders.

;;; Code:

(require 'org)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)

(defun pearl-gtd-review--daily ()
  "Run daily review."
  (let ((buffer-name "*Pearl-GTD Daily Review*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Daily Review\n")
      (insert "** Inbox\n")
      (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p inbox-file)
          (insert-file-contents inbox-file)))
      (insert "** Scheduled for Today\n")
      (let* ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
             (actions (pearl-gtd-core-filter-entries
                       actions-file
                       (list #'pearl-gtd-core-entry-todo-p
                             #'pearl-gtd-core-entry-scheduled-today-p))))
        (dolist (action actions)
          (insert (format "- %s\n" (nth 0 action)))))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--weekly ()
  "Run weekly review across all lists."
  (let ((buffer-name "*Pearl-GTD Weekly Review*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Weekly Review\n")
      (dolist (file '("inbox.org" "actions.org" "projects.org" "someday.org"))
        (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
          (when (file-exists-p file-path)
            (insert (format "** %s\n" (file-name-base file)))
            (insert-file-contents file-path)
            (goto-char (point-max))
            (unless (bolp) (insert "\n")))))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--undelegated ()
  "Review tasks that are not delegated."
  (let ((buffer-name "*Pearl-GTD: Undelegated*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Undelegated Tasks\n")
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p actions-file)
          (insert-file-contents actions-file)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (props (org-entry-properties)))
               (unless (assoc "DELEGATED" props)
                 (insert (format "- %s\n" head)))))
           "TODO" 'file)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--edit-task ()
  "Edit the task at point in the review buffer."
  (let ((head (org-get-heading t t)))
    (when head
      (let ((new-name (read-string "New task name: " head)))
        ;; Edit in actions.org directly - try to match headline without TODO keyword
        (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
          (when (file-exists-p actions-file)
            (with-current-buffer (find-file-noselect actions-file)
              (goto-char (point-min))
              ;; Try to match with or without TODO keyword
              (when (or (re-search-forward (concat "^\\*+ " (regexp-quote head) "\\($\\| \\)") nil t)
                        (re-search-forward (concat "^\\*+ TODO " (regexp-quote head) "\\($\\| \\)") nil t)
                        (re-search-forward (concat "^\\*+ " (regexp-quote (replace-regexp-in-string "^TODO " "" head)) "\\($\\| \\)") nil t))
                (org-edit-headline new-name)
                (save-buffer)
                (message "Task renamed to '%s'" new-name)))))))))

(defun pearl-gtd-review--overdue ()
  "Review overdue scheduled tasks."
  (let ((buffer-name "*Pearl-GTD: Overdue*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Overdue Tasks\n")
      (let* ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
             (actions (pearl-gtd-core-filter-entries
                       actions-file
                       (list #'pearl-gtd-core-entry-todo-p
                             #'pearl-gtd-core-entry-overdue-p))))
        (dolist (action actions)
          (insert (format "- %s\n" (nth 0 action)))))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--stuck-projects ()
  "Review projects with no next actions."
  (let ((buffer-name "*Pearl-GTD: Stuck Projects*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Stuck Projects\n")
      (let ((projects-file (expand-file-name "projects.org" pearl-gtd-init-base-directory))
            (actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (and (file-exists-p projects-file) (file-exists-p actions-file))
          (insert-file-contents projects-file)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (project-name (org-get-heading t t)))
               ;; Check if project has linked actions
               (with-temp-buffer
                 (insert-file-contents actions-file)
                 (unless (search-forward (format ":PROJECT:%s:" project-name) nil t)
                   (insert (format "- %s\n" head))))))
           "TODO" 'file)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--set-deadline ()
  "Set deadline for current task with reminder."
  (let ((deadline (read-string "Deadline (YYYY-MM-DD): "))
        (reminder (read-string "Reminder days before: ")))
    (unless (org-at-heading-p)
      (org-back-to-heading))
    (org-deadline nil deadline)
    (org-set-property "REMINDER_DAYS" reminder)
    (save-buffer)))

(defun pearl-gtd-review--view-upcoming-deadlines ()
  "View tasks with deadlines in next 7 days."
  (let ((buffer-name "*Pearl-GTD: Upcoming Deadlines*")
        (now (current-time))
        (tasks '()))
    (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
          (now-days (floor (/ (float-time now) 86400)))
          (seven-days-later (+ (floor (/ (float-time now) 86400)) 7)))
      (when (file-exists-p actions-file)
        (with-temp-buffer
          (insert-file-contents actions-file)
          (org-mode)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (deadline (org-entry-get nil "DEADLINE")))
               (when deadline
                 (let* ((deadline-time (org-time-string-to-time deadline))
                        (deadline-days (floor (/ (float-time deadline-time) 86400))))
                   (when (and (>= deadline-days now-days)
                              (<= deadline-days seven-days-later))
                     (push head tasks))))))
           nil nil))))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Upcoming Deadlines\n")
      (dolist (task (nreverse tasks))
        (insert (format "- %s\n" task)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--check-reminders ()
  "Check and display reminders for due tasks."
  (let ((buffer-name "*Pearl-GTD: Reminders*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Reminders\n")
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p actions-file)
          (insert-file-contents actions-file)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (deadline (org-entry-get nil "DEADLINE"))
                   (reminder-days (org-entry-get nil "REMINDER_DAYS")))
               (when (and deadline reminder-days)
                 (let ((deadline-time (org-time-string-to-time deadline))
                       (now (current-time))
                       (reminder-time (time-subtract deadline-time (days-to-time (string-to-number reminder-days)))))
                   (when (time-less-p reminder-time now)
                     (insert (format "- %s\n" head)))))))
           "TODO" 'file)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--track-delegation-status ()
  "Track status of delegated tasks and display waiting time."
  (let ((buffer-name "*Pearl-GTD: Delegated Status*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Delegated Task Status\n")
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p actions-file)
          (insert-file-contents actions-file)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (string= (org-get-todo-state) "TODO")
               (let* ((head (org-get-heading t t))
                      (props (org-entry-properties))
                      (delegated (cdr (assoc "DELEGATED" props)))
                      (delegated-date (org-entry-get nil "DELEGATED_DATE")))
                 (when delegated
                   (if delegated-date
                       (let* ((clean-date (string-trim delegated-date "<" ">"))
                              (del-time (date-to-time clean-date))
                              (diff (time-subtract (current-time) del-time))
                              (days-waiting (floor (/ (float-time diff) 86400))))
                         (insert (format "- %s (to %s, waiting %d days)\n" head delegated days-waiting)))
                     (insert (format "- %s (to %s, waiting unknown days)\n" head delegated)))))))
           nil nil)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review--send-delegation-reminder ()
  "Send reminder for overdue delegated task."
  (unless (org-at-heading-p)
    (org-back-to-heading))
  (let ((task (org-get-heading t t))
        (delegatee (org-entry-get nil "DELEGATED"))
        (deadline (org-entry-get nil "DEADLINE")))
    (when (and delegatee deadline task)
      (let ((deadline-time (org-time-string-to-time deadline)))
        (when (time-less-p deadline-time (current-time))
          (when (y-or-n-p (format "Send reminder to %s for task '%s'? " delegatee task))
            (org-set-property "REMINDER_SENT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
            (save-buffer)))))))

(provide 'pearl-gtd-review)

;;; pearl-gtd-review.el ends here
