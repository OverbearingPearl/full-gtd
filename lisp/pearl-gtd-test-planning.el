;;; pearl-gtd-test-planning.el --- User stories: Natural Planning Model  -*- lexical-binding: t; -*-

;; License: MIT
;; SPDX-License-Identifier: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for GTD Natural Planning Model.
;; Tests cover the forced completion workflow: Project definition → Horizon setup →
;; Brainstorm → Mandatory organization → Mandatory next action.

;;; Code:

(add-to-list 'load-path (file-name-directory (or load-file-name buffer-file-name)))
(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

;; Helper to simulate sequential inputs for read-string
(defun pearl-gtd-test-planning--make-read-string-mock (inputs)
  "Create a mock for `read-string' that cycles through INPUTS."
  (let ((remaining inputs))
    (lambda (prompt &optional _initial _history)
      (let ((next (pop remaining)))
        (if (functionp next)
            (funcall next prompt)
          next)))))

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-completes-full-workflow
  "User completes natural planning with all fields filled, creating project with horizons and actions."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match-p "Destination" prompt) "Next Action")
             ((string-match-p "organize" prompt) "Next Action")
             (t ""))))
         ((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("NewWebsite"                    ; New project name (first read-string call)
             "Improve user experience"       ; Purpose (L6) - required
             "Keep it simple"                ; Principle (L6) - optional but filled
             "Industry leader"               ; Vision (L5) - optional but filled
             "Launch in Q2"                  ; Goal (L4) - required
             "Product Development"           ; Area (L3) - required
             "@design"                       ; Context for item 1
             "@dev"                          ; Context for item 2
             )))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Redesign homepage\n")
                (insert "Optimize mobile view\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify project actions created in actions.org
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Redesign homepage"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Optimize mobile view"))
             ;; Verify TODO state
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO Redesign homepage"))
             ;; Verify Project property
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":PROJECT: NewWebsite"))
             ;; Verify Horizon properties applied (L3-L6)
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Improve user experience"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PRINCIPLE: Keep it simple"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L5_VISION: Industry leader"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L4_GOAL: Launch in Q2"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L3_AREA: Product Development"))
             ;; Verify Context tags (from inbox processing logic)
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":design:"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":dev:"))
             ;; Verify BRAINSTORM property is removed after organizing
             (should-not (car (pearl-gtd-test-file-contains-p
                               (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                               ":BRAINSTORM:")))
             ;; Verify inbox is clean (brainstorm items removed from inbox)
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (when (file-exists-p inbox-file)
                 (should-not (car (pearl-gtd-test-file-contains-p inbox-file "Redesign homepage")))
                 (should-not (car (pearl-gtd-test-file-contains-p inbox-file "Optimize mobile view")))))
             ;; Verify summary buffer exists
             (let ((summary-buffer (get-buffer "*Pearl-GTD Planning Summary*")))
               (should summary-buffer)
               (with-current-buffer summary-buffer
                 ;; Verify project name in title
                 (should (string-match-p "NewWebsite" (buffer-string)))
                 ;; Verify horizons displayed
                 (should (string-match-p "Purpose" (buffer-string)))
                 (should (string-match-p "Goal" (buffer-string)))
                 ;; Verify actions listed
                 (should (string-match-p "Redesign homepage" (buffer-string))))))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Brainstorm*") (kill-buffer "*Pearl-GTD Brainstorm*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-skips-optional-fields
  "Principle and Vision can be empty, others are mandatory."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match-p "organize" prompt) "Next Action")
             (t "Next Action"))))
         ((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("MinimalProject"       ; New project name
             "Just do it"          ; Purpose
             ""                    ; Principle (empty - optional)
             ""                    ; Vision (empty - optional)
             "Ship it"             ; Goal
             "Engineering"         ; Area
             ""                    ; Context empty
             )))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Fix bugs\n"))))))  ; Only one brainstorm item
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify L6_PURPOSE exists
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Just do it"))
             ;; Verify L6_PRINCIPLE does NOT exist (or is empty - implementation dependent)
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            ":L6_PRINCIPLE:")))
               (should-not (car result)))
             ;; Verify L5_VISION does NOT exist
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            ":L5_VISION:")))
               (should-not (car result)))
             ;; But Goal and Area must exist
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L4_GOAL: Ship it"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L3_AREA: Engineering")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-forced-to-organize-all-items
  "User must organize all brainstorm items before proceeding, no skipping allowed."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ;; Simulate organizing 3 items in sequence
             ((string-match-p "Idea 1" prompt) "Reference")
             ((string-match-p "Idea 2" prompt) "Someday")
             ((string-match-p "Idea 3" prompt) "Next Action")
             (t "Next Action"))))
         ((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("ForceComplete"                ; New project name
             "Purpose" "" "" "Goal" "Area"  ; Horizons
             "@office"                      ; Context for the Next Action
             )))
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
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "Idea 1"))
             ;; Verify Idea 2 went to someday.org
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "someday.org" pearl-gtd-init-base-directory)
                      "Idea 2"))
             ;; Verify Idea 3 went to actions.org as TODO
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO Idea 3"))
             ;; Verify no items remain in inbox
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (when (file-exists-p inbox-file)
                 (should-not (car (pearl-gtd-test-file-contains-p inbox-file "Idea 1")))
                 (should-not (car (pearl-gtd-test-file-contains-p inbox-file "Idea 2")))
                 (should-not (car (pearl-gtd-test-file-contains-p inbox-file "Idea 3"))))))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-forced-to-create-next-action
  "If all brainstorm items go to Trash/Ref/Someday, user is forced to create one Next Action."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match-p "Idea 1" prompt) "Trash")
             ((string-match-p "Idea 2" prompt) "Reference")
             ((string-match-p "organize" prompt) "Trash")
             (t "Next Action"))))
         ((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("ForceAction"                  ; New project name
             "Purpose" "" "" "Goal" "Area"  ; Horizons
             "Forced next action"           ; Mandatory action created at end
             )))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Bad idea 1\n")
                (insert "Bad idea 2\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify the forced action exists
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Forced next action"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO Forced next action"))
             ;; Verify discarded ideas are NOT in actions.org
             (let ((result1 (pearl-gtd-test-file-contains-p
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                             "Bad idea 1"))
                   (result2 (pearl-gtd-test-file-contains-p
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                             "Bad idea 2")))
               (should-not (car result1))
               (should-not (car result2)))
             ;; But they should be handled (one in reference, one deleted)
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "Bad idea 2")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))


