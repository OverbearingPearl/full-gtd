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

(defun pearl-gtd-review-daily ()
  "Run daily review."
  (interactive)
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
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p actions-file)
          (insert-file-contents actions-file)
          (org-map-entries
           (lambda ()
             (let ((scheduled (org-entry-get nil "SCHEDULED")))
               (when (and scheduled (string-match-p (format-time-string "%Y-%m-%d") scheduled))
                 (org-mark-subtree)
                 (let ((content (buffer-substring (region-beginning) (region-end))))
                   (erase-buffer)
                   (insert content)))))
           "TODO" 'file)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review-weekly ()
  "Run weekly review across all lists."
  (interactive)
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

(defun pearl-gtd-review-undelegated ()
  "Review tasks that are not delegated."
  (interactive)
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

(defun pearl-gtd-review-edit-task ()
  "Edit the task at point in the review buffer."
  (interactive)
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

(defun pearl-gtd-review-overdue ()
  "Review overdue scheduled tasks."
  (interactive)
  (let ((buffer-name "*Pearl-GTD: Overdue*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Overdue Tasks\n")
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p actions-file)
          (insert-file-contents actions-file)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (scheduled (org-entry-get nil "SCHEDULED")))
               (when (and scheduled (time-less-p (org-time-string-to-time scheduled) (current-time)))
                 (insert (format "- %s\n" head)))))
           "TODO" 'file)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review-stuck-projects ()
  "Review projects with no next actions."
  (interactive)
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

(defun pearl-gtd-review-set-deadline ()
  "Set deadline for current task with reminder."
  (interactive)
  (let ((deadline (read-string "Deadline (YYYY-MM-DD): "))
        (reminder (read-string "Reminder days before: ")))
    ;; Ensure we're at a task heading
    (unless (org-at-heading-p)
      (org-back-to-heading))
    ;; Set deadline using org-deadline - pass date without angle brackets
    (org-deadline nil deadline)
    ;; Set reminder days property
    (org-set-property "REMINDER_DAYS" reminder)
    (save-buffer)))

(defun pearl-gtd-review-view-upcoming-deadlines ()
  "View tasks with deadlines in next 7 days."
  (interactive)
  (let ((buffer-name "*Pearl-GTD: Upcoming Deadlines*")
        (now (current-time)))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Upcoming Deadlines\n")
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
            (now-days (floor (/ (float-time now) 86400)))
            (seven-days-later (+ (floor (/ (float-time now) 86400)) 7)))
        (when (file-exists-p actions-file)
          (insert-file-contents actions-file)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (deadline (org-entry-get nil "DEADLINE")))
               (when deadline
                 (let* ((deadline-time (org-time-string-to-time deadline))
                        (deadline-days (floor (/ (float-time deadline-time) 86400))))
                   (when (and (>= deadline-days now-days)
                              (<= deadline-days seven-days-later))
                     (insert (format "- %s\n" head)))))))
           nil 'file)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review-check-reminders ()
  "Check and display reminders for due tasks."
  (interactive)
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

(defun pearl-gtd-review-track-delegation-status ()
  "Track status of delegated tasks and display waiting time."
  (interactive)
  (let ((buffer-name "*Pearl-GTD: Delegated Status*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Delegated Task Status\n")
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p actions-file)
          (insert-file-contents actions-file)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (props (org-entry-properties))
                   (delegated-date (org-entry-get nil "DELEGATED_DATE")))
               (when (assoc "DELEGATED" props)
                 (let ((days-waiting (if delegated-date
                                         (let* ((del-time (condition-case nil
                                                              (org-time-string-to-time delegated-date)
                                                            (error (date-to-time delegated-date))))
                                                (diff (time-subtract (current-time) del-time)))
                                           (floor (/ (float-time diff) 86400)))
                                       0)))
                   (insert (format "- %s (to %s, waiting %d days)\n" head (cdr (assoc "DELEGATED" props)) days-waiting))))))
           "TODO" 'file)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-review-send-delegation-reminder ()
  "Send reminder for overdue delegated task."
  (interactive)
  (let ((task (org-get-heading t t))
        (delegatee (org-entry-get nil "DELEGATED"))
        (deadline (org-entry-get nil "DEADLINE")))
    (when (and delegatee deadline task)
      (let ((deadline-time (org-time-string-to-time deadline)))
        (when (time-less-p deadline-time (current-time))
          (when (y-or-n-p (format "Send reminder to %s for task '%s'? " delegatee task))
            ;; Use org-set-property to set REMINDER_SENT
            (org-set-property "REMINDER_SENT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
            ;; Save the current buffer
            (save-buffer)
            (message "Reminder sent to %s for task '%s'." delegatee task)))))))

(provide 'pearl-gtd-review)

;;; pearl-gtd-review.el ends here
