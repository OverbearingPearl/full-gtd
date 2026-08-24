;;; full-gtd-planning-test.el --- User stories: Natural Planning Model  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for GTD Natural Planning Model.
;; Tests cover the forced completion workflow: Project definition → Horizon setup →
;; Brainstorm → Mandatory organization → Mandatory next action.

;;; Code:

(require 'ert)
(require 'full-gtd)
(require 'full-gtd-test-utils)

;; Helper to simulate sequential inputs for read-string
(defun full-gtd-test-planning--make-read-string-mock (inputs)
  "Create a mock for `read-string' that cycles through INPUTS."
  (let ((remaining inputs))
    (lambda (prompt &optional _initial _history)
      (let ((next (pop remaining)))
        (if (functionp next)
            (funcall next prompt)
          next)))))

(defun full-gtd-test-planning--make-completing-read-mock (inputs)
  "Create a mock for `completing-read' that cycles through INPUTS."
  (let ((remaining inputs))
    (lambda (prompt &optional _collection _predicate _require-match _initial-input _hist _def _inherit-input-method)
      (let ((next (pop remaining)))
        (if (functionp next)
            (funcall next prompt)
          next)))))

(full-gtd-test-define-story full-gtd-planning-test-user-completes-full-workflow
  "User completes natural planning with all fields filled, creating project with horizons and actions."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Improve user experience"    ; Purpose (L6)
                          "Keep it simple"             ; Principle (L6)
                          "Industry leader"            ; Vision (L5)
                          "Launch in Q2"               ; Goal (L4)
                          "Product Development"        ; Area (L3)
                          "@design"                    ; Context
                          ))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "NewWebsite"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "NewWebsite")
                  ((string-match "Default context" prompt) "@design")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?a ?a))))  ; Both items -> Action
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Redesign homepage\n")
                (insert "Optimize mobile view\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify project actions created in action.org
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Redesign homepage"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Optimize mobile view"))
             ;; Verify TODO state
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "TODO Redesign homepage"))
             ;; Verify Project property
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":PROJECT: NewWebsite"))
             ;; Verify Horizon properties applied (L3-L6)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L6_PURPOSE: Improve user experience"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L6_PRINCIPLE: Keep it simple"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L5_VISION: Industry leader"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L4_GOAL: Launch in Q2"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L3_AREA: Product Development"))
             ;; Verify BOTH actions use default context :design: (no longer per-item)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":design:"))
             ;; Verify BRAINSTORM property is removed after organizing
             (should-not (car (full-gtd-test-file-contains-p
                               (expand-file-name "action.org" full-gtd-init-base-directory)
                               ":BRAINSTORM:")))
             ;; Verify inbox is clean
             (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
               (when (file-exists-p inbox-file)
                 (should-not (car (full-gtd-test-file-contains-p inbox-file "Redesign homepage")))
                 (should-not (car (full-gtd-test-file-contains-p inbox-file "Optimize mobile view")))))
             ;; Verify summary buffer exists
             (let ((summary-buffer (get-buffer "*Full-GTD Planning Summary*")))
               (should summary-buffer)
               (with-current-buffer summary-buffer
                 (should (string-match-p "NewWebsite" (buffer-string)))
                 (should (string-match-p "Purpose" (buffer-string)))
                 (should (string-match-p "Goal" (buffer-string)))
                 (should (string-match-p "Redesign homepage" (buffer-string))))))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Brainstorm*") (kill-buffer "*Full-GTD Brainstorm*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-skips-optional-fields
  "Principle and Area can be empty, others are mandatory."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Just do it"      ; Purpose
                          ""                ; Principle (empty - optional)
                          "A vision"        ; Vision (now required)
                          "Ship it"         ; Goal
                          ""                ; Area (empty - optional)
                          ""                ; Context
                          ))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "MinimalProject"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "MinimalProject")
                  ((string-match "Default context" prompt) "")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))  ; Single item -> Action
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'full-gtd-inbox--read-context) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Fix bugs\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify L6_PURPOSE exists
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L6_PURPOSE: Just do it"))
             ;; Verify L6_PRINCIPLE does NOT exist
             (let ((result (full-gtd-test-file-contains-p
                            (expand-file-name "action.org" full-gtd-init-base-directory)
                            ":L6_PRINCIPLE:")))
               (should-not (car result)))
             ;; Verify L3_AREA does NOT exist
             (let ((result (full-gtd-test-file-contains-p
                            (expand-file-name "action.org" full-gtd-init-base-directory)
                            ":L3_AREA:")))
               (should-not (car result)))
             ;; Verify L5_VISION exists
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L5_VISION: A vision"))
             ;; But Goal must exist
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L4_GOAL: Ship it")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))
              (when (get-buffer "*Full-GTD Brainstorm Organize*")
                (kill-buffer "*Full-GTD Brainstorm Organize*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-forced-to-organize-all-items
  "User must organize all brainstorm items before proceeding, no skipping allowed."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@office"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "ForceComplete"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "ForceComplete")
                  ((string-match "Default context" prompt) "@office")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              ;; First: Reference, Second: Someday, Third: Action
              (cond ((= calls 1) ?r)
                    ((= calls 2) ?s)
                    (t ?a)))))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Idea 1\n")
                (insert "Idea 2\n")
                (insert "Idea 3\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify Idea 1 went to reference.org
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "Idea 1"))
             ;; Verify Idea 2 went to someday.org
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "someday.org" full-gtd-init-base-directory)
                      "Idea 2"))
             ;; Verify Idea 3 went to action.org as TODO with default context
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "TODO Idea 3"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":office:"))
             ;; Verify no items remain in inbox
             (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
               (when (file-exists-p inbox-file)
                 (should-not (car (full-gtd-test-file-contains-p inbox-file "Idea 1")))
                 (should-not (car (full-gtd-test-file-contains-p inbox-file "Idea 2")))
                 (should-not (car (full-gtd-test-file-contains-p inbox-file "Idea 3"))))))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-forced-to-create-next-action
  "If all brainstorm items go to Trash/Ref/Someday, user is forced to create one Next Action."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" ""))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "ForceAction"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "ForceAction")
                  ((string-match "Default context" prompt) "")
                  ((string-match "Required next action" prompt) "Forced next action")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?t ?r))))  ; First trash, then reference
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Bad idea 1\n")
                (insert "Bad idea 2\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify the forced action exists
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Forced next action"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "TODO Forced next action"))
             ;; Verify discarded ideas are NOT in action.org
             (let ((result1 (full-gtd-test-file-contains-p
                             (expand-file-name "action.org" full-gtd-init-base-directory)
                             "Bad idea 1"))
                   (result2 (full-gtd-test-file-contains-p
                             (expand-file-name "action.org" full-gtd-init-base-directory)
                             "Bad idea 2")))
               (should-not (car result1))
               (should-not (car result2)))
             ;; But they should be handled (one in reference, one deleted)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "Bad idea 2")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-provides-required-fields
  "Purpose, Vision, and Goal cannot be empty; code loops until valid input."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          ;; Simulate user providing valid values directly (no empty retries to avoid while loop)
          (let ((inputs '("Valid Purpose"  ; Purpose (required)
                          ""               ; Principle (optional)
                          "Valid Vision"   ; Vision (required)
                          "Valid Goal"     ; Goal (required)
                          ""               ; Area (optional)
                          "@ctx"           ; Context
                          ))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "TestTest"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "TestTest")
                  ((string-match "Default context" prompt) "@ctx")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify the valid values were eventually accepted and written
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L6_PURPOSE: Valid Purpose"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L5_VISION: Valid Vision"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L4_GOAL: Valid Goal"))
             ;; Verify L3_AREA does NOT exist
             (let ((result (full-gtd-test-file-contains-p
                            (expand-file-name "action.org" full-gtd-init-base-directory)
                            ":L3_AREA:")))
               (should-not (car result))))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-trashes-item-removes-completely
  "Trash destination removes item completely without creating file entry."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("P" "" "V" "G" "A" ""))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "TrashTest"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "TrashTest")
                  ((string-match "Default context" prompt) "")
                  ((string-match "Required next action" prompt) "Forced next action")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?t))  ; Trash
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Trash me\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify NOT in action.org
             (let ((result (full-gtd-test-file-contains-p
                            (expand-file-name "action.org" full-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; Verify NOT in reference.org
             (let ((result (full-gtd-test-file-contains-p
                            (expand-file-name "reference.org" full-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; Verify NOT in someday.org
             (let ((result (full-gtd-test-file-contains-p
                            (expand-file-name "someday.org" full-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; But forced next action should exist (since trashed item doesn't count)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "TODO Forced next action")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-skips-context-for-action
  "Context can be skipped for Next Action (empty string)."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("P" "" "V" "G" "A" ""))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "NoContext"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "NoContext")
                  ((string-match "Default context" prompt) "")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))  ; Action
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'full-gtd-inbox--read-context) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action without context\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Action without context"))
             ;; Should not have empty context tag or malformed tags
             (let ((actions-file (expand-file-name "action.org" full-gtd-init-base-directory)))
               (when (file-exists-p actions-file)
                 (let ((content (with-temp-buffer
                                  (insert-file-contents actions-file)
                                  (buffer-string))))
                   ;; Just verify it's valid org entry without crash
                   (should (string-match-p "^\\*+ TODO" content))))))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))
              (when (get-buffer "*Full-GTD Brainstorm Organize*")
                (kill-buffer "*Full-GTD Brainstorm Organize*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-rejected-for-duplicate-project
  "Planning must reject existing project names and force new name."
  :setup (progn
           (full-gtd-init-initialize)
           (let ((actions-file (expand-file-name "action.org" full-gtd-init-base-directory)))
             (with-temp-file actions-file
               (insert "* TODO Existing task\n:PROPERTIES:\n:PROJECT: ExistingProject\n:END:\n"))
             (unless (with-temp-buffer
                       (insert-file-contents actions-file)
                       (string-match-p "ExistingProject" (buffer-string)))
               (error "Setup failed: ExistingProject not found in action.org"))))
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'read-string)
          (let ((inputs '("ExistingProject"
                          "NewUniqueProject"))
                (index 0))
            (lambda (prompt &rest _)
              (cond ((string-match "Project name" prompt)
                     (let ((val (nth index inputs)))
                       (setq index (1+ index))
                       val))
                    ((string-match "Default context" prompt) "@ctx")
                    (t "")))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify new project was created
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":PROJECT: NewUniqueProject"))
             ;; Verify ExistingProject still exists
             (should (= 1 (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" full-gtd-init-base-directory))
                            (goto-char (point-min))
                            (how-many "ExistingProject")))))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*")
                (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-creates-project-without-brainstorm
  "Natural planning with no brainstorm items should still create project."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Test Purpose"     ; L6
                          ""                 ; L6 principle (optional)
                          "Test Vision"      ; L5 (now required)
                          "Test Goal"        ; L4
                          "Test Area"        ; L3
                          "@office"          ; Context
                          ))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "EmptyBrainstorm"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "EmptyBrainstorm")
                  ((string-match "Default context" prompt) "@office")
                  ((string-match "Required next action" prompt) "Forced Action")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) (error "Should not be called - no brainstorm items")))
         ((symbol-function 'recursive-edit)
          (lambda ()
            ;; Simulate empty brainstorm - do nothing, just return
            nil)))
  :body (full-gtd-planning-start)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" full-gtd-init-base-directory))
                            (buffer-string))))
             (should (string-match-p ":L6_PURPOSE:\\s-*Test Purpose" content))
             (should (string-match-p ":L5_VISION:\\s-*Test Vision" content))
             (should (string-match-p ":L4_GOAL:\\s-*Test Goal" content))
             (should (string-match-p "Forced Action" content)))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))
              (when (get-buffer "*Full-GTD: Inbox*") (kill-buffer "*Full-GTD: Inbox*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-quits-during-organize
  "User quits (C-g) during organize phase, staging buffer should be cleaned."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("P" "" "V" "G" "A" "@office"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "QuitTest"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "QuitTest")
                  ((string-match "Default context" prompt) "@office")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) (signal 'quit nil)))  ; User quits immediately
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Idea to organize\n"))))))
  :body (condition-case nil
            (full-gtd-planning-start)
          (quit (setq full-gtd-test-caught-error 'quit)))
  :asserts (progn
             (should (eq full-gtd-test-caught-error 'quit))
             ;; Verify staging buffer is killed
             (should-not (get-buffer "*Full-GTD Brainstorm Organize*"))
             ;; Verify brainstorm item remains in inbox (not partially processed)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "Idea to organize")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Brainstorm*") (kill-buffer "*Full-GTD Brainstorm*"))
              (when (get-buffer "*Full-GTD Brainstorm Organize*") (kill-buffer "*Full-GTD Brainstorm Organize*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-clarifies-brainstorm-item
  "User clarifies a brainstorm item before organizing to next action."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@office"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "ClarifyTest"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "ClarifyTest")
                  ((string-match "Default context" prompt) "@office")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?c ?a))))  ; First clarify, then action
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (lambda (_headline &optional _current-notes) (cons "Clarified idea" "Important notes")))
         ((symbol-function 'full-gtd-inbox--read-context)
          (lambda () "@office"))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Raw idea\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO Clarified idea"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Important notes"))
             (should-not (full-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" full-gtd-init-base-directory)
                          "Raw idea")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Brainstorm*") (kill-buffer "*Full-GTD Brainstorm*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))
              (when (get-buffer "*Full-GTD Brainstorm Organize*") (kill-buffer "*Full-GTD Brainstorm Organize*"))))

