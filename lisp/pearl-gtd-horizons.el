;;; pearl-gtd-horizons.el --- Horizon system for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the Horizon system for GTD (L3 Area through L6 Purpose/Principles).
;; Hierarchy: L6 Purpose -> L5 Vision -> L4 Goal -> L3 Area -> Projects -> Actions.
;; L6 contains both Purpose and Principle (edited together via key `6` in review mode);
;; Principle requires Purpose to be set first.
;; Provides horizon alignment matrix view for reviewing vertical alignment.
;;
;; The horizon view displays projects in a matrix format:
;; - Rows: Projects (grouped by alignment status)
;; - Columns: L6 Purpose, L5 Vision, L4 Goal, L3 Area
;; - Empty cells indicate gaps in vertical alignment
;; - No-project actions shown separately (L3 Area only)

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)
(require 'pearl-gtd-review)
(require 'pearl-gtd-domain)
(require 'pearl-gtd-state)

(declare-function pearl-gtd-horizons-view "pearl-gtd")

(defun pearl-gtd-horizons--get-project-horizon (project property)
  "Get horizon PROPERTY value for PROJECT from any of its actions.
PROPERTY should be one of: L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE.
Returns the first non-empty value found among project actions."
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
                     (let ((v (org-entry-get nil property)))
                       (when (and v (not (string= v "")))
                         (setq value v)
                         (throw 'found value))))))))
           nil nil))))
    value))

(defun pearl-gtd-horizons--set-project-horizon (project property value)
  "Set horizon PROPERTY to VALUE for all actions in PROJECT.
PROPERTY should be one of: L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE.
Returns count of modified entries.
Handles multi-project tasks by preserving horizons from other projects."
  (let ((count 0)
        (project-horizons (make-hash-table :test 'equal)))
    (pearl-gtd-state--with-transaction '("actions.org")
      (pearl-gtd-state--with-file-buffer "actions.org"
        ;; First pass: collect current horizons for all projects
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (let ((projects (pearl-gtd-core--split-values proj))
                     (horiz (org-entry-get nil property)))
                 (when horiz
                   (dolist (p projects)
                     (unless (gethash p project-horizons)
                       (puthash p horiz project-horizons))))))))
         nil nil)
        ;; Update target project's horizon to new value
        (puthash project value project-horizons)
        ;; Second pass: update all tasks in target project with combined horizons
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (let ((projects (pearl-gtd-core--split-values proj)))
                 (when (member project projects)
                   ;; Collect unique horizon values from all projects this task belongs to
                   (let ((values nil))
                     (dolist (p projects)
                       (let ((v (gethash p project-horizons)))
                         (when (and v (not (string= v "")))
                           (unless (member v values)
                             (push v values)))))
                     (if values
                         (org-entry-put nil property (pearl-gtd-core--join-values (reverse values)))
                       (org-delete-property property))
                     (cl-incf count)))))))
         nil nil)))
    count))

