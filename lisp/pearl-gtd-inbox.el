;;; pearl-gtd-inbox.el --- Inbox handling for pearl-gtd  -*- lexical-binding: t; -*-

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
                          "N/A"))
               (headline (nth 0 entry))
               (escaped-headline (replace-regexp-in-string "|" "\\\\vert{}" headline)))
          (insert (format "| %s | | %s | %s |\n"
                          escaped-headline
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
                ;; Unescape pipe characters that were escaped for table display
                (setq headline (replace-regexp-in-string "\\\\vert{}" "|" headline))
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

(defun pearl-gtd-inbox--mark-deleted-impl (row)
  "Mark ROW as deleted. Internal implementation for state layer."
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
    (cl-pushnew row pearl-gtd-inbox--marked-deleted-rows)))

(defun pearl-gtd-inbox--mark-deleted (entry-ref)
  "Mark ENTRY-REF as deleted.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (pearl-gtd-inbox--mark-deleted-impl row))))

(defun pearl-gtd-inbox--mark-executed-impl (row)
  "Mark ROW as executed. Internal implementation for state layer."
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
    (cl-pushnew row pearl-gtd-inbox--marked-executed-rows)))

(defun pearl-gtd-inbox--mark-executed (entry-ref)
  "Mark ENTRY-REF as executed.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (pearl-gtd-inbox--mark-executed-impl row))))

(defun pearl-gtd-inbox--stage-change-impl (row col new-value)
  "Stage change for ROW at COL with NEW-VALUE.
Internal implementation for state layer."
  (push (list row col new-value) pearl-gtd-inbox--staging-changes)
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- row))
      (org-table-goto-column col)
      (org-table-blank-field)
      (insert new-value)
      (org-table-align)
      (pearl-gtd-inbox--reapply-marks (current-buffer)))))

