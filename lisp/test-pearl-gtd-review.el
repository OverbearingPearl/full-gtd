;;; test-pearl-gtd-review.el --- User stories: Review phase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for periodic reviews.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-review-daily-uses-table-view
  "Daily review shows inbox and today tasks in table format."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* New idea\n:PROPERTIES:\n:ID: table-1\n:END:\n")
          ("actions.org" (format "* TODO Daily task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: table-2\n:END:\n"
                                (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-review-daily)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Daily Review*"))
             (with-current-buffer "*Pearl-GTD Daily Review*"
               (goto-char (point-min))
               ;; Check for table header and content (without strict column alignment)
               (should (search-forward "Headline" nil t))
               (goto-char (point-min))
               (should (search-forward "New idea" nil t))
               (goto-char (point-min))
               (should (search-forward "Daily task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-context-with-default
  "Press 'c' to edit context with current value as default, empty to remove."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Task with context\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: edit-ctx-1\n:CONTEXT: home\n:END:\n"
                                (format-time-string "%Y-%m-%d"))))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional initial _history)
            (should (string-match-p "home" initial))
            "office")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "Task with context")
            (beginning-of-line)
            (pearl-gtd-review--edit-context-at-point)))
  :asserts (progn
             ;; Use regex to match property with optional extra spaces
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":CONTEXT:\\s-*office"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          ":CONTEXT:\\s-*home")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-remove-context-by-empty-input
  "Press 'c' and delete all to remove context property."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Task to clear\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: edit-ctx-2\n:CONTEXT: home\n:END:\n"
                                (format-time-string "%Y-%m-%d"))))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string= initial "home"))
            "")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "Task to clear")
            (beginning-of-line)
            (pearl-gtd-review--edit-context-at-point)))
  :asserts (should-not (test-pearl-gtd-file-contains-p
                        (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                        ":CONTEXT:"))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-delegated-with-default
  "Press 'd' to edit delegated with current value shown."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Delegated task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: edit-del-1\n:DELEGATED: John\n:END:\n"
                                (format-time-string "%Y-%m-%d"))))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string= initial "John"))
            "Bob")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "Delegated task")
            (beginning-of-line)
            (pearl-gtd-review--edit-delegated-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":DELEGATED: Bob"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          ":DELEGATED: John")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-schedule-with-default
  "Press 't' to edit scheduled date with current value as default."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Scheduled task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: edit-sch-1\n:END:\n"
                                (format-time-string "%Y-%m-%d"))))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string-match-p (format-time-string "%Y-%m-%d") (or initial "")))
            "2026-05-15")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "Scheduled task")
            (beginning-of-line)
            (pearl-gtd-review--edit-scheduled-at-point)))
  :asserts (progn
             ;; org-schedule adds day of week to date, so we check for date prefix only
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-05-15"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "SCHEDULED: <2026-05-01")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-jump-to-task-from-table
  "Press RET to jump to task in source file."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Jump target\n:PROPERTIES:\n:ID: jump-1\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "Jump target")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
             (with-current-buffer (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (should (looking-at-p "\\*+ TODO Jump target"))))
  :teardown (progn
             (kill-buffer "*Pearl-GTD Weekly Review*")
             (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
               (when buf (kill-buffer buf)))))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-runs-daily-review
  "User runs daily review to check today's actions and inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* New idea\n:PROPERTIES:\n:ID: daily-test-1\n:END:\n")
          ("actions.org" (format "* TODO Daily task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: daily-test-2\n:END:\n"
                                (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-review-daily)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Daily Review*"))
             (with-current-buffer "*Pearl-GTD Daily Review*"
               (goto-char (point-min))
               (should (search-forward "Daily task" nil t))
               (goto-char (point-min))
               (should (search-forward "New idea" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-runs-weekly-review
  "User runs weekly review across all lists."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Unprocessed\n:PROPERTIES:\n:ID: weekly-1\n:END:\n")
          ("actions.org" "* TODO Weekly task\n:PROPERTIES:\n:ID: weekly-2\n:END:\n")
          ("projects.org" "* Active project\n:PROPERTIES:\n:ID: weekly-3\n:END:\n")
          ("someday.org" "* Maybe later\n:PROPERTIES:\n:ID: weekly-4\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               (should (search-forward "Unprocessed" nil t))
               (should (search-forward "Weekly task" nil t))
               (should (search-forward "Active project" nil t))
               (should (search-forward "Maybe later" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-filters-undelegated-tasks
  "User reviews tasks that are not delegated."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task A\n:PROPERTIES:\n:ID: undel-1\n:DELEGATED: John\n:END:\n* TODO Task B\n:PROPERTIES:\n:ID: undel-2\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-undelegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Undelegated*"))
             (with-current-buffer "*Pearl-GTD: Undelegated*"
               (should (search-forward "Task B" nil t))
               (should-not (search-forward "Task A" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Undelegated*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-edits-task-in-review-window
  "User edits a task directly from review buffer."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Old task name\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: edit-old-1\n:END:\n"
                                (format-time-string "%Y-%m-%d"))))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Updated task name")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "Old task name")
            (beginning-of-line)
            (pearl-gtd-review--rename-task-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Updated task name"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Old task name")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-checks-overdue-tasks
  "User reviews overdue scheduled tasks."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Overdue task\nSCHEDULED: <2026-01-01>\n:PROPERTIES:\n:ID: overdue-1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-overdue)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Overdue*"))
             (with-current-buffer "*Pearl-GTD: Overdue*"
               (should (search-forward "Overdue task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Overdue*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-checks-stuck-projects
  "User reviews projects with no next actions."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Stuck project\n:PROPERTIES:\n:ID: stuck-1\n:CREATED: 2026-01-01\n:END:\n")
           ("actions.org" ""))
  :mock nil
  :body (pearl-gtd-review-stuck-projects)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Stuck Projects*"))
             (with-current-buffer "*Pearl-GTD: Stuck Projects*"
               (should (search-forward "Stuck project" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Stuck Projects*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-sets-deadline-with-reminder
  "User sets deadline with automatic reminder before due date."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task with deadline\n:PROPERTIES:\n:ID: deadline-1\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Deadline" prompt) "2026-05-20")
             ((string-match "Reminder days" prompt) "2")
             (t "")))))
  :body (progn
          (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
          (goto-char (point-min))
          (pearl-gtd-review-set-deadline))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-05-20"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER_DAYS: 2")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-review-user-views-upcoming-deadlines
  "User views tasks with deadlines in next 7 days."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Near deadline\nDEADLINE: <%s>\n:PROPERTIES:\n:ID: upcoming-1\n:END:\n* TODO Far deadline\nDEADLINE: <%s>\n:PROPERTIES:\n:ID: upcoming-2\n:END:\n"
                                  (format-time-string "%Y-%m-%d" (time-add (current-time) (days-to-time 3)))
                                  (format-time-string "%Y-%m-%d" (time-add (current-time) (days-to-time 30))))))
  :mock nil
  :body (pearl-gtd-review-view-upcoming-deadlines)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Upcoming Deadlines*"))
             (with-current-buffer "*Pearl-GTD: Upcoming Deadlines*"
               (should (search-forward "Near deadline" nil t))
               (should-not (search-forward "Far deadline" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Upcoming Deadlines*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-receives-due-reminders
  "User checks and receives notifications for due reminders."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Task with reminder\nDEADLINE: <%s>\n:PROPERTIES:\n:ID: remind-1\n:REMINDER_DAYS: 0\n:END:\n"
                                  (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-review-check-reminders)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Reminders*"))
             (with-current-buffer "*Pearl-GTD: Reminders*"
               (should (search-forward "Task with reminder" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Reminders*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-tracks-delegation-status
  "User checks status of delegated tasks and sees waiting time."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Delegated task\n:PROPERTIES:\n:ID: track-1\n:DELEGATED: Bob\n:DELEGATED_DATE: <%s>\n:END:\n"
                                  (format-time-string "%Y-%m-%d" (time-subtract (current-time) (days-to-time 54))))))
  :mock nil
  :body (pearl-gtd-review-track-delegation-status)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated Status*"))
             (with-current-buffer "*Pearl-GTD: Delegated Status*"
               (goto-char (point-min))
               (should (search-forward "Bob" nil t))
               (should (search-forward "54 days" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated Status*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-sends-reminder-for-overdue-delegation
  "User sends reminder for overdue delegated task."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Overdue delegated task\nDEADLINE: <2026-04-01>\n:PROPERTIES:\n:ID: send-1\n:DELEGATED: Charlie\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
  :body (progn
          (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
          (goto-char (point-min))
          (pearl-gtd-review-send-delegation-reminder))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER_SENT:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-review-weekly-shows-multiple-files
  "Weekly review table shows entries from inbox, actions, projects, someday."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Inbox item\n:PROPERTIES:\n:ID: multi-1\n:END:\n")
          ("actions.org" "* TODO Action item\n:PROPERTIES:\n:ID: multi-2\n:END:\n")
          ("projects.org" "* Project item\n:PROPERTIES:\n:ID: multi-3\n:END:\n")
          ("someday.org" "* Someday item\n:PROPERTIES:\n:ID: multi-4\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Check for table header and content (without strict column alignment)
               (should (search-forward "Headline" nil t))
               (should (search-forward "File" nil t))
               (should (search-forward "Inbox item" nil t))
               (should (search-forward "inbox.org" nil t))
               (should (search-forward "Action item" nil t))
               (should (search-forward "actions.org" nil t))
               (should (search-forward "Project item" nil t))
               (should (search-forward "projects.org" nil t))
               (should (search-forward "Someday item" nil t))
               (should (search-forward "someday.org" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(provide 'test-pearl-gtd-review)

;;; test-pearl-gtd-review.el ends here
