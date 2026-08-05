;;; pearl-gtd-test-horizons.el --- User stories: 6 Horizons  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for 6 Horizons of Focus.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-shows-project-matrix
  "Horizon view shows projects in matrix with L6-L3 columns."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:L4_GOAL: Goal1\n:L5_VISION: Vision1\n:L6_PURPOSE: Purpose1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Verify matrix table headers
               (goto-char (point-min))
               (search-forward "** Aligned Projects")
               (forward-line 1)
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Project\\s-*|\\s-*Total\\s-*|\\s-*Todo\\s-*|\\s-*Done\\s-*|\\s-*L6 Purpose\\s-*|\\s-*L6 Principle\\s-*|\\s-*L5 Vision\\s-*|\\s-*L4 Goal\\s-*|\\s-*L3 Area\\s-*|" nil t))
               ;; Verify project row has all horizon values
               (goto-char (point-min))
               (search-forward "TestProject")
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*TestProject\\s-*|\\s-*1\\s-*|\\s-*1\\s-*|\\s-*0\\s-*|\\s-*Purpose1\\s-*|\\s-*\\s-*|\\s-*Vision1\\s-*|\\s-*Goal1\\s-*|\\s-*Work\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-shows-critical-gaps
  "Projects without any horizon appear in Critical section."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task1\n:PROPERTIES:\n:ID: gap-1\n:PROJECT: NoHorizonProject\n:END:\n* TODO Task2\n:PROPERTIES:\n:ID: gap-2\n:PROJECT: HasHorizonProject\n:L3_AREA: Work\n:L4_GOAL: Goal1\n:L5_VISION: Vision1\n:L6_PURPOSE: Purpose1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Verify Critical section exists with NoHorizonProject
               (goto-char (point-min))
               (search-forward "** Critical: Projects Without Any Horizon")
               (should (search-forward "NoHorizonProject" nil t))
               ;; Verify HasHorizonProject is NOT in Critical
               (goto-char (point-min))
               (search-forward "** Aligned Projects")
               (should (search-forward "HasHorizonProject" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-shows-partial-alignment
  "Projects with only L3 appear in Partial section."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: partial-1\n:PROJECT: PartialProject\n:L3_AREA: Work\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               (goto-char (point-min))
               (search-forward "** Partial: Projects Missing Higher Horizons")
               (should (search-forward "PartialProject" nil t))
               ;; Verify L3 is shown but L4-L6 are empty
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*PartialProject\\s-*|.*|\\s-*Work\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-shows-no-project-actions
  "No-project actions shown in separate table with L3 only."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:L3_AREA: Personal\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               (goto-char (point-min))
               (search-forward "** No-Project Actions")
               (forward-line 1)
               (beginning-of-line)
               ;; Verify only L3 column, no L4-L6
               (should (search-forward-regexp "|\\s-*Headline\\s-*|\\s-*Status\\s-*|\\s-*Context\\s-*|\\s-*L3 Area\\s-*|" nil t))
               (should-not (search-forward-regexp "L4\\|L5\\|L6" (line-end-position) t))
               ;; Verify action appears
               (goto-char (point-min))
               (search-forward "** No-Project Actions")
               (should (search-forward "No project task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-shows-multi-horizon-projects
  "Projects with incomplete horizons and multiple values shown in dedicated section."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: multi-1\n:PROJECT: MultiProject\n:L3_AREA: Work; Personal\n:L4_GOAL: Goal1; Goal2\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               (goto-char (point-min))
               (search-forward "** Multi-Horizon Projects")
               (should (search-forward "MultiProject" nil t))
               ;; Verify semicolon-separated values displayed for incomplete project
               (beginning-of-line)
               (should (search-forward-regexp "Work; Personal" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-edits-l6-at-point
  "Press 6 to edit L6 Purpose in horizon view."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: edit-l6-1\n:PROJECT: EditProject\n:L3_AREA: Work\n:L4_GOAL: Goal1\n:L5_VISION: Vision1\n:L6_PURPOSE: OldPurpose\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "NewPurpose"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "NewPurpose")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "EditProject")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-purpose-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: NewPurpose")))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-jumps-to-project-actions
  "Press RET on project row to view its actions."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task A\n:PROPERTIES:\n:ID: jump-1\n:PROJECT: JumpProject\n:L3_AREA: Work\n:END:\n* TODO Task B\n:PROPERTIES:\n:ID: jump-2\n:PROJECT: JumpProject\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "JumpProject")
            (pearl-gtd-horizons--goto-project-at-point)))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Project: JumpProject*"))
             (with-current-buffer "*Pearl-GTD Project: JumpProject*"
               (should (search-forward "Task A" nil t))
               (should (search-forward "Task B" nil t))))
  :teardown (progn
              (kill-buffer "*Pearl-GTD Horizon View*")
              (when (get-buffer "*Pearl-GTD Project: JumpProject*")
                (kill-buffer "*Pearl-GTD Project: JumpProject*"))))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-view-shows-health-dashboard
  "Top of view shows health statistics."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO T1\n:PROPERTIES:\n:ID: h-1\n:PROJECT: P1\n:END:\n* TODO T2\n:PROPERTIES:\n:ID: h-2\n:PROJECT: P2\n:L3_AREA: Work\n:END:\n* TODO T3\n:PROPERTIES:\n:ID: h-3\n:PROJECT: P3\n:L3_AREA: Work\n:L4_GOAL: G1\n:L5_VISION: V1\n:L6_PURPOSE: Purpose1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (with-current-buffer "*Pearl-GTD Horizon View*"
             (goto-char (point-min))
             (should (search-forward-regexp "Health:" nil t))
             (should (search-forward-regexp "3 Projects" nil t))
             (should (search-forward-regexp "1 Orphaned" nil t))
             (should (search-forward-regexp "1 Partial" nil t))
             (should (search-forward-regexp "1 Aligned" nil t)))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-edit-applies-to-all-project-actions
  "Editing horizon in view applies to all actions of that project."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task 1\n:PROPERTIES:\n:ID: t1\n:PROJECT: TestProject\n:END:\n* TODO Task 2\n:PROPERTIES:\n:ID: t2\n:PROJECT: TestProject\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Work"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "Work")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "TestProject")
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (progn
             ;; Both tasks should have L3 set
             (let ((file (expand-file-name "action.org" pearl-gtd-init-base-directory)))
               (with-temp-buffer
                 (insert-file-contents file)
                 (let ((count 0))
                   (while (re-search-forward ":L3_AREA: +Work" nil t)
                     (cl-incf count))
                   (should (= count 2))))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-clearing-l3-removes-from-all-actions
  "Clearing L3 from project removes it from all project actions."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task 1\n:PROPERTIES:\n:ID: cascade-1\n:PROJECT: TestProj\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "TestProj")
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             (should-not (string-match-p ":L3_AREA:" content)))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-constraint-rejects-vision-without-goal
  "User is blocked when attempting to set Vision (L5) without Goal (L4)."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-1\n:PROJECT: ConstraintProj\n:L3_AREA: Area\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "VisionValue"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "VisionValue")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "ConstraintProj")
            (condition-case err
                (progn
                  (pearl-gtd-horizons--edit-vision-at-point)
                  (setq pearl-gtd-test-caught-error nil))
              (error (setq pearl-gtd-test-caught-error (error-message-string err))))))
  :asserts (progn
             (should (stringp pearl-gtd-test-caught-error))
             (should (string-match-p "L4 Goal must be set first" pearl-gtd-test-caught-error))
             (should-not (car (pearl-gtd-test-file-contains-p
                               (expand-file-name "action.org" pearl-gtd-init-base-directory)
                               ":L5_VISION:"))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-constraint-rejects-purpose-without-vision
  "User is blocked when attempting to set Purpose (L6) without Vision (L5)."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-2\n:PROJECT: ConstraintProj2\n:L3_AREA: Area\n:L4_GOAL: Goal\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PurposeValue"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "PurposeValue")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "ConstraintProj2")
            (condition-case err
                (progn
                  (pearl-gtd-horizons--edit-purpose-at-point)
                  (setq pearl-gtd-test-caught-error nil))
              (error (setq pearl-gtd-test-caught-error (error-message-string err))))))
  :asserts (progn
             (should (stringp pearl-gtd-test-caught-error))
             (should (string-match-p "L5 Vision must be set first" pearl-gtd-test-caught-error))
             (should-not (car (pearl-gtd-test-file-contains-p
                               (expand-file-name "action.org" pearl-gtd-init-base-directory)
                               ":L6_PURPOSE:"))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-constraint-rejects-principle-without-purpose
  "User is blocked when attempting to set L6 Principle without L6 Purpose."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-3\n:PROJECT: ConstraintProj3\n:L3_AREA: Area\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PrincipleValue"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "PrincipleValue")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "ConstraintProj3")
            (condition-case err
                (progn
                  (pearl-gtd-horizons--edit-principle-at-point)
                  (setq pearl-gtd-test-caught-error nil))
              (error (setq pearl-gtd-test-caught-error (error-message-string err))))))
  :asserts (progn
             (should (stringp pearl-gtd-test-caught-error))
             (should (string-match-p "L6 Purpose must be set first" pearl-gtd-test-caught-error))
             (should-not (car (pearl-gtd-test-file-contains-p
                               (expand-file-name "action.org" pearl-gtd-init-base-directory)
                               ":L6_PRINCIPLE:"))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-principle-allows-multiple-purposes
  "Setting Principle passes when any Purpose exists in multi-value."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: multi-purpose-1\n:PROJECT: MultiPurposeProj\n:L3_AREA: Area\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:L6_PURPOSE: P1; P2\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PrincipleValue"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "PrincipleValue")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "MultiPurposeProj")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-principle-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":L6_PRINCIPLE: PrincipleValue")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-user-edits-project-with-mixed-horizon-values
  "Editing project horizon when tasks have different existing values."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task1\n:PROPERTIES:\n:ID: mixed-1\n:PROJECT: MixedProj\n:L3_AREA: OldArea1\n:END:\n* TODO Task2\n:PROPERTIES:\n:ID: mixed-2\n:PROJECT: MixedProj\n:L3_AREA: OldArea2\n:END:\n* TODO Task3\n:PROPERTIES:\n:ID: mixed-3\n:PROJECT: MixedProj\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "NewArea"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "NewArea")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "MixedProj")
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (progn
             ;; All three tasks should now have NewArea
             (let ((file (expand-file-name "action.org" pearl-gtd-init-base-directory)))
               (with-temp-buffer
                 (insert-file-contents file)
                 (let ((count 0))
                   (while (re-search-forward ":L3_AREA: +NewArea" nil t)
                     (cl-incf count))
                   (should (= count 3))))
               ;; No old values should remain
               (should-not (car (pearl-gtd-test-file-contains-p file ":L3_AREA: +OldArea1")))
               (should-not (car (pearl-gtd-test-file-contains-p file ":L3_AREA: +OldArea2")))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-multi-project-task-cascading
  "Editing horizon for one project does not affect other projects sharing the same task."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO SharedTask\n:PROPERTIES:\n:ID: multi-proj-1\n:PROJECT: ProjA; ProjB\n:L3_AREA: OldArea\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "NewArea"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "NewArea")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "ProjA")
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (progn
             ;; Task should now have both areas (OldArea for ProjB, NewArea for ProjA)
             (let ((file (expand-file-name "action.org" pearl-gtd-init-base-directory)))
               (with-temp-buffer
                 (insert-file-contents file)
                 (let ((areas nil))
                   (while (re-search-forward ":L3_AREA: +\\([^\n]+\\)" nil t)
                     (push (match-string 1) areas))
                   ;; Should be exactly one property line (multiple values separated by semicolon)
                   (should (= (length areas) 1))
                   (let ((value (car areas)))
                     ;; Verify both values present in the combined property
                     (should (string-match-p "OldArea" value))
                     (should (string-match-p "NewArea" value)))))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-atomic-rollback-on-constraint-failure
  "When hierarchy constraint fails, no partial horizon changes are applied."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task1\n:PROPERTIES:\n:ID: atomic-1\n:PROJECT: AtomicProj\n:L3_AREA: Area\n:END:\n* TODO Task2\n:PROPERTIES:\n:ID: atomic-2\n:PROJECT: AtomicProj\n:L3_AREA: Area\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "VisionValue"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "VisionValue")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "AtomicProj")
            (condition-case err
                (progn
                  (pearl-gtd-horizons--edit-vision-at-point)
                  (setq pearl-gtd-test-caught-error nil))
              (error (setq pearl-gtd-test-caught-error (error-message-string err))))))
  :asserts (progn
             (should (stringp pearl-gtd-test-caught-error))
             (should (string-match-p "L4 Goal must be set first" pearl-gtd-test-caught-error))
             ;; Verify no L5_VISION property was added to any task
             (let ((file (expand-file-name "action.org" pearl-gtd-init-base-directory)))
               (should-not (car (pearl-gtd-test-file-contains-p file ":L5_VISION:")))
               ;; Also verify L3_AREA remains unchanged
               (with-temp-buffer
                 (insert-file-contents file)
                 (let ((count 0))
                   (while (re-search-forward ":L3_AREA: +Area" nil t)
                     (cl-incf count))
                   (should (= count 2))))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-multiple-values-shown-in-cell
  "Multiple horizon values shown semicolon-separated in matrix cell."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: multi-horizon-1\n:PROJECT: MultiHorizonProj\n:L6_PURPOSE: PurposeA; PurposeB\n:L5_VISION: VisionA; VisionB\n:L4_GOAL: GoalA; GoalB\n:L3_AREA: AreaA; AreaB\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Complete project with multi-values appears in Aligned section
               (goto-char (point-min))
               (search-forward "** Aligned Projects")
               (search-forward "MultiHorizonProj")
               (beginning-of-line)
               ;; Verify semicolon-separated values in cells
               (should (search-forward-regexp "PurposeA; PurposeB" (line-end-position) t))
               (should (search-forward-regexp "VisionA; VisionB" (line-end-position) t))
               (should (search-forward-regexp "GoalA; GoalB" (line-end-position) t))
               (should (search-forward-regexp "AreaA; AreaB" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-user-edits-multiple-values
  "Editing horizon shows joined values and saves split values."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO EditTask\n:PROPERTIES:\n:ID: edit-multi-1\n:PROJECT: EditProj\n:L5_VISION: VisionValue\n:L6_PURPOSE: Old1; Old2\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional initial _history)
            (should (string= initial "Old1; Old2"))
            "Old1; Old2; New3"))
         ((symbol-function 'pearl-gtd-core-read-property-with-completion) (lambda (&rest _) "Old1; Old2; New3")))
  :body (progn
          (pearl-gtd-horizons-view)
          (with-current-buffer "*Pearl-GTD Horizon View*"
            (goto-char (point-min))
            (search-forward "EditProj")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-purpose-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Old1; Old2; New3")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Horizon View*")))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-mixed-separators-normalized-in-view
  "Horizon values with mixed semicolons normalized for display."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: mix-sep-1\n:PROJECT: MixProj\n:L3_AREA: AreaVal\n:L4_GOAL: GoalVal\n:L5_VISION: VisionValue\n:L6_PURPOSE: P1; P2 ； P3\t;\tP4\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Complete project with mixed separators appears in Aligned section
               (goto-char (point-min))
               (search-forward "** Aligned Projects")
               (search-forward "MixProj")
               (beginning-of-line)
               ;; Should show normalized semicolon format
               (should (search-forward-regexp "P1; P2; P3; P4" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-multiple-projects-shown-as-multi-horizon
  "Project with complete horizons and multiple values shown in Aligned section."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: multi-ph-1\n:PROJECT: MultiProj\n:L3_AREA: Area1; Area2\n:L4_GOAL: Goal1; Goal2\n:L5_VISION: Vision1\n:L6_PURPOSE: Purpose1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Complete projects with multi-values should appear in Aligned, not Multi-Horizon
               (goto-char (point-min))
               (search-forward "** Aligned Projects")
               (should (search-forward "MultiProj" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-complete-multi-valued-in-aligned-section
  "Complete L3-L6 project with multiple values appears in Aligned, not Multi-Horizon."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: complete-multi-1\n:PROJECT: CompleteMultiProj\n:L3_AREA: Work; Personal\n:L4_GOAL: Goal1; Goal2\n:L5_VISION: VisionA; VisionB\n:L6_PURPOSE: Purpose1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Should be in Aligned section
               (goto-char (point-min))
               (search-forward "** Aligned Projects")
               (should (search-forward "CompleteMultiProj" nil t))
               ;; Should NOT be in Multi-Horizon section
               (goto-char (point-min))
               (search-forward "** Multi-Horizon Projects")
               (should-not (search-forward "CompleteMultiProj" (save-excursion (search-forward "** No-Project Actions") (point)) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-whitespace-only-values-ignored
  "Horizon values that are whitespace-only should be ignored in display."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: ws-val-1\n:PROJECT: WSProj\n:L3_AREA: ValidArea;   ; \t ;AnotherArea\n:L4_GOAL: GoalVal\n:L5_VISION: VisionVal\n:L6_PURPOSE: PurposeVal\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Complete project with multi-value L3 appears in Aligned section
               (goto-char (point-min))
               (search-forward "** Aligned Projects")
               (search-forward "WSProj")
               ;; Should show only valid values (whitespace-only filtered out)
               (should (search-forward-regexp "ValidArea; AnotherArea" (line-end-position) t))
               (should-not (search-forward-regexp "   ;" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(pearl-gtd-test-define-story pearl-gtd-horizons-test-empty-horizon-shown-as-partial
  "Project with some empty horizons shown in Partial section."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task1\n:PROPERTIES:\n:ID: empty-inherit-1\n:PROJECT: PartialProj\n:L3_AREA: WorkArea\n:L4_GOAL: \n:L5_VISION: \n:L6_PURPOSE: \n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizon View*"))
             (with-current-buffer "*Pearl-GTD Horizon View*"
               ;; Should be in Partial section (has L3 but missing L4-L6)
               (goto-char (point-min))
               (search-forward "** Partial: Projects Missing Higher Horizons")
               (should (search-forward "PartialProj" nil t))
               ;; Verify L3 shown but higher levels empty
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*PartialProj\\s-*|.*|\\s-*WorkArea\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Horizon View*"))

(provide 'pearl-gtd-horizons-test)

;;; pearl-gtd-horizons-test.el ends here
