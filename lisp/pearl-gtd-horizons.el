;;; pearl-gtd-horizons.el --- Horizon system for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the Horizon system for GTD (L3 Area through L6 Purpose/Principles).
;; L6 contains both Purpose and Principle; Principle requires Purpose to be set first.
;; Provides horizon editing and hierarchical views.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)
(require 'pearl-gtd-review)

(declare-function pearl-gtd-horizons-view "pearl-gtd")

(defun pearl-gtd-horizons--get-project-horizon (project property)
  "Get horizon PROPERTY value for PROJECT from any of its actions.
PROPERTY should be one of: L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (value nil))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (catch 'found
          (org-map-entries
           (lambda ()
             (let ((proj (org-entry-get nil "PROJECT")))
               (when proj
                 (let ((projects (pearl-gtd-core--split-values proj)))
                   (when (member project projects)
                     (setq value (org-entry-get nil property))
                     (when value (throw 'found value)))))))
           nil nil))))
    value))

(defun pearl-gtd-horizons--set-project-horizon (project property value)
  "Set horizon PROPERTY to VALUE for all actions in PROJECT.
PROPERTY should be one of: L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (count 0))
    (when (file-exists-p file-path)
      (let ((buf (find-file-noselect file-path)))
        (with-current-buffer buf
          (org-mode)
          (org-map-entries
           (lambda ()
             (let ((proj (org-entry-get nil "PROJECT")))
               (when proj
                 (let ((projects (pearl-gtd-core--split-values proj)))
                   (when (member project projects)
                     (if (string= value "")
                         (org-delete-property property)
                       (org-entry-put nil property value))
                     (cl-incf count))))))
           nil nil)
          (when (> count 0)
            (save-buffer))))
      (let ((buf (get-file-buffer file-path)))
        (when buf (kill-buffer buf))))
    count))

(defun pearl-gtd-horizons--check-hierarchy-constraint (project level)
  "Check hierarchy constraint for setting LEVEL horizon for PROJECT.
LEVEL should be a symbol:
  \\='area, \\='goal, \\='vision, \\='purpose, or \\='principle.
L5 (vision) requires L4 (goal), L6 (purpose) requires L5 (vision),
L6 (principle) requires L6 (purpose).
Returns non-nil if constraint is satisfied, nil otherwise."
  (cond
   ((eq level 'area) t)    ; L3_AREA: no constraint
   ((eq level 'goal) t)    ; L4_GOAL: no constraint
   ((eq level 'vision)     ; L5_VISION: needs L4_GOAL
    (let ((l4 (pearl-gtd-horizons--get-project-horizon project "L4_GOAL")))
      (and l4 (not (string= l4 "")))))
   ((eq level 'purpose)    ; L6_PURPOSE: needs L5_VISION
    (let ((l5 (pearl-gtd-horizons--get-project-horizon project "L5_VISION")))
      (and l5 (not (string= l5 "")))))
   ((eq level 'principle)  ; L6_PRINCIPLE: needs L6_PURPOSE
    (let ((l6 (pearl-gtd-horizons--get-project-horizon project "L6_PURPOSE")))
      ;; Support multiple purposes: check if any non-empty value exists
      (and l6
           (cl-some (lambda (v) (not (string= v "")))
                    (pearl-gtd-core--split-values l6)))))
   (t t)))

(defun pearl-gtd-horizons--edit-horizon-at-point (level &optional project)
  "Edit horizon LEVEL for entry at point or for PROJECT if provided.
LEVEL should be a symbol:
  \\='area, \\='goal, \\='vision, \\='purpose, or \\='principle.
Supports multiple values separated by semicolon."
  (let* ((entry (unless project (pearl-gtd-review--get-entry-at-point)))
         (project (or project
                      (save-excursion
                        (beginning-of-line)
                        (let ((end (line-end-position))
                              (proj nil))
                          (while (and (< (point) end) (not proj))
                            (setq proj (get-text-property (point) 'pearl-gtd-project))
                            (forward-char 1))
                          proj)))))
    (when (or entry project)
      (let* ((id (when entry (car entry)))
             (file (when entry (cdr entry)))
             (property (cond ((eq level 'area)      "L3_AREA")
                             ((eq level 'goal)      "L4_GOAL")
                             ((eq level 'vision)    "L5_VISION")
                             ((eq level 'purpose)   "L6_PURPOSE")
                             ((eq level 'principle) "L6_PRINCIPLE")
                             (t (error "Internal: unknown horizon level %S" level))))
             (current-value (if project
                                (pearl-gtd-horizons--get-project-horizon project property)
                              (pearl-gtd-review--get-property-by-id id file property)))
             (current-values-display (if current-value
                                        (string-join (pearl-gtd-core--split-values current-value) "; ")
                                      ""))
             (prompt (format "Horizon %s (RET=remove, use ; to separate multiple): "
                             (cond ((eq level 'area)      "L3 Area")
                                   ((eq level 'goal)      "L4 Goal")
                                   ((eq level 'vision)    "L5 Vision")
                                   ((eq level 'purpose)   "L6 Purpose")
                                   ((eq level 'principle) "L6 Principle")
                                   (t (symbol-name level)))))
             (new-value (read-string prompt current-values-display)))
        (if project
            (progn
              ;; For project, check hierarchy constraint
              (unless (pearl-gtd-horizons--check-hierarchy-constraint project level)
                (error "%s must be set first"
                       (cond ((eq level 'vision)    "L4 Goal")
                             ((eq level 'purpose)   "L5 Vision")
                             ((eq level 'principle) "L6 Purpose")
                             (t "Previous horizon"))))
              (let ((count (pearl-gtd-horizons--set-project-horizon project property new-value)))
                (message "Set %s horizon for %d actions in project %s"
                         (cond ((eq level 'area)      "L3 Area")
                               ((eq level 'goal)      "L4 Goal")
                               ((eq level 'vision)    "L5 Vision")
                               ((eq level 'purpose)   "L6 Purpose")
                               ((eq level 'principle) "L6 Principle")
                               (t (symbol-name level)))
                         count project))
              (pearl-gtd-review--refresh-view)
              project)  ; Return project name
          ;; For no-project action, only area is allowed
          (if (eq level 'area)
              (if (string= new-value "")
                  (pearl-gtd-review--remove-property-by-id id file property)
                (pearl-gtd-review--set-property-by-id id file property new-value))
            (error "Only L3 horizon can be set for no-project actions"))
          (pearl-gtd-review--refresh-view)
          nil)))))

(defun pearl-gtd-horizons--edit-area-at-point (&optional project)
  "Edit L3 Area horizon for entry at point or for PROJECT if provided."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'area project))

(defun pearl-gtd-horizons--edit-goal-at-point (&optional project)
  "Edit L4 Goal horizon for entry at point or for PROJECT if provided."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'goal project))

(defun pearl-gtd-horizons--edit-vision-at-point (&optional project)
  "Edit L5 Vision horizon for entry at point or for PROJECT if provided."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'vision project))

(defun pearl-gtd-horizons--edit-purpose-at-point (&optional project)
  "Edit L6 Purpose horizon for entry at point or for PROJECT if provided."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'purpose project))

(defun pearl-gtd-horizons--edit-principle-at-point (&optional project)
  "Edit L6 Principle horizon for entry at point or for PROJECT if provided."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'principle project))

(defun pearl-gtd-horizons--collect-horizon-hierarchy ()
  "Collect all horizon data in hierarchical structure.
Returns alist mapping L6 to L5, L5 to L4, L4 to L3,
and L3 to a list of projects and no-project actions.
Supports multiple values per horizon level (split by semicolon)."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (hierarchy (make-hash-table :test 'equal)))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let* ((id (org-entry-get nil "ID"))
                  (head (org-get-heading t t))
                  (todo-state (org-get-todo-state))
                  (proj (org-entry-get nil "PROJECT"))
                  (l3 (org-entry-get nil "L3_AREA"))
                  (l4 (org-entry-get nil "L4_GOAL"))
                  (l5 (org-entry-get nil "L5_VISION"))
                  (l6 (org-entry-get nil "L6_PURPOSE"))
                  (entry (list head id todo-state)))
             ;; Only process if any horizon is set
             (when (or l3 l4 l5 l6)
               ;; For entries with only L3 set, put them at top level
               (if (and l3 (not (or l4 l5 l6)))
                   (let* ((l3-values (pearl-gtd-core--split-values l3)))
                     (dolist (l3-key l3-values)
                       (let* ((l3-key-normalized (if (string= l3-key "") "" l3-key))
                              ;; Get or create top-level L3 entry
                              (l3-entry (or (gethash l3-key-normalized hierarchy)
                                            (puthash l3-key-normalized (list nil nil) hierarchy))))
                         ;; Add to no-project list
                         (setcdr l3-entry (cons entry (cdr l3-entry))))))
                 ;; For entries with L4/L5/L6, build full hierarchy
                 ;; Split each level into multiple values
                 (let* ((l6-values (pearl-gtd-core--split-values (or l6 "")))
                        (l5-values (pearl-gtd-core--split-values (or l5 "")))
                        (l4-values (pearl-gtd-core--split-values (or l4 "")))
                        (l3-values (pearl-gtd-core--split-values (or l3 ""))))
                   ;; Iterate over all combinations of L6, L5, L4, L3
                   (dolist (l6-key l6-values)
                     (let ((l6-entry (or (gethash l6-key hierarchy)
                                         (puthash l6-key (make-hash-table :test 'equal) hierarchy))))
                       (dolist (l5-key l5-values)
                         (let ((l5-entry (or (gethash l5-key l6-entry)
                                             (puthash l5-key (make-hash-table :test 'equal) l6-entry))))
                           (dolist (l4-key l4-values)
                             (let ((l4-entry (or (gethash l4-key l5-entry)
                                                 (puthash l4-key (make-hash-table :test 'equal) l5-entry))))
                               (dolist (l3-key l3-values)
                                 (let ((l3-entry (or (gethash l3-key l4-entry)
                                                     (puthash l3-key (list nil nil) l4-entry))))
                                   ;; Now add the entry to the appropriate place
                                   (if (and proj (not (string= proj "")))
                                       ;; Project action - add to project's list
                                       (let ((projects (pearl-gtd-core--split-values proj)))
                                         (dolist (p projects)
                                           (let* ((project-list (car l3-entry))
                                                  (existing (assoc p project-list))
                                                  (entry-with-proj (list head id todo-state p)))
                                             (if existing
                                                 (setcdr existing (cons entry-with-proj (cdr existing)))
                                               (setcar l3-entry (cons (list p entry-with-proj) project-list))))))
                                     ;; No-project action - add to no-project list
                                     (setcdr l3-entry (cons entry (cdr l3-entry)))))))))))))))))
         nil nil)))
    hierarchy))

(defun pearl-gtd-horizons--insert-hierarchy (hierarchy depth)
  "Insert horizon HIERARCHY at DEPTH level."
  ;; Sort keys: nested hash tables first, then alphabetically
  (let ((sorted-keys (sort (hash-table-keys hierarchy)
                           (lambda (a b)
                             (let ((a-nested (hash-table-p (gethash a hierarchy)))
                                   (b-nested (hash-table-p (gethash b hierarchy))))
                               (cond
                                ((and a-nested b-nested) (string< a b))
                                (a-nested t)
                                (b-nested nil)
                                (t (string< a b))))))))
    (dolist (key sorted-keys)
      (let ((value (gethash key hierarchy)))
        (pearl-gtd-horizons--insert-hierarchy-entry key value depth)))))

(defun pearl-gtd-horizons--view ()
  "Display horizon hierarchy view."
  (let* ((buffer-name "*Pearl-GTD Horizons*")
         (hierarchy (pearl-gtd-horizons--collect-horizon-hierarchy)))
    (with-current-buffer (get-buffer-create buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      ;; Add header line
      (setq-local header-line-format
                  "Horizon View | RET: jump to task | g: refresh | q: quit")

      (insert "#+TITLE: Horizon View\n\n")

      (if (zerop (hash-table-count hierarchy))
          (insert "(No horizon data)\n")
        ;; Sort keys: prefer keys that have nested hash tables (full hierarchy)
        ;; over leaf nodes (L3-only entries)
        (let ((sorted-keys (sort (hash-table-keys hierarchy)
                                 (lambda (a b)
                                   (let ((a-nested (hash-table-p (gethash a hierarchy)))
                                         (b-nested (hash-table-p (gethash b hierarchy))))
                                     ;; Both nested or both leaf: sort alphabetically
                                     ;; One nested, one leaf: nested first
                                     (cond
                                      ((and a-nested b-nested) (string< a b))
                                      (a-nested t)
                                      (b-nested nil)
                                      (t (string< a b))))))))
          (dolist (key sorted-keys)
            (let ((value (gethash key hierarchy)))
              (pearl-gtd-horizons--insert-hierarchy-entry key value 2)))))

      (setq buffer-read-only t)
      (goto-char (point-min)))
    (pop-to-buffer buffer-name)
    (pearl-gtd-horizons-view-mode 1)))

(defvar pearl-gtd-horizons-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "RET") #'pearl-gtd-horizons--goto-task-at-point)
    (define-key map (kbd "g") #'pearl-gtd-horizons-view)
    map))

(define-minor-mode pearl-gtd-horizons-view-mode
  "Minor mode for horizon hierarchy view."
  :init-value nil
  :lighter " Pearl-Horizons"
  :keymap pearl-gtd-horizons-view-mode-map
  :interactive nil)

(defun pearl-gtd-horizons--goto-task-at-point ()
  "Jump to task in source file from horizon view."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (let ((id (get-text-property (point) 'pearl-gtd-id))
          (file (get-text-property (point) 'pearl-gtd-file)))
      (when (and id file)
        (find-file (expand-file-name file pearl-gtd-init-base-directory))
        (goto-char (point-min))
        (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
          (org-back-to-heading))))))

(defun pearl-gtd-horizons--insert-hierarchy-entry (key value depth)
  "Insert a single hierarchy entry with KEY and VALUE at DEPTH."
  ;; Always insert level header, even for empty keys
  (if (string= key "")
      (insert (make-string depth ?*) " (No L" (number-to-string (+ 3 depth)) ")\n")
    (insert (make-string depth ?*) " " key "\n"))

  (if (hash-table-p value)
      (pearl-gtd-horizons--insert-hierarchy value (1+ depth))
    (let ((projects (car value))
          (no-project-actions (cdr value)))
      ;; Insert projects
      (dolist (project projects)
        (let ((project-name (car project))
              (actions (cdr project)))
          (insert (make-string (1+ depth) ?*) " " project-name "\n")
          (dolist (action actions)
            (let ((head (nth 0 action))
                  (id (nth 1 action))
                  (todo-state (nth 2 action)))
              (when head
                (insert (make-string (+ 2 depth) ?*) " "
                        (if (and todo-state (member todo-state org-not-done-keywords))
                            (concat todo-state " ")
                          (if todo-state (concat todo-state " ") ""))
                        head "\n")
                ;; Add text properties for jumping
                (save-excursion
                  (forward-line -1)
                  (beginning-of-line)
                  (put-text-property (point) (line-end-position) 'pearl-gtd-id id)
                  (put-text-property (point) (line-end-position) 'pearl-gtd-file "actions.org")))))))
      ;; Insert no-project actions
      (dolist (action no-project-actions)
        (let ((head (nth 0 action))
              (id (nth 1 action))
              (todo-state (nth 2 action)))
          (when head
            (insert (make-string (1+ depth) ?*) " "
                    (if (and todo-state (member todo-state org-not-done-keywords))
                        (concat todo-state " ")
                      (if todo-state (concat todo-state " ") ""))
                    head "\n")
            (save-excursion
              (forward-line -1)
              (beginning-of-line)
              (put-text-property (point) (line-end-position) 'pearl-gtd-id id)
              (put-text-property (point) (line-end-position) 'pearl-gtd-file "actions.org"))))))))

;; Add horizon editing keybindings to review mode
(defvar pearl-gtd-horizons--review-bindings
  (let ((map pearl-gtd-review-view-mode-map))
    (define-key map (kbd "3") #'pearl-gtd-horizons--edit-area-at-point)
    (define-key map (kbd "4") #'pearl-gtd-horizons--edit-goal-at-point)
    (define-key map (kbd "5") #'pearl-gtd-horizons--edit-vision-at-point)
    (define-key map (kbd "6") #'pearl-gtd-horizons--edit-purpose-at-point)
    (define-key map (kbd "7") #'pearl-gtd-horizons--edit-principle-at-point)
    map))

(provide 'pearl-gtd-horizons)

;;; pearl-gtd-horizons.el ends here
