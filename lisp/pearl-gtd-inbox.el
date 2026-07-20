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

;;;; Compute Layer (Pure Functions with User Interaction)

(defun pearl-gtd-inbox--clarify-entry-compute (headline)
  "Collect clarify decisions for HEADLINE via user interaction.
Returns (NEW-HEADLINE . REMARKS)."
  (let* ((rename (read-string (format "Rename '%s'? (RET to keep, or type new name): " headline)))
         (new-headline (let ((trimmed (string-trim rename)))
                        (unless (string= trimmed "") trimmed)))
         (remark-text (read-string (format "Add remarks for '%s'? (RET to skip, or type remarks): "
                                          (or new-headline headline))))
         (remarks (unless (string= remark-text "") remark-text)))
    (cons new-headline remarks)))

(defun pearl-gtd-inbox--compute-actionable-action (headline new-headline remarks)
  "Compute action spec for actionable entry.
Returns action spec: (clarify-and-move TARGET PROPS NEW-HEADLINE REMARKS DEADLINE) or (execute ...)."
  (let ((display-headline (or new-headline headline)))
    (if (y-or-n-p (format "Can '%s' be done in 2 minutes? " display-headline))
        (list 'execute new-headline remarks)
      ;; Collect additional fields
      (let* ((context (let ((c (read-string (format "Context for '%s' (e.g. @home, RET to skip): " display-headline))))
                       (unless (string= c "") c)))
             (schedule (let ((s (read-string (format "Schedule for '%s' (e.g. 2026-04-10, RET to skip): " display-headline))))
                        (unless (string= s "") s)))
             (deadline (if schedule
                          (let ((d (read-string (format "Deadline for '%s' (RET to use schedule, or enter date): " display-headline))))
                            (if (string= d "") schedule d))
                        (let ((d (read-string (format "Deadline for '%s' (RET to skip): " display-headline))))
                          (unless (string= d "") d))))
             (delegatee (let ((d (read-string (format "Delegate '%s' to (e.g. John, RET to skip): " display-headline))))
                         (unless (string= d "") d)))
             (projects (let ((p (read-string (format "Project name(s) for '%s' (comma separated, RET to skip): " display-headline))))
                        (seq-filter (lambda (s) (not (string-empty-p s)))
                                   (mapcar #'string-trim (split-string p "," t)))))
             (props (pearl-gtd-inbox--build-props context schedule delegatee projects)))
        (list 'clarify-and-move "actions.org" props new-headline remarks deadline)))))

(defun pearl-gtd-inbox--build-props (context schedule delegatee projects)
  "Build properties string from components."
  (let ((tags '()))
    (when context (push context tags))
    (when schedule (push (format ":SCHEDULED:%s:" schedule) tags))
    (when delegatee (push (format ":DELEGATED:%s:" delegatee) tags))
    (when projects (push (format ":PROJECT:%s:" (mapconcat #'identity projects ",")) tags))
    (mapconcat #'identity (nreverse tags) " ")))

(defun pearl-gtd-inbox--compute-non-actionable-action (headline new-headline remarks)
  "Compute action spec for non-actionable entry."
  (let* ((display-headline (or new-headline headline))
         (assign-to (completing-read (format "Assign '%s' to: " display-headline)
                                    '("reference" "someday" "trash") nil t)))
    (pcase assign-to
      ("reference" (list 'clarify-and-move "reference.org" nil new-headline remarks nil))
      ("someday" (list 'clarify-and-move "someday.org" nil new-headline remarks nil))
      ("trash" (list 'delete new-headline remarks))
      (_ (error "Internal: invalid assignment target %s" assign-to)))))

(defun pearl-gtd-inbox--compute-action-spec (headline new-headline remarks)
  "Compute complete action spec based on user decisions."
  (let ((display-headline (or new-headline headline)))
    (if (y-or-n-p (format "Is '%s' actionable? " display-headline))
        (pearl-gtd-inbox--compute-actionable-action headline new-headline remarks)
      (pearl-gtd-inbox--compute-non-actionable-action headline new-headline remarks))))

;;;; Execution Layer (Thin State Wrapper)

(defun pearl-gtd-inbox--execute-action-spec (headline spec entry-ref)
  "Execute action SPEC for HEADLINE. Internal errors crash (no catch-all).
ENTRY-REF is (BUFFER . ROW) for staging buffer operations."
  ;; Verify internal state (trust boundary: internal input must be valid)
  (cl-assert (consp entry-ref) t "Internal: entry-ref must be cons")
  (cl-assert (bufferp (car entry-ref)) t "Internal: entry-ref buffer invalid")
  (cl-assert (stringp headline) t "Internal: headline must be string")

  (pcase (car spec)
    ('clarify-and-move
     (let ((target (nth 1 spec))
           (props (nth 2 spec))
           (new-headline (nth 3 spec))
           (remarks (nth 4 spec))
           (deadline (nth 5 spec)))
       ;; Update staging buffer (internal state)
       (pearl-gtd-inbox--stage-change entry-ref 2 (or remarks ""))
       (pearl-gtd-inbox--stage-change entry-ref 1 (or new-headline headline))
       (when (and props (string= target "actions.org"))
         (pearl-gtd-inbox--stage-change entry-ref 4 props))
       ;; Queue for file operations
       (push (list headline target props new-headline remarks deadline)
             pearl-gtd-inbox--pending-moves)))

    ('execute
     (let ((new-headline (nth 1 spec))
           (remarks (nth 2 spec)))
       (pearl-gtd-inbox--mark-executed entry-ref)
       (push (list headline nil nil new-headline remarks nil)
             pearl-gtd-inbox--pending-moves)))

    ('delete
     (let ((new-headline (nth 1 spec))
           (remarks (nth 2 spec)))
       (pearl-gtd-inbox--mark-deleted entry-ref)
       (push (list headline nil nil new-headline remarks nil)
             pearl-gtd-inbox--pending-moves)))

    (_ (error "Internal: unknown action type %s" (car spec)))))

;;;; Entry Point

(defun pearl-gtd-inbox--process-entry (headline buffer entry-ref)
  "Process entry with separation of concerns.
Compute layer collects decisions, execution layer modifies state."
  (pearl-gtd-inbox--highlight-entry entry-ref)
  (let* ((clarify-result (pearl-gtd-inbox--clarify-entry-compute headline))
         (new-headline (car clarify-result))
         (remarks (cdr clarify-result))
         ;; Compute phase: pure interaction, no state changes
         (action-spec (pearl-gtd-inbox--compute-action-spec headline new-headline remarks)))
    ;; Execution phase: state changes, internal errors crash
    (pearl-gtd-inbox--execute-action-spec headline action-spec entry-ref)))

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
