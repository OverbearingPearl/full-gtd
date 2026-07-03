;;; pearl-gtd-inbox.el --- Inbox handling for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file handles inbox-related functions for pearl-gtd, including capture and processing with user interaction via staging, fully aligned with GTD workflow.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)

(defface pearl-gtd-inbox--highlight
  '((t :inherit highlight))
  "Face for highlighting the current entry."
  :group 'pearl-gtd)

(defface pearl-gtd-inbox--deleted
  '((t :inherit shadow :strike-through t))
  "Face for deleted (trash) entries."
  :group 'pearl-gtd)

(defface pearl-gtd-inbox--executed
  '((t :inherit success :strike-through t))
  "Face for executed (2-minute rule) entries."
  :group 'pearl-gtd)

(defvar pearl-gtd-inbox--current-test-name nil
  "Current running test name for debugging.")

(defvar pearl-gtd-inbox--staging-original-file nil
  "The original Org file path for the staging buffer.")

(defvar pearl-gtd-inbox--staging-changes nil
  "A list to store staged changes, e.g., ((row col new-value) ...).")

(defvar pearl-gtd-inbox--current-prompt-type nil
  "Current prompt type: 'rename, 'remarks, 'context, 'schedule, 'deadline, 'delegate, 'project.")

(defvar-local pearl-gtd-inbox--current-highlight nil
  "Current highlight overlay in the staging buffer.")

(defvar-local pearl-gtd-inbox--marked-deleted-rows '()
  "Buffer-local list of row numbers marked as deleted.")

(defvar-local pearl-gtd-inbox--marked-executed-rows '()
  "Buffer-local list of row numbers marked as executed.")

(defun pearl-gtd-inbox--create-staging-buffer (file-path &optional buffer-name)
  "Create a staging buffer from FILE-PATH.
Optional BUFFER-NAME specifies the buffer name.
Return the created buffer."
  (setq pearl-gtd-inbox--staging-original-file file-path
        pearl-gtd-inbox--staging-changes nil
        pearl-gtd-inbox--marked-deleted-rows '()
        pearl-gtd-inbox--marked-executed-rows '())
  (let ((actual-buffer-name (or buffer-name (generate-new-buffer-name " *pearl-gtd-inbox-staging*")))
        (headlines '()))
    (with-current-buffer (get-buffer-create actual-buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert-file-contents file-path)
      (org-mode)
      (org-map-entries
       (lambda ()
         (push (list (org-get-heading t t)
                     (org-get-tags-at)
                     (org-get-todo-state)
                     (org-entry-get nil "CREATED"))
               headlines)))
      (erase-buffer)
      (insert "| Headline | Remarks | Age | Tags |\n")
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
                          "N/A")))
          (insert (format "| %s | | %s | %s |\n"
                          (nth 0 entry)
                          age-str
                          (mapconcat #'identity (nth 1 entry) ",")))))
      (org-table-align)
      (setq buffer-read-only t)
      (current-buffer))))

(defun pearl-gtd-inbox--map-entries (buffer func)
  "Map over all entries in BUFFER.
Calls FUNC with headline and entry-ref for each entry."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (forward-line 2)
      (let ((entries '()))
        (while (not (eobp))
          (let ((current-row (line-number-at-pos)))
            (when (looking-at "|")
              (let ((headline (string-trim (org-table-get-field 1))))
                (when (and headline (not (string= headline "")))
                  (push (cons headline (cons buffer current-row)) entries)))))
          (forward-line 1))
        (dolist (entry (nreverse entries))
          (funcall func (car entry) (cdr entry)))))))

(defun pearl-gtd-inbox--highlight-entry (entry-ref)
  "Highlight ENTRY-REF in staging buffer.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (save-excursion
        (when pearl-gtd-inbox--current-highlight
          (delete-overlay pearl-gtd-inbox--current-highlight))
        (goto-char (point-min))
        (forward-line (1- row))
        (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
          (overlay-put ov 'face 'pearl-gtd-inbox--highlight)
          (overlay-put ov 'evaporate t)
          (setq pearl-gtd-inbox--current-highlight ov))))))

(defun pearl-gtd-inbox--mark-deleted (entry-ref)
  "Mark ENTRY-REF as deleted.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (point-min))
          (forward-line (1- row))
          (org-table-goto-column 1)
          (let* ((start (point))
                 (end (progn (skip-chars-forward "^|") (point)))
                 (ov (make-overlay start end)))
            (overlay-put ov 'face 'pearl-gtd-inbox--deleted)
            (overlay-put ov 'evaporate t)))
        (cl-pushnew row pearl-gtd-inbox--marked-deleted-rows)))))

(defun pearl-gtd-inbox--mark-executed (entry-ref)
  "Mark ENTRY-REF as executed.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (point-min))
          (forward-line (1- row))
          (org-table-goto-column 1)
          (let* ((start (point))
                 (end (progn (skip-chars-forward "^|") (point)))
                 (ov (make-overlay start end)))
            (overlay-put ov 'face 'pearl-gtd-inbox--executed)
            (overlay-put ov 'evaporate t)))
        (cl-pushnew row pearl-gtd-inbox--marked-executed-rows)))))

(defun pearl-gtd-inbox--stage-change (entry-ref col new-value)
  "Stage change for ENTRY-REF at COL with NEW-VALUE.
ENTRY-REF is a cons cell (BUFFER . ROW).
COL is the column number to modify.
NEW-VALUE is the string to insert."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (push (list row col new-value) pearl-gtd-inbox--staging-changes)
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (point-min))
          (forward-line (1- row))
          (org-table-goto-column col)
          (org-table-blank-field)
          (insert new-value)
          (org-table-align)
          (pearl-gtd-inbox--reapply-marks buffer))))))

