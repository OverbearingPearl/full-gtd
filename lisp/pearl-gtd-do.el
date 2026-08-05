;;; pearl-gtd-do.el --- Do/Work phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the "Do" phase of GTD via a single-card,
;; session-based workflow.  It provides smart prioritization,
;; constraint awareness (context and energy), and GTD-aligned
;; state transitions.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)

;;;; Session state

(defvar-local pearl-gtd-do--session-actions nil
  "List of action plists for the current Do session.")

(defvar-local pearl-gtd-do--session-context nil
  "Current context filter for the session, or nil for all contexts.")

(defvar-local pearl-gtd-do--session-energy nil
  "Current energy level for the session, or nil for no filter.")

(defvar-local pearl-gtd-do--session-time-budget nil
  "Current time budget in minutes for the session, or nil for no filter.")

(defvar-local pearl-gtd-do--session-total-count nil
  "Total number of matching actions at session start.
Decrements when actions are completed, unchanged when skipped.")

(defvar-local pearl-gtd-do--session-view-type nil
  "Type of the current session: `next, `delegated, or `today.")

(defvar pearl-gtd-do--energy-levels '("high" "normal" "low")
  "Supported energy levels.")

;;;; Scoring

(defconst pearl-gtd-do--score-weights
  '((overdue . 100)
    (deadline-1d . 50)
    (deadline-3d . 30)
    (deadline-7d . 15)
    (scheduled-today . 20)
    (age-day . 1)
    (age-max . 30)
    (l6-purpose . 20)
    (l5-vision . 15)
    (l4-goal . 10)
    (l3-area . 5)
    (project . 5)
    (context-match . 10))
  "Weights for action priority scoring.")

(defun pearl-gtd-do--days-until (date-string)
  "Return number of days until DATE-STRING, or nil if not a date.
DATE-STRING should be an Org date or timestamp."
  (when date-string
    (let ((time (ignore-errors (org-time-string-to-time date-string))))
      (when time
        (/ (- (float-time time) (float-time (current-time))) 86400.0)))))

