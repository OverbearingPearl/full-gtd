;;; pearl-gtd-planning.el --- Natural Planning Model for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file implements the GTD Natural Planning Model.
;; Provides a guided workflow for project planning with forced completion.
;;
;; **Theoretical Boundaries**
;; - Purpose (L6), Vision (L5) and Goal (L4) are mandatory per Natural Planning Model:
;;   * Purpose answers "Why does this project exist?" (Allen: without sufficient
;;     purpose, the project should not exist).
;;   * Vision defines the 3‑5‑year strategic direction (Allen: essential for
;;     alignment and long-term clarity).
;;   * Goal defines the concrete outcome vision (Allen: essential for effective
;;     project planning).
;; - Principle (L6) and Area (L3) are optional per Horizons of Focus design:
;;   * Principles are only required when value conflicts or constraints exist.
;;   * Area is a system‑implementation convenience for Reviews and Horizons views,
;;     though not strictly required by GTD for every individual project.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)
(require 'pearl-gtd-horizons)

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

(defun pearl-gtd-planning--read-brainstorm-destination (headline)
  "Read single key for brainstorm item destination for HEADLINE.
Returns one of: ?n (next), ?r (reference), ?s (someday), ?t (trash),
?c (clarify).
Signals \\='quit if user presses \\`C-g\\'."
  (message "Organize '%s': [n]ext [r]ef [s]omeday [t]rash [c]larify: " headline)
  (let ((key (read-key)))
    (while (not (or (memq key '(?n ?N ?r ?R ?s ?S ?t ?T ?c ?C))
                    (eq key 7)))  ; C-g is character 7
      (message "Invalid key. Organize '%s': [n]ext [r]ef [s]omeday [t]rash [c]larify: " headline)
      (setq key (read-key)))
    (if (eq key 7)
        (signal 'quit nil)
      (downcase key))))

(defun pearl-gtd-planning--project-exists-p (proj-name)
  "Check if PROJ-NAME already exists in actions.org.
Handles multi-project tags (comma-separated)."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (goto-char (point-min))
        (catch 'found
          (while (re-search-forward (concat ":PROJECT:[ \t]+\\([^\n]*\\)") nil t)
            (let ((project-value (match-string 1)))
              ;; Split by comma and trim whitespace
              (dolist (proj (split-string project-value "," t))
                (when (string= (string-trim proj) proj-name)
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
                 ;; Handle multi-project tags (comma-separated)
                 (dolist (p (split-string proj "," t))
                   (let ((trimmed (string-trim p)))
                     (when (not (string= trimmed ""))
                       (cl-pushnew trimmed projects :test #'string=))))))))
         nil nil)))
    (nreverse projects)))

(defun pearl-gtd-planning--select-project ()
  "Prompt user to create new project name with completion from brainstorm projects.
Return project name string after validation (non-empty and not existing)."
  (let ((project-name "")
        (brainstorm-projects (pearl-gtd-planning--collect-brainstorm-projects)))
    (while (or (string= project-name "")
               (pearl-gtd-planning--project-exists-p project-name))
      (setq project-name (completing-read "Project name: <Unique identifier> (e.g., Website-Redesign, Q1-Marketing) [TAB for brainstorm projects]: "
                                          brainstorm-projects nil nil))
      (cond
       ((string= project-name "")
        (message "Project name cannot be empty, please re-enter.")
        (sit-for 1))
       ((pearl-gtd-planning--project-exists-p project-name)
        (message "Project '%s' already exists, please use a new name." project-name)
        (sit-for 1)
        (setq project-name ""))))
    project-name))

(defun pearl-gtd-planning--ask-horizon (level description &optional optional example-level)
  "Prompt for horizon value at LEVEL with DESCRIPTION.
LEVEL is a number (3-7).  DESCRIPTION is a string describing the horizon.
If OPTIONAL is non-nil, empty input is allowed.
EXAMPLE-LEVEL is the level to use for examples (defaults to LEVEL).
Return the input string (guaranteed non-empty when OPTIONAL is nil)."
  (let* ((examples '((3 . "Career, Health, Family, Personal Development")
                     (4 . "Launch website by March, Complete certification Q2")
                     (5 . "Become industry leader in 3 years, Build sustainable business")
                     (6 . "Help professionals organize work, Create positive impact")
                     (7 . "Quality over speed, Family first, Continuous learning")))
         (example-idx (or example-level level))
         (example (or (cdr (assoc example-idx examples)) "value"))
         (required-str (if optional "optional" "required"))
         (prompt (format "%s (L%d, %s): <Description> [RET %s] (e.g., %s): "
                         description level required-str
                         (if optional "skip" "must fill")
                         example)))
    (let ((input (read-string prompt)))
      (while (and (not optional) (string= input ""))
        (message "This field is required, please enter a value.")
        (sit-for 1)
        (setq input (read-string prompt)))
      input)))

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

(defun pearl-gtd-planning--organize-brainstorm-items (project)
  "Organize all brainstorm items for PROJECT using inbox processing.
Force completion of all items.  Return t if at least one next
action created."
  (pearl-gtd-inbox--process t pearl-gtd-planning--default-context project)
  ;; Verify at least one next action exists for this project
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (has-next-action nil))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (and (pearl-gtd-core-entry-todo-p)
                      (let ((proj (org-entry-get nil "PROJECT")))
                        (and proj (string= proj project))))
             (setq has-next-action t)))
         nil nil)))
    has-next-action))




