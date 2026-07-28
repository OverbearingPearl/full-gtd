;;; pearl-gtd-test-horizons.el --- User stories: 6 Horizons  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for 6 Horizons of Focus.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-horizons-user-views-horizon-columns-test
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
               (should (search-forward-regexp "|\\s-*Project\\s-*|\\s-*Total\\s-*|\\s-*Todo\\s-*|\\s-*Done\\s-*|\\s-*Next Deadline\\s-*|\\s-*L3_AREA\\s-*|\\s-*L4_GOAL\\s-*|\\s-*L5_VISION\\s-*|\\s-*L6_PURPOSE\\s-*|" nil t))

               ;; Verify No Project table has L3 column only
               (goto-char (point-min))
               (search-forward "** actions.org - No Project")
               (forward-line 1) ; Skip to table header
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Headline\\s-*|\\s-*Status\\s-*|\\s-*Scheduled\\s-*|\\s-*Deadline\\s-*|\\s-*Context\\s-*|\\s-*Delegated\\s-*|\\s-*L3_AREA\\s-*|" nil t))
               (should-not (search-forward-regexp "|\\s-*L4\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*L5\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*L6\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-user-sets-area-for-action-test
  "Set Area (L3) horizon for no-project action in weekly review."
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
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                  (pattern ":L3_AREA: +Personal")
                  (result (pearl-gtd-test-file-contains-p file pattern))
                  (found (car result)))
             (should found))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-user-sets-area-for-project-test
  "Set Area (L3) horizon for project in weekly review."
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
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                  (pattern ":L3_AREA: +Work")
                  (result (pearl-gtd-test-file-contains-p file pattern))
                  (found (car result)))
             (should found))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-user-sets-goal-through-purpose-test
  "Set Goal (L4), Vision (L5), and Purpose (L6) horizons for project with hierarchy constraints."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional _initial _history)
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
            (let ((proj (pearl-gtd-horizons--edit-goal-at-point)))
              (pearl-gtd-horizons--edit-vision-at-point proj)
              (pearl-gtd-horizons--edit-purpose-at-point proj))))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern1 ":L4_GOAL: +Goal: Complete project")
                    (result1 (pearl-gtd-test-file-contains-p file pattern1))
                    (found1 (car result1)))
               (should found1))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern2 ":L5_VISION: +Vision: Professional growth")
                    (result2 (pearl-gtd-test-file-contains-p file pattern2))
                    (found2 (car result2)))
               (should found2))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern3 ":L6_PURPOSE: +Purpose: Make impact")
                    (result3 (pearl-gtd-test-file-contains-p file pattern3))
                    (found3 (car result3)))
               (should found3)))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-user-sees-horizon-inheritance-test
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
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern ":L3_AREA: +Work")
                    (result (pearl-gtd-test-file-contains-p file pattern))
                    (found (car result)))
               (should found))
             ;; Both tasks should inherit L3 from project
             (let ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
               (with-temp-buffer
                 (insert-file-contents file)
                 (let ((count 0))
                   (while (re-search-forward ":L3_AREA: +Work" nil t)
                     (cl-incf count))
                   (should (= count 2)))))  ; 2 tasks, no project entry
             )
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-user-removes-project-clears-horizon-test
  "Action leaving project loses project horizon."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: t1\n:PROJECT: TestProject\n:L3_AREA: Work\n:END:\n"))
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
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern1 ":PROJECT: TestProject")
                    (result1 (pearl-gtd-test-file-contains-p file pattern1))
                    (found1 (car result1)))
               (should-not found1))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern2 ":L3_AREA: Work")
                    (result2 (pearl-gtd-test-file-contains-p file pattern2))
                    (found2 (car result2)))
               (should-not found2)))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-user-views-hierarchy-test
  "Horizon view shows L6 to L3 hierarchy with projects and actions."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:L3_AREA: Personal\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:L6_PURPOSE: Purpose\n:END:\n"))
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