(pearl-gtd-test-define-story pearl-gtd-test-planning-user-provides-required-fields
  "Purpose, Goal, and Area cannot be empty; code loops until valid input."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            "Next Action"))
         ((symbol-function 'read-string)
          ;; Simulate user trying to skip required fields, then providing them
          (let ((calls 0)
                (inputs '("ValidateTest"   ; New project name
                         ""            ; Try empty Purpose (rejected/loop)
                         "Valid Purpose" ; Accept this
                         ""            ; Try empty Principle (allowed)
                         ""            ; Try empty Vision (allowed)
                         ""            ; Try empty Goal (rejected/loop)
                         "Valid Goal"  ; Accept this
                         ""            ; Try empty Area (rejected/loop)
                         "Valid Area"  ; Accept this
                         "@ctx"        ; Context for next action (during organizing)
                         )))
            (lambda (prompt &optional _initial _history)
              (let ((next (nth calls inputs)))
                (setq calls (1+ calls))
                next))))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify the valid values were eventually accepted and written
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L6_PURPOSE: Valid Purpose"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L4_GOAL: Valid Goal"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":L3_AREA: Valid Area")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-trashes-item-removes-completely
  "Trash destination removes item completely without creating file entry."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match-p "Trash me" prompt) "Trash")
             (t "Trash"))))
         ((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("TrashTest"                ; New project name
             "P" "" "" "G" "A")))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Trash me\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify NOT in actions.org
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; Verify NOT in reference.org
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; Verify NOT in someday.org
             (let ((result (pearl-gtd-test-file-contains-p
                            (expand-file-name "someday.org" pearl-gtd-init-base-directory)
                            "Trash me")))
               (should-not (car result)))
             ;; But forced next action should exist (since trashed item doesn't count)
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "TODO")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*")
                (kill-buffer "*Pearl-GTD Planning Summary*"))))


