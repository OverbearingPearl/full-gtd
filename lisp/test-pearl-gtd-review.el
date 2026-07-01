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

(test-pearl-gtd-define-story test-pearl-gtd-review-daily-shows-separated-sections
  "Daily review shows Today, Next Actions, and Inbox in separate tables."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* New idea\n:PROPERTIES:\n:ID: d-1\n:CREATED: 2026-01-15\n:END:\n")
          ("actions.org" "* TODO Today task\nSCHEDULED: <2026-01-15 Thu>\n:PROPERTIES:\n:ID: d-2\n:PROJECT: Web\n:CREATED: 2026-01-10\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: d-3\n:PROJECT: App\n:CREATED: 2026-01-11\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (pearl-gtd-review-daily)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Daily Review*"))
             (with-current-buffer "*Pearl-GTD Daily Review*"
               ;; Verify sections exist
               (goto-char (point-min))
               (should (search-forward "** actions.org - Today" nil t))
               (should (search-forward "** actions.org - Next Actions" nil t))
               (should (search-forward "** inbox.org - Inbox" nil t))
               ;; Verify Today task is in Today section, not in Next Actions
               (goto-char (point-min))
               (let* ((today-start (search-forward "** actions.org - Today"))
                      (today-end (save-excursion
                                   (search-forward "** actions.org - Next Actions" nil t)
                                   (line-beginning-position))))
                 ;; Verify Today task is in Today section
                 (goto-char today-start)
                 (should (search-forward "Today task" today-end t))
                 ;; Verify Next task is NOT in Today section
                 (goto-char today-start)
                 (should-not (search-forward "Next task" today-end t)))
               ;; Verify Next Actions contains Next task but not Today task
               (goto-char (point-min))
               (let* ((next-start (search-forward "** actions.org - Next Actions"))
                      (next-end (point-max)))
                 (goto-char next-start)
                 (should (search-forward "Next task" next-end t))
                 (goto-char next-start)
                 (should-not (search-forward "Today task" next-end t)))
               ;; Verify new columns exist using regex to match aligned headers
               (goto-char (point-min))
               (should (search-forward-regexp "|[ \t]*Headline[ \t]*|[ \t]*Status[ \t]*|[ \t]*Scheduled[ \t]*|[ \t]*Deadline[ \t]*|[ \t]*Context[ \t]*|[ \t]*Delegated[ \t]*|[ \t]*Project[ \t]*|[ \t]*Created[ \t]*|" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-weekly-shows-all-sections
  "Weekly review aggregates all lists and action sub-views into separate tables."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Unprocessed\n:PROPERTIES:\n:ID: w-1\n:END:\n")
          ("actions.org" "* TODO Normal action\n:PROPERTIES:\n:ID: w-2\n:PROJECT: Active project\n:END:\n* TODO Overdue task\nSCHEDULED: <2026-01-01 Wed>\n:PROPERTIES:\n:ID: w-overdue\n:END:\n* TODO Delegated task\n:PROPERTIES:\n:ID: w-del\n:DELEGATED: Bob\n:END:\n")
          ("someday.org" "* Maybe later\n:PROPERTIES:\n:ID: w-4\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Verify all sections present
               (goto-char (point-min))
               (should (search-forward "** inbox.org - Inbox" nil t))
               (should (search-forward "** actions.org - Overdue" nil t))
               (should (search-forward "** actions.org - Upcoming Deadlines" nil t))
               (should (search-forward "** actions.org - Delegated" nil t))
               (should (search-forward "** actions.org - Next Actions" nil t))
               (should (search-forward "** Projects - Stuck" nil t))
               (should (search-forward "** Projects - Active" nil t))
               (should (search-forward "** someday.org - Someday" nil t))
               ;; Verify content isolation
               (goto-char (point-min))
               (search-forward "** actions.org - Overdue")
               (should (search-forward "Overdue task" nil t))
               (goto-char (point-min))
               (search-forward "** actions.org - Delegated")
               (should (search-forward "Delegated task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-context-with-default
  "Press 'c' to edit context with current value as default."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (concat "* TODO Task with context\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a") ">\n:PROPERTIES:\n:ID: edit-ctx-1\n:CONTEXT: home\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional initial _history)
            (should (string-match-p "home" initial))
            "office")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Today")
            (search-forward "Task with context")
            (beginning-of-line)
            (pearl-gtd-review--edit-context-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":CONTEXT:\\s-*office")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-remove-context-by-empty-input
  "Press 'c' and delete all to remove context property."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (concat "* TODO Task to clear\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a") ">\n:PROPERTIES:\n:ID: edit-ctx-2\n:CONTEXT: home\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string= initial "home"))
            "")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Today")
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
  :files (("actions.org" "* TODO Delegated task\n:PROPERTIES:\n:ID: edit-del-1\n:DELEGATED: John\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string= initial "John"))
            "Bob")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Delegated")
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
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-schedule-with-default
  "Press 't' to edit scheduled date with current value as default."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (concat "* TODO Scheduled task\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a") ">\n:PROPERTIES:\n:ID: edit-sch-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string-match-p (format-time-string "%Y-%m-%d") (or initial "")))
            "2026-05-15")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Today")
            (search-forward "Scheduled task")
            (beginning-of-line)
            (pearl-gtd-review--edit-scheduled-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-05-15"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "SCHEDULED: <2026-01-01")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-jump-to-task-from-table
  "Press RET to jump to task in source file."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Jump target\n:PROPERTIES:\n:ID: jump-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock nil
  :body (progn
         (pearl-gtd-review-weekly)
         (with-current-buffer "*Pearl-GTD Weekly Review*"
           (goto-char (point-min))
           (search-forward "** actions.org - Next Actions")
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

(test-pearl-gtd-define-story test-pearl-gtd-review-keybinding-set-deadline
  "Press 's' in review buffer to set deadline for task at point."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task for deadline\n:PROPERTIES:\n:ID: dl-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Deadline" prompt) "2026-05-20")
             ((string-match "Reminder" prompt) "2")
             (t "")))))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Task for deadline")
            (beginning-of-line)
            (pearl-gtd-review--set-deadline-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-05-20"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER_DAYS: 2")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-edits-task-in-review-window
  "User edits a task directly from review buffer."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Old task name\n:PROPERTIES:\n:ID: edit-old-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Updated task name")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Old task name")
            (beginning-of-line)
            (pearl-gtd-review--rename-task-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Updated task name"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "* TODO Old task name")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-jump-across-sections-and-files
  "RET jump works correctly from tasks in different sections and source files."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Today task\nSCHEDULED: <2026-01-15 Thu>\n:PROPERTIES:\n:ID: jump-sec-1\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: jump-sec-2\n:END:\n")
          ("inbox.org" "* Inbox item\n:PROPERTIES:\n:ID: jump-sec-3\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Next task")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
             (with-current-buffer (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (should (looking-at-p "\\*+ TODO Next task"))))
  :teardown (progn
              (kill-buffer "*Pearl-GTD Daily Review*")
              (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(provide 'test-pearl-gtd-review)

;;; test-pearl-gtd-review.el ends here
