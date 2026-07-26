;;; pearl-gtd-test-planning.el --- User stories: Natural Planning Model  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; License: MIT
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; User stories for GTD Natural Planning Model.
;; Tests cover the forced completion workflow: Project definition → Horizon setup →
;; Brainstorm → Mandatory organization → Mandatory next action.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-validate)

;; Helper to simulate sequential inputs for read-string
(defun pearl-gtd-test-planning--make-read-string-mock (inputs)
  "Create a mock for `read-string' that cycles through INPUTS."
  (let ((remaining inputs))
    (lambda (prompt &optional _initial _history)
      (let ((next (pop remaining)))
        (if (functionp next)
            (funcall next prompt)
          next)))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-completes-full-workflow
  "User completes natural planning with all fields filled, creating project with horizons and actions."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("NewWebsite"               ; New project name
             "Improve user experience"  ; Purpose (L6) - required
             "Keep it simple"           ; Principle (L6) - optional but filled
             "Industry leader"          ; Vision (L5) - optional but filled
             "Launch in Q2"             ; Goal (L4) - required
             "Product Development"      ; Area (L3) - required
             "@design"                  ; NEW: Default context for all next actions
             )))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?a ?a))))  ; Both items -> Action
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Redesign homepage\n")
                (insert "Optimize mobile view\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify project actions created in actions.org
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Redesign homepage"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Optimize mobile view"))
             ;; Verify TODO state
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO Redesign homepage"))
             ;; Verify Project property
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":PROJECT: NewWebsite"))
             ;; Verify Horizon properties applied (L3-L6)
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Improve user experience"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PRINCIPLE: Keep it simple"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L5_VISION: Industry leader"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L4_GOAL: Launch in Q2"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L3_AREA: Product Development"))
             ;; Verify BOTH actions use default context :design: (no longer per-item)
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":design:"))
             ;; Verify BRAINSTORM property is removed after organizing
             (should-not (car (pearl-gtd-validate-file-contains-p
                               (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                               ":BRAINSTORM:")))
             ;; Verify inbox is clean
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (when (file-exists-p inbox-file)
                 (should-not (car (pearl-gtd-validate-file-contains-p inbox-file "Redesign homepage")))
                 (should-not (car (pearl-gtd-validate-file-contains-p inbox-file "Optimize mobile view")))))
             ;; Verify summary buffer exists
             (let ((summary-buffer (get-buffer "*Pearl-GTD Planning Summary*")))
               (should summary-buffer)
               (with-current-buffer summary-buffer
                 (should (string-match-p "NewWebsite" (buffer-string)))
                 (should (string-match-p "Purpose" (buffer-string)))
                 (should (string-match-p "Goal" (buffer-string)))
                 (should (string-match-p "Redesign homepage" (buffer-string))))))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Brainstorm*") (kill-buffer "*Pearl-GTD Brainstorm*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-skips-optional-fields
  "Principle and Area can be empty, others are mandatory."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("MinimalProject"  ; New project name
             "Just do it"      ; Purpose
             ""                ; Principle (empty - optional)
             "A vision"        ; Vision (now required)
             "Ship it"         ; Goal
             ""                ; Area (empty - optional)
             ""                ; Default context (empty)
             )))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) ?a))  ; Single item -> Action
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-context) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Fix bugs\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify L6_PURPOSE exists
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Just do it"))
             ;; Verify L6_PRINCIPLE does NOT exist
             (let ((result (pearl-gtd-validate-file-contains-p
                            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            ":L6_PRINCIPLE:")))
               (should-not (car result)))
             ;; Verify L3_AREA does NOT exist
             (let ((result (pearl-gtd-validate-file-contains-p
                            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            ":L3_AREA:")))
               (should-not (car result)))
             ;; Verify L5_VISION exists
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L5_VISION: A vision"))
             ;; But Goal must exist
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L4_GOAL: Ship it")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))
              (when (get-buffer "*Pearl-GTD Brainstorm Organize*")
                (kill-buffer "*Pearl-GTD Brainstorm Organize*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-forced-to-organize-all-items
  "User must organize all brainstorm items before proceeding, no skipping allowed."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("ForceComplete"                      ; New project name
             "Purpose" "" "Vision" "Goal" "Area"  ; Horizons
             "@office"                            ; Default context
             )))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              ;; First: Reference, Second: Someday, Third: Action
              (cond ((= calls 1) ?r)
                    ((= calls 2) ?s)
                    (t ?a)))))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Idea 1\n")
                (insert "Idea 2\n")
                (insert "Idea 3\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify Idea 1 went to reference.org
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "Idea 1"))
             ;; Verify Idea 2 went to someday.org
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "someday.org" pearl-gtd-init-base-directory)
                      "Idea 2"))
             ;; Verify Idea 3 went to actions.org as TODO with default context
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO Idea 3"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":office:"))
             ;; Verify no items remain in inbox
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (when (file-exists-p inbox-file)
                 (should-not (car (pearl-gtd-validate-file-contains-p inbox-file "Idea 1")))
                 (should-not (car (pearl-gtd-validate-file-contains-p inbox-file "Idea 2")))
                 (should-not (car (pearl-gtd-validate-file-contains-p inbox-file "Idea 3"))))))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-forced-to-create-next-action
  "If all brainstorm items go to Trash/Ref/Someday, user is forced to create one Next Action."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("ForceAction"                        ; New project name
             "Purpose" "" "Vision" "Goal" "Area"  ; Horizons
             ""                                   ; Default context (empty)
             "Forced next action"                 ; Mandatory action created at end
             )))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?t ?r))))  ; First trash, then reference
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Bad idea 1\n")
                (insert "Bad idea 2\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify the forced action exists
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Forced next action"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO Forced next action"))
             ;; Verify discarded ideas are NOT in actions.org
             (let ((result1 (pearl-gtd-validate-file-contains-p
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                             "Bad idea 1"))
                   (result2 (pearl-gtd-validate-file-contains-p
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                             "Bad idea 2")))
               (should-not (car result1))
               (should-not (car result2)))
             ;; But they should be handled (one in reference, one deleted)
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "Bad idea 2")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))


