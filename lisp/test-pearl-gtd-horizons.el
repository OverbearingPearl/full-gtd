;;; test-pearl-gtd-horizons.el --- User stories: 6 Horizons  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for 6 Horizons of Focus.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-horizons-weekly-review-shows-columns
  "Weekly review shows horizon columns for project and no-project tables."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Verify Project table has Horizon columns
               (goto-char (point-min))
               (search-forward "** Projects - Active")
               (forward-line 1) ; Skip to table header
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Project\\s-*|\\s-*Total\\s-*|\\s-*Todo\\s-*|\\s-*Done\\s-*|\\s-*Next Deadline\\s-*|\\s-*L3\\s-*|\\s-*L4\\s-*|\\s-*L5\\s-*|\\s-*L6\\s-*|" nil t))

               ;; Verify No Project table has L3 column only
               (goto-char (point-min))
               (search-forward "** actions.org - No Project")
               (forward-line 1) ; Skip to table header
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Headline\\s-*|\\s-*Status\\s-*|\\s-*Scheduled\\s-*|\\s-*Deadline\\s-*|\\s-*Context\\s-*|\\s-*Delegated\\s-*|\\s-*L3\\s-*|" nil t))
               (should-not (search-forward-regexp "|\\s-*L4\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*L5\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*L6\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-set-l3-for-no-project-action
  "Set L3 horizon for no-project action in weekly review."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Personal")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - No Project")
            (search-forward "No project task")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-l3-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":HORIZON_L3: Personal")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-set-l3-for-project
  "Set L3 horizon for project in weekly review."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Work")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-l3-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":HORIZON_L3: Work")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-set-l4-l5-l6-for-project
  "Set L4, L5, L6 horizons for project with hierarchy constraints."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:HORIZON_L3: Work\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional initial _history)
            (cond
             ((string-match "L4" prompt) "Goal: Complete project")
             ((string-match "L5" prompt) "Vision: Professional growth")
             ((string-match "L6" prompt) "Purpose: Make impact")
             (t "")))))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (let ((proj (pearl-gtd-horizons--edit-l4-at-point)))
              (pearl-gtd-horizons--edit-l5-at-point proj)
              (pearl-gtd-horizons--edit-l6-at-point proj))))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":HORIZON_L4: Goal: Complete project"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":HORIZON_L5: Vision: Professional growth"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":HORIZON_L6: Purpose: Make impact")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-cannot-set-l4-without-l3
  "Cannot set L4 horizon without L3 set first."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Goal")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-l4-at-point)
              (error (should (string-match-p "L3 must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-cannot-set-l5-without-l4
  "Cannot set L5 horizon without L4 set first."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:HORIZON_L3: Work\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Vision")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-l5-at-point)
              (error (should (string-match-p "L4 must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-cannot-set-l6-without-l5
  "Cannot set L6 horizon without L5 set first."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:HORIZON_L3: Work\n:HORIZON_L4: Goal\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Purpose")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-l6-at-point)
              (error (should (string-match-p "L5 must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-project-horizon-inheritance
  "Project horizon inheritance to its actions."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1\n:PROPERTIES:\n:ID: t1\n:PROJECT: TestProject\n:END:\n* TODO Task 2\n:PROPERTIES:\n:ID: t2\n:PROJECT: TestProject\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Work")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-l3-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":HORIZON_L3: Work"))
             ;; Both tasks should inherit L3 from project
             (with-temp-buffer
               (insert-file-contents (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (let ((count 0))
                 (while (re-search-forward ":HORIZON_L3: Work" nil t)
                   (cl-incf count))
                 (should (= count 2))  ; 2 tasks, no project entry
                 )))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-action-leaves-project-loses-horizon
  "Action leaving project loses project horizon."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: t1\n:PROJECT: TestProject\n:HORIZON_L3: Work\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          ;; Remove project from task
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Task")
            (beginning-of-line)
            (pearl-gtd-review--edit-project-at-point)))
  :asserts (progn
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          ":PROJECT: TestProject"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          ":HORIZON_L3: Work")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-view-shows-hierarchy
  "Horizon view shows L6 to L3 hierarchy with projects and actions."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:HORIZON_L3: Personal\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:HORIZON_L3: Work\n:HORIZON_L4: Goal\n:HORIZON_L5: Vision\n:HORIZON_L6: Purpose\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizons*"))
             (with-current-buffer "*Pearl-GTD Horizons*"
               ;; Verify hierarchy structure
               (goto-char (point-min))
               (should (search-forward "** Purpose" nil t))
               (should (search-forward "*** Vision" nil t))
               (should (search-forward "**** Goal" nil t))
               (should (search-forward "***** Work" nil t))
               (should (search-forward "****** TestProject" nil t))
               (should (search-forward "******* TODO Project task" nil t))
               (should (search-forward "** Personal" nil t))
               (should (search-forward "*** TODO No project task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizons*"))

(provide 'test-pearl-gtd-horizons)

;;; test-pearl-gtd-horizons.el ends here
