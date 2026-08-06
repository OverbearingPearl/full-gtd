;;; pearl-gtd-test-review.el --- User stories: Review phase  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for periodic reviews.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-review-test-user-views-daily-sections
  "Daily review shows Today, Next Actions, and Inbox in separate tables."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* New idea\n:PROPERTIES:\n:ID: d-1\n:CREATED: 2026-01-15\n:END:\n")
          ("action.org" "* TODO Today task\nSCHEDULED: <2026-01-15 Thu>\n:PROPERTIES:\n:ID: d-2\n:PROJECT: Web\n:CREATED: 2026-01-10\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: d-3\n:PROJECT: App\n:CREATED: 2026-01-11\n:END:\n* DONE Completed today task\nCLOSED: [2026-01-15 Thu 10:00]\n:PROPERTIES:\n:ID: d-4\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026 t))))
  :body (pearl-gtd-review-daily)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Daily Review*"))
             (with-current-buffer "*Pearl-GTD Daily Review*"
               ;; Verify sections exist
               (goto-char (point-min))
               (should (search-forward "** action.org - Today" nil t))
               (should (search-forward "** action.org - Completed Today" nil t))
               (should (search-forward "** action.org - Next Actions" nil t))
               (should (search-forward "** inbox.org - Inbox" nil t))
               ;; Verify Today task is in Today section, not in Next Actions
               (goto-char (point-min))
               (let* ((today-start (search-forward "** action.org - Today"))
                      (today-end (save-excursion
                                   (search-forward "** action.org - Next Actions" nil t)
                                   (line-beginning-position))))
                 ;; Verify Today task is in Today section
                 (goto-char today-start)
                 (should (search-forward "Today task" today-end t))
                 ;; Verify Next task is NOT in Today section
                 (goto-char today-start)
                 (should-not (search-forward "Next task" today-end t)))
               ;; Verify Next Actions contains Next task but not Today task
               (goto-char (point-min))
               (let* ((next-start (search-forward "** action.org - Next Actions"))
                      (next-end (point-max)))
                 (goto-char next-start)
                 (should (search-forward "Next task" next-end t))
                 (goto-char next-start)
                 (should-not (search-forward "Today task" next-end t)))
               ;; Verify Today section has 7 columns (no Created)
               (goto-char (point-min))
               (search-forward "** action.org - Today")
               (forward-line 1)
               (beginning-of-line)
               (should (search-forward-regexp "|[ \t]*Headline[ \t]*|[ \t]*Status[ \t]*|[ \t]*Scheduled[ \t]*|[ \t]*Deadline[ \t]*|[ \t]*Context[ \t]*|[ \t]*Delegated[ \t]*|[ \t]*Project[ \t]*|" nil t))
               ;; Verify Inbox section has only 2 columns (Headline and Created)
               (goto-char (point-min))
               (search-forward "** inbox.org - Inbox")
               (forward-line 1)
               (beginning-of-line)
               (should (search-forward-regexp "|[ \t]*Headline[ \t]*|[ \t]*Created[ \t]*|" nil t))
               (should-not (search-forward-regexp "|[ \t]*Status[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Scheduled[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Deadline[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Context[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Delegated[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Project[ \t]*|" (line-end-position) t))
               ;; Verify GTD workflow order: Today → Completed Today → Next Actions → Inbox
               (goto-char (point-min))
               (let ((pos-today (search-forward "** action.org - Today" nil t))
                     (pos-completed (search-forward "** action.org - Completed Today" nil t))
                     (pos-next (search-forward "** action.org - Next Actions" nil t))
                     (pos-inbox (search-forward "** inbox.org - Inbox" nil t)))
                 (should (< pos-today pos-completed))
                 (should (< pos-completed pos-next))
                 (should (< pos-next pos-inbox)))
               ;; Verify completed task is in Completed Today section and not in Today
               (goto-char (point-min))
               (let* ((today-start (search-forward "** action.org - Today"))
                      (today-end (save-excursion
                                   (search-forward "** action.org - Completed Today" nil t)
                                   (line-beginning-position))))
                 (goto-char today-start)
                 (should-not (search-forward "Completed today task" today-end t)))
               (goto-char (point-min))
               (search-forward "** action.org - Completed Today")
               (should (search-forward "Completed today task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-views-weekly-sections
  "Weekly review aggregates all lists and action sub-views into separate tables."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Unprocessed\n:PROPERTIES:\n:ID: w-1\n:END:\n")
          ("action.org" "* TODO Normal action\n:PROPERTIES:\n:ID: w-2\n:PROJECT: Active project\n:END:\n* TODO Overdue task\nSCHEDULED: <2026-01-01 Wed>\n:PROPERTIES:\n:ID: w-overdue\n:END:\n* TODO Delegated task\n:PROPERTIES:\n:ID: w-del\n:DELEGATED: Bob\n:END:\n* DONE Completed today task\nCLOSED: [2026-01-15 Thu 10:00]\n:PROPERTIES:\n:ID: w-done-today\n:END:\n* TODO No project task\n:PROPERTIES:\n:ID: w-no-proj\n:END:\n")
          ("someday.org" "* Maybe later\n:PROPERTIES:\n:ID: w-4\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Verify all sections present
               (goto-char (point-min))
               (should (search-forward "** inbox.org - Inbox" nil t))
               (should (search-forward "** action.org - Overdue" nil t))
               (should (search-forward "** action.org - Upcoming Deadlines" nil t))
               (should (search-forward "** action.org - Completed" nil t))
               (should (search-forward "** action.org - Delegated" nil t))
               (should (search-forward "** action.org - Next Actions" nil t))
               (should (search-forward "** Projects - Stuck" nil t))
               (should (search-forward "** Projects - Active" nil t))
               (should (search-forward "** action.org - No Project" nil t))
               (should (search-forward "** someday.org - Someday" nil t))
               ;; Verify content isolation
               (goto-char (point-min))
               (search-forward "** action.org - Overdue")
               (should (search-forward "Overdue task" nil t))
               (goto-char (point-min))
               (search-forward "** action.org - Delegated")
               (should (search-forward "Delegated task" nil t))
               ;; Verify No Project section content
               (goto-char (point-min))
               (search-forward "** action.org - No Project")
               (should (search-forward "No project task" nil t))
               ;; Verify No Project section has correct columns (no Project column and no Created column)
               (goto-char (point-min))
               (search-forward "** action.org - No Project")
               (forward-line 1) ; Skip to table header (next line after title)
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Headline\\s-*|\\s-*Status\\s-*|\\s-*Scheduled\\s-*|\\s-*Deadline\\s-*|\\s-*Context\\s-*|\\s-*Delegated\\s-*|" nil t))
               (should-not (search-forward-regexp "|\\s-*Project\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*Created\\s-*|" (line-end-position) t))
               ;; Verify GTD weekly review order: Inbox → Overdue/Upcoming → Completed → Delegated → Next Actions → Projects → No Project → Someday
               (goto-char (point-min))
               (let ((positions (list (search-forward "** inbox.org - Inbox" nil t)
                                      (search-forward "** action.org - Overdue" nil t)
                                      (search-forward "** action.org - Upcoming Deadlines" nil t)
                                      (search-forward "** action.org - Completed" nil t)
                                      (search-forward "** action.org - Delegated" nil t)
                                      (search-forward "** action.org - Next Actions" nil t)
                                      (search-forward "** Projects - Stuck" nil t)
                                      (search-forward "** Projects - Active" nil t)
                                      (search-forward "** action.org - No Project" nil t)
                                      (search-forward "** someday.org - Someday" nil t))))
                 (should (equal positions (sort (copy-sequence positions) #'<))))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-edits-context-with-default
  "Press 'c' to edit context with current value as default."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" (concat "* TODO Task with context\nSCHEDULED: <" (format-time-string "%F %a") ">\n:PROPERTIES:\n:ID: edit-ctx-1\n:CONTEXT: home\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'pearl-gtd-core-read-property-with-completion)
          (lambda (_prompt _type &optional initial)
            (should (string-match-p "home" initial))
            "office"))
         ((symbol-function 'read-string)
          (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Today")
            (search-forward "Task with context")
            (beginning-of-line)
            (pearl-gtd-review--edit-context-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":CONTEXT:\\s-*office")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-removes-context-by-empty-input
  "Press 'c' and delete all to remove context property."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" (concat "* TODO Task to clear\nSCHEDULED: <" (format-time-string "%F %a") ">\n:PROPERTIES:\n:ID: edit-ctx-2\n:CONTEXT: home\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'pearl-gtd-core-read-property-with-completion)
          (lambda (_prompt _type &optional initial)
            (should (string= initial "home"))
            ""))
         ((symbol-function 'read-string)
          (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Today")
            (search-forward "Task to clear")
            (beginning-of-line)
            (pearl-gtd-review--edit-context-at-point)))
  :asserts (let ((result (pearl-gtd-test-file-contains-p
                          (expand-file-name "action.org" pearl-gtd-init-base-directory)
                          ":CONTEXT:")))
             (should-not (car result)))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-edits-delegated-with-default
  "Press 'd' to edit delegated with current value shown."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Delegated task\n:PROPERTIES:\n:ID: edit-del-1\n:DELEGATED: John\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-core-read-property-with-completion)
          (lambda (_prompt _type &optional initial)
            (should (string= initial "John"))
            "Bob"))
         ((symbol-function 'read-string)
          (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Delegated")
            (search-forward "Delegated task")
            (beginning-of-line)
            (pearl-gtd-review--edit-delegated-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":DELEGATED: Bob"))
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "action.org" pearl-gtd-init-base-directory)
                            ":DELEGATED: John")))
               (should-not (car result))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-edits-schedule-with-default
  "Press 't' to edit scheduled date with current value as default."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" (concat "* TODO Scheduled task\nSCHEDULED: <" (format-time-string "%F %a") ">\n:PROPERTIES:\n:ID: edit-sch-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string-match-p (format-time-string "%F") (or initial "")))
            "2026-05-15")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Today")
            (search-forward "Scheduled task")
            (beginning-of-line)
            (pearl-gtd-review--edit-scheduled-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-05-15"))
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "action.org" pearl-gtd-init-base-directory)
                            "SCHEDULED: <2026-01-01")))
               (should-not (car result))))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-jumps-to-task-from-table
  "Press RET to jump to task in source file."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Jump target\n:PROPERTIES:\n:ID: jump-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Next Actions")
            (search-forward "Jump target")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory)))
             (with-current-buffer (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory))
               (should (looking-at-p "\\*+ TODO Jump target"))))
  :teardown (progn
             (kill-buffer "*Pearl-GTD Weekly Review*")
             (let ((buf (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory))))
               (when buf (kill-buffer buf)))))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-sets-deadline-with-keybinding
  "Press 's' in review buffer to set deadline for task at point."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task for deadline\n:PROPERTIES:\n:ID: dl-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (when (string-match "Deadline" prompt)
              "2026-05-20"))))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Next Actions")
            (search-forward "Task for deadline")
            (beginning-of-line)
            (pearl-gtd-review--set-deadline-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-05-20")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-edits-task-in-review-window
  "User edits a task directly from review buffer."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Old task name\n:PROPERTIES:\n:ID: edit-old-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Updated task name")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Next Actions")
            (search-forward "Old task name")
            (beginning-of-line)
            (pearl-gtd-review--rename-task-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "* TODO Updated task name"))
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "action.org" pearl-gtd-init-base-directory)
                            "* TODO Old task name")))
               (should-not (car result))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-jumps-across-sections
  "RET jump works correctly from tasks in different sections and source files."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Today task\nSCHEDULED: <2026-01-15 Thu>\n:PROPERTIES:\n:ID: jump-sec-1\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: jump-sec-2\n:END:\n")
          ("inbox.org" "* Inbox item\n:PROPERTIES:\n:ID: jump-sec-3\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** action.org - Next Actions")
            (search-forward "Next task")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory)))
             (with-current-buffer (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory))
               (should (looking-at-p "\\*+ TODO Next task"))))
  :teardown (progn
              (kill-buffer "*Pearl-GTD Daily Review*")
              (let ((buf (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-views-project-stats
  "Project row displays total, todo, done counts and next deadline."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task 1\n:PROPERTIES:\n:ID: p1-1\n:PROJECT: Website\n:END:\n* DONE Task 2\n:PROPERTIES:\n:ID: p1-2\n:PROJECT: Website\n:END:\n* TODO Task 3\nDEADLINE: <2026-05-20>\n:PROPERTIES:\n:ID: p1-3\n:PROJECT: Website\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               (goto-char (point-min))
               (search-forward "** Projects - Active")
               (forward-line 3)
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Website\\s-*|\\s-*3\\s-*|\\s-*2\\s-*|\\s-*1\\s-*|\\s-*<2026-05-20[^>]*>\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-jumps-to-project-tasks
  "Press RET on project row opens project task sub-view."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task A\n:PROPERTIES:\n:ID: proj-a-1\n:PROJECT: Alpha\n:END:\n* TODO Task B\n:PROPERTIES:\n:ID: proj-a-2\n:PROJECT: Alpha\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "Alpha")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Project: Alpha*"))
             (with-current-buffer "*Pearl-GTD Project: Alpha*"
               (should (search-forward "Task A" nil t))
               (should (search-forward "Task B" nil t))
               ;; Verify table column count matches header (Created column must exist)
               (goto-char (point-min))
               (let* ((_header-start (search-forward "| Headline |" nil t))
                      (header-line (buffer-substring (line-beginning-position) (line-end-position)))
                      (pipe-count (cl-count ?| header-line)))
                 ;; 8 columns = 9 pipes (Headline Status Scheduled Deadline Context Delegated Project Created)
                 (should (= pipe-count 9))
                 ;; Verify exact column headers including Created
                 (should (string-match-p "Created" header-line)))
               ;; Verify data rows have same column count
               (goto-char (point-min))
               (search-forward "|---------") ; Skip to separator
               (forward-line 1)
               (let ((data-line (buffer-substring (line-beginning-position) (line-end-position))))
                 (should (= (cl-count ?| data-line) 9)))))
  :teardown (progn
              (kill-buffer "*Pearl-GTD Weekly Review*")
              (when (get-buffer "*Pearl-GTD Project: Alpha*")
                (kill-buffer "*Pearl-GTD Project: Alpha*"))))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-returns-from-project-view
  "Press q in project sub-view returns to weekly review."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: ret-1\n:PROJECT: Beta\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "Beta")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point))
          (with-current-buffer "*Pearl-GTD Project: Beta*"
            (pearl-gtd-review--quit-or-return)))
  :asserts (progn
             (should-not (get-buffer "*Pearl-GTD Project: Beta*"))
             (should (get-buffer "*Pearl-GTD Weekly Review*")))
  :teardown (when (get-buffer "*Pearl-GTD Weekly Review*")
              (kill-buffer "*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-identifies-stuck-project
  "Stuck project shows zero todo count."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* DONE Completed task\n:PROPERTIES:\n:ID: stuck-1\n:PROJECT: StuckProj\n:END:\n* Scheduled but no todo\nSCHEDULED: <2026-04-10 Fri>\n:PROPERTIES:\n:ID: stuck-2\n:PROJECT: StuckProj\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               (goto-char (point-min))
               (search-forward "** Projects - Stuck")
               (forward-line 3)
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*StuckProj\\s-*|\\s-*2\\s-*|\\s-*0\\s-*|\\s-*1\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-project-exact-match-not-substring
  "Project names that are substrings of each other are matched exactly."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* DONE P1 task\n:PROPERTIES:\n:ID: exact-1\n:PROJECT: P1\n:END:\n* TODO P10 task\n:PROPERTIES:\n:ID: exact-2\n:PROJECT: P10\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Get section boundaries first
               (goto-char (point-min))
               (let* ((stuck-pos (search-forward "** Projects - Stuck"))
                      (active-pos (search-forward "** Projects - Active"))
                      (someday-pos (search-forward "** someday.org - Someday"))
                      (stuck-start stuck-pos)
                      (stuck-end active-pos)
                      (active-start active-pos)
                      (active-end someday-pos))
                 ;; P1 has no TODO, must appear in Stuck
                 (goto-char stuck-start)
                 (should (re-search-forward "|\\s-*P1\\s-*|" stuck-end t))
                 (goto-char stuck-start)
                 (should-not (re-search-forward "|\\s-*P10\\s-*|" stuck-end t))
                 ;; P10 has TODO, must appear in Active
                 (goto-char active-start)
                 (should (re-search-forward "|\\s-*P10\\s-*|" active-end t))
                 (goto-char active-start)
                 (should-not (re-search-forward "|\\s-*P1\\s-*|" active-end t)))
               ;; Verify P1 stats: Total=1, Todo=0, Done=1
               (goto-char (point-min))
               (search-forward "** Projects - Stuck")
               (search-forward "P1")
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*P1\\s-*|\\s-*1\\s-*|\\s-*0\\s-*|\\s-*1\\s-*|" (line-end-position) t))
               ;; Verify P10 stats: Total=1, Todo=1, Done=0
               (goto-char (point-min))
               (search-forward "** Projects - Active")
               (search-forward "P10")
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*P10\\s-*|\\s-*1\\s-*|\\s-*1\\s-*|\\s-*0\\s-*|" (line-end-position) t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-review-test-weekly-no-project-table-no-project-column
  "No Project table should not have Project column and should be after Project sections."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO No project task 1\n:PROPERTIES:\n:ID: np-1\n:CREATED: 2026-01-15\n:END:\n* TODO No project task 2\nSCHEDULED: <2026-01-20 Fri>\n:PROPERTIES:\n:ID: np-2\n:CONTEXT: home\n:CREATED: 2026-01-16\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:CREATED: 2026-01-17\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Verify No Project section is after Project sections
               (goto-char (point-min))
               (let ((pos-active (search-forward "** Projects - Active" nil t))
                     (pos-no-project (search-forward "** action.org - No Project" nil t))
                     (pos-someday (search-forward "** someday.org - Someday" nil t)))
                 (should (< pos-active pos-no-project))
                 (should (< pos-no-project pos-someday)))
               ;; Verify No Project table has correct columns (7 columns: no Project and no Created, but with L3)
               (goto-char (point-min))
               (search-forward "** action.org - No Project")
               (forward-line 1) ; Skip to table header
               (beginning-of-line)
               (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                 ;; Count pipe separators - should be 8 pipes for 7 columns
                 (let ((pipe-count (cl-count ?| line)))
                   (should (= pipe-count 8)))
                 ;; Verify column headers
                 (should (string-match-p "Headline" line))
                 (should (string-match-p "Status" line))
                 (should (string-match-p "Scheduled" line))
                 (should (string-match-p "Deadline" line))
                 (should (string-match-p "Context" line))
                 (should (string-match-p "Delegated" line))
                 (should (string-match-p "L3" line))
                 (should-not (string-match-p "Project" line))
                 (should-not (string-match-p "Created" line)))
               ;; Verify data rows also have correct number of columns
               (goto-char (point-min))
               (search-forward "** action.org - No Project")
               (search-forward "|---------") ; Separator line
               (forward-line 1)
               (while (and (not (eobp)) (looking-at "|"))
                 (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                   (let ((pipe-count (cl-count ?| line)))
                     (should (= pipe-count 8))) ; 7 columns + closing pipe
                   (should (string-match-p "No project task" line))
                   (should-not (string-match-p "TestProject" line)))
                 (forward-line 1))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-renames-task-and-view-updates
  "Renaming task in review buffer should refresh display."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Old name\n:PROPERTIES:\n:ID: rename-view-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "New name")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "Old name")
            (beginning-of-line)
            (pearl-gtd-review--rename-task-at-point)))
  :asserts (with-current-buffer "*Pearl-GTD Weekly Review*"
             (goto-char (point-min))
             (should (search-forward "New name" nil t))
             (should-not (search-forward "Old name" nil t)))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-completes-no-project-task-deletes
  "Completing a task without project property should delete it."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO No project task\n:PROPERTIES:\n:ID: no-proj-1\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: proj-1\n:PROJECT: Test\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** action.org - No Project")
            (search-forward "No project task")
            (beginning-of-line)
            (pearl-gtd-review--complete-task-at-point)))
  :asserts (progn
             ;; Verify no-project task is deleted
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" pearl-gtd-init-base-directory)
                          "* TODO No project task"))
             ;; Verify project task remains
             (should (pearl-gtd-test-file-contains-p-bool
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "* TODO Project task")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-archives-completed-project
  "User can archive a project when all actions are DONE and none are shared."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* DONE Task 1\n:PROPERTIES:\n:ID: ar-1\n:PROJECT: ArchProj\n:END:\n* DONE Task 2\n:PROPERTIES:\n:ID: ar-2\n:PROJECT: ArchProj\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review--archive-project "ArchProj")
  :asserts (progn
             ;; action.org no longer contains ArchProj entries
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "action.org" pearl-gtd-init-base-directory)
                            ":PROJECT: ArchProj")))
               (should-not (car result)))
             ;; archive.org exists with project heading and task entries
             (should (file-exists-p (expand-file-name "archive.org" pearl-gtd-init-base-directory)))
             (let ((content (with-temp-buffer
                              (insert-file-contents (expand-file-name "archive.org" pearl-gtd-init-base-directory))
                              (buffer-string))))
               (should (string-match-p "\\* ArchProj" content))
               (should (string-match-p "Task 1" content))
               (should (string-match-p "Task 2" content))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Daily Review*" "*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-review-test-user-cannot-archive-project-with-todo-actions
  "Archiving fails when project still has non-DONE actions."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* DONE Task 1\n:PROPERTIES:\n:ID: todo-ar-1\n:PROJECT: MixedProj\n:END:\n* TODO Task 2\n:PROPERTIES:\n:ID: todo-ar-2\n:PROJECT: MixedProj\n:END:\n"))
  :mock nil
  :body (should-error (pearl-gtd-review--archive-project "MixedProj")
                      :type 'error)
  :asserts (progn
             ;; action.org still has both entries
             (should (pearl-gtd-test-file-contains-p-bool
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":PROJECT: MixedProj"))
             (should-not (file-exists-p (expand-file-name "archive.org" pearl-gtd-init-base-directory))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-review-test-user-cannot-archive-project-with-actions-in-other-projects
  "Archiving fails when a task belongs to multiple projects."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* DONE Task 1\n:PROPERTIES:\n:ID: multi-ar-1\n:PROJECT: ProjA; ProjB\n:END:\n* DONE Task 2\n:PROPERTIES:\n:ID: multi-ar-2\n:PROJECT: ProjA\n:END:\n"))
  :mock nil
  :body (should-error (pearl-gtd-review--archive-project "ProjA")
                      :type 'error)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p-bool
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "ProjA"))
             (should-not (file-exists-p (expand-file-name "archive.org" pearl-gtd-init-base-directory))))
  :teardown nil)

(provide 'pearl-gtd-review-test)

;;; pearl-gtd-review-test.el ends here