(defun pearl-gtd-inbox--stage-change (entry-ref col new-value)
  "Stage change for ENTRY-REF at COL with NEW-VALUE.
ENTRY-REF is a cons cell (BUFFER . ROW).
COL is the column number to modify.
NEW-VALUE is the string to insert."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (pearl-gtd-inbox--stage-change-impl row col new-value))))

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
  "List of pending moves after staging.

Each element is a list:
ORIGINAL-HEADLINE, TARGET-FILE, PROPERTIES-STRING,
NEW-HEADLINE, REMARKS, and DEADLINE.

If TARGET-FILE is nil, the entry is deleted (trash).
PROPERTIES-STRING contains tags and properties.
NEW-HEADLINE is the clarified headline, or nil if unchanged.
REMARKS is the clarified remarks text, or nil if none.
DEADLINE is the deadline date string, or nil if not set.")

(defvar pearl-gtd-inbox-stage-buffer-name nil
  "The name of the current inbox staging buffer.")

(defun pearl-gtd-inbox--capture ()
  "Capture a new item to the inbox with a timestamp."
  (let ((item (string-trim (read-string "Enter item to capture: "))))
    (unless (string-empty-p item)
      ;; Sanitize: remove control chars and normalize newlines
      (setq item (replace-regexp-in-string "[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f]" "" item))
      (setq item (replace-regexp-in-string "\n" " " item))
      (with-current-buffer (find-file-noselect (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (goto-char (point-max))
        (insert (format "* %s\n:PROPERTIES:\n:CREATED: %s\n:END:\n" item (format-time-string "%Y-%m-%d %H:%M:%S")))
        (forward-line -2)
        (org-id-get-create)
        (save-buffer)))))

;;;; State Machine Layer

(defun pearl-gtd-inbox--transition (state input)
  "State machine transition function.
STATE is current state symbol, INPUT is user input.
Returns next state or (next-state . payload)."
  (pcase `(,state ,input)
    ;; Clarifying phase
    (`(clarify (rename . ,new-name)) `(clarify . ,new-name))
    (`(clarify (remarks . ,remarks)) `(classify . ,remarks))

    ;; Classification
    (`(classify ,headline ,remarks . ,_)
     `(deciding ,headline ,remarks))
    (`(deciding ,headline ,remarks actionable)
     `(specify-actionable ,headline ,remarks))
    (`(deciding ,headline ,remarks non-actionable)
     `(specify-non-actionable ,headline ,remarks))

    ;; Actionable specification
    (`(specify-actionable ,headline ,remarks (two-minute . t))
     `(execute ,headline ,remarks))
    (`(specify-actionable ,headline ,remarks (two-minute . nil))
     `(collect-fields ,headline ,remarks nil))
    (`(collect-fields ,headline ,remarks ,fields (context . ,ctx))
     `(collect-fields ,headline ,remarks ,(cons `(context . ,ctx) fields)))
    (`(collect-fields ,headline ,remarks ,fields (schedule . ,date))
     `(collect-fields ,headline ,remarks ,(cons `(schedule . ,date) fields)))
    (`(collect-fields ,headline ,remarks ,fields (deadline . ,date))
     `(collect-fields ,headline ,remarks ,(cons `(deadline . ,date) fields)))
    (`(collect-fields ,headline ,remarks ,fields (delegate . ,person))
     `(collect-fields ,headline ,remarks ,(cons `(delegate . ,person) fields)))
    (`(collect-fields ,headline ,remarks ,fields (project . ,proj))
     `(collect-fields ,headline ,remarks ,(cons `(project . ,proj) fields)))
    (`(collect-fields ,headline ,remarks ,fields done)
     `(move-to-actions ,headline ,remarks ,(nreverse fields)))

    ;; Non-actionable specification
    (`(specify-non-actionable ,headline ,remarks (destination . "reference"))
     `(move-to "reference.org" ,headline ,remarks))
    (`(specify-non-actionable ,headline ,remarks (destination . "someday"))
     `(move-to "someday.org" ,headline ,remarks))
    (`(specify-non-actionable ,headline ,remarks (destination . "trash"))
     `(delete ,headline ,remarks))

    ;; Terminal states
    (`(execute ,headline ,remarks) `(completed (execute ,headline ,remarks)))
    (`(move-to ,file ,headline ,remarks) `(completed (move ,file ,headline ,remarks)))
    (`(move-to-actions ,headline ,remarks ,fields) `(completed (move-action ,headline ,remarks ,fields)))
    (`(delete ,headline ,remarks) `(completed (delete ,headline ,remarks)))

    (_ (error "Invalid transition: state=%S input=%S" state input))))