(defun pearl-gtd-do--score-action (action &optional context-filter)
  "Calculate priority score for ACTION plist.
Optional CONTEXT-FILTER boosts matching contexts."
  (let ((score 0)
        (deadline (plist-get action :deadline))
        (scheduled (plist-get action :scheduled))
        (created (plist-get action :created))
        (context (plist-get action :context))
        (project (plist-get action :project))
        (l3 (plist-get action :l3))
        (l4 (plist-get action :l4))
        (l5 (plist-get action :l5))
        (l6 (plist-get action :l6))
        (delegated (plist-get action :delegated)))
    ;; Urgency: deadline
    (when deadline
      (let ((days (pearl-gtd-do--days-until deadline)))
        (cond
         ((null days) nil)
         ((< days 0) (setq score (+ score (cdr (assq 'overdue pearl-gtd-do--score-weights)))))
         ((<= days 1) (setq score (+ score (cdr (assq 'deadline-1d pearl-gtd-do--score-weights)))))
         ((<= days 3) (setq score (+ score (cdr (assq 'deadline-3d pearl-gtd-do--score-weights)))))
         ((<= days 7) (setq score (+ score (cdr (assq 'deadline-7d pearl-gtd-do--score-weights))))))))
    ;; Urgency: scheduled today
    (when (and scheduled
               (string-match-p (format-time-string "<%F" (current-time)) scheduled))
      (setq score (+ score (cdr (assq 'scheduled-today pearl-gtd-do--score-weights)))))
    ;; Urgency: age
    (when created
      (let* ((created-time (ignore-errors (date-to-time created)))
             (days (when created-time
                     (/ (- (float-time (current-time)) (float-time created-time)) 86400.0))))
        (when days
          (setq score (+ score (min (* days (cdr (assq 'age-day pearl-gtd-do--score-weights)))
                                    (cdr (assq 'age-max pearl-gtd-do--score-weights))))))))
    ;; Importance: horizons
    (when (and l6 (not (string= l6 "")))
      (setq score (+ score (cdr (assq 'l6-purpose pearl-gtd-do--score-weights)))))
    (when (and l5 (not (string= l5 "")))
      (setq score (+ score (cdr (assq 'l5-vision pearl-gtd-do--score-weights)))))
    (when (and l4 (not (string= l4 "")))
      (setq score (+ score (cdr (assq 'l4-goal pearl-gtd-do--score-weights)))))
    (when (and l3 (not (string= l3 "")))
      (setq score (+ score (cdr (assq 'l3-area pearl-gtd-do--score-weights)))))
    ;; Project presence
    (when (and project (not (string= project "")))
      (setq score (+ score (cdr (assq 'project pearl-gtd-do--score-weights)))))
    ;; Context match
    (when (and context-filter context)
      (let ((ctxs (pearl-gtd-do--split-contexts context)))
        (when (member context-filter ctxs)
          (setq score (+ score (cdr (assq 'context-match pearl-gtd-do--score-weights)))))))
    ;; Penalties
    ;; Delegated tasks: -100 points
    (when (and delegated (not (string= delegated "")))
      (setq score (- score 100)))
    ;; Future scheduled tasks: -50 points
    (when scheduled
      (let ((days (pearl-gtd-do--days-until scheduled)))
        (when (and days (> days 0))
          (setq score (- score 50)))))
    score))

;;;; Action collection

(defun pearl-gtd-do--normalize-context (context)
  "Normalize CONTEXT string by removing @ prefix."
  (if (string-prefix-p "@" context)
      (substring context 1)
    context))

(defun pearl-gtd-do--split-contexts (context-string)
  "Split CONTEXT-STRING by comma and normalize each value.
CONTEXT-STRING uses @ prefixes like \"@office,@home\"."
  (when context-string
    (mapcar #'pearl-gtd-do--normalize-context
            (seq-filter (lambda (s) (not (string-empty-p s)))
                        (mapcar #'string-trim (split-string context-string ","))))))

(defun pearl-gtd-do--collect-actions (predicates)
  "Collect TODO actions from action.org matching PREDICATES.
Returns list of action plists."
  (let* ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
         (file-name (file-name-nondirectory file-path))
         (actions '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (cl-every (lambda (pred) (funcall pred)) predicates)
             (push (list
                    :headline (org-get-heading t t)
                    :context (mapconcat (lambda (c) (concat "@" c)) (org-get-tags) ",")
                    :status (org-get-todo-state)
                    :scheduled (org-entry-get nil "SCHEDULED")
                    :delegated (org-entry-get nil "DELEGATED")
                    :project (org-entry-get nil "PROJECT")
                    :created (org-entry-get nil "CREATED")
                    :id (org-entry-get nil "ID")
                    :file file-name
                    :deadline (org-entry-get nil "DEADLINE")
                    :l3 (org-entry-get nil "L3_AREA")
                    :l4 (org-entry-get nil "L4_GOAL")
                    :l5 (org-entry-get nil "L5_VISION")
                    :l6 (org-entry-get nil "L6_PURPOSE"))
                   actions)))
         nil nil)))
    (nreverse actions)))

(defun pearl-gtd-do--context-matches-p (action context-filter)
  "Return non-nil if ACTION context matches CONTEXT-FILTER.
CONTEXT-FILTER is a normalized context string (without @)."
  (if (null context-filter)
      t
    (let ((contexts (pearl-gtd-do--split-contexts (plist-get action :context))))
      (member context-filter contexts))))

(defun pearl-gtd-do--filter-actions (actions &optional context)
  "Filter ACTIONS by CONTEXT constraint."
  (seq-filter
   (lambda (action)
     (pearl-gtd-do--context-matches-p action context))
   actions))

(defun pearl-gtd-do--sort-actions (actions context-filter)
  "Sort ACTIONS by priority score, highest first.
CONTEXT-FILTER is used for context-match bonus."
  (sort (copy-sequence actions)
        (lambda (a b)
          (> (pearl-gtd-do--score-action a context-filter)
             (pearl-gtd-do--score-action b context-filter)))))

;;;; Session UI

(defun pearl-gtd-do--session-buffer-name (view-type)
  "Return buffer name for VIEW-TYPE session."
  (pcase view-type
    ('delegated "*Pearl-GTD: Delegated Session*")
    ('today "*Pearl-GTD: Today Session*")
    (_ "*Pearl-GTD: Do Session*")))

(defun pearl-gtd-do--format-date (date-string)
  "Format Org DATE-STRING for display, including relative days."
  (when date-string
    (let ((days (pearl-gtd-do--days-until date-string)))
      (cond
       ((null days) date-string)
       ((< days 0) (format "%s (overdue %.0f days)" date-string (abs days)))
       ((= days 0) (format "%s (today)" date-string))
       ((<= days 7) (format "%s (in %.0f days)" date-string days))
       (t date-string)))))

(defun pearl-gtd-do--render-card (buffer)
  "Render current action card in BUFFER."
  (with-current-buffer buffer
    (setq buffer-read-only nil)
    (erase-buffer)
    ;; Save all session state before org-mode clears buffer-local vars
    (let ((saved-actions pearl-gtd-do--session-actions)
          (saved-context pearl-gtd-do--session-context)
          (saved-energy pearl-gtd-do--session-energy)
          (saved-time-budget pearl-gtd-do--session-time-budget)
          (saved-total-count pearl-gtd-do--session-total-count)
          (saved-view-type pearl-gtd-do--session-view-type))
      (org-mode)
      ;; Restore all session state after org-mode clears buffer-local vars
      (setq-local pearl-gtd-do--session-actions saved-actions)
      (setq-local pearl-gtd-do--session-context saved-context)
      (setq-local pearl-gtd-do--session-energy saved-energy)
      (setq-local pearl-gtd-do--session-time-budget saved-time-budget)
      (setq-local pearl-gtd-do--session-total-count saved-total-count)
      (setq-local pearl-gtd-do--session-view-type saved-view-type)
      (let* ((actions pearl-gtd-do--session-actions)
             (action (when actions (car actions))))
      (if (null action)
          (progn
            (insert "#+TITLE: Pearl-GTD Do Session\n\n")
            (insert "* Session Complete\n\n")
            (when pearl-gtd-do--session-total-count
              (insert (format "Completed: %d / %d tasks\n\n"
                             (- pearl-gtd-do--session-total-count (length actions))
                             pearl-gtd-do--session-total-count)))
            (insert "No more actions matching current conditions.\n\n")
            (insert "** Current Conditions\n")
            (insert (format "| Context | %s |\n" (or pearl-gtd-do--session-context "All")))
            (insert (format "| Energy  | %s |\n" (or pearl-gtd-do--session-energy "Any")))
            (insert (format "| Time    | %s |\n" (if pearl-gtd-do--session-time-budget
                                                   (format "%d min" pearl-gtd-do--session-time-budget)
                                                 "Unlimited")))
            (org-table-align)
            (insert "\nPress [q] to quit, or [c] to change conditions.\n"))
        (let ((headline (plist-get action :headline))
              (status (plist-get action :status))
              (project (plist-get action :project))
              (context (plist-get action :context))
              (deadline (plist-get action :deadline))
              (scheduled (plist-get action :scheduled))
              (delegated (plist-get action :delegated))
              (created (plist-get action :created))
              (l3 (plist-get action :l3))
              (l4 (plist-get action :l4))
              (l5 (plist-get action :l5))
              (l6 (plist-get action :l6))
              (score (pearl-gtd-do--score-action action pearl-gtd-do--session-context)))
          (insert "#+TITLE: Pearl-GTD Do Session\n\n")
          (insert (format "* %s\n\n" headline))
          (when pearl-gtd-do--session-total-count
            (insert (format "Backlog: %d task%s remaining\n\n"
                           pearl-gtd-do--session-total-count
                           (if (= pearl-gtd-do--session-total-count 1) "" "s"))))
          (insert "** Current Conditions\n")
          (insert (format "| Context | %s |\n" (or pearl-gtd-do--session-context "All")))
          (insert (format "| Energy  | %s |\n" (or pearl-gtd-do--session-energy "Any")))
          (insert (format "| Time    | %s |\n" (if pearl-gtd-do--session-time-budget
                                                 (format "%d min" pearl-gtd-do--session-time-budget)
                                               "Unlimited")))
          (org-table-align)
          (insert "\n** Task Details\n")
          (insert (format "| Score     | %d |\n" (round score)))
          (insert (format "| Status    | %s |\n" (or status "TODO")))
          (when (and project (not (string= project "")))
            (insert (format "| Project   | %s |\n" project)))
          (when (and context (not (string= context "")))
            (insert (format "| Context   | %s |\n" context)))
          (when (and deadline (not (string= deadline "")))
            (insert (format "| Deadline  | %s |\n" (pearl-gtd-do--format-date deadline))))
          (when (and scheduled (not (string= scheduled "")))
            (insert (format "| Scheduled | %s |\n" (pearl-gtd-do--format-date scheduled))))
          (when (and delegated (not (string= delegated "")))
            (insert (format "| Delegated | %s |\n" delegated)))
          (when (and created (not (string= created "")))
            (insert (format "| Created   | %s |\n" created)))
          (when (and l6 (not (string= l6 "")))
            (insert (format "| L6 Purpose | %s |\n" l6)))
          (when (and l5 (not (string= l5 "")))
            (insert (format "| L5 Vision  | %s |\n" l5)))
          (when (and l4 (not (string= l4 "")))
            (insert (format "| L4 Goal    | %s |\n" l4)))
          (when (and l3 (not (string= l3 "")))
            (insert (format "| L3 Area    | %s |\n" l3)))
          (org-table-align)
          (insert "\n** Commands\n\n")
          (insert "| [C]     | Done (mark complete) |\n")
          (insert "| [s]     | Skip (next task)     |\n")
          (insert "| [z]     | Snooze to tomorrow   |\n")
          (insert "| [r]     | Rename               |\n")
          (insert "| [RET]   | Jump to source       |\n")
          (insert "| [c]     | Change conditions    |\n")
          (insert "| [q]     | Quit session         |\n")
          (insert "| [?]     | Help                 |\n")
          (org-table-align))))
      (setq buffer-read-only t)
      (goto-char (point-min)))))

;;;; Session commands

(defun pearl-gtd-do--current-action ()
  "Return current action plist in session, or nil."
  (when pearl-gtd-do--session-actions
    (car pearl-gtd-do--session-actions)))

(defun pearl-gtd-do--remove-current-action ()
  "Remove current action from session list."
  (when pearl-gtd-do--session-actions
    (setq pearl-gtd-do--session-actions (cdr pearl-gtd-do--session-actions))))

(defun pearl-gtd-do--should-delete-on-completion-p (action)
  "Return non-nil if ACTION should be deleted when completed.
Actions whose source entry lacks a PROJECT property should be deleted."
  (let* ((id (plist-get action :id))
         (file (plist-get action :file))
         (project (pearl-gtd-core-with-entry-at-id id file
                     (org-entry-get nil "PROJECT"))))
    (or (null project) (string= project ""))))

(defun pearl-gtd-do--delete-entry (action)
  "Delete entry for ACTION from its file."
  (let ((id (plist-get action :id))
        (file (plist-get action :file)))
    (pearl-gtd-core-with-entry-at-id id file
      (org-cut-subtree)
      (save-buffer))))

(defun pearl-gtd-do--complete-current ()
  "Mark current action as done. Delete if it has no PROJECT property."
  (let ((action (pearl-gtd-do--current-action)))
    (when action
      (if (pearl-gtd-do--should-delete-on-completion-p action)
          (progn
            (pearl-gtd-do--delete-entry action)
            (when (numberp pearl-gtd-do--session-total-count)
              (setq pearl-gtd-do--session-total-count (1- pearl-gtd-do--session-total-count)))
            (pearl-gtd-do--remove-current-action)
            (message "Task deleted (no project)"))
        (let ((id (plist-get action :id))
              (file (plist-get action :file)))
          (when (numberp pearl-gtd-do--session-total-count)
            (setq pearl-gtd-do--session-total-count (1- pearl-gtd-do--session-total-count)))
          (pearl-gtd-core-with-entry-at-id id file
            (let ((org-log-done 'time)) (org-todo 'done)))
          (pearl-gtd-do--remove-current-action)
          (message "Task completed"))))))

(defun pearl-gtd-do--snooze-current ()
  "Reschedule current action to tomorrow."
  (let ((action (pearl-gtd-do--current-action)))
    (when action
      (let ((id (plist-get action :id))
            (file (plist-get action :file))
            (tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600)))))
        (pearl-gtd-core-with-entry-at-id id file
          (org-schedule nil tomorrow))
        (pearl-gtd-do--remove-current-action)
        (message "Task snoozed to %s" tomorrow)))))

(defun pearl-gtd-do--rename-current ()
  "Rename current action."
  (let ((action (pearl-gtd-do--current-action)))
    (when action
      (let* ((id (plist-get action :id))
             (file (plist-get action :file))
             (new-name (read-string "New task name: " (plist-get action :headline))))
        (when (and new-name (not (string= new-name "")))
          (pearl-gtd-core-with-entry-at-id id file
            (org-edit-headline new-name))
          (plist-put action :headline new-name)
          (message "Task renamed"))))))

(defun pearl-gtd-do--jump-to-current ()
  "Jump to source of current action."
  (let ((action (pearl-gtd-do--current-action)))
    (when action
      (let* ((id (plist-get action :id))
             (file (plist-get action :file))
             (buffer (find-file-noselect (expand-file-name file pearl-gtd-init-base-directory))))
        (pop-to-buffer buffer)
        (goto-char (point-min))
        (if (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
            (org-back-to-heading)
          (message "Task not found in source file"))))))

(defun pearl-gtd-do--skip-current ()
  "Skip current action without marking done."
  (pearl-gtd-do--remove-current-action)
  (message "Task skipped"))

(defun pearl-gtd-do--prompt-conditions ()
  "Prompt user for context, time budget, and energy level.
Returns a list (context time-budget energy)."
  (let* ((contexts (pearl-gtd-do--collect-contexts))
         (context-choice (completing-read "Context (RET=all): " contexts nil nil))
         (context (if (string= context-choice "") nil (pearl-gtd-do--normalize-context context-choice)))
         (time-options '("15" "30" "60" "120" "240"))
         (time-choice (completing-read "Available time in minutes (RET=unlimited): " time-options nil nil))
         (time-budget (if (string= time-choice "") nil (string-to-number time-choice)))
         (energy-choice (completing-read "Energy level (RET=any): " pearl-gtd-do--energy-levels nil nil))
         (energy (if (string= energy-choice "") nil energy-choice)))
    (list context time-budget energy)))

(defun pearl-gtd-do--refresh-session (context time-budget energy)
  "Rebuild session actions with given filters.
CONTEXT is the context filter string, or nil for all contexts.
TIME-BUDGET is available time in minutes, or nil for unlimited.
ENERGY is the energy level string, or nil for any."
  (let* ((view-type pearl-gtd-do--session-view-type)
         (predicates (pcase view-type
                       ('delegated (list #'pearl-gtd-core-entry-todo-p
                                         #'pearl-gtd-core-entry-delegated-p))
                       ('today (list #'pearl-gtd-core-entry-todo-p
                                     #'pearl-gtd-core-entry-scheduled-today-p))
                       (_ (list #'pearl-gtd-core-entry-todo-p))))
         (actions (pearl-gtd-do--collect-actions predicates))
         (filtered (pearl-gtd-do--filter-actions actions context))
         (sorted (pearl-gtd-do--sort-actions filtered context)))
    (setq pearl-gtd-do--session-actions sorted
          pearl-gtd-do--session-context context
          pearl-gtd-do--session-total-count (length sorted)
          pearl-gtd-do--session-energy energy
          pearl-gtd-do--session-time-budget time-budget)
    (pearl-gtd-do--render-card (current-buffer))))

;;;; Session startup

(defun pearl-gtd-do--collect-contexts ()
  "Collect all unique context tags from action.org."
  (pearl-gtd-core-collect-contexts
   (expand-file-name "action.org" pearl-gtd-init-base-directory)))

(defun pearl-gtd-do--start-session (&optional view-type context time-budget energy)
  "Start a Do session.
VIEW-TYPE is `next, `delegated, or `today.
CONTEXT, TIME-BUDGET, and ENERGY are optional initial filters."
  (let* ((view-type (or view-type 'next))
         (buffer-name (pearl-gtd-do--session-buffer-name view-type))
         (predicates (pcase view-type
                       ('delegated (list #'pearl-gtd-core-entry-todo-p
                                         #'pearl-gtd-core-entry-delegated-p))
                       ('today (list #'pearl-gtd-core-entry-todo-p
                                     #'pearl-gtd-core-entry-scheduled-today-p))
                       (_ (list #'pearl-gtd-core-entry-todo-p))))
         (actions (pearl-gtd-do--collect-actions predicates))
         (filtered (pearl-gtd-do--filter-actions actions context))
         (sorted (pearl-gtd-do--sort-actions filtered context))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (setq pearl-gtd-do--session-actions sorted
            pearl-gtd-do--session-context context
            pearl-gtd-do--session-total-count (length sorted)
            pearl-gtd-do--session-energy energy
            pearl-gtd-do--session-time-budget time-budget
            pearl-gtd-do--session-view-type view-type)
      (pearl-gtd-do--render-card buffer)
      (pearl-gtd-do-session-mode 1))
    (pop-to-buffer buffer)))

;;;; Minor mode

(defvar pearl-gtd-do-session-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C") #'pearl-gtd-do--session-done)
    (define-key map (kbd "s") #'pearl-gtd-do--session-skip)
    (define-key map (kbd "z") #'pearl-gtd-do--session-snooze)
    (define-key map (kbd "r") #'pearl-gtd-do--session-rename)
    (define-key map (kbd "RET") #'pearl-gtd-do--session-jump)
    (define-key map (kbd "c") #'pearl-gtd-do--session-change-conditions)
    (define-key map (kbd "q") #'pearl-gtd-do--session-quit)
    (define-key map (kbd "?") #'pearl-gtd-do--session-help)
    map)
  "Keymap for Do session mode.")

(define-minor-mode pearl-gtd-do-session-mode
  "Minor mode for Pearl-GTD Do card session."
  :init-value nil
  :lighter " Pearl-Do"
  :keymap pearl-gtd-do-session-mode-map
  :interactive nil)

(defun pearl-gtd-do--session-done ()
  "Mark current card as done and advance. Delete if no project."
  (interactive)
  (pearl-gtd-do--complete-current)
  (if pearl-gtd-do--session-actions
      (pearl-gtd-do--render-card (current-buffer))
    (let ((choice (read-char-choice "Continue with same conditions? (y/n): " '(?y ?n))))
      (if (eq choice ?y)
          (pearl-gtd-do--refresh-session pearl-gtd-do--session-context
                                         pearl-gtd-do--session-time-budget
                                         pearl-gtd-do--session-energy)
        (pearl-gtd-do--session-change-conditions)))))

(defun pearl-gtd-do--session-skip ()
  "Skip current card without marking done."
  (interactive)
  (pearl-gtd-do--skip-current)
  (if pearl-gtd-do--session-actions
      (pearl-gtd-do--render-card (current-buffer))
    (let ((choice (read-char-choice "Continue with same conditions? (y/n): " '(?y ?n))))
      (if (eq choice ?y)
          (pearl-gtd-do--refresh-session pearl-gtd-do--session-context
                                         pearl-gtd-do--session-time-budget
                                         pearl-gtd-do--session-energy)
        (pearl-gtd-do--session-change-conditions)))))

(defun pearl-gtd-do--session-snooze ()
  "Snooze current card to tomorrow."
  (interactive)
  (pearl-gtd-do--snooze-current)
  (if pearl-gtd-do--session-actions
      (pearl-gtd-do--render-card (current-buffer))
    (let ((choice (read-char-choice "Continue with same conditions? (y/n): " '(?y ?n))))
      (if (eq choice ?y)
          (pearl-gtd-do--refresh-session pearl-gtd-do--session-context
                                         pearl-gtd-do--session-time-budget
                                         pearl-gtd-do--session-energy)
        (pearl-gtd-do--session-change-conditions)))))

(defun pearl-gtd-do--session-rename ()
  "Rename current card."
  (interactive)
  (pearl-gtd-do--rename-current)
  (pearl-gtd-do--render-card (current-buffer)))

(defun pearl-gtd-do--session-jump ()
  "Jump to source of current card."
  (interactive)
  (pearl-gtd-do--jump-to-current))

(defun pearl-gtd-do--session-change-conditions ()
  "Change context, time budget, and energy filters."
  (interactive)
  (let ((conditions (pearl-gtd-do--prompt-conditions)))
    (apply #'pearl-gtd-do--refresh-session conditions)))

(defun pearl-gtd-do--session-quit ()
  "Quit Do session."
  (interactive)
  (quit-window))

(defun pearl-gtd-do--session-help ()
  "Show help for Do session."
  (interactive)
  (message "Do | C: done | s: skip | z: snooze | r: rename | RET: jump | c: change | q: quit"))

;;;; Public entry points
;; The single entry point pearl-gtd-do is defined in pearl-gtd.el

(provide 'pearl-gtd-do)

;;; pearl-gtd-do.el ends here
