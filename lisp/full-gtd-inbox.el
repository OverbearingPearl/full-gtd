;;; full-gtd-inbox.el --- Inbox handling for full-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles inbox-related functions for full-gtd,
;; including capture and processing with user interaction via staging,
;; fully aligned with GTD workflow.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'full-gtd-core)
(require 'full-gtd-horizons)

(defface full-gtd-inbox--highlight
  '((t :inherit highlight))
  "Face for highlighting the current entry."
  :group 'full-gtd)

(defface full-gtd-inbox--deleted
  '((t :inherit shadow :strike-through t))
  "Face for deleted (trash) entries."
  :group 'full-gtd)

(defface full-gtd-inbox--executed
  '((t :inherit success :strike-through t))
  "Face for executed (2-minute rule) entries."
  :group 'full-gtd)

(defvar full-gtd-inbox--staging-original-file nil
  "The original Org file path for the staging buffer.")

(defvar full-gtd-inbox--staging-changes nil
  "A list to store staged changes, e.g., ((row col new-value) ...).")

(defvar full-gtd-inbox--last-context nil
  "Last context used during current inbox processing session.")

(defun full-gtd-inbox--read-destination-key (headline)
  "Read single key for destination choice for HEADLINE.
Returns one of: ?a (Next Action), ?r (Reference), ?s (Someday), ?t (Trash),
?x (Execute <2min), ?c (Clarify).
Signals \\='quit if user presses \\`C-g\\'.
If a multi-key command is typed \(e.g., \\[other-window]\ or
\\[delete-other-windows]\), it is executed immediately and processing
continues afterwards."
  (message "Process '%s': [a] Next Action | [r] Reference | [s] Someday | [t] Trash | [x] Execute (<2min) | [c] Clarify: "
           (substring headline 0 (min 30 (length headline))))
  (redisplay t)
  (let ((seq (read-key-sequence nil)))
    (cond
     ((and (= (length seq) 1)
           (memq (aref seq 0) '(?a ?A ?r ?R ?s ?S ?t ?T ?x ?X ?c ?C)))
      (downcase (aref seq 0)))
     ((and (= (length seq) 1)
           (eq (aref seq 0) 7))  ; C-g
      (signal 'quit nil))
     ((= (length seq) 1)
      (message "Invalid key. Process '%s': [a] Next Action | [r] Reference | [s] Someday | [t] Trash | [x] Execute (<2min) | [c] Clarify: "
               (substring headline 0 (min 30 (length headline))))
      (sit-for 0.5)
      (full-gtd-inbox--read-destination-key headline))
     (t
      ;; Multi-key command (e.g., C-x o): execute it immediately and
      ;; continue processing afterwards.
      (condition-case err
          (progn
            (execute-kbd-macro seq)
            (full-gtd-inbox--read-destination-key headline))
        (quit (signal 'quit nil))
        (error
         (message "Invalid key: %S" err)
         (sit-for 0.5)
         (full-gtd-inbox--read-destination-key headline)))))))

(defun full-gtd-inbox--clarify-entry (headline &optional default-notes)
  "Clarify HEADLINE and notes.
DEFAULT-NOTES is the current notes text (or nil).
Returns (NEW-HEADLINE . NEW-NOTES).  NEW-NOTES is nil if cleared."
  (let* ((new (read-string (format "Clarify '%s' [RET keep]: <Clear next action> (e.g., Buy organic milk from Whole Foods, Call John about project): "
                                   headline)))
         (new-headline (let ((trimmed (string-trim new)))
                        (unless (string= trimmed "") trimmed)))
         (notes-text (string-trim
                      (read-string (format "Notes for '%s' [RET keep, empty to clear]: <Details or constraints> (e.g., Check brand: Organic Valley, Ask about deadline): "
                                           (or new-headline headline))
                                   (or default-notes "")))))
    (cons new-headline (unless (string= notes-text "") notes-text))))

(defun full-gtd-inbox--collect-action-attrs (&optional staging-buffer default-context default-project)
  "Collect action attributes with context inheritance.
If STAGING-BUFFER is provided, ensure focus returns to it after each input.
If DEFAULT-CONTEXT is a non-empty string, use it directly.
If DEFAULT-PROJECT is a non-empty string, use it directly.
Returns alist: ((context . VAL) (schedule . VAL) (deadline . VAL)
               (delegate . VAL) (project . VAL))"
  (let* ((ctx (if (and default-context (not (string= default-context "")))
                  default-context
                (progn
                  (when staging-buffer (pop-to-buffer staging-buffer))
                  (full-gtd-inbox--read-context))))
         (sched (progn
                  (when staging-buffer (pop-to-buffer staging-buffer))
                  (full-gtd-core-read-date 'schedule)))
         (dead (progn
                 (when staging-buffer (pop-to-buffer staging-buffer))
                 (full-gtd-core-read-date 'deadline)))
         (deleg (progn
                  (when staging-buffer (pop-to-buffer staging-buffer))
                  (full-gtd-inbox--read-delegate)))
         (proj (if (and default-project (not (string= default-project "")))
                   default-project
                 (progn
                   (when staging-buffer (pop-to-buffer staging-buffer))
                   (full-gtd-inbox--read-project)))))
    `((context . ,ctx) (schedule . ,sched) (deadline . ,dead)
      (delegate . ,deleg) (project . ,proj))))

(defun full-gtd-inbox--read-context ()
  "Read context with completion from existing actions, allowing free input.
Supports spaces in context names.  Examples: @office, @home office, @phone."
  (let* ((default (or full-gtd-inbox--last-context ""))
         (prompt (format "Context [RET %s, TAB complete]: " (if (string= default "") "none" (concat "keep '" default "'"))))
         (input (full-gtd-core-read-property-with-completion prompt 'context default)))
    (unless (string= input "") (setq full-gtd-inbox--last-context input))
    (if (string= input "") "" input)))

(defun full-gtd-inbox--read-project ()
  "Read project with completion from existing projects.
Supports spaces in project names.  Use ; to separate multiple projects.
Examples: Website Redesign, Q1 Marketing; Q2 Planning."
  (full-gtd-core-read-property-with-completion "Project [RET none, TAB complete]: " 'project))

(defun full-gtd-inbox--read-delegate ()
  "Read delegate with completion from existing delegates.
Supports full names with spaces.  Examples: John Smith, Alice Johnson."
  (full-gtd-core-read-property-with-completion "Delegated to [RET none, TAB complete]: " 'delegate))

(defvar-local full-gtd-inbox--current-highlight nil
  "Current highlight overlay in the staging buffer.")

(defvar-local full-gtd-inbox--marked-deleted-rows '()
  "Buffer-local list of row numbers marked as deleted.")

(defvar-local full-gtd-inbox--marked-executed-rows '()
  "Buffer-local list of row numbers marked as executed.")

(defun full-gtd-inbox--create-staging-buffer (file-path &optional buffer-name filter-pred)
  "Create a staging buffer from FILE-PATH.
Optional BUFFER-NAME specifies the buffer name.  Return the created buffer.
Optional FILTER-PRED is a predicate called with no arguments in the
context of each entry; only entries matching the predicate are included."
  (setq full-gtd-inbox--staging-original-file file-path
        full-gtd-inbox--staging-changes nil
        full-gtd-inbox--marked-deleted-rows '()
        full-gtd-inbox--marked-executed-rows '())
  (let ((actual-buffer-name (or buffer-name (generate-new-buffer-name " *full-gtd-inbox-staging*")))
        (headlines '()))
    (with-current-buffer (get-buffer-create actual-buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert-file-contents file-path)
      (org-mode)
      (org-map-entries
       (lambda ()
         (when (or (null filter-pred) (funcall filter-pred))
           (push (list (org-get-heading t t)
                       (org-get-tags)
                       (org-get-todo-state)
                       (org-entry-get nil "CREATED"))
                 headlines))))
      (erase-buffer)
      (insert "| Headline | Notes | Age | Tags |\n")
      (insert "|----------+---------+-----+------|\n")
      (dolist (entry (nreverse headlines))
        (let* ((created-str (nth 3 entry))
               (age-str (if created-str
                            (let* ((created-time (date-to-time created-str))
                                   (diff (time-subtract (current-time) created-time))
                                   (total-seconds (floor (float-time diff)))
                                   (days (/ total-seconds 86400))
                                   (hours (/ (% total-seconds 86400) 3600))
                                   (minutes (/ (% total-seconds 3600) 60)))
                              (format "%dd %dh %dm" days hours minutes))
                          "N/A"))
               (headline (nth 0 entry))
               (escaped-headline (replace-regexp-in-string "|" "\\\\vert{}" headline)))
          (insert (format "| %s | | %s | %s |\n"
                          escaped-headline
                          age-str
                          (mapconcat #'identity (nth 1 entry) ",")))))
      (org-table-align)
      (font-lock-ensure (point-min) (point-max))
      (redisplay t)
      (setq buffer-read-only t)
      (current-buffer))))

(defun full-gtd-inbox--map-entries (buffer func)
  "Map over all entries in BUFFER.
Calls FUNC with headline, entry-ref, and original-tags for each entry."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (forward-line 2)
      (let ((entries '()))
        (while (not (eobp))
          (let ((current-row (line-number-at-pos)))
            (when (looking-at "|")
              (let ((headline (string-trim (org-table-get-field 1)))
                    (tags-field (string-trim (org-table-get-field 4))))
                ;; Unescape pipe characters that were escaped for table display
                (setq headline (replace-regexp-in-string "\\\\vert{}" "|" headline))
                (when (and headline (not (string= headline "")))
                  (push (list headline (cons buffer current-row) tags-field) entries)))))
          (forward-line 1))
        (dolist (entry (nreverse entries))
          (funcall func (nth 0 entry) (nth 1 entry) (nth 2 entry)))))))

(defun full-gtd-inbox--highlight-entry (entry-ref)
  "Highlight ENTRY-REF in staging buffer.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (save-excursion
        (when full-gtd-inbox--current-highlight
          (delete-overlay full-gtd-inbox--current-highlight))
        (goto-char (point-min))
        (forward-line (1- row))
        (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
          (overlay-put ov 'face 'full-gtd-inbox--highlight)
          (overlay-put ov 'evaporate t)
          (setq full-gtd-inbox--current-highlight ov)
          (redisplay t))))))

(defun full-gtd-inbox--mark-deleted-impl (row)
  "Mark ROW as deleted.  Internal implementation for state layer."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- row))
      (org-table-goto-column 1)
      (let* ((start (point))
             (end (progn (skip-chars-forward "^|") (point)))
             (ov (make-overlay start end)))
        (overlay-put ov 'face 'full-gtd-inbox--deleted)
        (overlay-put ov 'evaporate t)))
    (cl-pushnew row full-gtd-inbox--marked-deleted-rows)))

(defun full-gtd-inbox--mark-deleted (entry-ref)
  "Mark ENTRY-REF as deleted.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (full-gtd-inbox--mark-deleted-impl row))))

(defun full-gtd-inbox--mark-executed-impl (row)
  "Mark ROW as executed.  Internal implementation for state layer."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- row))
      (org-table-goto-column 1)
      (let* ((start (point))
             (end (progn (skip-chars-forward "^|") (point)))
             (ov (make-overlay start end)))
        (overlay-put ov 'face 'full-gtd-inbox--executed)
        (overlay-put ov 'evaporate t)))
    (cl-pushnew row full-gtd-inbox--marked-executed-rows)))

(defun full-gtd-inbox--mark-executed (entry-ref)
  "Mark ENTRY-REF as executed.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (full-gtd-inbox--mark-executed-impl row))))

(defun full-gtd-inbox--stage-change-impl (row col new-value)
  "Stage change for ROW at COL with NEW-VALUE.
Internal implementation for state layer."
  (push (list row col new-value) full-gtd-inbox--staging-changes)
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- row))
      (org-table-goto-column col)
      (org-table-blank-field)
      (insert new-value)
      (org-table-align)
      (full-gtd-inbox--reapply-marks (current-buffer)))))

(defun full-gtd-inbox--stage-change (entry-ref col new-value)
  "Stage change for ENTRY-REF at COL with NEW-VALUE.
ENTRY-REF is a cons cell (BUFFER . ROW).
COL is the column number to modify.
NEW-VALUE is the string to insert."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (full-gtd-inbox--stage-change-impl row col new-value))))

(defun full-gtd-inbox--reapply-marks (buffer)
  "Reapply mark to BUFFER after table alignment.
BUFFER is the staging buffer to update."
  (with-current-buffer buffer
    (dolist (row full-gtd-inbox--marked-deleted-rows)
      (condition-case nil
          (progn
            (goto-char (point-min))
            (forward-line (1- row))
            (org-table-goto-column 1)
            (let* ((start (point))
                   (end (progn (skip-chars-forward "^|") (point)))
                   (ov (make-overlay start end)))
              (overlay-put ov 'face 'full-gtd-inbox--deleted)
              (overlay-put ov 'evaporate t)))
        (error nil)))
    (dolist (row full-gtd-inbox--marked-executed-rows)
      (condition-case nil
          (progn
            (goto-char (point-min))
            (forward-line (1- row))
            (org-table-goto-column 1)
            (let* ((start (point))
                   (end (progn (skip-chars-forward "^|") (point)))
                   (ov (make-overlay start end)))
              (overlay-put ov 'face 'full-gtd-inbox--executed)
              (overlay-put ov 'evaporate t)))
        (error nil)))))

(defvar full-gtd-inbox--pending-moves nil
  "List of pending moves after staging.

Each element is a list:
ORIGINAL-HEADLINE, TARGET-FILE, PROPERTIES-STRING,
NEW-HEADLINE, NOTES, and DEADLINE.

If TARGET-FILE is nil, the entry is deleted (trash).
PROPERTIES-STRING contains tags and properties.
NEW-HEADLINE is the clarified headline, or nil if unchanged.
NOTES is the clarified notes text, or nil if none.
DEADLINE is the deadline date string, or nil if not set.")

(defvar full-gtd-inbox-stage-buffer-name nil
  "The name of the current inbox staging buffer.")

(defun full-gtd-inbox--capture ()
  "Capture one or more items to the inbox, each with a timestamp.
Separate multiple items with semicolons (English or Chinese)."
  (let* ((raw-input (read-string "Capture to inbox: <Raw idea or task> (separate with ; or ； for multiple): "))
         (items (full-gtd-core--split-values raw-input)))
    (dolist (item items)
      (setq item (replace-regexp-in-string "[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f]" "" item))
      (setq item (replace-regexp-in-string "\n" " " item))
      (with-current-buffer (find-file-noselect (expand-file-name "inbox.org" full-gtd-init-base-directory))
        (goto-char (point-max))
        (insert (format "* %s\n:PROPERTIES:\n:CREATED: %s\n:END:\n" (string-trim item) (format-time-string "%F %T")))
        (forward-line -2)
        (org-id-get-create)
        (save-buffer)))))

;;;; State Machine Layer

(defun full-gtd-inbox--fields-to-props (fields)
  "Convert FIELDS alist to properties string for org entry."
  (let ((parts '()))
    (dolist (f fields)
      (pcase f
        (`(context . ,ctx)
         (when ctx (push (string-trim ctx) parts)))
        (`(schedule . ,sched)
         (when sched (push (format ":SCHEDULED:%s:" (string-trim sched)) parts)))
        (`(deadline . ,dead)
         (when dead (push (format ":DEADLINE:%s:" (string-trim dead)) parts)))
        (`(delegate . ,deleg)
         (when deleg (push (format ":DELEGATED:%s:" (string-trim deleg)) parts)))
        (`(project . ,proj)
         (when proj (push (format ":PROJECT:%s:" (string-trim proj)) parts)))))
    (mapconcat #'identity (nreverse parts) "\n")))

(defun full-gtd-inbox--parse-properties-string (properties-string)
  "Parse PROPERTIES-STRING and apply to current entry.
PROPERTIES-STRING contains tags and properties in special format."
  (let ((components (split-string properties-string "\n" t)))
    (dolist (comp components)
      (cond
       ((string-match "^:SCHEDULED:\\(.+\\):$" comp)
        (let ((date-str (match-string 1 comp)))
          (org-schedule nil date-str)))
       ((string-match "^:PROJECT:\\(.+\\):$" comp)
        (let ((projects (match-string 1 comp)))
          (let ((normalized-projects (full-gtd-core--normalize-project-input projects)))
            (when normalized-projects
              (org-set-property "PROJECT" normalized-projects)))))
       ((string-match "^:\\([^:]+\\):\\(.+\\):$" comp)
        (let ((prop-name (match-string 1 comp))
              (prop-value (match-string 2 comp)))
          (org-set-property prop-name prop-value)))
       ((string-match "^@\\(.+\\)$" (string-trim comp))
        (let ((tag (match-string 1 (string-trim comp))))
          (when tag
            (org-set-tags (list tag)))))
       ((not (string-match "^:" (string-trim comp)))
        (let ((trimmed (string-trim comp)))
          (unless (string-empty-p trimmed)
            (org-set-tags (list trimmed)))))))))

;;;; Entry Point

(defun full-gtd-inbox--process-entry (headline buffer entry-ref original-tags &optional default-context default-project)
  "Process HEADLINE entry in BUFFER with new streamlined flow.
ENTRY-REF is the staging entry reference (BUFFER . ROW).
BUFFER is the staging buffer containing the entry.
Optional DEFAULT-CONTEXT and DEFAULT-PROJECT are passed to action
attribute collection.  ORIGINAL-TAGS is the original tags string from
the staging buffer."
  (let ((current-headline headline)
        (current-notes nil)
        (dest nil))
    (while (not dest)
      (full-gtd-inbox--highlight-entry entry-ref)
      (let ((key (full-gtd-inbox--read-destination-key current-headline)))
        (pcase key
          (?c (let ((clarified (full-gtd-inbox--clarify-entry current-headline current-notes)))
                (when (car clarified)
                  (setq current-headline (car clarified))
                  (full-gtd-inbox--stage-change entry-ref 1 current-headline))
                (setq current-notes (cdr clarified))
                (full-gtd-inbox--stage-change entry-ref 2 (or current-notes ""))))
          (?a (setq dest 'action))
          (?r (setq dest 'ref))
          (?s (setq dest 'someday))
          (?t (setq dest 'trash))
          (?x (setq dest 'execute))
          (_ (message "Invalid key") (sit-for 0.5)))))
    (pcase dest
      ('execute
       (full-gtd-inbox--mark-executed entry-ref)
       (full-gtd-inbox--stage-change entry-ref 4 "Executed")
       (push (list headline nil nil current-headline current-notes nil)
             full-gtd-inbox--pending-moves))
      ('trash
       (full-gtd-inbox--mark-deleted entry-ref)
       (full-gtd-inbox--stage-change entry-ref 4 "Trashed")
       (push (list headline nil nil current-headline current-notes nil)
             full-gtd-inbox--pending-moves))
      ('ref
       (full-gtd-inbox--stage-change entry-ref 4 "Reference")
       (push (list headline "reference.org" nil current-headline current-notes nil)
             full-gtd-inbox--pending-moves))
      ('someday
       (full-gtd-inbox--stage-change entry-ref 4 "Someday")
       (push (list headline "someday.org" nil current-headline current-notes nil)
             full-gtd-inbox--pending-moves))
      ('action
       (let* ((attrs (full-gtd-inbox--collect-action-attrs buffer default-context default-project))
              (deadline (cdr (assoc 'deadline attrs)))
              (context (cdr (assoc 'context attrs)))
              (project (cdr (assoc 'project attrs)))
              (tags-summary original-tags))
         ;; Build tags summary from original tags + new attributes
         (when (and context (not (string= context "")))
           (setq tags-summary (if (string= tags-summary "")
                                 context
                               (concat tags-summary "," context))))
         (when (and project (not (string= project "")))
           (setq tags-summary (if (string= tags-summary "")
                                 (concat "Project:" project)
                               (concat tags-summary ",Project:" project))))
         (when (and deadline (not (string= deadline "")))
           (setq tags-summary (if (string= tags-summary "")
                                 (concat "Deadline:" deadline)
                               (concat tags-summary ",Deadline:" deadline))))
         (when buffer (pop-to-buffer buffer))
         (full-gtd-inbox--stage-change entry-ref 4 tags-summary)
         (push (list headline "action.org"
                     (full-gtd-inbox--fields-to-props attrs)
                     current-headline current-notes deadline)
               full-gtd-inbox--pending-moves))))))

(defun full-gtd-inbox--apply-pending-moves (&optional brainstorm)
  "Apply all pending move operations to target files and cleanup inbox.
If BRAINSTORM is non-nil, remove BRAINSTORM property before moving.
Returns t if inbox file was deleted (empty after processing)."
  (dolist (move full-gtd-inbox--pending-moves)
    (full-gtd-inbox--do-move (nth 0 move) (nth 1 move) (nth 2 move)
                              (nth 3 move) (nth 4 move) (nth 5 move)
                              brainstorm))
  (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
    (when (and (file-exists-p inbox-file)
               (= 0 (file-attribute-size (file-attributes inbox-file))))
      (delete-file inbox-file)
      t)))

(defun full-gtd-inbox--process (&optional brainstorm default-context default-project)
  "Process the inbox according to GTD clarify and organize procedure.
If BRAINSTORM is non-nil, only process entries with BRAINSTORM property
set to \"t\".  DEFAULT-CONTEXT and DEFAULT-PROJECT are used when
BRAINSTORM is non-nil."
  (setq full-gtd-inbox--last-context nil)
  (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
    (setq full-gtd-inbox--pending-moves '())
    (when (and full-gtd-inbox-stage-buffer-name (get-buffer full-gtd-inbox-stage-buffer-name))
      (kill-buffer full-gtd-inbox-stage-buffer-name))
    (if (file-exists-p inbox-file)
        (let* ((attrs (file-attributes inbox-file))
               (file-size (file-attribute-size attrs)))
          (if (> file-size 0)
              (let* ((buffer-name (if brainstorm
                                      (format " *brainstorm-organize: %s*" (or default-project "unknown"))
                                    " *inbox-processing*"))
                     (staging-buffer (full-gtd-inbox--create-staging-buffer
                                      inbox-file
                                      buffer-name
                                      (when brainstorm
                                        (lambda ()
                                          (and (string= (org-entry-get nil "BRAINSTORM") "t")
                                               (or (null default-project)
                                                   (string= (org-entry-get nil "PROJECT") default-project))))))))
                (setq full-gtd-inbox-stage-buffer-name (buffer-name staging-buffer))
                (pop-to-buffer staging-buffer)
                (redisplay t)
                (condition-case _
                    (catch 'full-gtd-inbox-abort
                      (with-current-buffer staging-buffer
                        (org-mode)
                        (font-lock-ensure (point-min) (point-max))
                        (redisplay t)
                        (full-gtd-inbox--map-entries
                         staging-buffer
                         (lambda (headline entry-ref original-tags)
                           (full-gtd-inbox--process-entry headline staging-buffer entry-ref original-tags default-context default-project)))
                        (when full-gtd-inbox--current-highlight
                          (delete-overlay full-gtd-inbox--current-highlight)
                          (setq full-gtd-inbox--current-highlight nil))
                        (setq full-gtd-inbox--pending-moves (nreverse full-gtd-inbox--pending-moves))
                        (when (full-gtd-inbox--apply-pending-moves brainstorm)
                          (message "Inbox empty, deleted."))
                        (message "Inbox processing complete and changes applied per GTD workflow.")))
                  (quit
                   (message "Inbox processing cancelled.")
                   (when (buffer-live-p staging-buffer)
                     (kill-buffer staging-buffer))
                   (signal 'quit nil))))
            (let ((buffer-name "*Full-GTD: Inbox*"))
              (get-buffer-create buffer-name)
              (with-current-buffer buffer-name
                (setq buffer-read-only nil)
                (erase-buffer)
                (org-mode)
                (insert "(Inbox is empty - nothing to process)\n")
                (setq buffer-read-only t)
                (goto-char (point-min)))
              (pop-to-buffer buffer-name)
              (message "Inbox is empty, nothing to process."))))
      (let ((buffer-name "*Full-GTD: Inbox*"))
        (get-buffer-create buffer-name)
        (with-current-buffer buffer-name
          (setq buffer-read-only nil)
          (erase-buffer)
          (org-mode)
          (insert "(Inbox is empty - nothing to process)\n")
          (setq buffer-read-only t)
          (goto-char (point-min)))
        (pop-to-buffer buffer-name)
        (message "Inbox is empty, nothing to process.")))))

(defun full-gtd-inbox--do-move (headline target-file properties-string new-headline notes deadline &optional brainstorm)
  "Move HEADLINE to TARGET-FILE and delete from inbox.
If TARGET-FILE is nil, just delete from inbox (trash).
If BRAINSTORM is non-nil, remove BRAINSTORM property before moving.
PROPERTIES-STRING contains tags and properties.
NEW-HEADLINE is the clarified headline (nil if unchanged).
NOTES is the clarified notes text (nil if none).
DEADLINE is the deadline date string (nil if not set)."
  (let ((inbox-path (expand-file-name "inbox.org" full-gtd-init-base-directory))
        subtree-content)
    (when (and properties-string (not (string= properties-string "")))
      (with-current-buffer (find-file-noselect inbox-path)
        (org-mode)
        (goto-char (point-min))
        (when (re-search-forward (concat "^\\*+[ \t]+" (regexp-quote headline) "\\($\\| \\)") nil t)
          (beginning-of-line)
          (full-gtd-inbox--parse-properties-string properties-string)
          (save-buffer))))
    (when (and deadline (not (string= deadline "")))
      (with-current-buffer (find-file-noselect inbox-path)
        (org-mode)
        (goto-char (point-min))
        (if (re-search-forward (concat "^\\*+[ \t]+" (regexp-quote (or new-headline headline)) "\\($\\| \\)") nil t)
            (progn
              (org-deadline nil deadline)
              (save-buffer))
          nil)))
    (with-current-buffer (find-file-noselect inbox-path)
      (org-mode)
      (goto-char (point-min))
      (when (re-search-forward (concat "^\\*+[ \t]+" (regexp-quote headline) "\\($\\| \\)") nil t)
        (beginning-of-line)
        (when new-headline
          (org-edit-headline new-headline))
        (when (and target-file (string= target-file "action.org"))
          (org-todo (car org-not-done-keywords))
          (org-id-get-create)
          (full-gtd-horizons--sync-entry-horizons))
        (when notes
          (org-end-of-meta-data t)
          (unless (bolp)
            (insert "\n"))
          (insert notes "\n"))
        (goto-char (point-min))
        (re-search-forward (concat "^\\*+[ \t]+\\(?:[A-Z]+[ \t]+\\)?"
                                   (regexp-quote (or new-headline headline))
                                   "\\($\\| \\)"))
        (beginning-of-line)
        (when (and brainstorm target-file)
          (org-delete-property "BRAINSTORM"))
        (org-mark-subtree)
        (setq subtree-content (buffer-substring (region-beginning) (region-end)))
        (kill-region (region-beginning) (region-end))
        (save-buffer))
      (when (and target-file subtree-content)
        (let ((target-path (expand-file-name target-file full-gtd-init-base-directory)))
          (with-current-buffer (find-file-noselect target-path)
            (org-mode)
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert subtree-content)
            (unless (bolp) (insert "\n"))
            (save-buffer)))))))

(provide 'full-gtd-inbox)

;;; full-gtd-inbox.el ends here