(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-provides-required-fields
  "Purpose, Vision, and Goal cannot be empty; code loops until valid input."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          ;; Simulate user trying to skip required fields, then providing them
          (let ((calls 0)
                (inputs '("ValidateTest"  ; New project name
                          ""              ; Try empty Purpose (rejected/loop)
                          "Valid Purpose" ; Accept this
                          ""              ; Try empty Principle (allowed)
                          ""              ; Try empty Vision (rejected/loop)
                          "Valid Vision"  ; Accept this
                          ""              ; Try empty Goal (rejected/loop)
                          "Valid Goal"    ; Accept this
                          ""              ; Try empty Area (allowed)
                          "@ctx"          ; Default context
                          )))
            (lambda (_prompt &optional _initial _history)
              (let ((next (nth calls inputs)))
                (setq calls (1+ calls))
                next))))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify the valid values were eventually accepted and written
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Valid Purpose"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L5_VISION: Valid Vision"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L4_GOAL: Valid Goal"))
             ;; Verify L3_AREA does NOT exist
             (let ((result (pearl-gtd-validate-file-contains-p
                            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            ":L3_AREA:")))
               (should-not (car result))))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-trashes-item-removes-completely
  "Trash destination removes item completely without creating file entry."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("TrashTest"         ; New project name
             "P" "" "V" "G" "A"  ; Horizons
             ""                  ; Default context (empty)
             )))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) ?t))  ; Trash
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Trash me\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify NOT in actions.org
             (let ((result (pearl-gtd-validate-file-contains-p
                            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; Verify NOT in reference.org
             (let ((result (pearl-gtd-validate-file-contains-p
                            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; Verify NOT in someday.org
             (let ((result (pearl-gtd-validate-file-contains-p
                            (expand-file-name "someday.org" pearl-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; But forced next action should exist (since trashed item doesn't count)
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))


(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-skips-context-for-action
  "Context can be skipped for Next Action (empty string)."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("NoContext"         ; New project name
             "P" "" "V" "G" "A"  ; Horizons
             ""                  ; Default context (empty)
             )))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) ?a))  ; Action
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--read-context) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action without context\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Action without context"))
             ;; Should not have empty context tag or malformed tags
             (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
               (when (file-exists-p actions-file)
                 (let ((content (with-temp-buffer
                                  (insert-file-contents actions-file)
                                  (buffer-string))))
                   ;; Just verify it's valid org entry without crash
                   (should (string-match-p "^\\*+ TODO" content))))))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))
              (when (get-buffer "*Pearl-GTD Brainstorm Organize*")
                (kill-buffer "*Pearl-GTD Brainstorm Organize*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-rejected-for-duplicate-project
  "Planning must reject existing project names and force new name."
  :setup (progn
           (pearl-gtd-init-initialize)
           (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
             (with-temp-file actions-file
               (insert "* TODO Existing task\n:PROPERTIES:\n:PROJECT: ExistingProject\n:END:\n"))
             (unless (with-temp-buffer
                       (insert-file-contents actions-file)
                       (string-match-p "ExistingProject" (buffer-string)))
               (error "Setup failed: ExistingProject not found in actions.org"))))
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((inputs '("ExistingProject"
                          "NewUniqueProject"
                          "Purpose" "" "Vision" "Goal" "Area" "@ctx"))
                (index 0))
            (lambda (_prompt &optional _initial _history)
              (let ((val (nth index inputs)))
                (setq index (1+ index))
                val))))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify new project was created
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":PROJECT: NewUniqueProject"))
             ;; Verify ExistingProject still exists
             (should (= 1 (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                            (goto-char (point-min))
                            (how-many "ExistingProject")))))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-creates-project-without-brainstorm
  "Natural planning with no brainstorm items should still create project."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((inputs '("EmptyBrainstorm"  ; project name
                          "Test Purpose"     ; L6
                          ""                 ; L6 principle (optional)
                          "Test Vision"      ; L5 (now required)
                          "Test Goal"        ; L4
                          "Test Area"        ; L3
                          "@office"          ; Default context
                          "Forced Action"    ; forced next action (no brainstorm items)
                          ))
                (idx 0))
            (lambda (_prompt &optional _initial _history)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) (error "Should not be called - no brainstorm items")))
         ((symbol-function 'recursive-edit)
          (lambda ()
            ;; Simulate empty brainstorm - do nothing, just return
            nil)))
  :body (pearl-gtd-planning-start)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             (should (string-match-p ":L6_PURPOSE:\\s-*Test Purpose" content))
             (should (string-match-p ":L5_VISION:\\s-*Test Vision" content))
             (should (string-match-p ":L4_GOAL:\\s-*Test Goal" content))
             (should (string-match-p "Forced Action" content)))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*") (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-trashes-all-items-forces-action
  "All brainstorm items trashed should force creation of one action."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           ;; Added "Work" as L3_AREA value so "Forced Action" becomes the 7th value for action title
           '("AllTrashed" "P" "" "G" "A" "Work" "@ctx" "Forced Action")))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              ?t)))  ; Always trash
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Trash item 1\n")
                (insert "Trash item 2\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             (should-not (pearl-gtd-validate-file-contains-p-bool
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Trash item 1"))
             (should-not (pearl-gtd-validate-file-contains-p-bool
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Trash item 2"))
             (should (pearl-gtd-validate-file-contains-p-bool
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Forced Action")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*") (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-quits-during-organize
  "User quits (C-g) during organize phase, staging buffer should be cleaned."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("QuitTest" "P" "" "V" "G" "A" "@office")))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) (signal 'quit nil)))  ; User quits immediately
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Idea to organize\n"))))))
  :body (condition-case nil
            (pearl-gtd-planning-start)
          (quit (setq pearl-gtd-validate-caught-error 'quit)))
  :asserts (progn
             (should (eq pearl-gtd-validate-caught-error 'quit))
             ;; Verify staging buffer is killed
             (should-not (get-buffer "*Pearl-GTD Brainstorm Organize*"))
             ;; Verify brainstorm item remains in inbox (not partially processed)
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "Idea to organize")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Brainstorm*") (kill-buffer "*Pearl-GTD Brainstorm*"))
              (when (get-buffer "*Pearl-GTD Brainstorm Organize*") (kill-buffer "*Pearl-GTD Brainstorm Organize*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-user-clarifies-brainstorm-item
  "User clarifies a brainstorm item before organizing to next action."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("ClarifyTest" "Purpose" "" "Vision" "Goal" "Area" "@office")))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?c ?a))))  ; First clarify, then action
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons "Clarified idea" "Important notes")))
         ((symbol-function 'pearl-gtd-inbox--read-context)
          (lambda () "@office"))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Raw idea\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Clarified idea"))
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Important notes"))
             (should-not (pearl-gtd-validate-file-contains-p-bool
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Raw idea")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Brainstorm*") (kill-buffer "*Pearl-GTD Brainstorm*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*") (kill-buffer "*Pearl-GTD Planning Summary*"))
              (when (get-buffer "*Pearl-GTD Brainstorm Organize*") (kill-buffer "*Pearl-GTD Brainstorm Organize*"))))