(defun pearl-gtd-horizons--check-hierarchy-constraint (project level)
  "Check hierarchy constraint for setting LEVEL horizon for PROJECT.
PROJECT is project name string (external input, must be string).
LEVEL is symbol: \\='area, \\='goal, \\='vision, \\='purpose, or \\='principle."
  (cl-assert (stringp project) t "Internal: project must be string")
  (let ((existing-horizons
         (list (cons 'L3_AREA (pearl-gtd-horizons--get-project-horizon project "L3_AREA"))
               (cons 'L4_GOAL (pearl-gtd-horizons--get-project-horizon project "L4_GOAL"))
               (cons 'L5_VISION (pearl-gtd-horizons--get-project-horizon project "L5_VISION"))
               (cons 'L6_PURPOSE (pearl-gtd-horizons--get-project-horizon project "L6_PURPOSE")))))
    (car (pearl-gtd-domain--check-hierarchy-constraint existing-horizons level))))

(defun pearl-gtd-horizons--get-project-at-point ()
  "Get project name from text property in current table row."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (project nil))
      (while (and (not project) (< (point) end))
        (setq project (get-text-property (point) 'pearl-gtd-project))
        (forward-char 1))
      project)))

(defun pearl-gtd-horizons--edit-horizon-at-point (level &optional project)
  "Edit horizon LEVEL for PROJECT at point.
LEVEL should be a symbol:
  \\='area, \\='goal, \\='vision, \\='purpose, or \\='principle.
Supports multiple values separated by semicolon."
  (let* ((project (or project
                      (pearl-gtd-horizons--get-project-at-point))))
    (when project
      (let* ((property (cond ((eq level 'area)      "L3_AREA")
                             ((eq level 'goal)      "L4_GOAL")
                             ((eq level 'vision)    "L5_VISION")
                             ((eq level 'purpose)   "L6_PURPOSE")
                             ((eq level 'principle) "L6_PRINCIPLE")
                             (t (error "Internal: unknown horizon level %S" level))))
             (current-value (pearl-gtd-horizons--get-project-horizon project property))
             (current-values-display (if current-value
                                        (string-join (pearl-gtd-core--split-values current-value) "; ")
                                      ""))
             (prompt (format "Horizon %s (empty to remove, use ; to separate multiple): "
                             (cond ((eq level 'area)      "L3 Area")
                                   ((eq level 'goal)      "L4 Goal")
                                   ((eq level 'vision)    "L5 Vision")
                                   ((eq level 'purpose)   "L6 Purpose")
                                   ((eq level 'principle) "L6 Principle")
                                   (t (symbol-name level)))))
             (raw-input (string-trim (read-string prompt current-values-display)))
             (new-value (if (string-match-p "[;；]" raw-input)
                           (pearl-gtd-core--join-values (pearl-gtd-core--split-values raw-input))
                         raw-input)))
        ;; Check hierarchy constraint
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
        (pearl-gtd-horizons--view)
        project))))

(defun pearl-gtd-horizons--edit-area-at-point ()
  "Edit L3 Area horizon for project at point."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'area))

(defun pearl-gtd-horizons--edit-goal-at-point ()
  "Edit L4 Goal horizon for project at point."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'goal))

(defun pearl-gtd-horizons--edit-vision-at-point ()
  "Edit L5 Vision horizon for project at point."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'vision))

(defun pearl-gtd-horizons--edit-purpose-at-point ()
  "Edit L6 Purpose and Principle horizons for project at point.
Prompts for Purpose first, then immediately prompts for Principle."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'purpose)
  ;; After setting purpose, immediately prompt for principle (same horizon level)
  (pearl-gtd-horizons--edit-horizon-at-point 'principle))

(defun pearl-gtd-horizons--edit-principle-at-point ()
  "Edit L6 Principle horizon for project at point."
  (interactive)
  (pearl-gtd-horizons--edit-horizon-at-point 'principle))

(defun pearl-gtd-horizons--collect-all-projects ()
  "Collect all unique project names from actions.org with their stats.
Returns list of (PROJECT-NAME TOTAL TODO DONE L6 L5 L4 L3)."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (projects (make-hash-table :test 'equal)))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT"))
                 (todo-state (org-get-todo-state))
                 (l3 (org-entry-get nil "L3_AREA"))
                 (l4 (org-entry-get nil "L4_GOAL"))
                 (l5 (org-entry-get nil "L5_VISION"))
                 (l6 (org-entry-get nil "L6_PURPOSE")))
             (when proj
               (dolist (p (pearl-gtd-core--split-values proj))
                 (let ((data (or (gethash p projects)
                                 (puthash p (list 0 0 0 nil nil nil nil) projects))))
                   (cl-incf (nth 0 data))  ; Total
                   (cond
                    ((member todo-state org-done-keywords) (cl-incf (nth 2 data)))
                    ((member todo-state org-not-done-keywords) (cl-incf (nth 1 data))))
                   ;; Store first non-empty horizon value
                   (unless (nth 3 data) (setf (nth 3 data) (and l6 (not (string= l6 "")) l6)))
                   (unless (nth 4 data) (setf (nth 4 data) (and l5 (not (string= l5 "")) l5)))
                   (unless (nth 5 data) (setf (nth 5 data) (and l4 (not (string= l4 "")) l4)))
                   (unless (nth 6 data) (setf (nth 6 data) (and l3 (not (string= l3 "")) l3))))))))
         nil nil)))
    ;; Convert hash to list
    (let (result)
      (maphash (lambda (k v) (push (cons k v) result)) projects)
      result)))

(defun pearl-gtd-horizons--collect-no-project-actions ()
  "Collect TODO actions without project, with L3 Area.
Returns list of (HEADLINE STATUS CONTEXT L3)."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (actions '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (pearl-gtd-core-entry-todo-p)
             (let ((proj (org-entry-get nil "PROJECT"))
                   (head (org-get-heading t t))
                   (status (org-get-todo-state))
                   (context (mapconcat (lambda (c) (concat "@" c)) (org-get-tags) ","))
                   (l3 (org-entry-get nil "L3_AREA")))
               (when (or (null proj) (string= proj ""))
                 (push (list head status context (or l3 "")) actions)))))
         nil nil)))
    (nreverse actions)))

(defun pearl-gtd-horizons--classify-projects (projects)
  "Classify PROJECTS into categories based on horizon alignment.
Returns (CRITICAL PARTIAL ALIGNED MULTI) where each is a list of projects."
  (let ((critical '())
        (partial '())
        (aligned '())
        (multi '()))
    (dolist (proj projects)
      (let* ((name (car proj))
             (l6 (nth 3 (cdr proj)))
             (l5 (nth 4 (cdr proj)))
             (l4 (nth 5 (cdr proj)))
             (l3 (nth 6 (cdr proj)))
             (has-l6 (and l6 (not (string= l6 ""))))
             (has-l5 (and l5 (not (string= l5 ""))))
             (has-l4 (and l4 (not (string= l4 ""))))
             (has-l3 (and l3 (not (string= l3 ""))))
             (multi-p (or (and l6 (string-match-p "[;；]" l6))
                         (and l5 (string-match-p "[;；]" l5))
                         (and l4 (string-match-p "[;；]" l4))
                         (and l3 (string-match-p "[;；]" l3)))))
        (cond
         ((and (not has-l6) (not has-l5) (not has-l4) (not has-l3))
          (push proj critical))
         ((and (not has-l6) (not has-l5) (not has-l4) has-l3)
          (push proj partial))
         (multi-p
          (push proj multi))
         ((and has-l6 has-l5 has-l4 has-l3)
          (push proj aligned))
         (t
          (push proj partial)))))
    (list (nreverse critical) (nreverse partial) (nreverse aligned) (nreverse multi))))

(defun pearl-gtd-horizons--insert-project-row (proj)
  "Insert table row for PROJECT."
  (let* ((name (car proj))
         (total (nth 0 (cdr proj)))
         (todo (nth 1 (cdr proj)))
         (done (nth 2 (cdr proj)))
         (l6 (or (nth 3 (cdr proj)) ""))
         (l5 (or (nth 4 (cdr proj)) ""))
         (l4 (or (nth 5 (cdr proj)) ""))
         (l3 (or (nth 6 (cdr proj)) ""))
         ;; Normalize display values
         (l6-display (string-join (pearl-gtd-core--split-values l6) "; "))
         (l5-display (string-join (pearl-gtd-core--split-values l5) "; "))
         (l4-display (string-join (pearl-gtd-core--split-values l4) "; "))
         (l3-display (string-join (pearl-gtd-core--split-values l3) "; ")))
    (insert "| ")
    (let ((start (point)))
      (insert name)
      (put-text-property start (point) 'pearl-gtd-project name))
    (insert (format " | %s | %s | %s | %s | %s | %s | %s |\n"
                    total todo done
                    (if (string= l6-display "") " " l6-display)
                    (if (string= l5-display "") " " l5-display)
                    (if (string= l4-display "") " " l4-display)
                    (if (string= l3-display "") " " l3-display)))))

(defun pearl-gtd-horizons--insert-no-project-row (action)
  "Insert table row for no-project ACTION."
  (let ((head (nth 0 action))
        (status (nth 1 action))
        (context (nth 2 action))
        (l3 (or (nth 3 action) ""))
        (l3-display (string-join (pearl-gtd-core--split-values (or (nth 3 action) "")) "; ")))
    (insert "| ")
    (let ((start (point)))
      (insert head)
      (put-text-property start (point) 'pearl-gtd-action head))
    (insert (format " | %s | %s | %s |\n"
                    status
                    (if (string= context "") " " context)
                    (if (string= l3-display "") " " l3-display)))))

(defun pearl-gtd-horizons--view ()
  "Display horizon alignment matrix view."
  (let* ((buffer-name "*Pearl-GTD Horizon View*")
         (projects (pearl-gtd-horizons--collect-all-projects))
         (classified (pearl-gtd-horizons--classify-projects projects))
         (critical (nth 0 classified))
         (partial (nth 1 classified))
         (aligned (nth 2 classified))
         (multi (nth 3 classified))
         (no-project (pearl-gtd-horizons--collect-no-project-actions))
         (total-proj (length projects))
         (orphaned (length critical))
         (partial-count (length partial))
         (aligned-count (length aligned)))
    (with-current-buffer (get-buffer-create buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (setq-local header-line-format
                  "Horizon View | 3=L3, 4=L4, 5=L5, 6=L6 | RET=project actions | g=refresh | q=quit")

      (insert "#+TITLE: Horizon Alignment View\n\n")

      ;; Health dashboard
      (insert (format "Health: %d Projects | %d Orphaned (no horizon) | %d Partial (L3 only) | %d Aligned | %d No-Project Actions\n\n"
                      total-proj orphaned partial-count aligned-count (length no-project)))

      ;; Critical: No horizon
      (insert "** Critical: Projects Without Any Horizon\n")
      (insert "| Project | Total | Todo | Done | L6 Purpose | L5 Vision | L4 Goal | L3 Area |\n")
      (insert "|---------+-------+------+------+------------+-----------+---------+---------|\n")
      (if (null critical)
          (insert "| (No entries) | | | | | | | |\n")
        (dolist (proj critical)
          (pearl-gtd-horizons--insert-project-row proj)))
      (org-table-align)
      (insert "\n")

      ;; Partial: L3 only
      (insert "** Partial: Projects Missing Higher Horizons\n")
      (insert "| Project | Total | Todo | Done | L6 Purpose | L5 Vision | L4 Goal | L3 Area |\n")
      (insert "|---------+-------+------+------+------------+-----------+---------+---------|\n")
      (if (null partial)
          (insert "| (No entries) | | | | | | | |\n")
        (dolist (proj partial)
          (pearl-gtd-horizons--insert-project-row proj)))
      (org-table-align)
      (insert "\n")

      ;; Aligned: Complete
      (insert "** Aligned Projects\n")
      (insert "| Project | Total | Todo | Done | L6 Purpose | L5 Vision | L4 Goal | L3 Area |\n")
      (insert "|---------+-------+------+------+------------+-----------+---------+---------|\n")
      (if (null aligned)
          (insert "| (No entries) | | | | | | | |\n")
        (dolist (proj aligned)
          (pearl-gtd-horizons--insert-project-row proj)))
      (org-table-align)
      (insert "\n")

      ;; Multi-horizon
      (insert "** Multi-Horizon Projects\n")
      (insert "| Project | Total | Todo | Done | L6 Purpose | L5 Vision | L4 Goal | L3 Area |\n")
      (insert "|---------+-------+------+------+------------+-----------+---------+---------|\n")
      (if (null multi)
          (insert "| (No entries) | | | | | | | |\n")
        (dolist (proj multi)
          (pearl-gtd-horizons--insert-project-row proj)))
      (org-table-align)
      (insert "\n")

      ;; No-project actions
      (insert "** No-Project Actions (L3 Area Only)\n")
      (insert "| Headline | Status | Context | L3 Area |\n")
      (insert "|----------+--------+---------+---------|\n")
      (if (null no-project)
          (insert "| (No entries) | | | |\n")
        (dolist (action no-project)
          (pearl-gtd-horizons--insert-no-project-row action)))
      (org-table-align)
      (insert "\n")

      (setq buffer-read-only t)
      (goto-char (point-min)))
    (pop-to-buffer buffer-name)
    (pearl-gtd-horizons-view-mode 1)))

(defun pearl-gtd-horizons--data-row-boundaries ()
  "Return cons cell (FIRST-DATA-ROW . LAST-DATA-ROW) positions."
  (save-excursion
    (goto-char (point-min))
    (while (and (not (eobp))
                (or (looking-at "|[-+]")
                    (looking-at "| Project[ \t]*|")
                    (looking-at "| Headline[ \t]*|")
                    (not (looking-at "|"))))
      (forward-line 1))
    (let ((first-data (line-beginning-position)))
      (goto-char (point-max))
      (forward-line -1)
      (while (and (not (bobp))
                  (or (looking-at "|[-+]")
                      (looking-at "| Project[ \t]*|")
                      (looking-at "| Headline[ \t]*|")
                      (not (looking-at "|"))
                      (looking-at "^$")))
        (forward-line -1))
      (cons first-data (line-beginning-position)))))

(pearl-gtd-core-define-table-navigators
  "pearl-gtd-horizons"
  #'pearl-gtd-horizons--data-row-boundaries
  "| Project[ \t]*|")

(defvar pearl-gtd-horizons-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "RET") #'pearl-gtd-horizons--goto-project-at-point)
    (define-key map (kbd "g") #'pearl-gtd-horizons--view)
    (define-key map (kbd "n") #'pearl-gtd-horizons--next-row)
    (define-key map (kbd "p") #'pearl-gtd-horizons--previous-row)
    (define-key map (kbd "j") #'pearl-gtd-horizons--next-row)
    (define-key map (kbd "k") #'pearl-gtd-horizons--previous-row)
    (define-key map (kbd "3") #'pearl-gtd-horizons--edit-area-at-point)
    (define-key map (kbd "4") #'pearl-gtd-horizons--edit-goal-at-point)
    (define-key map (kbd "5") #'pearl-gtd-horizons--edit-vision-at-point)
    (define-key map (kbd "6") #'pearl-gtd-horizons--edit-purpose-at-point)
    map))

(define-minor-mode pearl-gtd-horizons-view-mode
  "Minor mode for horizon alignment matrix view."
  :init-value nil
  :lighter " Pearl-Horizons"
  :keymap pearl-gtd-horizons-view-mode-map
  :interactive nil)

(defun pearl-gtd-horizons--goto-project-at-point ()
  "Show project task sub-view for project at point."
  (interactive)
  (let ((project (pearl-gtd-horizons--get-project-at-point)))
    (when project
      (pearl-gtd-review--show-project-tasks project))))

;; Horizon editing keybindings are now in pearl-gtd-horizons-view-mode-map

(provide 'pearl-gtd-horizons)

;;; pearl-gtd-horizons.el ends here
