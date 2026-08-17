;;; full-gtd-do.el --- Do/Work phase for full-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the "Do" phase of GTD via a single-card,
;; session-based workflow.  It provides smart prioritization,
;; constraint awareness (context and energy), and GTD-aligned
;; state transitions.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'full-gtd-init)
(require 'full-gtd-core)

;;;; Session state

(defvar-local full-gtd-do--session-actions nil
  "List of action plists for the current Do session.")

(defvar-local full-gtd-do--session-context nil
  "Current context filter for the session, or nil for all contexts.")

(defvar-local full-gtd-do--session-energy nil
  "Current energy level for the session, or nil for no filter.")

(defvar-local full-gtd-do--session-time-budget nil
  "Current time budget in minutes for the session, or nil for no filter.")

(defvar-local full-gtd-do--session-total-count nil
  "Total number of matching actions at session start.
Decrements when actions are completed, unchanged when skipped.")

(defvar-local full-gtd-do--session-view-type nil
  "Type of the current session: `next, `delegated, or `today.")

(defvar full-gtd-do--energy-levels '("high" "normal" "low")
  "Supported energy levels.")

;;;; Scoring

(defconst full-gtd-do--score-weights
  '((overdue . 100)
    (deadline-1d . 50)
    (deadline-3d . 30)
    (deadline-7d . 15)
    (scheduled-today . 20)
    (l6-purpose . 20)
    (l5-vision . 15)
    (l4-goal . 10)
    (l3-area . 5)
    (project . 5)
    (context-match . 10))
  "Weights for action priority scoring.")

(defun full-gtd-do--days-until (date-string)
  "Return number of days until DATE-STRING, or nil if not a date.
DATE-STRING should be an Org date or timestamp."
  (when date-string
    (let ((time (ignore-errors (org-time-string-to-time date-string))))
      (when time
        (/ (- (float-time time) (float-time (current-time))) 86400.0)))))

(defun full-gtd-do--score-action (action &optional context-filter)
  "Calculate priority score for ACTION plist.
Optional CONTEXT-FILTER boosts matching contexts."
  (let ((score 0)
        (deadline (plist-get action :deadline))
        (scheduled (plist-get action :scheduled))
        (context (plist-get action :context))
        (project (plist-get action :project))
        (l3 (plist-get action :l3))
        (l4 (plist-get action :l4))
        (l5 (plist-get action :l5))
        (l6 (plist-get action :l6))
        (delegated (plist-get action :delegated)))
    ;; Urgency: deadline
    (when deadline
      (let ((days (full-gtd-do--days-until deadline)))
        (cond
         ((null days) nil)
         ((< days 0) (setq score (+ score (cdr (assq 'overdue full-gtd-do--score-weights)))))
         ((<= days 1) (setq score (+ score (cdr (assq 'deadline-1d full-gtd-do--score-weights)))))
         ((<= days 3) (setq score (+ score (cdr (assq 'deadline-3d full-gtd-do--score-weights)))))
         ((<= days 7) (setq score (+ score (cdr (assq 'deadline-7d full-gtd-do--score-weights))))))))
    ;; Urgency: scheduled today
    (when (and scheduled
               (string-match-p (format-time-string "<%F" (current-time)) scheduled))
      (setq score (+ score (cdr (assq 'scheduled-today full-gtd-do--score-weights)))))
    ;; Importance: horizons
    (when (and l6 (not (string= l6 "")))
      (setq score (+ score (cdr (assq 'l6-purpose full-gtd-do--score-weights)))))
    (when (and l5 (not (string= l5 "")))
      (setq score (+ score (cdr (assq 'l5-vision full-gtd-do--score-weights)))))
    (when (and l4 (not (string= l4 "")))
      (setq score (+ score (cdr (assq 'l4-goal full-gtd-do--score-weights)))))
    (when (and l3 (not (string= l3 "")))
      (setq score (+ score (cdr (assq 'l3-area full-gtd-do--score-weights)))))
    ;; Project presence
    (when (and project (not (string= project "")))
      (setq score (+ score (cdr (assq 'project full-gtd-do--score-weights)))))
    ;; Context match
    (when (and context-filter context)
      (let ((ctxs (full-gtd-do--split-contexts context)))
        (when (member context-filter ctxs)
          (setq score (+ score (cdr (assq 'context-match full-gtd-do--score-weights)))))))
    ;; Penalties
    ;; Delegated tasks: -100 points
    (when (and delegated (not (string= delegated "")))
      (setq score (- score 100)))
    ;; Future scheduled tasks: -50 points
    (when scheduled
      (let ((days (full-gtd-do--days-until scheduled)))
        (when (and days (> days 0))
          (setq score (- score 50)))))
    score))

;;;; Action collection

(defun full-gtd-do--normalize-context (context)
  "Normalize CONTEXT string by removing @ prefix."
  (if (string-prefix-p "@" context)
      (substring context 1)
    context))

(defun full-gtd-do--split-contexts (context-string)
  "Split CONTEXT-STRING by comma and normalize each value.
CONTEXT-STRING uses @ prefixes like \"@office,@home\"."
  (when context-string
    (mapcar #'full-gtd-do--normalize-context
            (seq-filter (lambda (s) (not (string-empty-p s)))
                        (mapcar #'string-trim (split-string context-string ","))))))

(defun full-gtd-do--collect-actions (predicates)
  "Collect TODO actions from action.org matching PREDICATES.
Returns list of action plists."
  (let* ((file-path (expand-file-name "action.org" full-gtd-init-base-directory))
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

(defun full-gtd-do--context-matches-p (action context-filter)
  "Return non-nil if ACTION context matches CONTEXT-FILTER.
CONTEXT-FILTER is a normalized context string (without @)."
  (if (null context-filter)
      t
    (let ((contexts (full-gtd-do--split-contexts (plist-get action :context))))
      (member context-filter contexts))))

(defun full-gtd-do--filter-actions (actions &optional context)
  "Filter ACTIONS by CONTEXT constraint."
  (seq-filter
   (lambda (action)
     (full-gtd-do--context-matches-p action context))
   actions))

(defun full-gtd-do--sort-actions (actions context-filter)
  "Sort ACTIONS by priority score, highest first.
CONTEXT-FILTER is used for context-match bonus.
When scores are equal, earlier CREATED timestamps sort first."
  (sort (copy-sequence actions)
        (lambda (a b)
          (let ((score-a (full-gtd-do--score-action a context-filter))
                (score-b (full-gtd-do--score-action b context-filter)))
            (if (= score-a score-b)
                (let ((created-a (plist-get a :created))
                      (created-b (plist-get b :created)))
                  (cond
                   ((and created-a created-b)
                    (string< created-a created-b))
                   (created-a
                    t)
                   (created-b
                    nil)
                   (t nil)))
              (> score-a score-b))))))

;;;; Session UI

(defun full-gtd-do--session-buffer-name (view-type)
  "Return buffer name for VIEW-TYPE session."
  (pcase view-type
    ('delegated "*Full-GTD: Delegated Session*")
    ('today "*Full-GTD: Today Session*")
    (_ "*Full-GTD: Do Session*")))

(defun full-gtd-do--format-date (date-string)
  "Format Org DATE-STRING for display, including relative days."
  (when date-string
    (let ((days (full-gtd-do--days-until date-string)))
      (cond
       ((null days) date-string)
       ((< days 0) (format "%s (overdue %.0f days)" date-string (abs days)))
       ((= days 0) (format "%s (today)" date-string))
       ((<= days 7) (format "%s (in %.0f days)" date-string days))
       (t date-string)))))

(defun full-gtd-do--render-card (buffer)
  "Render current action card in BUFFER."
  (with-current-buffer buffer
    (setq buffer-read-only nil)
    (erase-buffer)
    ;; Save all session state before org-mode clears buffer-local vars
    (let ((saved-actions full-gtd-do--session-actions)
          (saved-context full-gtd-do--session-context)
          (saved-energy full-gtd-do--session-energy)
          (saved-time-budget full-gtd-do--session-time-budget)
          (saved-total-count full-gtd-do--session-total-count)
          (saved-view-type full-gtd-do--session-view-type))
      (org-mode)
      ;; Restore all session state after org-mode clears buffer-local vars
      (setq-local full-gtd-do--session-actions saved-actions)
      (setq-local full-gtd-do--session-context saved-context)
      (setq-local full-gtd-do--session-energy saved-energy)
      (setq-local full-gtd-do--session-time-budget saved-time-budget)
      (setq-local full-gtd-do--session-total-count saved-total-count)
      (setq-local full-gtd-do--session-view-type saved-view-type)
      ;; org-mode resets buffer-local variables; re-enable session minor mode.
      (full-gtd-do-session-mode 1)
      (let* ((actions full-gtd-do--session-actions)
             (action (when actions (car actions))))
      (if (null action)
          (progn
            (insert "#+TITLE: Full-GTD Do Session\n\n")
            (insert "* Session Complete\n\n")
            (when full-gtd-do--session-total-count
              (insert (format "Completed: %d / %d tasks\n\n"
                             (- full-gtd-do--session-total-count (length actions))
                             full-gtd-do--session-total-count)))
            (insert "No more actions matching current conditions.\n\n")
            (insert "** Current Conditions\n")
            (insert (format "| Context | %s |\n" (or full-gtd-do--session-context "All")))
            (insert (format "| Energy  | %s |\n" (or full-gtd-do--session-energy "Any")))
            (insert (format "| Time    | %s |\n" (if full-gtd-do--session-time-budget
                                                   (format "%d min" full-gtd-do--session-time-budget)
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
              (score (full-gtd-do--score-action action full-gtd-do--session-context)))
          (insert "#+TITLE: Full-GTD Do Session\n\n")
          (insert (format "* %s\n\n" headline))
          (when full-gtd-do--session-total-count
            (insert (format "Backlog: %d task%s remaining\n\n"
                           full-gtd-do--session-total-count
                           (if (= full-gtd-do--session-total-count 1) "" "s"))))
          (insert "** Current Conditions\n")
          (insert (format "| Context | %s |\n" (or full-gtd-do--session-context "All")))
          (insert (format "| Energy  | %s |\n" (or full-gtd-do--session-energy "Any")))
          (insert (format "| Time    | %s |\n" (if full-gtd-do--session-time-budget
                                                 (format "%d min" full-gtd-do--session-time-budget)
                                               "Unlimited")))
          (org-table-align)
          (insert "\n** Task Details\n")
          (insert (format "| Score     | %d |\n" (round score)))
          (insert (format "| Status    | %s |\n" (or status (full-gtd-core--default-todo-keyword))))
          (when (and project (not (string= project "")))
            (insert (format "| Project   | %s |\n" project)))
          (when (and context (not (string= context "")))
            (insert (format "| Context   | %s |\n" context)))
          (when (and deadline (not (string= deadline "")))
            (insert (format "| Deadline  | %s |\n" (full-gtd-do--format-date deadline))))
          (when (and scheduled (not (string= scheduled "")))
            (insert (format "| Scheduled | %s |\n" (full-gtd-do--format-date scheduled))))
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
          ;; Insert Notes section if the action has notes (body)
          (let ((notes (full-gtd-core-with-entry-at-id (plist-get action :id) (plist-get action :file)
                          (full-gtd-core--get-entry-notes))))
            (when notes
              (insert "\n** Notes\n")
              (insert (replace-regexp-in-string "^" "  " notes))
              (insert "\n")))
          (insert "\n** Commands\n\n")
          (insert "| [C]     | Done (mark complete) |\n")
          (insert "| [s]     | Skip (next task)     |\n")
          (insert "| [z]     | Snooze to tomorrow   |\n")
          (insert "| [r]     | Rename               |\n")
          (insert "| [e]     | Edit notes           |\n")
          (insert "| [RET]   | Jump to source       |\n")
          (insert "| [c]     | Change conditions    |\n")
          (insert "| [q]     | Quit session         |\n")
          (insert "| [?]     | Help                 |\n")
          (org-table-align))))
      (setq buffer-read-only t)
      (goto-char (point-min)))))

;;;; Session commands

(defun full-gtd-do--current-action ()
  "Return current action plist in session, or nil."
  (when full-gtd-do--session-actions
    (car full-gtd-do--session-actions)))

(defun full-gtd-do--remove-current-action ()
  "Remove current action from session list."
  (when full-gtd-do--session-actions
    (setq full-gtd-do--session-actions (cdr full-gtd-do--session-actions))))

(defun full-gtd-do--should-delete-on-completion-p (action)
  "Return non-nil if ACTION should be deleted when completed.
Actions whose source entry lacks a PROJECT property should be deleted."
  (let* ((id (plist-get action :id))
         (file (plist-get action :file))
         (project (full-gtd-core-with-entry-at-id id file
                     (org-entry-get nil "PROJECT"))))
    (or (null project) (string= project ""))))

(defun full-gtd-do--delete-entry (action)
  "Delete entry for ACTION from its file."
  (let ((id (plist-get action :id))
        (file (plist-get action :file)))
    (full-gtd-core-with-entry-at-id id file
      (org-cut-subtree)
      (save-buffer))))

(defun full-gtd-do--complete-current ()
  "Mark current action as done.  Delete if it has no PROJECT property."
  (let ((action (full-gtd-do--current-action)))
    (when action
      (if (full-gtd-do--should-delete-on-completion-p action)
          (progn
            (full-gtd-do--delete-entry action)
            (when (numberp full-gtd-do--session-total-count)
              (setq full-gtd-do--session-total-count (1- full-gtd-do--session-total-count)))
            (full-gtd-do--remove-current-action)
            (message "Task deleted (no project)"))
        (let ((id (plist-get action :id))
              (file (plist-get action :file)))
          (when (numberp full-gtd-do--session-total-count)
            (setq full-gtd-do--session-total-count (1- full-gtd-do--session-total-count)))
          (full-gtd-core-with-entry-at-id id file
            (let ((org-log-done 'time)) (org-todo 'done)))
          (full-gtd-do--remove-current-action)
          (message "Task completed"))))))

(defun full-gtd-do--snooze-current ()
  "Reschedule current action to tomorrow."
  (let ((action (full-gtd-do--current-action)))
    (when action
      (let ((id (plist-get action :id))
            (file (plist-get action :file))
            (tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600)))))
        (full-gtd-core-with-entry-at-id id file
          (org-schedule nil tomorrow))
        (full-gtd-do--remove-current-action)
        (message "Task snoozed to %s" tomorrow)))))

(defun full-gtd-do--rename-current ()
  "Rename current action."
  (let ((action (full-gtd-do--current-action)))
    (when action
      (let* ((id (plist-get action :id))
             (file (plist-get action :file))
             (new-name (read-string "New task name: " (plist-get action :headline))))
        (when (and new-name (not (string= new-name "")))
          (full-gtd-core-with-entry-at-id id file
            (org-edit-headline new-name))
          (plist-put action :headline new-name)
          (message "Task renamed"))))))

(defun full-gtd-do--jump-to-current ()
  "Jump to source of current action."
  (let ((action (full-gtd-do--current-action)))
    (when action
      (let* ((id (plist-get action :id))
             (file (plist-get action :file))
             (buffer (find-file-noselect (expand-file-name file full-gtd-init-base-directory))))
        (pop-to-buffer buffer)
        (goto-char (point-min))
        (if (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
            (org-back-to-heading)
          (message "Task not found in source file"))))))

(defun full-gtd-do--skip-current ()
  "Skip current action without marking done."
  (full-gtd-do--remove-current-action)
  (message "Task skipped"))

(defun full-gtd-do--prompt-conditions ()
  "Prompt user for context, time budget, and energy level.
Returns a list (context time-budget energy)."
  (let* ((contexts (full-gtd-do--collect-contexts))
         (context-choice (completing-read "Context (RET=all): " contexts nil nil))
         (context (if (string= context-choice "") nil (full-gtd-do--normalize-context context-choice)))
         (time-options '("15" "30" "60" "120" "240"))
         (time-choice (completing-read "Available time in minutes (RET=unlimited): " time-options nil nil))
         (time-budget (if (string= time-choice "") nil (string-to-number time-choice)))
         (energy-choice (completing-read "Energy level (RET=any): " full-gtd-do--energy-levels nil nil))
         (energy (if (string= energy-choice "") nil energy-choice)))
    (list context time-budget energy)))

(defun full-gtd-do--refresh-session (context time-budget energy)
  "Rebuild session actions with given filters.
CONTEXT is the context filter string, or nil for all contexts.
TIME-BUDGET is available time in minutes, or nil for unlimited.
ENERGY is the energy level string, or nil for any."
  (let* ((view-type full-gtd-do--session-view-type)
         (predicates (pcase view-type
                       ('delegated (list #'full-gtd-core-entry-todo-p
                                         #'full-gtd-core-entry-delegated-p))
                       ('today (list #'full-gtd-core-entry-todo-p
                                     #'full-gtd-core-entry-scheduled-today-p))
                       (_ (list #'full-gtd-core-entry-todo-p))))
         (actions (full-gtd-do--collect-actions predicates))
         (filtered (full-gtd-do--filter-actions actions context))
         (sorted (full-gtd-do--sort-actions filtered context)))
    (setq full-gtd-do--session-actions sorted
          full-gtd-do--session-context context
          full-gtd-do--session-total-count (length sorted)
          full-gtd-do--session-energy energy
          full-gtd-do--session-time-budget time-budget)
    (full-gtd-do--render-card (current-buffer))))

;;;; Session startup

(defun full-gtd-do--collect-contexts ()
  "Collect all unique context tags from action.org."
  (full-gtd-core-collect-contexts
   (expand-file-name "action.org" full-gtd-init-base-directory)))

(defun full-gtd-do--start-session (&optional view-type context time-budget energy)
  "Start a Do session.
VIEW-TYPE is `next, `delegated, or `today.
CONTEXT, TIME-BUDGET, and ENERGY are optional initial filters."
  (let* ((view-type (or view-type 'next))
         (buffer-name (full-gtd-do--session-buffer-name view-type))
         (predicates (pcase view-type
                       ('delegated (list #'full-gtd-core-entry-todo-p
                                         #'full-gtd-core-entry-delegated-p))
                       ('today (list #'full-gtd-core-entry-todo-p
                                     #'full-gtd-core-entry-scheduled-today-p))
                       (_ (list #'full-gtd-core-entry-todo-p))))
         (actions (full-gtd-do--collect-actions predicates))
         (filtered (full-gtd-do--filter-actions actions context))
         (sorted (full-gtd-do--sort-actions filtered context))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (setq full-gtd-do--session-actions sorted
            full-gtd-do--session-context context
            full-gtd-do--session-total-count (length sorted)
            full-gtd-do--session-energy energy
            full-gtd-do--session-time-budget time-budget
            full-gtd-do--session-view-type view-type)
      (full-gtd-do--render-card buffer)
      (full-gtd-do-session-mode 1))
    (pop-to-buffer buffer)))

;;;; Minor mode

(defvar full-gtd-do-session-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C") #'full-gtd-do--session-done)
    (define-key map (kbd "s") #'full-gtd-do--session-skip)
    (define-key map (kbd "z") #'full-gtd-do--session-snooze)
    (define-key map (kbd "r") #'full-gtd-do--session-rename)
    (define-key map (kbd "e") #'full-gtd-do--edit-notes)
    (define-key map (kbd "RET") #'full-gtd-do--session-jump)
    (define-key map (kbd "c") #'full-gtd-do--session-change-conditions)
    (define-key map (kbd "q") #'full-gtd-do--session-quit)
    (define-key map (kbd "?") #'full-gtd-do--session-help)
    map)
  "Keymap for Do session mode.")

(define-minor-mode full-gtd-do-session-mode
  "Minor mode for Full-GTD Do card session."
  :init-value nil
  :lighter " Full-Do"
  :keymap full-gtd-do-session-mode-map
  :interactive nil)

(defun full-gtd-do--edit-notes ()
  "Edit notes (body) for current action."
  (interactive)
  (let ((action (full-gtd-do--current-action)))
    (when action
      (let ((id (plist-get action :id))
            (file (plist-get action :file)))
        (full-gtd-core-with-entry-at-id id file
          (full-gtd-core--edit-entry-notes)))
      (full-gtd-do--render-card (current-buffer)))))

(defun full-gtd-do--session-done ()
  "Mark current card as done and advance.  Delete if no project."
  (interactive)
  (full-gtd-do--complete-current)
  (if full-gtd-do--session-actions
      (full-gtd-do--render-card (current-buffer))
    (let ((choice (read-char-choice "Continue with same conditions? (y/n): " '(?y ?n))))
      (if (eq choice ?y)
          (full-gtd-do--refresh-session full-gtd-do--session-context
                                         full-gtd-do--session-time-budget
                                         full-gtd-do--session-energy)
        (full-gtd-do--session-change-conditions)))))

(defun full-gtd-do--session-skip ()
  "Skip current card without marking done."
  (interactive)
  (full-gtd-do--skip-current)
  (if full-gtd-do--session-actions
      (full-gtd-do--render-card (current-buffer))
    (let ((choice (read-char-choice "Continue with same conditions? (y/n): " '(?y ?n))))
      (if (eq choice ?y)
          (full-gtd-do--refresh-session full-gtd-do--session-context
                                         full-gtd-do--session-time-budget
                                         full-gtd-do--session-energy)
        (full-gtd-do--session-change-conditions)))))

(defun full-gtd-do--session-snooze ()
  "Snooze current card to tomorrow."
  (interactive)
  (full-gtd-do--snooze-current)
  (if full-gtd-do--session-actions
      (full-gtd-do--render-card (current-buffer))
    (let ((choice (read-char-choice "Continue with same conditions? (y/n): " '(?y ?n))))
      (if (eq choice ?y)
          (full-gtd-do--refresh-session full-gtd-do--session-context
                                         full-gtd-do--session-time-budget
                                         full-gtd-do--session-energy)
        (full-gtd-do--session-change-conditions)))))

(defun full-gtd-do--session-rename ()
  "Rename current card."
  (interactive)
  (full-gtd-do--rename-current)
  (full-gtd-do--render-card (current-buffer)))

(defun full-gtd-do--session-jump ()
  "Jump to source of current card."
  (interactive)
  (full-gtd-do--jump-to-current))

(defun full-gtd-do--session-change-conditions ()
  "Change context, time budget, and energy filters."
  (interactive)
  (let ((conditions (full-gtd-do--prompt-conditions)))
    (apply #'full-gtd-do--refresh-session conditions)))

(defun full-gtd-do--session-quit ()
  "Quit Do session."
  (interactive)
  (quit-window))

(defun full-gtd-do--session-help ()
  "Show help for Do session."
  (interactive)
  (message "Do | C: done | s: skip | z: snooze | r: rename | RET: jump | c: change | q: quit"))

;;;; Public entry points
;; The single entry point full-gtd-do is defined in full-gtd.el

(provide 'full-gtd-do)

;;; full-gtd-do.el ends here