(defun pearl-gtd-inbox--clear-changes (buffer)
  "Clear changes in BUFFER.
BUFFER is the staging buffer to clear."
  (with-current-buffer buffer
    (setq pearl-gtd-inbox--staging-changes nil)))

(defun pearl-gtd-inbox--reapply-marks (buffer)
  "Reapply marks to BUFFER after table alignment.
BUFFER is the staging buffer to update."
  (with-current-buffer buffer
    (dolist (row pearl-gtd-inbox--marked-deleted-rows)
      (condition-case nil
          (progn
            (goto-char (point-min))
            (forward-line (1- row))
            (org-table-goto-column 1)
            (let* ((start (point))
                   (end (progn (skip-chars-forward "^|") (point)))
                   (ov (make-overlay start end)))
              (overlay-put ov 'face 'pearl-gtd-inbox--deleted)
              (overlay-put ov 'evaporate t)))
        (error nil)))
    (dolist (row pearl-gtd-inbox--marked-executed-rows)
      (condition-case nil
          (progn
            (goto-char (point-min))
            (forward-line (1- row))
            (org-table-goto-column 1)
            (let* ((start (point))
                   (end (progn (skip-chars-forward "^|") (point)))
                   (ov (make-overlay start end)))
              (overlay-put ov 'face 'pearl-gtd-inbox--executed)
              (overlay-put ov 'evaporate t)))
        (error nil)))))

(defvar pearl-gtd-inbox--pending-moves nil
  "List of (list original-headline target-file properties-string
new-headline remarks deadline) pending to be moved after staging.
If target-file is nil, means delete (trash).
Properties-string contains tags and properties.
New-headline is the clarified headline (nil if unchanged).
Remarks is the clarified remarks text (nil if none).
Deadline is the deadline date string (nil if not set).")

(defvar pearl-gtd-inbox-stage-buffer-name nil
  "The name of the current inbox staging buffer.")

(defun pearl-gtd-inbox--capture ()
  "Capture a new item to the inbox with a timestamp."
  (let ((item (string-trim (read-string "Enter item to capture: "))))
    (unless (string-empty-p item)
      (with-current-buffer (find-file-noselect (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (goto-char (point-max))
        (insert (format "* %s\n:PROPERTIES:\n:CREATED: %s\n:END:\n" item (format-time-string "%Y-%m-%d %H:%M:%S")))
        (forward-line -2)
        (org-id-get-create)
        (save-buffer)))))

(defun pearl-gtd-inbox--clarify-entry (headline buffer entry-ref)
  "Clarify the entry by asking user to rename or add remarks.
HEADLINE is the current entry heading.
BUFFER is the staging buffer.
ENTRY-REF is the reference to the entry.
Returns a cons cell (NEW-HEADLINE . REMARKS)."
  (let ((new-headline nil)
        (remarks nil))
    ;; Ask for rename
    (setq pearl-gtd-inbox--current-prompt-type 'rename)
    (let ((rename (read-string (format "Rename '%s'? (RET to keep, or type new name): " headline))))
      (when (not (string= rename ""))
        (setq new-headline rename)
        (pearl-gtd-inbox--stage-change entry-ref 1 rename)))
    ;; Ask for remarks
    (setq pearl-gtd-inbox--current-prompt-type 'remarks)
    (let ((remark-text (read-string (format "Add remarks for '%s'? (RET to skip, or type remarks): " (or new-headline headline)))))
      (when (not (string= remark-text ""))
        (setq remarks remark-text)
        ;; Update stage buffer to show remarks in column 4
        (pearl-gtd-inbox--stage-change entry-ref 2 remark-text)))
    (cons new-headline remarks)))

(defun pearl-gtd-inbox--process-entry (headline buffer entry-ref)
  "Process a single entry according to GTD steps.
HEADLINE is the entry heading to process.
BUFFER is the staging buffer.
ENTRY-REF is the reference to the entry."
  ;; Step 1: Clarify - ask for rename and remarks
  (let* ((clarify-result (pearl-gtd-inbox--clarify-entry headline buffer entry-ref))
         (new-headline (car clarify-result))
         (remarks (cdr clarify-result))
         (display-headline (or new-headline headline)))
    ;; Step 2: Process - check if actionable
    (let ((is-actionable (y-or-n-p (format "Is '%s' actionable? " display-headline))))
      (if is-actionable
          (pearl-gtd-inbox--handle-actionable headline buffer entry-ref new-headline remarks)
        (pearl-gtd-inbox--handle-non-actionable headline buffer entry-ref new-headline remarks)))))

(defun pearl-gtd-inbox--handle-actionable (headline buffer entry-ref new-headline remarks)
  "Handle actionable entries.
HEADLINE is the original entry heading.
BUFFER is the staging buffer.
ENTRY-REF is the reference to the entry.
NEW-HEADLINE is the clarified headline (nil if unchanged).
REMARKS is the clarified remarks text (nil if none)."
  (let ((can-do-in-2min (y-or-n-p (format "Can '%s' be done in 2 minutes? " (or new-headline headline)))))
    (if can-do-in-2min
        (pearl-gtd-inbox--execute-immediately headline buffer entry-ref new-headline remarks)
      (pearl-gtd-inbox--handle-further-checks headline buffer entry-ref new-headline remarks))))

(defun pearl-gtd-inbox--execute-immediately (headline buffer entry-ref new-headline remarks)
  "Execute and stage immediate actions.
HEADLINE is the original entry heading.
BUFFER is the staging buffer.
ENTRY-REF is the reference to the entry.
NEW-HEADLINE is the clarified headline (nil if unchanged).
REMARKS is the clarified remarks text (nil if none)."
  (message "Executing '%s' immediately." (or new-headline headline))
  (pearl-gtd-inbox--mark-executed entry-ref)
  (push (list headline nil nil new-headline remarks nil) pearl-gtd-inbox--pending-moves))

(defun pearl-gtd-inbox--handle-further-checks (headline buffer entry-ref new-headline remarks)
  "Handle further checks for non-immediate actionable entries.
HEADLINE is the original entry heading.
BUFFER is the staging buffer.
ENTRY-REF is the reference to the entry.
NEW-HEADLINE is the clarified headline (nil if unchanged).
REMARKS is the clarified remarks text (nil if none)."
  (let ((tags '())
        (display-headline (or new-headline headline))
        (deadline nil))
    ;; Context
    (setq pearl-gtd-inbox--current-prompt-type 'context)
    (let ((context (read-string (format "Context for '%s' (e.g. @home, RET to skip): " display-headline))))
      (when (not (string= context ""))
        (push context tags)))

    ;; Schedule
    (setq pearl-gtd-inbox--current-prompt-type 'schedule)
    (let ((schedule (read-string (format "Schedule for '%s' (e.g. 2026-04-10, RET to skip): " display-headline))))
      (when (not (string= schedule ""))
        (push (format ":SCHEDULED:%s:" schedule) tags)
        ;; If schedule is set, ask about deadline with schedule as default
        (setq pearl-gtd-inbox--current-prompt-type 'deadline)
        (let* ((deadline-prompt (format "Deadline for '%s' (RET to use schedule, or enter date): " display-headline))
               (deadline-input (read-string deadline-prompt)))
          (when (not (string= deadline-input ""))
            (setq deadline deadline-input))
          (when (and (string= deadline-input "") (not (string= schedule "")))
            (setq deadline schedule)))))

    ;; If no schedule was set, still ask about deadline (no default)
    (let ((schedule-set (cl-find-if (lambda (tag) (string-match "^:SCHEDULED:" tag)) tags)))
      (unless schedule-set
        (setq pearl-gtd-inbox--current-prompt-type 'deadline)
        (let ((deadline-input (read-string (format "Deadline for '%s' (RET to skip): " display-headline))))
          (when (not (string= deadline-input ""))
            (setq deadline deadline-input)))))

    ;; Delegated
    (setq pearl-gtd-inbox--current-prompt-type 'delegate)
    (let ((delegatee (read-string (format "Delegate '%s' to (e.g. John, RET to skip): " display-headline))))
      (when (not (string= delegatee ""))
        (push (format ":DELEGATED:%s:" delegatee) tags)))

    ;; Project
    (setq pearl-gtd-inbox--current-prompt-type 'project)
    (let ((project-input (read-string (format "Project name(s) for '%s' (comma separated, RET to skip): " display-headline))))
      (let ((projects (mapcar #'string-trim (split-string project-input "," t))))
        (when projects
          (push (format ":PROJECT:%s:" (mapconcat 'identity projects ",")) tags))))

    (let ((props (when tags (mapconcat 'identity (nreverse tags) " "))))
      (when props
        (pearl-gtd-inbox--stage-change entry-ref 4 props))
      ;; Store headline, target-file, and properties, plus clarify info and deadline
      (push (list headline "actions.org" props new-headline remarks deadline) pearl-gtd-inbox--pending-moves))))

(defun pearl-gtd-inbox--handle-non-actionable (headline buffer entry-ref new-headline remarks)
  "Handle non-actionable entries.
HEADLINE is the original entry heading.
BUFFER is the staging buffer.
ENTRY-REF is the reference to the entry.
NEW-HEADLINE is the clarified headline (nil if unchanged).
REMARKS is the clarified remarks text (nil if none)."
  (let ((assign-to (completing-read (format "Assign '%s' to: " (or new-headline headline))
                                    '("reference" "someday" "trash")
                                    nil t)))
    (cond
     ((string= assign-to "reference")
      (pearl-gtd-inbox--stage-change entry-ref 1 (format "[Reference] %s" (or new-headline headline)))
      (push (list headline "reference.org" nil new-headline remarks nil) pearl-gtd-inbox--pending-moves))
     ((string= assign-to "someday")
      (pearl-gtd-inbox--stage-change entry-ref 1 (format "[Someday] %s" (or new-headline headline)))
      (push (list headline "someday.org" nil new-headline remarks nil) pearl-gtd-inbox--pending-moves))
     ((string= assign-to "trash")
      (pearl-gtd-inbox--mark-deleted entry-ref)
      (push (list headline nil nil new-headline remarks nil) pearl-gtd-inbox--pending-moves))
     (t nil))))

(defun pearl-gtd-inbox--process ()
  "Process the inbox according to GTD clarify and organize steps, with user interaction via staging buffer."
  (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
    (setq pearl-gtd-inbox--pending-moves '())
    (when (and pearl-gtd-inbox-stage-buffer-name (get-buffer pearl-gtd-inbox-stage-buffer-name))
      (kill-buffer pearl-gtd-inbox-stage-buffer-name))
    (if (file-exists-p inbox-file)
        (let* ((attrs (file-attributes inbox-file))
               (file-size (file-attribute-size attrs)))
          (if (> file-size 0)
              (let ((staging-buffer (pearl-gtd-inbox--create-staging-buffer inbox-file " *inbox-processing*")))
                (setq pearl-gtd-inbox-stage-buffer-name (buffer-name staging-buffer))
                (pop-to-buffer staging-buffer)
                (with-current-buffer staging-buffer
                  (org-mode)
                  (pearl-gtd-inbox--map-entries
                   staging-buffer
                   (lambda (headline entry-ref)
                     (pearl-gtd-inbox--highlight-entry entry-ref)
                     (pearl-gtd-inbox--process-entry headline staging-buffer entry-ref)))
                  ;; Clear highlight after processing all entries
                  (when pearl-gtd-inbox--current-highlight
                    (delete-overlay pearl-gtd-inbox--current-highlight)
                    (setq pearl-gtd-inbox--current-highlight nil))
                  (pearl-gtd-inbox--clear-changes staging-buffer)
                  (setq pearl-gtd-inbox--pending-moves (nreverse pearl-gtd-inbox--pending-moves))
                  (dolist (move pearl-gtd-inbox--pending-moves)
                    (pearl-gtd-inbox--do-move (nth 0 move) (nth 1 move) (nth 2 move) (nth 3 move) (nth 4 move) (nth 5 move)))
                  (when (and (file-exists-p inbox-file)
                             (= 0 (file-attribute-size (file-attributes inbox-file))))
                    (delete-file inbox-file)))
                (message "Inbox processing complete and changes applied per GTD workflow."))
            ;; Empty inbox - create buffer with message
            (let ((buffer-name "*Pearl-GTD: Inbox*"))
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
      ;; Inbox file does not exist - create buffer with unified message
      (let ((buffer-name "*Pearl-GTD: Inbox*"))
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

(defun pearl-gtd-inbox--do-move (headline target-file properties-string new-headline remarks deadline)
  "Move HEADLINE to TARGET-FILE and delete from inbox.
If TARGET-FILE is nil, just delete from inbox (trash).
PROPERTIES-STRING contains properties such as \":SCHEDULED:2026-04-10:\",
\":DELEGATED:John:\", and \":PROJECT:Proj1,Proj2:\",
as well as tags like \"@office\".
HEADLINE is the entry heading to process.
TARGET-FILE is the destination file.
PROPERTIES-STRING is the string of properties.
NEW-HEADLINE is the clarified headline (nil if unchanged).
REMARKS is the clarified remarks text (nil if none).
DEADLINE is the deadline date string (nil if not set)."
  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        subtree-content)
    ;; First, add properties and tags to the entry in inbox
    (when (and properties-string (not (string= properties-string "")))
      (with-current-buffer (find-file-noselect inbox-path)
        (org-mode)
        (goto-char (point-min))
        (when (re-search-forward (concat "^\\*+ " (regexp-quote headline) "\\($\\| \\)") nil t)
          (beginning-of-line)
          ;; Parse components separated by space
          (let ((components (split-string properties-string " " t)))
            (dolist (comp components)
              (cond
               ;; SCHEDULED is built-in property, use org-schedule, not in PROPERTIES drawer
               ((string-match "^:SCHEDULED:\\(.+\\):$" comp)
                (let ((date-str (match-string 1 comp)))
                  (org-schedule nil date-str)))
               ;; PROJECT uses multivalued property (supports multiple projects)
               ((string-match "^:PROJECT:\\(.+\\):$" comp)
                (let ((projects (match-string 1 comp)))
                  (dolist (proj (split-string projects "," t))
                    (org-entry-add-to-multivalued-property
                     nil "PROJECT" (string-trim proj)))))
               ;; Other property format: :KEY:VALUE: (excluding SCHEDULED and PROJECT)
               ((string-match "^:\\([^:]+\\):\\(.+\\):$" comp)
                (let ((prop-name (match-string 1 comp))
                      (prop-value (match-string 2 comp)))
                  (org-set-property prop-name prop-value)))
               ;; Context tag format: @context - remove @ and set as only tag (overwrite old)
               ((string-match "^@\\(.+\\)$" comp)
                (let ((tag (match-string 1 comp)))
                  (org-set-tags-to (list tag))))
               ;; Simple tag without @ (fallback, also ensure unique)
               ((not (string-match "^:" comp))
                (org-set-tags-to (list comp))))))
          (save-buffer))))
    ;; Add deadline if set
    (when deadline
      (with-current-buffer (find-file-noselect inbox-path)
        (org-mode)
        (goto-char (point-min))
        (if (re-search-forward (concat "^\\*+ " (regexp-quote (or new-headline headline)) "\\($\\| \\)") nil t)
            (progn
              (org-deadline nil deadline)
              (save-buffer))
          nil)))
    ;; Then, extract the subtree from inbox (now with properties)
    (with-current-buffer (find-file-noselect inbox-path)
      (org-mode)
      (goto-char (point-min))
      (when (re-search-forward (concat "^\\*+ " (regexp-quote headline) "\\($\\| \\)") nil t)
        (beginning-of-line)
        ;; Apply headline rename using org-edit-headline to preserve tags
        (when new-headline
          (org-edit-headline new-headline))
        ;; Add TODO state when moving to actions.org
        (when (and target-file (string= target-file "actions.org"))
          (org-todo "TODO"))
        ;; Apply remarks if provided (add as body text after properties drawer)
        (when remarks
          (org-end-of-meta-data t)
          (unless (bolp)
            (insert "\n"))
          (insert remarks "\n"))
        ;; Re-locate to headline start after modifications
        (goto-char (point-min))
        (re-search-forward (concat "^\\*+[ \t]+\\(?:[A-Z]+[ \t]+\\)?"
                                   (regexp-quote (or new-headline headline))
                                   "\\($\\| \\)") nil t)
        (beginning-of-line)
        (org-mark-subtree)
        (setq subtree-content (buffer-substring (region-beginning) (region-end)))
        (kill-region (region-beginning) (region-end))
        (save-buffer)))
    ;; Then, insert to target file if needed
    (when (and target-file subtree-content)
      (let ((target-path (expand-file-name target-file pearl-gtd-init-base-directory)))
        (with-current-buffer (find-file-noselect target-path)
          (org-mode)
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert subtree-content)
          (unless (bolp) (insert "\n"))
          (save-buffer))))))

(provide 'pearl-gtd-inbox)

;;; pearl-gtd-inbox.el ends here