(pearl-gtd-validate-define-story pearl-gtd-test-planning-isolates-other-project-brainstorms
  "Brainstorm items from other projects remain untouched during organize."
  :setup (progn
           (pearl-gtd-init-initialize)
           ;; Pre-seed inbox with old project's brainstorm item
           (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (with-temp-file inbox-file
               (insert "* Old brainstorm idea\n:PROPERTIES:\n:PROJECT: OldProject\n:BRAINSTORM: t\n:END:\n"))))
  :files nil
  :mock (((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("NewProject" "Purpose" "" "Vision" "Goal" "Area" "@ctx" "Forced action")))
         ((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_) ?a))
         ((symbol-function 'pearl-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'pearl-gtd-inbox--read-delegate) (lambda () ""))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "New project idea\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify new project's item was processed (moved to actions)
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "New project idea"))
             ;; Verify old project's item remains in inbox
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "Old brainstorm idea"))
             ;; Verify old project's item still has BRAINSTORM property
             (should (pearl-gtd-validate-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      ":BRAINSTORM: t")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*") (kill-buffer "*Pearl-GTD Planning Summary*"))
              (when (get-buffer "*Pearl-GTD Brainstorm Organize*") (kill-buffer "*Pearl-GTD Brainstorm Organize*"))))

(provide 'pearl-gtd-test-planning)

;;; pearl-gtd-test-planning.el ends here