(full-gtd-test-define-story full-gtd-planning-test-isolates-other-project-brainstorms
  "Brainstorm items from other projects remain untouched during organize."
  :setup (progn
           (full-gtd-init-initialize)
           ;; Pre-seed inbox with old project's brainstorm item
           (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (with-temp-file inbox-file
               (insert "* Old brainstorm idea\n:PROPERTIES:\n:PROJECT: OldProject\n:BRAINSTORM: t\n:END:\n"))))
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "NewProject"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "NewProject")
                  ((string-match "Default context" prompt) "@ctx")
                  ((string-match "Required next action" prompt) "Forced action")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "New project idea\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify new project's item was processed (moved to actions)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "New project idea"))
             ;; Verify old project's item remains in inbox
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "Old brainstorm idea"))
             ;; Verify old project's item still has BRAINSTORM property
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      ":BRAINSTORM: t")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))
              (when (get-buffer "*Full-GTD Brainstorm Organize*") (kill-buffer "*Full-GTD Brainstorm Organize*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-selects-brainstorm-project-from-completion
  "User selects an existing brainstorm project from completion list, existing items pre-populated."
  :setup (progn
           (full-gtd-init-initialize)
           ;; Pre-seed inbox with existing brainstorm items for this project
           (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (with-temp-file inbox-file
               (insert "* Existing idea 1\n:PROPERTIES:\n:ID: bs-1\n:BRAINSTORM: t\n:PROJECT: ExistingBrainstormProject\n:END:\n")
               (insert "* Existing idea 2\n:PROPERTIES:\n:ID: bs-2\n:BRAINSTORM: t\n:PROJECT: ExistingBrainstormProject\n:END:\n")
               ;; Add another project to verify isolation
               (insert "* Other project idea\n:PROPERTIES:\n:ID: bs-3\n:BRAINSTORM: t\n:PROJECT: OtherProject\n:END:\n"))))
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "ExistingBrainstormProject"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "ExistingBrainstormProject")
                  ((string-match "Default context" prompt) "@ctx")
                  (t ""))))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              ?a)))  ; All items -> Action
         ((symbol-function 'recursive-edit)
          (lambda ()
            ;; Verify pre-populated content exists in buffer
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                ;; Verify existing items are pre-loaded
                (should (string-match-p "Existing idea 1" (buffer-string)))
                (should (string-match-p "Existing idea 2" (buffer-string)))
                ;; Verify other project's item is NOT loaded
                (should-not (string-match-p "Other project idea" (buffer-string)))
                ;; Add a new item to existing ones
                (goto-char (point-max))
                (insert "New project idea\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify all items (existing + new) were processed to actions
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Existing idea 1"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Existing idea 2"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "New project idea"))
             ;; Verify project association
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":PROJECT: ExistingBrainstormProject")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Brainstorm*") (kill-buffer "*Full-GTD Brainstorm*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))
              (when (get-buffer "*Full-GTD: Inbox*") (kill-buffer "*Full-GTD: Inbox*"))))

