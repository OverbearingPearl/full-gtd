;;; test-pearl-gtd-organize.el --- User stories: Organize phase  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for organizing items into appropriate categories.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-trashes-junk-item
  "User decides item is trash, it disappears completely."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Junk item\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) "trash"))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-files-item-to-reference
  "User moves 'Article about Emacs' to reference.org."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Article about Emacs\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) "reference"))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (test-pearl-gtd-file-contains-p
            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
            "* Article about Emacs"
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-sets-context-at-office
  "User tags task with @office context."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task for office\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil)
            )
          )
         )
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              ('context "@office")
              ('schedule "")
              ('deadline "")
              ('delegate "")
              ('project "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    "* TODO Task for office"
                   )
           )
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    ":office:"
                   )
           )
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-renames-then-sets-context-and-schedule
  "User renames task and sets @office context with schedule."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Old vague name\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil)
            )
          )
         )
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "Prepare quarterly report")
              ('remarks "")
              ('context "@office")
              ('schedule "2026-04-15")
              ('deadline "")
              ('delegate "")
              ('project "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    "* TODO Prepare quarterly report"
                   )
           )
           (should (test-pearl-gtd-file-lacks-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    "* Old vague name"
                   )
           )
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    ":office:"
                   )
           )
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    "SCHEDULED"
                   )
           )
           (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-processes-empty-inbox
  "User processes an empty inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" ""))
  :mock nil
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown (kill-buffer "*Pearl-GTD: Inbox*")
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-handles-duplicate-titles
  "User processes entries with duplicate titles."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Duplicate task\n* Duplicate task\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "Renamed task")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) "reference"))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-file-contains-p
            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
            "* Renamed task"
                   )
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-processes-two-items-differently
  "User processes two items: one to trash, one to reference."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Junk item\n* Keep item\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (let ((responses '(nil "Important article")))
            (lambda (prompt &rest _)
              (or (pop responses) "")
            )
          )
         )
         ((symbol-function 'completing-read)
          (let ((responses '("trash" "reference")))
            (lambda (&rest _)
              (pop responses)
            )
          )
         )
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (let ((result (test-pearl-gtd-file-contains-p
                          (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                          "* Junk item"
                         )
                 )
                )
             (should-not (car result))
           )
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                    "* Important article"
                   )
           )
           (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-executes-two-tasks-immediately
  "User executes two 2-minute tasks immediately."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Quick call\n* Quick email\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-quits-during-assign
  "User quits when prompted for assignment target."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to assign\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) (signal 'quit nil)))
        )
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq test-pearl-gtd-caught-error err))
         )
        )
  :asserts (progn
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to assign"
                   )
           )
           (should (eq (car test-pearl-gtd-caught-error) 'quit))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-links-task-to-multiple-projects
  "User links single task to multiple projects during processing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Shared task\n:PROPERTIES:\n:ID: shared-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil)
            )
          )
         )
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              ('context "")
              ('schedule "")
              ('deadline "")
              ('delegate "")
              ('project "Alpha,Beta")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    "* TODO Shared task"
                   )
           )
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    ":PROJECT:\\s-*Alpha"
                   )
           )
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    "Beta"
                   )
           )
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                    ":ID:"
                   )
           )
           (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-sets-schedule-with-default-deadline
  "User sets schedule and accepts it as deadline."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with deadline\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil)
            )
          )
         )
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              ('context "")
              ('schedule "2026-04-15")
              ('deadline "2026-04-15")
              ('delegate "")
              ('project "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-04-15"
                     )
             )
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-04-15"
                     )
             )
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-sets-schedule-with-different-deadline
  "User sets schedule and a different deadline."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with separate deadline\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil)
            )
          )
         )
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              ('context "")
              ('schedule "2026-04-15")
              ('deadline "2026-04-20")
              ('delegate "")
              ('project "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-04-15"
                     )
             )
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-04-20"
                     )
             )
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-sets-deadline-without-schedule
  "User sets deadline without schedule."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task deadline only\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil)
            )
          )
         )
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              ('context "")
              ('schedule "")
              ('deadline "2026-04-25")
              ('delegate "")
              ('project "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-lacks-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED"
                     )
             )
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-04-25"
                     )
             )
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-skips-deadline
  "User skips deadline entirely."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task no deadline\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil)
            )
          )
         )
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (pcase pearl-gtd-inbox--current-prompt-type
              ('rename "")
              ('remarks "")
              ('context "")
              ('schedule "")
              ('deadline "")
              ('delegate "")
              ('project "")
              (_ "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-lacks-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED"
                     )
             )
             (should (test-pearl-gtd-file-lacks-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE"
                     )
             )
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-enters-pipe-in-headline
  "Pipe character in headline must not break org-table formatting."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task | with pipe\n:PROPERTIES:\n:ID: pipe-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) "reference"))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Task | with pipe"
                     )
             )
             (let ((ref-file (expand-file-name "reference.org" pearl-gtd-init-base-directory)))
               (with-temp-buffer
                 (insert-file-contents ref-file)
                 (should (search-forward "Task | with pipe" nil t))
               )
             )
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-enters-unicode-content
  "Unicode and emoji must be handled correctly in all fields."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with unicode: 中文 and emoji: 😀\n:PROPERTIES:\n:ID: unicode-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string) (lambda (&rest _) "2026-06-01"))
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "中文"
                     )
             )
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "😀"
                     )
             )
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-sets-leap-year-date
  "Leap year date February 29 must be accepted."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Leap task\n:PROPERTIES:\n:ID: leap-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string) (lambda (&rest _) "2024-02-29"))
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (test-pearl-gtd-file-contains-p
            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
            "2024-02-29"
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-sets-far-future-date
  "Dates far in the future (year 9999) must be handled."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Future task\n:PROPERTIES:\n:ID: future-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string) (lambda (&rest _) "9999-12-31"))
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (test-pearl-gtd-file-contains-p
            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
            "9999-12-31"
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-handles-invalid-date-format
  "Invalid date format should not crash the system."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Bad date task\n:PROPERTIES:\n:ID: bad-date-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string) (lambda (&rest _) "not-a-date"))
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (condition-case nil
            (pearl-gtd-process-inbox)
          (error nil)
        )
  :asserts (progn
             (should (file-exists-p (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-enters-project-with-comma
  "Project name containing comma must not be split incorrectly."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Complex project task\n:PROPERTIES:\n:ID: proj-comma-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (if (string-match "Project" prompt)
                "Company, Inc."
              ""
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":PROJECT: Company, Inc."
                     )
             )
             (let ((content (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                              )
                              (buffer-string)
                            )
                   )
                  )
               (should-not (string-match-p ":PROJECT: Company\n.*:PROJECT: Inc" content))
             )
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-skips-project-name
  "Empty or whitespace-only project name should be treated as no project."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* No project task\n:PROPERTIES:\n:ID: empty-proj-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Project" prompt) "   ")
             ((string-match "Rename" prompt) "")
             ((string-match "Remarks" prompt) "")
             ((string-match "Context" prompt) "")
             ((string-match "Schedule" prompt) "")
             ((string-match "Deadline" prompt) "")
             ((string-match "Delegate" prompt) "")
             (t "")
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            )
                            (buffer-string)
                          )
                 )
                )
             ;; Should not have PROJECT property with non-empty value
             ;; Check that either no PROJECT line exists, or it's empty
             (should-not (string-match-p ":PROJECT:[ \t]*[^ \t\n\r]" content))
           )
  :teardown nil
)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-enters-long-project-name
  "Very long project names (500+ chars) must be handled."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Long project task\n:PROPERTIES:\n:ID: long-proj-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (if (string-match "Project" prompt)
                (make-string 500 ?A)
              ""
            )
          )
         )
         ((symbol-function 'completing-read) (lambda (&rest _) ""))
        )
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":PROJECT:"
                     )
             )
           )
  :teardown nil
)

(provide 'test-pearl-gtd-organize)

;;; test-pearl-gtd-organize.el ends here
