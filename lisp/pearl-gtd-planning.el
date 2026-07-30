;;; pearl-gtd-planning.el --- Natural Planning Model for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Natural Planning Model workflow: Purpose -> Principle -> Vision
;; -> Goal -> Area -> Brainstorm -> Organize -> Next Actions.
;; Coordinator pattern: this module orchestrates user interaction,
;; delegates business rule validation to pearl-gtd-domain,
;; and delegates all file operations to pearl-gtd-state.
;; Transaction boundary: entire planning workflow is atomic.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)
(require 'pearl-gtd-horizons)
(require 'pearl-gtd-state)

(declare-function pearl-gtd-core-read-date "pearl-gtd-core")
(declare-function pearl-gtd-inbox--read-context "pearl-gtd-inbox")
(declare-function pearl-gtd-inbox--read-delegate "pearl-gtd-inbox")
(declare-function pearl-gtd-inbox--highlight-entry "pearl-gtd-inbox")
(declare-function pearl-gtd-inbox--map-entries "pearl-gtd-inbox")
(declare-function pearl-gtd-inbox--clarify-entry "pearl-gtd-inbox")
(declare-function pearl-gtd-inbox--stage-change "pearl-gtd-inbox")

(defvar pearl-gtd-planning--current-project nil
  "Current project name during planning session.")

(defvar pearl-gtd-planning--default-context nil
  "Default context for next actions during current planning session.")

(defun pearl-gtd-planning--project-exists-p (proj-name)
  "Check if PROJ-NAME already exists in actions.org.
This also handles multi-project values separated by semicolons
\(English and Chinese)."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (goto-char (point-min))
        (catch 'found
          (while (re-search-forward (concat ":PROJECT:[ \t]+\\([^\n]*\\)") nil t)
            (let ((project-value (match-string 1)))
              (dolist (proj (pearl-gtd-core--split-values project-value))
                (when (string= proj proj-name)
                  (throw 'found t)))))
          nil)))))

(defun pearl-gtd-planning--collect-brainstorm-projects ()
  "Collect unique project names from inbox.org entries with BRAINSTORM property.
Returns list of unique project names from entries where BRAINSTORM is \"t\"."
  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (projects '()))
    (when (file-exists-p inbox-path)
      (with-temp-buffer
        (insert-file-contents inbox-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (string= (org-entry-get nil "BRAINSTORM") "t")
             (let ((proj (org-entry-get nil "PROJECT")))
               (when proj
                 (let ((normalized (pearl-gtd-core--normalize-project-input proj)))
                   (when normalized
                     (dolist (p (pearl-gtd-core--split-values normalized))
                       (cl-pushnew p projects :test #'string=))))))))
         nil nil)))
    (nreverse projects)))

(defun pearl-gtd-planning--select-project ()
  "Prompt user to create new project name with completion from brainstorm projects.
Return project name string after validation (non-empty and not existing).
Supports spaces in project names."
  (let ((proj-name "")
        (brainstorm-projects (pearl-gtd-planning--collect-brainstorm-projects)))
    (while (or (string= proj-name "")
               (pearl-gtd-planning--project-exists-p proj-name))
      (setq proj-name (string-trim (completing-read
                          "Project name: <Unique identifier> (e.g., Website Redesign) [TAB for existing projects]: "
                          brainstorm-projects nil nil)))
      ;; Planning is for single project only, reject multi-project input
      (when (string-match-p "[;；]" proj-name)
        (message "Only single project name is allowed in planning mode")
        (sit-for 1)
        (setq proj-name ""))
      (cond
       ((string= proj-name "")
        (message "Project name cannot be empty, please re-enter.")
        (sit-for 1))
       ((pearl-gtd-planning--project-exists-p proj-name)
        (message "Project '%s' already exists, please use a new name." proj-name)
        (sit-for 1)
        (setq proj-name ""))))
    proj-name))

(defun pearl-gtd-planning--ask-horizon (level description &optional optional example-level)
  "Prompt for horizon value at LEVEL with DESCRIPTION.
LEVEL is a number (3-7).  DESCRIPTION is a string describing the horizon.
If OPTIONAL is non-nil, empty input is allowed.
EXAMPLE-LEVEL is the level to use for examples (defaults to LEVEL).
Return the input string (guaranteed non-empty when OPTIONAL is nil).
Supports multiple values separated by semicolon (;)."
  (let* ((examples '((3 . "Career Development")
                     (4 . "Launch website by March 2026")
                     (5 . "Become industry leader in 3 years")
                     (6 . "Help professionals organize work")
                     (7 . "Quality over speed")))
         (example-idx (or example-level level))
         (example (or (cdr (assoc example-idx examples)) "value"))
         (required-str (if optional "optional" "required"))
         (prompt (format "%s (L%d, %s): <Description> [RET %s] (e.g., %s; use ; to separate multiple): "
                         description level required-str
                         (if optional "to skip" "must fill")
                         example)))
    (let ((input (string-trim (read-string prompt))))
      (while (and (not optional) (string= input ""))
        (message "This field is required, please enter a value.")
        (sit-for 1)
        (setq input (string-trim (read-string prompt))))
      ;; Normalize multiple values if present
      (if (string-match-p "[;；]" input)
          (let ((values (pearl-gtd-core--split-values input)))
            (pearl-gtd-core--join-values values))
        input))))

(defun pearl-gtd-planning--collect-brainstorm-items (project)
  "Collect brainstorm item headlines for PROJECT from inbox.org.
Returns list of headline strings."
  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (items '()))
    (when (file-exists-p inbox-path)
      (with-temp-buffer
        (insert-file-contents inbox-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (and (string= (org-entry-get nil "BRAINSTORM") "t")
                      (let ((proj (org-entry-get nil "PROJECT")))
                        (and proj (string= proj project))))
             (push (org-get-heading t t) items)))
         nil nil)))
    (nreverse items)))

(defun pearl-gtd-planning--ask-brainstorm (project)
  "Collect brainstorm items for PROJECT via temp buffer.
If PROJECT already has brainstorm items in inbox, they are pre-populated.
Return list of written headline strings.
Signal error if user aborts."
  (let ((buf (get-buffer-create "*Pearl-GTD Brainstorm*"))
        (existing-items (pearl-gtd-planning--collect-brainstorm-items project)))
    (with-current-buffer buf
      (erase-buffer)
      (text-mode)
      ;; Pre-populate with existing items if any
      (when existing-items
        (insert (string-join existing-items "\n"))
        (unless (bolp) (insert "\n")))
      (setq-local header-line-format
                  "One item per line (e.g., Redesign homepage) | C-c C-c finish | C-c C-k abort")
      (local-set-key (kbd "C-c C-c") #'exit-recursive-edit)
      (local-set-key (kbd "C-c C-k")
                     (lambda ()
                       (interactive)
                       (setq-local brainstorm-abort t)
                       (exit-recursive-edit)))
      (setq-local brainstorm-abort nil))

    (pop-to-buffer buf)
    (unwind-protect
        (progn
          (recursive-edit)
          (if (buffer-local-value 'brainstorm-abort buf)
              (error "Brainstorm cancelled")
            (with-current-buffer buf
              ;; Parse non-empty lines
              (let ((lines (seq-filter (lambda (s) (not (string-blank-p s)))
                                       (split-string (buffer-string) "\n"))))
                ;; Write to inbox
                (dolist (item lines)
                  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
                    (with-current-buffer (find-file-noselect inbox-path)
                      (goto-char (point-max))
                      (unless (bolp) (insert "\n"))
                      (insert "* " item "\n")
                      (org-set-property "PROJECT" project)
                      (org-set-property "BRAINSTORM" "t")
                      (org-set-property "CREATED" (format-time-string "%F %T"))
                      (org-id-get-create)
                      (save-buffer))))
                lines))))
      (kill-buffer buf))))

(defun pearl-gtd-planning--has-brainstorm-items-p (project)
  "Check if PROJECT has brainstorm items in inbox (pure query)."
  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
    (and (file-exists-p inbox-path)
         (with-temp-buffer
           (insert-file-contents inbox-path)
           (org-mode)
           (catch 'found
             (org-map-entries
              (lambda ()
                (when (and (string= (org-entry-get nil "BRAINSTORM") "t")
                           (string= (org-entry-get nil "PROJECT") project))
                  (throw 'found t)))
              nil nil)
             nil)))))

(defun pearl-gtd-planning--read-forced-action (prompt)
  "Read forced next action from user with validation using PROMPT.
Returns non-empty string."
  (let ((action ""))
    (while (string= action "")
      (let ((raw (read-string prompt)))
        (setq action (string-trim raw))))
    action))

(defun pearl-gtd-planning--organize-brainstorm-items (project default-context)
  "Organize all brainstorm items for PROJECT with DEFAULT-CONTEXT.
Returns count of next actions created (integer)."
  (let ((count 0))
    (pearl-gtd-inbox--process t default-context project)
    ;; Count next actions created for this project
    (pearl-gtd-state--with-file-buffer "actions.org"
      (org-map-entries
       (lambda ()
         (let ((todo-p (pearl-gtd-core-entry-todo-p))
               (proj (org-entry-get nil "PROJECT")))
           (when (and todo-p (string= proj project))
             (cl-incf count))))
       nil nil))
    count))

(defun pearl-gtd-planning--create-action (headline project context horizons)
  "Create a new action in actions.org.
HEADLINE is the task title.
PROJECT is the project name.
CONTEXT is the context tag (may be empty).
HORIZONS is an alist of horizon properties."
  (pearl-gtd-state--with-file-buffer "actions.org"
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* " (car org-not-done-keywords) " " (or headline "Unnamed action") "\n")
    (org-set-property "PROJECT" (or project "NoProject"))
    (when (and context (stringp context) (not (string= context "")))
      (if (string-match "^@" context)
          (org-set-tags (list (substring context 1)))
        (org-set-tags (list context))))
    (dolist (horizon horizons)
      (let ((prop (car horizon))
            (val (cdr horizon)))
        (when (and val (stringp val) (not (string= val "")))
          (org-set-property prop val))))
    (org-id-get-create)))

(defun pearl-gtd-planning--apply-horizons-to-project (project horizons)
  "Apply HORIZONS to all actions in newly created PROJECT.
HORIZONS is an alist of horizon properties."
  (pearl-gtd-state--with-file-buffer "actions.org"
    (org-map-entries
     (lambda ()
       (let ((proj (org-entry-get nil "PROJECT")))
         (when (and proj (string= proj project))
           (dolist (horizon horizons)
             (let ((prop (car horizon))
                   (val (cdr horizon)))
               (if (string= val "")
                   (org-delete-property prop)
                 (org-entry-put nil prop val)))))))
     nil nil)))

(defun pearl-gtd-planning--show-project-summary (project horizons)
  "Display PROJECT overview with HORIZONS and all related items."
  (let ((buffer (get-buffer-create "*Pearl-GTD Planning Summary*"))
        (actions '())
        (references '())
        (someday '())
        (base pearl-gtd-init-base-directory))

    ;; Collect items from each file
    (dolist (file '("actions.org" "reference.org" "someday.org"))
      (let ((file-path (expand-file-name file base)))
        (when (file-exists-p file-path)
          (with-temp-buffer
            (insert-file-contents file-path)
            (org-mode)
            (org-map-entries
             (lambda ()
               (let ((proj (org-entry-get nil "PROJECT"))
                     (headline (org-get-heading t t))
                     (todo (org-get-todo-state))
                     (tags (org-get-tags)))
                 (when (and proj (string= proj project))
                   (let ((item (list :headline headline
                                    :todo todo
                                    :tags tags
                                    :file file)))
                     (cond
                      ((string= file "actions.org") (push item actions))
                      ((string= file "reference.org") (push item references))
                      ((string= file "someday.org") (push item someday)))))))
             nil nil)))))

    ;; Display in buffer
    (with-current-buffer buffer
      (erase-buffer)
      (org-mode)
      (insert (format "#+TITLE: Project Summary: %s\n\n" project))

      ;; Horizons section
      (insert "* Horizons of Focus\n")
      (dolist (h '(("L6_PURPOSE" . "Purpose (L6)")
                   ("L6_PRINCIPLE" . "Principle (L6)")
                   ("L5_VISION" . "Vision (L5)")
                   ("L4_GOAL" . "Goal (L4)")
                   ("L3_AREA" . "Area (L3)")))
        (let ((val (cdr (assoc (car h) horizons))))
          (insert (format "- %s: %s\n" (cdr h)
                         (if (string= val "")
                             "(not set)"
                           ;; Split and display multiple values
                           (string-join (pearl-gtd-core--split-values val) ", "))))))

      ;; Next Actions
      (insert "\n* Next Actions\n")
      (if actions
          (dolist (a (nreverse actions))
            (insert (format "- %s %s %s\n"
                           (or (plist-get a :todo) "TODO")
                           (plist-get a :headline)
                           (if (plist-get a :tags)
                               (format ":%s:" (string-join (plist-get a :tags) ":"))
                             ""))))
        (insert "- (No next actions defined)\n"))

      ;; Reference items
      (when references
        (insert "\n* Reference Items\n")
        (dolist (r (nreverse references))
          (insert (format "- %s\n" (plist-get r :headline)))))

      ;; Someday items
      (when someday
        (insert "\n* Someday/Maybe\n")
        (dolist (s (nreverse someday))
          (insert (format "- %s\n" (plist-get s :headline)))))

      (insert (format "\n* End\nPlanning completed at %s\n"
                     (format-time-string "%F %T"))))

    (pop-to-buffer buffer)
    (goto-char (point-min))))

(defun pearl-gtd-planning--start ()
  "Start Natural Planning Model workflow.
Coordinator pattern: delegates all business logic to domain layer,
all state operations to state layer."
  (let* (;; Step 1: Collect inputs (interaction layer)
         (proj-name (pearl-gtd-planning--select-project))
         (purpose (pearl-gtd-planning--ask-horizon 6 "Purpose" nil))
         (principle (pearl-gtd-planning--ask-horizon 6 "Principle" t))
         (vision (pearl-gtd-planning--ask-horizon 5 "Vision" nil))
         (goal (pearl-gtd-planning--ask-horizon 4 "Goal" nil))
         (area (pearl-gtd-planning--ask-horizon 3 "Area" t))
         (default-context (read-string "Default context [RET for none]: "))
         (horizons `(("L6_PURPOSE" . ,purpose)
                     ("L6_PRINCIPLE" . ,principle)
                     ("L5_VISION" . ,vision)
                     ("L4_GOAL" . ,goal)
                     ("L3_AREA" . ,area))))

    ;; Validate inputs (domain layer)
    (cl-destructuring-bind (valid-p . error-msg)
        (pearl-gtd-domain--planning-input-valid-p proj-name purpose vision goal)
      (unless valid-p
        (error "Planning validation failed: %s" error-msg)))

    ;; Execute workflow with transaction (state layer)
    (pearl-gtd-state--with-transaction '("actions.org" "inbox.org")
      ;; Brainstorm phase
      (pearl-gtd-planning--ask-brainstorm proj-name)

      ;; Organize phase (returns count of next actions created)
      (let ((next-action-count
             (if (pearl-gtd-planning--has-brainstorm-items-p proj-name)
                 (pearl-gtd-planning--organize-brainstorm-items proj-name default-context)
               0)))

        ;; Force next action if required (domain rule)
        (when (pearl-gtd-domain--require-next-action-p next-action-count)
          (let ((forced-action
                 (pearl-gtd-planning--read-forced-action "Required next action: ")))
            (pearl-gtd-planning--create-action
             forced-action proj-name default-context horizons)))

        ;; Apply horizons to all project actions
        (pearl-gtd-planning--apply-horizons-to-project proj-name horizons)))

    ;; Presentation
    (pearl-gtd-planning--show-project-summary proj-name horizons)
    (message "Natural planning completed for project: %s" proj-name)))

(defun pearl-gtd-planning-start ()
  "Start Natural Planning Model workflow."
  (interactive)
  (pearl-gtd-planning--start))

(provide 'pearl-gtd-planning)

;;; pearl-gtd-planning.el ends here