(pearl-gtd-test-define-story pearl-gtd-horizons-user-clears-area-cascades-to-actions-test
  "Clearing Area (L3) from project should remove inherited Area from actions."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1\n:PROPERTIES:\n:ID: cascade-1\n:PROJECT: TestProj\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProj")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             (should-not (string-match-p ":L3_AREA:" content)))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-constraint-rejects-vision-without-goal-test
  "User is blocked when attempting to set Vision (L5) without Goal (L4)."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-1\n:PROJECT: ConstraintProj\n:L3_AREA: Area\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "VisionValue")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "ConstraintProj")
            (beginning-of-line)
            (condition-case err
                (progn
                  (pearl-gtd-horizons--edit-vision-at-point)
                  (setq pearl-gtd-test-caught-error nil))
              (error (setq pearl-gtd-test-caught-error (error-message-string err))))))
  :asserts (progn
             (should (stringp pearl-gtd-test-caught-error))
             (should (string-match-p "L4 Goal must be set first" pearl-gtd-test-caught-error))
             (should-not (car (pearl-gtd-test-file-contains-p
                               (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                               ":L5_VISION:"))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-constraint-rejects-purpose-without-vision-test
  "User is blocked when attempting to set Purpose (L6) without Vision (L5)."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-2\n:PROJECT: ConstraintProj2\n:L3_AREA: Area\n:L4_GOAL: Goal\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PurposeValue")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "ConstraintProj2")
            (beginning-of-line)
            (condition-case err
                (progn
                  (pearl-gtd-horizons--edit-purpose-at-point)
                  (setq pearl-gtd-test-caught-error nil))
              (error (setq pearl-gtd-test-caught-error (error-message-string err))))))
  :asserts (progn
             (should (stringp pearl-gtd-test-caught-error))
             (should (string-match-p "L5 Vision must be set first" pearl-gtd-test-caught-error))
             (should-not (car (pearl-gtd-test-file-contains-p
                               (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                               ":L6_PURPOSE:"))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-constraint-rejects-principle-without-purpose-test
  "User is blocked when attempting to set L6 Principle without L6 Purpose."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-3\n:PROJECT: ConstraintProj3\n:L3_AREA: Area\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PrincipleValue")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "ConstraintProj3")
            (beginning-of-line)
            (condition-case err
                (progn
                  (pearl-gtd-horizons--edit-principle-at-point)
                  (setq pearl-gtd-test-caught-error nil))
              (error (setq pearl-gtd-test-caught-error (error-message-string err))))))
  :asserts (progn
             (should (stringp pearl-gtd-test-caught-error))
             (should (string-match-p "L6 Purpose must be set first" pearl-gtd-test-caught-error))
             (should-not (car (pearl-gtd-test-file-contains-p
                               (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                               ":L6_PRINCIPLE:"))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-principle-allows-multiple-purposes-test
  "Setting Principle passes when any Purpose exists in multi-value."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: multi-purpose-1\n:PROJECT: MultiPurposeProj\n:L3_AREA: Area\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:L6_PURPOSE: P1; P2\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PrincipleValue")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "MultiPurposeProj")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-principle-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PRINCIPLE: PrincipleValue")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-multiple-values-in-hierarchy-test
  "Entry with multiple horizon values appears under each node."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO MultiHorizonTask\n:PROPERTIES:\n:ID: multi-horizon-1\n:PROJECT: MultiHorizonProj\n:L6_PURPOSE: PurposeA; PurposeB\n:L5_VISION: VisionA; VisionB\n:L4_GOAL: GoalA; GoalB\n:L3_AREA: AreaA; AreaB\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizons*"))
             (with-current-buffer "*Pearl-GTD Horizons*"
               ;; Should appear under both PurposeA and PurposeB
               (goto-char (point-min))
               (should (search-forward "** PurposeA" nil t))
               (should (search-forward "*** VisionA" nil t))
               (should (search-forward "**** GoalA" nil t))
               (should (search-forward "***** AreaA" nil t))
               (should (search-forward "****** MultiHorizonProj" nil t))
               (should (search-forward "TODO MultiHorizonTask" nil t))
               (goto-char (point-min))
               (should (search-forward "** PurposeB" nil t))
               (should (search-forward "*** VisionB" nil t))
               (should (search-forward "**** GoalB" nil t))
               (should (search-forward "***** AreaB" nil t))
               (should (search-forward "****** MultiHorizonProj" nil t))
               (should (search-forward "TODO MultiHorizonTask" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizons*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-user-edits-multiple-values-test
  "Editing horizon shows joined values and saves split values."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO EditTask\n:PROPERTIES:\n:ID: edit-multi-1\n:PROJECT: EditProj\n:L5_VISION: VisionValue\n:L6_PURPOSE: Old1; Old2\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional initial _history)
            (should (string= initial "Old1; Old2"))
            "Old1; Old2; New3")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "EditProj")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-purpose-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Old1; Old2; New3")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-mixed-separators-with-whitespace-test
  "Horizon values with mixed semicolons and surrounding whitespace."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: mix-sep-1\n:PROJECT: MixProj\n:L3_AREA: AreaVal\n:L4_GOAL: GoalVal\n:L5_VISION: VisionValue\n:L6_PURPOSE: P1; P2 ； P3\t;\tP4\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizons*"))
             (with-current-buffer "*Pearl-GTD Horizons*"
               ;; Should appear under all four purpose values (L6 is top level)
               (goto-char (point-min))
               (should (search-forward "** P1" nil t))
               (goto-char (point-min))
               (should (search-forward "** P2" nil t))
               (goto-char (point-min))
               (should (search-forward "** P3" nil t))
               (goto-char (point-min))
               (should (search-forward "** P4" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizons*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-multiple-projects-multiple-horizons-test
  "Action with multiple projects and multiple horizon values."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO SharedTask\n:PROPERTIES:\n:ID: multi-ph-1\n:PROJECT: ProjA; ProjB\n:L3_AREA: Area1; Area2\n:L4_GOAL: Goal1; Goal2\n:L5_VISION: Vision1\n:L6_PURPOSE: Purpose1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizons*"))
             (with-current-buffer "*Pearl-GTD Horizons*"
               ;; Task should appear under both projects
               (goto-char (point-min))
               (should (search-forward "****** ProjA" nil t))
               (should (search-forward "******* TODO SharedTask" nil t))
               (goto-char (point-min))
               (should (search-forward "****** ProjB" nil t))
               (should (search-forward "******* TODO SharedTask" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizons*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-whitespace-only-values-ignored-test
  "Horizon values that are whitespace-only should be ignored."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: ws-val-1\n:PROJECT: WSProj\n:L3_AREA: ValidArea;   ; \t ;AnotherArea\n:L4_GOAL: GoalVal\n:L5_VISION: VisionVal\n:L6_PURPOSE: PurposeVal\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizons*"))
             (with-current-buffer "*Pearl-GTD Horizons*"
               ;; Should only show valid areas, not whitespace entries
               ;; L3 Area appears at level 5 (*****) under L4/L5/L6 hierarchy
               ;; L6=** (level 2), L5=*** (level 3), L4=**** (level 4), L3=***** (level 5)
               (goto-char (point-min))
               (should (search-forward "***** ValidArea" nil t))
               (goto-char (point-min))
               (should (search-forward "***** AnotherArea" nil t))
               ;; Should NOT have entries for whitespace-only values
               (goto-char (point-min))
               (should-not (search-forward "*****    " nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizons*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-empty-horizon-inheritance-test
  "Project with some empty horizons should still inherit non-empty ones."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task1\n:PROPERTIES:\n:ID: empty-inherit-1\n:PROJECT: PartialProj\n:L3_AREA: WorkArea\n:L4_GOAL: \n:L5_VISION: \n:L6_PURPOSE: \n:END:\n* TODO Task2\n:PROPERTIES:\n:ID: empty-inherit-2\n:PROJECT: PartialProj\n:L3_AREA: WorkArea\n:L4_GOAL: SomeGoal\n:L5_VISION: \n:L6_PURPOSE: \n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizons*"))
             (with-current-buffer "*Pearl-GTD Horizons*"
               ;; Both tasks should be under WorkArea at L3 level
               ;; With empty L6/L5/L4, tasks go directly under L3 Area at top level (level 2)
               (goto-char (point-min))
               (should (search-forward "** WorkArea" nil t))
               ;; Project should appear under WorkArea at level 3
               (goto-char (point-min))
               (should (search-forward "*** PartialProj" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizons*"))

(provide 'pearl-gtd-test-horizons)

;;; pearl-gtd-test-horizons.el ends here