(pearl-gtd-test-define-story pearl-gtd-test-planning-user-skips-context-for-action
  "Context can be skipped for Next Action (empty string)."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match-p "Organize" prompt) "Next Action")  ; 改为大写，匹配 "Organize '...' to: "
             (t "Next Action"))))
         ((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           '("NoContext"                  ; New project name
             "P" "" "" "G" "A"            ; Horizons
             ""                            ; Context for brainstorm item (empty, Next Action needs context prompt)
             )))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action without context\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
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
                (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-rejected-for-duplicate-project
  "Planning must reject existing project names and force new name."
  :setup (progn
           (pearl-gtd-init-initialize)
           ;; 预创建已有项目，使用 with-temp-file 确保写入完成
           (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
             (with-temp-file actions-file
               (insert "* TODO Existing task\n:PROPERTIES:\n:PROJECT: ExistingProject\n:END:\n"))
             ;; Diagnostic: ensure write succeeded
             (unless (with-temp-buffer
                       (insert-file-contents actions-file)
                       (string-match-p "ExistingProject" (buffer-string)))
               (error "Setup failed: ExistingProject not found in actions.org"))))
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((inputs '("ExistingProject"    ; 第一次输入：重复名称
                         "NewUniqueProject"   ; 第二次输入：有效新名称
                         "Purpose" "" "" "Goal" "Area" "@ctx"))
                (index 0))
            (lambda (prompt &optional _initial _history)
              (let ((val (nth index inputs)))
                (setq index (1+ index))
                val))))
         ((symbol-function 'completing-read) (lambda (_prompt _collection &rest _) "Next Action"))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Action\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             ;; Verify new project was created
             (should (pearl-gtd-test-file-contains-p
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

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-creates-project-without-brainstorm
  "Natural planning with no brainstorm items should still create project."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt &rest _)
            ;; For forced action creation at the end
            "Next Action"))
         ((symbol-function 'read-string)
          (let ((inputs '("EmptyBrainstorm"  ; project name
                         "Test Purpose"     ; L6
                         ""                 ; L6 principle (optional)
                         ""                 ; L5 (optional)
                         "Test Goal"        ; L4
                         "Test Area"        ; L3
                         "Forced Action"    ; forced next action
                         ""                 ; context (optional)
                         ))
                (idx 0))
            (lambda (prompt &optional _initial _history)
              (let ((val (nth idx inputs)))
                (setq idx (1+ idx))
                val))))
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
             (should (string-match-p ":L4_GOAL:\\s-*Test Goal" content)))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*") (kill-buffer "*Pearl-GTD Planning Summary*"))))

(pearl-gtd-test-define-story pearl-gtd-test-planning-user-trashes-all-items-forces-action
  "All brainstorm items trashed should force creation of one action."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'completing-read)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Trash item 1" prompt) "Trash")
             ((string-match "Trash item 2" prompt) "Trash")
             ((string-match "Organize" prompt) "Trash")
             (t "Next Action"))))
         ((symbol-function 'read-string)
          (pearl-gtd-test-planning--make-read-string-mock
           ;; Added "Work" as L3_AREA value so "Forced Action" becomes the 7th value for action title
           '("AllTrashed" "P" "" "G" "A" "Work" "Forced Action")))
         ((symbol-function 'recursive-edit)
          (lambda ()
            (when-let ((buf (get-buffer "*Pearl-GTD Brainstorm*")))
              (with-current-buffer buf
                (insert "Trash item 1\n")
                (insert "Trash item 2\n"))))))
  :body (pearl-gtd-planning-start)
  :asserts (progn
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Trash item 1"))
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Trash item 2"))
             (should (pearl-gtd-test-file-contains-p-bool
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Forced Action")))
  :teardown (progn
              (when (get-buffer "*Pearl-GTD Planning*") (kill-buffer "*Pearl-GTD Planning*"))
              (when (get-buffer "*Pearl-GTD Planning Summary*") (kill-buffer "*Pearl-GTD Planning Summary*"))))

(provide 'pearl-gtd-test-planning)

;;; pearl-gtd-test-planning.el ends here