(defun pearl-gtd-inbox--fields-to-props (fields)
  "Convert FIELDS alist to properties string."
  (let ((parts '()))
    (dolist (f fields)
      (pcase f
        (`(context . ,ctx)
         (when ctx (push ctx parts)))
        (`(schedule . ,sched)
         (when sched (push (format ":SCHEDULED:%s:" sched) parts)))
        (`(delegate . ,deleg)
         (when deleg (push (format ":DELEGATED:%s:" deleg) parts)))
        (`(project . ,proj)
         (when proj (push (format ":PROJECT:%s:" proj) parts)))))
    (mapconcat #'identity (nreverse parts) " ")))

;;;; Entry Point

(defun pearl-gtd-inbox--process-entry (headline buffer entry-ref)
  "Process entry using explicit state machine."
  (let ((original-headline headline)
        (state `(clarify . ,headline))
        (row (cdr entry-ref))
        (context '()))
    (while (not (eq (car-safe state) 'completed))
      (pearl-gtd-inbox--highlight-entry entry-ref)
      (setq state
        (pcase state
          (`(clarify . ,current-headline)
           (let* ((rename (read-string (format "Rename '%s'? (RET to keep): " current-headline)))
                  (new-name (let ((trimmed (string-trim rename))) (unless (string= trimmed "") trimmed)))
                  (remark-text (read-string (format "Add remarks for '%s'? (RET to skip): "
                                                   (or new-name current-headline))))
                  (remarks (unless (string= remark-text "") remark-text)))
             (setq context `(:headline ,(or new-name current-headline) :remarks ,remarks))
             `(deciding ,(or new-name current-headline) ,remarks)))

          (`(deciding ,h ,r)
           (if (y-or-n-p (format "Is '%s' actionable? " h))
               `(specify-actionable ,h ,r)
             `(specify-non-actionable ,h ,r)))

          (`(specify-actionable ,h ,r)
           (if (y-or-n-p (format "Can '%s' be done in 2 minutes? " h))
               `(execute ,h ,r)
             `(collect-fields ,h ,r nil)))

          (`(collect-fields ,h ,r ,fields)
           (let* ((ctx (read-string (format "Context for '%s' (RET to skip): " h)))
                  (sched (read-string (format "Schedule for '%s' (RET to skip): " h)))
                  (dead (if (and sched (not (string= sched "")))
                           (read-string (format "Deadline for '%s' (RET to use schedule): " h))
                         (read-string (format "Deadline for '%s' (RET to skip): " h))))
                  (deleg (read-string (format "Delegate '%s' to (RET to skip): " h)))
                  (projs (read-string (format "Project name(s) for '%s' (comma separated, RET to skip): " h))))
             `(move-to-actions ,h ,r ,(list
                                        (cons 'context (unless (string= ctx "") ctx))
                                        (cons 'schedule (unless (string= sched "") sched))
                                        (cons 'deadline (if (string= dead "")
                                                           (unless (string= sched "") sched)
                                                         dead))
                                        (cons 'delegate (unless (string= deleg "") deleg))
                                        (cons 'project (unless (string= projs "") projs))))))

          (`(specify-non-actionable ,h ,r)
           (let ((dest (completing-read (format "Assign '%s' to: " h)
                                       '("reference" "someday" "trash") nil t)))
             (pcase dest
               ("reference" `(move-to "reference.org" ,h ,r))
               ("someday" `(move-to "someday.org" ,h ,r))
               ("trash" `(delete ,h ,r)))))

          (`(execute ,h ,r)
           (pearl-gtd-inbox--mark-executed entry-ref)
           (push (list original-headline nil nil h r nil) pearl-gtd-inbox--pending-moves)
           `(completed (executed ,h)))

          (`(move-to ,file ,h ,r)
           (push (list original-headline file nil h r nil) pearl-gtd-inbox--pending-moves)
           `(completed (moved ,file ,h)))

          (`(move-to-actions ,h ,r ,fields)
           (let ((props (pearl-gtd-inbox--fields-to-props fields))
                 (deadline (cdr (assoc 'deadline fields))))
             (push (list original-headline "actions.org" props h r deadline) pearl-gtd-inbox--pending-moves))
           `(completed (moved-to-actions ,h)))

          (`(delete ,h ,r)
           (pearl-gtd-inbox--mark-deleted entry-ref)
           (push (list original-headline nil nil h r nil) pearl-gtd-inbox--pending-moves)
           `(completed (deleted ,h)))

          (_ (error "Unknown state: %S" state)))))
    ;; Apply staged changes after state machine completes
    (pearl-gtd-inbox--apply-staged-changes buffer row context)))

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
                (condition-case err
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
                      ;; Only delete inbox if processing completed successfully and file is empty
                      (when (and (file-exists-p inbox-file)
                                 (= 0 (file-attribute-size (file-attributes inbox-file))))
                        (delete-file inbox-file))
                      (message "Inbox processing complete and changes applied per GTD workflow."))
                  (quit
                   ;; Ensure we don't delete inbox on quit - preserve original file
                   (message "Inbox processing cancelled.")
                   (kill-buffer staging-buffer)
                   (signal 'quit nil))))  ; Re-signal quit for test to catch
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
    ;; Add deadline if set and not empty
    (when (and deadline (not (string= deadline "")))
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
                                   "\\($\\| \\)"))
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
