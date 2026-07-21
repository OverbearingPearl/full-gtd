;;; pearl-gtd-planning.el --- Natural Planning Model for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; SPDX-License-Identifier: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file implements the GTD Natural Planning Model.
;; Provides a guided workflow for project planning with forced completion.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)
(require 'pearl-gtd-horizons)

(defvar pearl-gtd-planning--current-project nil
  "Current project name during planning session.")

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

(defun pearl-gtd-planning--select-project ()
  "Prompt user to create new project name.
Return project name string after validation (non-empty and not existing)."
  (let ((project-name ""))
    (while (or (string= project-name "")
               (pearl-gtd-planning--project-exists-p project-name))
      (setq project-name (read-string "New project name: "))
      (cond
       ((string= project-name "")
        (message "Project name cannot be empty, please re-enter.")
        (sit-for 1))
       ((pearl-gtd-planning--project-exists-p project-name)
        (message "Project '%s' already exists, please use a new name." project-name)
        (sit-for 1)
        (setq project-name ""))))
    project-name))

(defun pearl-gtd-planning--ask-horizon (level description &optional optional)
  "Prompt for horizon value at LEVEL with DESCRIPTION.
LEVEL is a number (3-7).  DESCRIPTION is a string describing the horizon.
If OPTIONAL is non-nil, empty input is allowed.
Return the input string (may be empty)."
  (let ((prompt (format "%s (L%d)%s: " description level
                        (if optional " (optional)" ""))))
    (read-string prompt)))

(defun pearl-gtd-planning--ask-brainstorm (project)
  "Collect brainstorm items for PROJECT via temp buffer.
Return list of written headline strings.
Signal error if user aborts."
  (let ((buf (get-buffer-create "*Pearl-GTD Brainstorm*")))
    (with-current-buffer buf
      (erase-buffer)
      (text-mode)
      (setq-local header-line-format
                  "One item per line | C-c C-c to finish | C-c C-k to abort")
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
  "Organize all brainstorm items from inbox for PROJECT.
Force completion of all items.  Return t if at least one next
action created."
  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (has-next-action nil)
        (items-to-process '()))
    ;; Collect brainstorm items for this project
    (when (file-exists-p inbox-path)
      (with-temp-buffer
        (insert-file-contents inbox-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT"))
                 (brainstorm (org-entry-get nil "BRAINSTORM"))
                 (headline (org-get-heading t t))
                 (id (org-entry-get nil "ID")))
             (when (and proj (string= proj project)
                        brainstorm (string= brainstorm "t")
                        id)
               (push (list headline id) items-to-process))))
         nil nil))
      (setq items-to-process (nreverse items-to-process)))

    ;; Process each item - force completion
    (dolist (item-info items-to-process)
      (let* ((headline (nth 0 item-info))
             (id (nth 1 item-info))
             (result (pearl-gtd-planning--process-brainstorm-item headline id project)))
        (when (eq (car result) 'next-action)
          (setq has-next-action t))))

    has-next-action))

(defun pearl-gtd-planning--process-brainstorm-item (headline id project)
  "Process single brainstorm item with forced completion.
HEADLINE is the item title.  ID is the org entry id.
PROJECT is the project name.
Return (DESTINATION . CONTEXT) where DESTINATION is one of:
\\='next-action, \\='reference, \\='someday, \\='trash."
  (let ((dest nil)
        (context "")
        (valid-destinations '("Next Action" "Reference" "Someday" "Trash")))
    ;; Force valid selection
    (while (not dest)
      (condition-case nil
          (let ((choice (completing-read (format "Organize '%s' to: " headline)
                                        valid-destinations nil t)))
            (setq dest (downcase choice))
            (when (string= dest "next action")
              (setq context (read-string (format "Context for '%s' (empty to skip): " headline)))))
        (quit (message "Must complete organization! Please choose destination.")
              (sit-for 1))))

    ;; Execute the move immediately
    (pearl-gtd-planning--execute-brainstorm-move headline id project dest context)

    (cons (intern (replace-regexp-in-string " " "-" dest)) context)))

(defun pearl-gtd-planning--execute-brainstorm-move (_headline id _project dest context)
  "Execute move for brainstorm item from inbox to DEST.
HEADLINE is the item title.  ID is the org entry id.
PROJECT is the project name.  DEST is the destination type.
CONTEXT is the context tag.
Internal errors crash (no catch-all)."
  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (target-file nil))
    (cond
     ((string= dest "next action")
      (setq target-file "actions.org"))
     ((string= dest "reference")
      (setq target-file "reference.org"))
     ((string= dest "someday")
      (setq target-file "someday.org"))
     ((string= dest "trash")
      (setq target-file nil)))

    ;; Trust boundary: inbox must exist (internal state, crash if violated)
    (cl-assert (file-exists-p inbox-path) t "Internal: inbox must exist")

    ;; Process in inbox buffer
    (let ((inbox-buffer (find-file-noselect inbox-path)))
      (with-current-buffer inbox-buffer
        (org-mode)
        (widen)
        (goto-char (point-min))
        ;; Trust boundary: entry must exist (internal state, crash if violated)
        (cl-assert (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
                   t "Internal: brainstorm entry must exist in inbox")
        (org-back-to-heading)
        ;; First make modifications (point is at heading)
        ;; Remove brainstorm marker, no longer needed after organization
        (org-delete-property "BRAINSTORM")

        (when (string= dest "next action")
          (org-todo "TODO")
          (when (and context (not (string= context "")))
            (if (string-match "^@" context)
                (org-set-tags (list (substring context 1)))
              (org-set-tags (list context)))))

        ;; After modifications, get subtree content
        (let ((subtree-content (buffer-substring (point) (org-end-of-subtree))))
          ;; Trust boundary: content must exist (internal state, crash if violated)
          (cl-assert (not (string= subtree-content ""))
                     t "Internal: subtree content must not be empty")
          ;; Delete from inbox
          (org-mark-subtree)
          (kill-region (region-beginning) (region-end))
          (save-buffer)
          ;; Insert to target if not trash
          (when target-file
            (let ((target-path (expand-file-name target-file pearl-gtd-init-base-directory)))
              (with-current-buffer (find-file-noselect target-path)
                (org-mode)
                (goto-char (point-max))
                (unless (bolp) (insert "\n"))
                (insert subtree-content)
                (unless (bolp) (insert "\n"))
                (save-buffer)))))))))

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
         (principle (pearl-gtd-planning--ask-horizon 6 "Principle" t))
         (vision (pearl-gtd-planning--ask-horizon 5 "Vision" t))
         (goal (pearl-gtd-planning--ask-horizon 4 "Goal" nil))
         (area (pearl-gtd-planning--ask-horizon 3 "Area" nil))
         (horizons `(("L6_PURPOSE" . ,purpose)
                     ("L6_PRINCIPLE" . ,principle)
                     ("L5_VISION" . ,vision)
                     ("L4_GOAL" . ,goal)
                     ("L3_AREA" . ,area))))

    ;; 2. Brainstorm - write to inbox
    (pearl-gtd-planning--ask-brainstorm pearl-gtd-planning--current-project)

    ;; 3. Organize - force complete all brainstorm items
    (let ((has-next-action (pearl-gtd-planning--organize-brainstorm-items pearl-gtd-planning--current-project)))

      ;; 4. Force at least one next action if none created
      (unless has-next-action
        (let ((forced-action ""))
          (while (string= forced-action "")
            (setq forced-action (read-string "Must create at least one next action: ")))
          (let ((forced-context (read-string "Context (empty to skip): ")))
            (pearl-gtd-planning--create-action forced-action pearl-gtd-planning--current-project forced-context horizons))))

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
