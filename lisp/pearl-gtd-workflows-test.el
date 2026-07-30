;;; pearl-gtd-test-workflows.el --- User stories: End-to-end workflows  -*- lexical-binding: t; -*-

;;; Commentary:

;; Complete user workflows spanning multiple phases.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-workflows-user-processes-full-gtd-pipeline-test
  "User captures, clarifies, organizes, and completes processing."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt) "Buy birthday gift")
             (t ""))))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              ;; First item: clarify then action
              (if (= calls 1) ?c ?a))))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons "Buy gift for mom" "Check Amazon first")))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@errands") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Buy gift for mom"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Check Amazon first"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":errands:"))
             ;; Verify ID is preserved after processing
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-user-interrupts-processing-test
  "User interrupts processing midway."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to interrupt\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) (signal 'quit nil)))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq pearl-gtd-test-caught-error err))))
  :asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to interrupt"))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-user-processes-mixed-destinations-test
  "User processes entries with mixed destinations."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Action task\n* Reference task\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?a ?r))))  ; First action, then reference
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Action task"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Reference task")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-user-captures-and-processes-two-items-test
  "User captures two items then processes both."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Capture to inbox" prompt)) "First capture")
               ((and (= count 2) (string-match "Capture to inbox" prompt)) "Second capture")
               (t "")))))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* First capture"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Second capture")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-user-sees-id-preserved-after-processing-test
  "ID is preserved when task is moved from inbox to actions."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt) "Test task")
             (t ""))))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             ;; Task moved to actions.org
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Test task"))
             ;; ID preserved in actions.org
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:"))
             ;; Inbox is empty
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-user-sees-duplicate-titles-get-different-ids-test
  "Same title in different files gets different IDs."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Existing task\n:PROPERTIES:\n:ID: existing-id-1\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt) "Buy milk")
             (t "")))))
  :body (pearl-gtd-capture)
  :asserts (progn
             ;; New entry in inbox
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Buy milk"))
             ;; New entry has different ID
             (with-temp-buffer
               (insert-file-contents (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (let ((_id-pos (point)))
                 (should-not (search-forward "existing-id-1" nil t)))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-user-processes-duplicate-titles-test
  "User captures two tasks with same title, both processed correctly."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Capture to inbox" prompt)) "Task")
               ((and (= count 2) (string-match "Capture to inbox" prompt)) "Task")
               (t "")))))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
             ;; Should have two tasks in actions.org
             (with-temp-buffer
               (insert-file-contents (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward "* TODO Task" nil t))
               (should (search-forward "* TODO Task" nil t))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-duplicate-ids-in-file-test
  "Malformed file with duplicate IDs should still allow jumping to first match."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task A\n:PROPERTIES:\n:ID: dup-id\n:END:\n* TODO Task B\n:PROPERTIES:\n:ID: dup-id\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (goto-char (point-min))
            (search-forward "Task A")
            (beginning-of-line)
            (pearl-gtd-do--session-jump)))
  :asserts (progn
             (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
               (should buf)
               (with-current-buffer buf
                 (should (looking-at-p "\\*+ TODO Task")))))
  :teardown (progn
              (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*"))
              (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(pearl-gtd-test-define-story pearl-gtd-workflows-multi-project-action-inheritance-test
  "Action linked to multiple projects inherits horizons from all."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Shared action\n:PROPERTIES:\n:ID: shared-multi-1\n:PROJECT: Alpha; Beta\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-review--get-project-stats)
          (lambda (proj)
            ;; Return stats that mark both projects as active (have TODOs)
            '("1" "1" "0" "" "" "" "" ""))))
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             ;; Should appear in project views - look in Active Projects section
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               (goto-char (point-min))
               (let ((active-pos (search-forward "** Projects - Active" nil t)))
                 (should active-pos)
                 ;; Both projects should be listed
                 (goto-char active-pos)
                 (should (search-forward "Alpha" nil t))
                 (goto-char active-pos)
                 (should (search-forward "Beta" nil t)))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-workflows-multiple-contexts-on-single-action-test
  "Action can have multiple context tags."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Multi context task\n:PROPERTIES:\n:ID: multi-ctx-1\n:CONTEXT: office\n:END:\n"))
  :mock nil
  :body (progn
          ;; Add second context manually
          (let ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
            (with-current-buffer (find-file-noselect file)
              (goto-char (point-min))
              (re-search-forward "Multi context task")
              (org-set-tags '("office" "phone"))
              (save-buffer)
              (kill-buffer))))
          (pearl-gtd-do-view-all-actions)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: All Actions*"))
             (with-current-buffer "*Pearl-GTD: All Actions*"
               (should (search-forward "@office" nil t))
               (should (search-forward "@phone" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: All Actions*")))

(pearl-gtd-test-define-story pearl-gtd-workflows-extreme-whitespace-in-fields-test
  "Extreme whitespace in various fields should be handled."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "*    Task with lots of spaces    \n:PROPERTIES:\n:ID: ws-extreme-1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () "  Bob  "))
         ((symbol-function 'pearl-gtd-inbox--read-context) (lambda () "  @office  "))
         ((symbol-function 'pearl-gtd-inbox--read-project) (lambda () "  ProjA  ;  ProjB  ")))
  :body (pearl-gtd-process-inbox)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             ;; All values should be trimmed (allow for whitespace after colon)
             (should (string-match-p ":office:" content))
             (should (string-match-p ":DELEGATED:[ \t]*Bob" content))
             (should (string-match-p ":PROJECT:[ \t]*ProjA; ProjB" content))
             ;; Original whitespace should not be preserved
             (should-not (string-match-p ":  @office  :" content)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-workflows-large-number-entries-test
  "System should handle 100+ entries without significant slowdown."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" (concat "* Task 1\n:PROPERTIES:\n:ID: perf-1\n:END:\n"
                               (mapconcat (lambda (i)
                                           (format "* Task %d\n:PROPERTIES:\n:ID: perf-%d\n:END:\n" i i))
                                         (number-sequence 2 100) ""))))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?t))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (let ((start (float-time)))
          (pearl-gtd-process-inbox)
          (should (< (- (float-time) start) 10.0)))
  :asserts (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil)

(provide 'pearl-gtd-workflows-test)

;;; pearl-gtd-workflows-test.el ends here