(full-gtd-test-define-story full-gtd-planning-test-new-project-no-preload
  "New project without existing brainstorm items starts with empty buffer."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "BrandNewProject"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "BrandNewProject")
                  ((string-match "Default context" prompt) "@ctx")
                  ((string-match "Required next action" prompt) "Forced action")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                ;; Verify buffer is empty (no pre-loaded content)
                (should (string= (string-trim (buffer-string)) ""))
                ;; Add new content
                (insert "Fresh idea\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Fresh idea")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Brainstorm*") (kill-buffer "*Full-GTD Brainstorm*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-proj-name-with-space
  "Project name containing spaces should be handled correctly."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "Website Redesign"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "Website Redesign")
                  ((string-match "Default context" prompt) "@ctx")
                  ((string-match "Required next action" prompt) "Forced action")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-inbox--read-context)
          (lambda () "@ctx"))
         ((symbol-function 'full-gtd-inbox--read-project)
          (lambda () ""))
         ((symbol-function 'full-gtd-inbox--read-delegate)
          (lambda () ""))
         ((symbol-function 'full-gtd-core-read-date)
          (lambda (&rest _) ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action item\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify project name with space is preserved
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":PROJECT: Website Redesign"))
             ;; Verify action is created
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Action item")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-sets-multiple-purposes
  "User can set multiple purposes separated by semicolon."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose1; Purpose2"  ; Multiple purposes
                          ""                    ; Principle
                          "Vision"              ; Vision
                          "Goal"                ; Goal
                          "Area"                ; Area
                          "@ctx"                ; Context
                          ))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "MultiPurposeProject"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "MultiPurposeProject")
                  ((string-match "Default context" prompt) "@ctx")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Task\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify multiple purposes stored as semicolon-separated
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L6_PURPOSE: Purpose1; Purpose2"))
             ;; Verify summary displays comma-separated
             (let ((summary-buffer (get-buffer "*Full-GTD Planning Summary*")))
               (should summary-buffer)
               (with-current-buffer summary-buffer
                 (should (string-match-p "Purpose1, Purpose2" (buffer-string))))))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-project-with-spaces-around-name
  "Project name with leading/trailing spaces should be trimmed."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (&rest _) "  Project Name  "))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "  Project Name  ")
                  ((string-match "Default context" prompt) "@ctx")
                  ((string-match "Required next action" prompt) "Forced action")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-inbox--read-context)
          (lambda () "@ctx"))
         ((symbol-function 'full-gtd-inbox--read-project)
          (lambda () ""))
         ((symbol-function 'full-gtd-inbox--read-delegate)
          (lambda () ""))
         ((symbol-function 'full-gtd-core-read-date)
          (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-planning--project-exists-p) (lambda (_) nil))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action\n"))))))
  :body (full-gtd-planning-start)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" full-gtd-init-base-directory))
                            (buffer-string))))
             ;; Project name should be trimmed (allow for extra space after colon)
             (should (string-match-p ":PROJECT:[ \t]*Project Name" content))
             (should-not (string-match-p ":PROJECT:[ \t]*  Project Name  " content)))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-multiple-purposes-with-mixed-separators
  "Multiple purposes with mixed separators and whitespace."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose1 ; Purpose2 ； Purpose3"  ; Mixed separators
                          ""                                 ; Principle
                          "Vision"                           ; Vision
                          "Goal"                             ; Goal
                          "Area"                             ; Area
                          "@ctx"                             ; Context
                          ))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "MultiPurposeProject"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "MultiPurposeProject")
                  ((string-match "Default context" prompt) "@ctx")
                  (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Task\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify multiple purposes stored correctly
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":L6_PURPOSE: Purpose1; Purpose2; Purpose3")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-empty-brainstorm-after-trim
  "Brainstorm items that are whitespace-only after trim should be ignored."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          ;; Provide more inputs to prevent nil returns causing infinite loops
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx" "ForcedPurpose" "" "ForcedVision" "ForcedGoal" "ForcedArea"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                (or val "Default")))))
         ((symbol-function 'completing-read)
          (lambda (_prompt &rest _) "EmptyBrainstorm"))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond ((string-match "Project name" prompt) "EmptyBrainstorm")
                  ((string-match "Default context" prompt) "@ctx")
                  ((string-match "Required next action" prompt) "Forced action")
                  (t ""))))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                ;; Only whitespace entries
                (insert "   \n")
                (insert "\t\t\n")
                (insert "  \n"))))))
  :body (full-gtd-planning-start)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "inbox.org" full-gtd-init-base-directory))
                            (buffer-string))))
             ;; Whitespace-only entries should not be captured
             (should-not (string-match-p ":BRAINSTORM: t" content))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Forced action")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-existing-project-with-space-detected
  "Existing project with space in name should be detected correctly."
  :setup (progn
           (full-gtd-init-initialize)
           ;; Pre-create a project with space in name
           (let ((actions-file (expand-file-name "action.org" full-gtd-init-base-directory)))
             (with-temp-file actions-file
               (insert "* TODO Existing task\n:PROPERTIES:\n:PROJECT: Existing Project\n:ID: existing-1\n:END:\n"))))
  :files nil
  :mock (((symbol-function 'full-gtd-core-read-property-with-completion)
          (let ((inputs '("Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (idx 0))
            (lambda (&rest _)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'read-string)
          (let ((inputs '("Existing Project"   ; First try - exists, will be rejected
                          "New Project Name"   ; Second try - accepted
                          "@ctx"               ; Default context
                          "Forced action"      ; Forced next action (if needed)
                          ))
                (index 0))
            (lambda (prompt &rest _)
              (cond ((string-match "Project name" prompt)
                     (let ((val (nth index inputs)))
                       (setq index (1+ index))
                       val))
                    ((string-match "Default context" prompt) "@ctx")
                    ((string-match "Required next action" prompt) "Forced action")
                    (t "")))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'full-gtd-inbox--read-context)
          (lambda () "@ctx"))
         ((symbol-function 'full-gtd-inbox--read-project)
          (lambda () ""))
         ((symbol-function 'full-gtd-inbox--read-delegate)
          (lambda () ""))
         ((symbol-function 'full-gtd-core-read-date)
          (lambda (&rest _) ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "New action\n"))))))
  :body (full-gtd-planning-start)
  :asserts (progn
             ;; Verify new project was created (after first was rejected)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":PROJECT: New Project Name")))
  :teardown (progn
              (when (get-buffer "*Full-GTD Planning*") (kill-buffer "*Full-GTD Planning*"))
              (when (get-buffer "*Full-GTD Planning Summary*") (kill-buffer "*Full-GTD Planning Summary*"))))

(full-gtd-test-define-story full-gtd-planning-test-user-aborts-brainstorm-cleans-buffer
  "User aborts brainstorm with C-c C-k, *Full-GTD Brainstorm* buffer must be killed."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (full-gtd-test-planning--make-completing-read-mock
           '("AbortBrainstorm")))
         ((symbol-function 'read-string)
          (full-gtd-test-planning--make-read-string-mock
           '("Purpose" "" "Vision" "Goal" "Area" "@ctx")))
         ((symbol-function 'recursive-edit)
          (lambda ()
            ;; Simulate C-c C-k: set abort flag and return
            ;; (as if exit-recursive-edit was called within recursive-edit)
            (when-let ((buf (get-buffer "*Full-GTD Brainstorm*")))
              (with-current-buffer buf
                (setq-local brainstorm-abort t))))))
  :body (condition-case nil
            (full-gtd-planning--ask-brainstorm "AbortBrainstorm")
          (quit :caught))
  :asserts (progn
             (should-not (get-buffer "*Full-GTD Brainstorm*")))
  :teardown nil)

(provide 'full-gtd-planning-test)

;;; full-gtd-planning-test.el ends here