(defun pearl-gtd-planning--create-action (headline project context horizons)
  "Create a new action in actions.org.
HEADLINE is the task title.
PROJECT is the project name.
CONTEXT is the context tag (may be empty).
HORIZONS is an alist of horizon properties."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
    (with-current-buffer (find-file-noselect file-path)
      (org-mode)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "* TODO " (or headline "Unnamed action") "\n")
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
      (org-id-get-create)
      (save-buffer))))

(defun pearl-gtd-planning--apply-horizons-to-project (project horizons)
  "Apply HORIZONS to all actions in newly created PROJECT.
HORIZONS is an alist of horizon properties."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
    (when (file-exists-p file-path)
      (with-current-buffer (find-file-noselect file-path)
        (org-mode)
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
         nil nil)
        (save-buffer)))))

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
          (insert (format "- %s: %s\n" (cdr h) (if (string= val "") "(not set)" val)))))

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
  "Start Natural Planning Model workflow."
  (setq pearl-gtd-planning--current-project (pearl-gtd-planning--select-project))

  ;; 1. Define horizons
  (let* ((purpose (pearl-gtd-planning--ask-horizon 6 "Purpose" nil))
         (principle (pearl-gtd-planning--ask-horizon 6 "Principle" t 7))
         (vision (pearl-gtd-planning--ask-horizon 5 "Vision" nil))
         (goal (pearl-gtd-planning--ask-horizon 4 "Goal" nil))
         (area (pearl-gtd-planning--ask-horizon 3 "Area" t))
         (default-context (read-string
                          (format "Default context for '%s' [RET none]: <@location/tool> (e.g., @phone, @office): "
                                  pearl-gtd-planning--current-project)))
         (horizons `(("L6_PURPOSE" . ,purpose)
                     ("L6_PRINCIPLE" . ,principle)
                     ("L5_VISION" . ,vision)
                     ("L4_GOAL" . ,goal)
                     ("L3_AREA" . ,area))))
    ;; Store default context for organize phase
    (setq pearl-gtd-planning--default-context default-context)

    ;; 2. Brainstorm - write to inbox
    (pearl-gtd-planning--ask-brainstorm pearl-gtd-planning--current-project)

    ;; 3. Organize - force complete all brainstorm items
    (let ((has-next-action (pearl-gtd-planning--organize-brainstorm-items pearl-gtd-planning--current-project)))

      ;; 4. Force at least one next action if none created
      (unless has-next-action
        (let ((forced-action ""))
          (while (string= forced-action "")
            (setq forced-action (read-string "Required next action: <Specific physical action> (e.g., Call designer for quote): ")))
          ;; Use default-context directly, no need to ask again
          (pearl-gtd-planning--create-action forced-action pearl-gtd-planning--current-project default-context horizons)))

      ;; 5. Apply horizons to all project actions
      (pearl-gtd-planning--apply-horizons-to-project pearl-gtd-planning--current-project horizons)

      ;; 6. Show project summary (NEW)
      (pearl-gtd-planning--show-project-summary pearl-gtd-planning--current-project horizons)

      (message "Natural planning completed for project: %s" pearl-gtd-planning--current-project))))

(defun pearl-gtd-planning-start ()
  "Start Natural Planning Model workflow."
  (interactive)
  (pearl-gtd-planning--start))

(provide 'pearl-gtd-planning)

;;; pearl-gtd-planning.el ends here
