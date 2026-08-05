;;; pearl-gtd-test-organize.el --- User stories: Organize phase  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for organizing items into appropriate categories.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-trashes-junk-item
  "User decides item is trash, it disappears completely."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Junk item\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?t))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (pearl-gtd-process-inbox)
  :asserts (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-files-item-to-reference
  "User moves 'Article about Emacs' to reference.org."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Article about Emacs\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (pearl-gtd-process-inbox)
  :asserts (pearl-gtd-test-file-contains-p
            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
            "* Article about Emacs")
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-sets-context-at-office
  "User tags task with @office context."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task for office\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    "* TODO Task for office"))
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    ":office:")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-inbox-test-staging-shows-tags
  "Staging buffer displays existing org tags."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with tag :office:\n:PROPERTIES:\n:ID: tag-test\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (with-current-buffer " *inbox-processing*"
             (goto-char (point-min))
             (search-forward "Task with tag")
             (beginning-of-line)
             (should (search-forward "| office |" (line-end-position) t)))
  :teardown (kill-buffer " *inbox-processing*"))

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-renames-then-sets-context-and-schedule
  "User renames task and sets @office context with schedule."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Old vague name\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons "Prepare quarterly report" nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "2026-04-15") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    "* TODO Prepare quarterly report"))
           (should (pearl-gtd-test-file-lacks-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    "* Old vague name"))
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    ":office:"))
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    "SCHEDULED"))
           (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-processes-empty-inbox
  "User processes an empty inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" ""))
  :mock nil
  :body (pearl-gtd-process-inbox)
  :asserts (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown (kill-buffer "*Pearl-GTD: Inbox*"))

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-handles-duplicate-titles
  "User processes entries with duplicate titles."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Duplicate task\n* Duplicate task\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons "Renamed task" nil))))
  :body (pearl-gtd-process-inbox)
  :asserts (should (pearl-gtd-test-file-contains-p
            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
            "* Renamed task"))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-processes-two-items-differently
  "User processes two items: one to trash, one to reference."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Junk item\n* Keep item\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?t ?r))))  ; First trash, then reference
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (headline)
            (if (string-match-p "Keep" headline)
                (cons "Important article" nil)
              (cons nil nil)))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (let ((result (pearl-gtd-test-file-contains-p
                          (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                          "* Junk item")))
             (should-not (car result)))
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                    "* Important article"))
           (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-executes-two-tasks-immediately
  "User executes two 2-minute tasks immediately."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Quick call\n* Quick email\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?x))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (pearl-gtd-process-inbox)
  :asserts (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-quits-during-assign
  "User quits when prompted for assignment target."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to assign\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) (signal 'quit nil)))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq pearl-gtd-test-caught-error err))))
  :asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to assign"))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-links-task-to-multiple-projects
  "User links single task to multiple projects during processing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Shared task\n:PROPERTIES:\n:ID: shared-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "") (deadline . "")
              (delegate . "") (project . "Alpha;Beta")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    "* TODO Shared task"))
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    ":PROJECT:\\s-*Alpha"))
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    "Beta"))
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "action.org" pearl-gtd-init-base-directory)
                    ":ID:"))
           (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-sets-schedule-with-default-deadline
  "User sets schedule and accepts it as deadline."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with deadline\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "2026-04-15") (deadline . "2026-04-15")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-04-15"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-04-15"))
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-sets-schedule-with-different-deadline
  "User sets schedule and a different deadline."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with separate deadline\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "2026-04-15") (deadline . "2026-04-20")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-04-15"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-04-20"))
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-sets-deadline-without-schedule
  "User sets deadline without schedule."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task deadline only\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "") (deadline . "2026-04-25")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-lacks-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "SCHEDULED"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-04-25"))
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-skips-deadline
  "User skips deadline entirely."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task no deadline\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . nil) (deadline . nil)
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-lacks-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "SCHEDULED"))
             (should (pearl-gtd-test-file-lacks-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "DEADLINE"))
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-pipe-in-headline
  "Pipe character in headline must not break org-table formatting."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task | with pipe\n:PROPERTIES:\n:ID: pipe-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Task | with pipe"))
             (let ((ref-file (expand-file-name "reference.org" pearl-gtd-init-base-directory)))
               (with-temp-buffer
                 (insert-file-contents ref-file)
                 (should (search-forward "Task | with pipe" nil t)))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-unicode-content
  "Unicode and emoji must be handled correctly in all fields."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with unicode: 中文 and emoji: 😀\n:PROPERTIES:\n:ID: unicode-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "2026-06-01") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "中文"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "😀")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-sets-leap-year-date
  "Leap year date February 29 must be accepted."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Leap task\n:PROPERTIES:\n:ID: leap-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "2024-02-29") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (pearl-gtd-test-file-contains-p
            (expand-file-name "action.org" pearl-gtd-init-base-directory)
            "2024-02-29")
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-sets-far-future-date
  "Dates far in the future (year 9999) must be handled."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Future task\n:PROPERTIES:\n:ID: future-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "9999-12-31") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (pearl-gtd-test-file-contains-p
            (expand-file-name "action.org" pearl-gtd-init-base-directory)
            "9999-12-31")
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-handles-invalid-date-format
  "Invalid date format should not crash the system."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Bad date task\n:PROPERTIES:\n:ID: bad-date-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ;; Mock collect-action-attrs to simulate date validation failure scenario
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _) '((context . "") (schedule . "") (deadline . "")
                       (delegate . "") (project . "")))))
  :body (condition-case nil
            (pearl-gtd-process-inbox)
          (error nil))
  :asserts (progn
             (should (file-exists-p (expand-file-name "action.org" pearl-gtd-init-base-directory))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-project-with-comma
  "Project name containing comma must not be split incorrectly."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Complex project task\n:PROPERTIES:\n:ID: proj-comma-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "") (deadline . "")
              (delegate . "") (project . "Company, Inc.")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":PROJECT: Company, Inc."))
             (let ((content (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "action.org" pearl-gtd-init-base-directory))
                              (buffer-string))))
               (should-not (string-match-p ":PROJECT: Company\n.*:PROJECT: Inc" content))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-project-with-mixed-separators
  "Project input with mixed semicolons and surrounding whitespace."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Multi project task\n:PROPERTIES:\n:ID: proj-mixed-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-context) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-project) (lambda () "Project A ; Project B ； Project C")))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (let ((content (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "action.org" pearl-gtd-init-base-directory))
                              (buffer-string))))
               ;; All three projects should be stored (allow for whitespace after colon)
               (should (string-match-p ":PROJECT:[ \t]*Project A; Project B; Project C" content))
               ;; Should not have malformed split
               (should-not (string-match-p ":PROJECT: Project A\n" content))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-project-with-tabs
  "Project input with tabs as separators or around separators."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Tab project task\n:PROPERTIES:\n:ID: proj-tab-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-context) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-project) (lambda () "ProjA\t;\tProjB")))
  :body (pearl-gtd-process-inbox)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             ;; Allow for whitespace after colon
             (should (string-match-p ":PROJECT:[ \t]*ProjA; ProjB" content)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-context-with-mixed-whitespace
  "Context input with leading/trailing spaces and tabs."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Context task\n:PROPERTIES:\n:ID: ctx-ws-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-context) (lambda () "  @office  "))
         ((symbol-function 'pearl-gtd-inbox--read-project) (lambda () "")))
  :body (pearl-gtd-process-inbox)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             ;; Context should be trimmed (tag format)
             (should (string-match-p ":office:" content))
             (should-not (string-match-p ":  @office  :" content)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-empty-project-whitespace-only
  "Whitespace-only project should be treated as empty."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* No project task\n:PROPERTIES:\n:ID: empty-proj-2\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-context) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-project) (lambda () "   \t  ")))  ; Only whitespace
  :body (pearl-gtd-process-inbox)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             ;; Should not have PROJECT property with non-empty value
             (should-not (string-match-p ":PROJECT:[ \t]*[^ \t\n\r]" content)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-headline-with-org-special-chars
  "Headline with org special chars like *, #, [ should be handled."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with [brackets] and *stars*\n:PROPERTIES:\n:ID: org-chars-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (pearl-gtd-process-inbox)
  :asserts (let ((ref-file (expand-file-name "reference.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool ref-file "* Task with")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-enters-long-proj-name
  "Very long project names (500+ chars) must be handled."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Long project task\n:PROPERTIES:\n:ID: long-proj-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            `((context . "")
              (schedule . "")
              (deadline . "")
              (delegate . "")
              (project . ,(make-string 500 ?A))))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":PROJECT:"))
             ;; Verify the long project name is preserved (allow for extra space after colon)
             (let ((content (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "action.org" pearl-gtd-init-base-directory))
                              (buffer-string))))
               (should (string-match-p (format ":PROJECT:[ \t]*%s" (make-string 500 ?A)) content))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-organize-test-user-quits-during-date-input
  "User presses C-g during date input to cancel."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task with date\n:PROPERTIES:\n:ID: date-quit-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ;; Simulate user pressing C-g during date collection
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            (signal 'quit nil))))
  :body (condition-case nil
            (pearl-gtd-process-inbox)
          (quit (setq pearl-gtd-test-caught-error 'quit)))
  :asserts (progn
             (should (eq pearl-gtd-test-caught-error 'quit))
             ;; Task should remain in inbox after quit
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task with date")))
  :teardown nil)

;;; Unit tests for inbox context and attribute collection

(ert-deftest pearl-gtd-organize-test-context-completion-list-populated ()
  "Test that `completing-read' receives existing contexts from action.org."
  (let ((pearl-gtd-inbox--last-context nil))
    (cl-letf (((symbol-function 'pearl-gtd-core-read-property-with-completion)
               (lambda (_prompt _type &optional _initial)
                 "@office")))
      (should (string= (pearl-gtd-inbox--read-context) "@office"))
      (should (string= pearl-gtd-inbox--last-context "@office")))))

(ert-deftest pearl-gtd-organize-test-context-allows-free-input ()
  "User can enter context not in existing list."
  (let ((pearl-gtd-inbox--last-context nil))
    (cl-letf (((symbol-function 'pearl-gtd-core-read-property-with-completion)
               (lambda (_prompt _type &optional _initial)
                 "@newcontext")))
      (should (string= (pearl-gtd-inbox--read-context) "@newcontext"))
      (should (string= pearl-gtd-inbox--last-context "@newcontext")))))

(ert-deftest pearl-gtd-organize-test-context-inherits-default ()
  "Default prompt shows last context; RET accepts it."
  (let ((pearl-gtd-inbox--last-context "@office"))
    (cl-letf (((symbol-function 'pearl-gtd-core-read-property-with-completion)
               (lambda (_prompt _type &optional initial)
                 (should (string= initial "@office"))
                 "@office")))
      (should (string= (pearl-gtd-inbox--read-context) "@office")))))

(ert-deftest pearl-gtd-organize-test-context-empty-preserves-last ()
  "Empty input returns empty string without updating last-context."
  (let ((pearl-gtd-inbox--last-context "@office"))
    (cl-letf (((symbol-function 'pearl-gtd-core-read-property-with-completion)
               (lambda (_prompt _type &optional _initial)
                 "")))
      (should (string= (pearl-gtd-inbox--read-context) ""))
      (should (string= pearl-gtd-inbox--last-context "@office")))))

(ert-deftest pearl-gtd-organize-test-collect-attrs-allows-skip-dates ()
  "Verify `pearl-gtd-core-read-date' returning nil results in nil schedule/deadline."
  (cl-letf (((symbol-function 'pearl-gtd-core-read-date)
             (lambda (&rest _) nil))  ; Mock: user pressed RET to skip
            ((symbol-function 'pearl-gtd-inbox--read-context)
             (lambda () (cl-letf (((symbol-function 'pearl-gtd-core-read-property-with-completion)
                                   (lambda (&rest _) ""))))))
            ((symbol-function 'pearl-gtd-inbox--read-delegate)
             (lambda () ""))
            ((symbol-function 'pearl-gtd-inbox--read-project)
             (lambda () "")))
    (let ((result (pearl-gtd-inbox--collect-action-attrs)))
      (should (null (cdr (assoc 'schedule result))))
      (should (null (cdr (assoc 'deadline result)))))))

(provide 'pearl-gtd-organize-test)

;;; pearl-gtd-organize-test.el ends here
