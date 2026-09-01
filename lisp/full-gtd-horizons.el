;;; full-gtd-horizons.el --- Horizon system for full-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the Horizon system for GTD (L3 Area through L6 Purpose/Principles).
;; Hierarchy: L6 Purpose -> L5 Vision -> L4 Goal -> L3 Area -> Projects -> Actions.
;; L6 contains both Purpose and Principle (edited together via key '6' in review mode);
;; Principle requires Purpose to be set first.
;; Provides horizon alignment matrix view for reviewing vertical alignment.
;;
;; The horizon view displays projects in a matrix format:
;; - Rows: Projects (grouped by alignment status)
;; - Columns: L6 Purpose, L5 Vision, L4 Goal, L3 Area
;; - Empty cells indicate gaps in vertical alignment
;; - No-project actions shown separately (L3 Area only)
;;
;; In the matrix view, press 'A' to archive a completed project.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'full-gtd-init)
(require 'full-gtd-core)
(require 'full-gtd-domain)
(require 'full-gtd-state)
(require 'full-gtd-ui)
(require 'full-gtd-project-utils)

(defun full-gtd-horizons--get-project-horizon (project property)
  "Get horizon PROPERTY value for PROJECT from any of its actions.
PROPERTY should be one of:
L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE, L6_PRINCIPLE.
Returns the first non-empty value found among project actions."
  (let ((file-path (expand-file-name "action.org" full-gtd-init-base-directory))
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
                 (let ((projects (full-gtd-core--split-values proj)))
                   (when (member project projects)
                     (let ((v (org-entry-get nil property)))
                       (when (and v (not (string= v "")))
                         (setq value v)
                         (throw 'found value))))))))
           nil nil))))
    value))

(defun full-gtd-horizons--set-project-horizon (project property value)
  "Set horizon PROPERTY to VALUE for all actions in PROJECT.
PROPERTY should be one of:
L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE, L6_PRINCIPLE.
Returns count of modified entries.
Handles multi-project tasks by preserving horizons from other projects."
  (let ((count 0)
        (project-horizons (make-hash-table :test 'equal)))
    (full-gtd-state--with-transaction '("action.org")
      (full-gtd-state--with-file-buffer "action.org"
        ;; First pass: collect current horizons for all projects
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (let ((projects (full-gtd-core--split-values proj))
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
               (let ((projects (full-gtd-core--split-values proj)))
                 (when (member project projects)
                   ;; Collect unique horizon values from all projects this task belongs to
                   (let ((all-values nil)
                         (values nil))
                     (dolist (p projects)
                       (let ((v (gethash p project-horizons)))
                         (when (and v (not (string= v "")))
                           (setq all-values
                                 (nconc all-values (full-gtd-core--split-values v))))))
                     ;; Deduplicate preserving insertion order
                     (dolist (v all-values)
                       (unless (member v values)
                         (push v values)))
                     (setq values (nreverse values))
                     (if values
                         (org-entry-put nil property (full-gtd-core--join-values values))
                       (org-delete-property property))
                     (cl-incf count)))))))
         nil nil)))
    count))

(defun full-gtd-horizons--check-hierarchy-constraint (project level)
  "Check hierarchy constraint for setting LEVEL horizon for PROJECT.
PROJECT is project name string (external input, must be string).
LEVEL is symbol: \\='area, \\='goal, \\='vision, \\='purpose, or \\='principle."
  (cl-assert (stringp project) t "Internal: project must be string")
  (let ((existing-horizons
         (list (cons 'L3_AREA (full-gtd-horizons--get-project-horizon project "L3_AREA"))
               (cons 'L4_GOAL (full-gtd-horizons--get-project-horizon project "L4_GOAL"))
               (cons 'L5_VISION (full-gtd-horizons--get-project-horizon project "L5_VISION"))
               (cons 'L6_PURPOSE (full-gtd-horizons--get-project-horizon project "L6_PURPOSE"))
               (cons 'L6_PRINCIPLE (full-gtd-horizons--get-project-horizon project "L6_PRINCIPLE")))))
    (car (full-gtd-domain--check-hierarchy-constraint existing-horizons level))))

(defun full-gtd-horizons--get-project-at-point ()
  "Get project name from text property in current table row."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (project nil))
      (while (and (not project) (< (point) end))
        (setq project (get-text-property (point) 'full-gtd-project))
        (forward-char 1))
      project)))

(defun full-gtd-horizons--edit-horizon-at-point (level &optional project)
  "Edit horizon LEVEL for PROJECT at point.
LEVEL should be a symbol:
  \\='area, \\='goal, \\='vision, \\='purpose, or \\='principle.
Supports multiple values separated by semicolon."
  (let* ((project (or project
                      (full-gtd-horizons--get-project-at-point))))
    (unless project
      (error "Horizons are managed at project level.  Use M-x full-gtd-horizons-view to edit them"))
    (when project
      (let* ((property (full-gtd-horizons--level-to-property level))
             (current-value (full-gtd-horizons--get-project-horizon project property))
             (current-values-display (or current-value ""))
             (prompt (format "Horizon %s (empty to remove, use ; to separate multiple): "
                             (cond ((eq level 'area)      "L3 Area")
                                   ((eq level 'goal)      "L4 Goal")
                                   ((eq level 'vision)    "L5 Vision")
                                   ((eq level 'purpose)   "L6 Purpose")
                                   ((eq level 'principle) "L6 Principle")
                                   (t (symbol-name level)))))
             (new-value (full-gtd-core-read-property-with-completion
                         prompt (full-gtd-horizons--level-to-symbol level)
                         current-values-display)))
        ;; Check hierarchy constraint
        (unless (full-gtd-horizons--check-hierarchy-constraint project level)
          (error "%s must be set first"
                 (cond ((eq level 'vision)    "L4 Goal")
                       ((eq level 'purpose)   "L5 Vision")
                       ((eq level 'principle) "L6 Purpose")
                       (t "Previous horizon"))))
        (let ((count (full-gtd-horizons--set-project-horizon project property new-value)))
          (message "Set %s horizon for %d actions in project %s"
                   (cond ((eq level 'area)      "L3 Area")
                         ((eq level 'goal)      "L4 Goal")
                         ((eq level 'vision)    "L5 Vision")
                         ((eq level 'purpose)   "L6 Purpose")
                         ((eq level 'principle) "L6 Principle")
                         (t (symbol-name level)))
                   count project))
        (full-gtd-horizons--view)
        project))))

(defun full-gtd-horizons--level-to-property (level)
  "Convert LEVEL symbol to property string."
  (pcase level
    ('area "L3_AREA")
    ('goal "L4_GOAL")
    ('vision "L5_VISION")
    ('purpose "L6_PURPOSE")
    ('principle "L6_PRINCIPLE")
    (_ (error "Internal: unknown horizon level %S" level))))

(defun full-gtd-horizons--level-to-symbol (level)
  "Convert LEVEL symbol to property type symbol."
  (pcase level
    ('area 'l3)
    ('goal 'l4)
    ('vision 'l5)
    ('purpose 'l6)
    ('principle 'principle)
    (_ (error "Internal: unknown horizon level %S" level))))

(defun full-gtd-horizons--edit-area-at-point ()
  "Edit L3 Area horizon for project at point."
  (interactive)
  (full-gtd-horizons--edit-horizon-at-point 'area))

(defun full-gtd-horizons--edit-goal-at-point ()
  "Edit L4 Goal horizon for project at point."
  (interactive)
  (full-gtd-horizons--edit-horizon-at-point 'goal))

(defun full-gtd-horizons--edit-vision-at-point ()
  "Edit L5 Vision horizon for project at point."
  (interactive)
  (full-gtd-horizons--edit-horizon-at-point 'vision))

(defun full-gtd-horizons--edit-purpose-at-point ()
  "Edit L6 Purpose and Principle horizons for project at point.
Prompts for Purpose first, then immediately prompts for Principle."
  (interactive)
  (let ((project (full-gtd-horizons--get-project-at-point)))
    (when project
      (full-gtd-horizons--edit-horizon-at-point 'purpose project)
      (full-gtd-horizons--edit-horizon-at-point 'principle project))))

(defun full-gtd-horizons--edit-principle-at-point ()
  "Edit L6 Principle horizon for project at point."
  (interactive)
  (full-gtd-horizons--edit-horizon-at-point 'principle))

(defun full-gtd-horizons--archive-project-at-point ()
  "Archive project at point from horizon view."
  (interactive)
  (let ((project (full-gtd-horizons--get-project-at-point)))
    (unless project
      (error "No project at point"))
    (full-gtd-project-utils--archive-project project)
    (full-gtd-horizons--view)))

(defun full-gtd-horizons--classify-projects (projects)
  "Classify PROJECTS into categories based on horizon alignment.
Returns (CRITICAL PARTIAL ALIGNED MULTI) where each is a list of projects."
  (let ((critical '())
        (partial '())
        (aligned '())
        (multi '()))
    (dolist (proj projects)
      (let* ((l6-purpose (nth 3 (cdr proj)))
             (l6-principle (nth 4 (cdr proj)))
             (l5 (nth 5 (cdr proj)))
             (l4 (nth 6 (cdr proj)))
             (l3 (nth 7 (cdr proj)))
             (has-l6-purpose (and l6-purpose (not (string= l6-purpose ""))))
             (has-l6-principle (and l6-principle (not (string= l6-principle ""))))
             (has-l5 (and l5 (not (string= l5 ""))))
             (has-l4 (and l4 (not (string= l4 ""))))
             (has-l3 (and l3 (not (string= l3 ""))))
             (multi-p (or (and l6-purpose (string-match-p "[;；]" l6-purpose))
                         (and l6-principle (string-match-p "[;；]" l6-principle))
                         (and l5 (string-match-p "[;；]" l5))
                         (and l4 (string-match-p "[;；]" l4))
                         (and l3 (string-match-p "[;；]" l3)))))
        (cond
         ((and (not has-l6-purpose) (not has-l6-principle) (not has-l5) (not has-l4) (not has-l3))
          (push proj critical))
         ((and (not has-l6-purpose) (not has-l6-principle) (not has-l5) (not has-l4) has-l3)
          (push proj partial))
         ((and has-l6-purpose has-l5 has-l4 has-l3)
          (push proj aligned))
         (multi-p
          (push proj multi))
         (t
          (push proj partial)))))
    (list (nreverse critical) (nreverse partial) (nreverse aligned) (nreverse multi))))

(defun full-gtd-horizons--insert-project-row (proj)
  "Insert table row for PROJ."
  (let* ((name (car proj))
         (total (nth 0 (cdr proj)))
         (todo (nth 1 (cdr proj)))
         (done (nth 2 (cdr proj)))
         (l6-purpose (or (nth 3 (cdr proj)) ""))
         (l6-principle (or (nth 4 (cdr proj)) ""))
         (l5 (or (nth 5 (cdr proj)) ""))
         (l4 (or (nth 6 (cdr proj)) ""))
         (l3 (or (nth 7 (cdr proj)) "")))
    (let ((l6-purpose-display (string-join (full-gtd-core--split-values l6-purpose) "; "))
          (l6-principle-display (string-join (full-gtd-core--split-values l6-principle) "; "))
          (l5-display (string-join (full-gtd-core--split-values l5) "; "))
          (l4-display (string-join (full-gtd-core--split-values l4) "; "))
          (l3-display (string-join (full-gtd-core--split-values l3) "; ")))
      (full-gtd-ui--insert-table-row name nil "action.org"
                                      (list total todo done l6-purpose-display l6-principle-display l5-display l4-display l3-display)
                                      t))))

(defun full-gtd-horizons--insert-no-project-row (action)
  "Insert table row for no-project ACTION."
  (let* ((head (nth 0 action))
         (status (nth 1 action))
         (context (nth 2 action))
         (l3 (or (nth 3 action) ""))
         (l3-display (string-join (full-gtd-core--split-values l3) "; ")))
    (full-gtd-ui--insert-table-row head nil "action.org"
                                    (list status context l3-display)
                                    nil)))

(defun full-gtd-horizons--view ()
  "Display horizon alignment matrix view."
  (let* ((buffer-name "*Full-GTD Horizon View*")
         (anchor (when (get-buffer buffer-name)
                   (with-current-buffer (get-buffer buffer-name)
                     (full-gtd-ui--anchor-at-point))))
         (projects (full-gtd-project-utils--collect-project-statistics))
         (classified (full-gtd-horizons--classify-projects projects))
         (critical (nth 0 classified))
         (partial (nth 1 classified))
         (aligned (nth 2 classified))
         (multi (nth 3 classified))
         (no-project (full-gtd-project-utils--collect-no-project-actions))
         (total-proj (length projects))
         (orphaned (length critical))
         (partial-count (length partial))
         (aligned-count (length aligned))
         (empty-heading-markers '()))
    ;; Calculate health score based on action-level horizon coverage
    (let ((health-score
           (let ((total-score 0)
                 (total-actions 0))
             ;; Projects: each action inherits project horizons
             (dolist (proj projects)
               (let* ((data (cdr proj))
                      (action-count (nth 0 data))
                      (l6-purpose (nth 3 data))
                      (l6-principle (nth 4 data))
                      (l5 (nth 5 data))
                      (l4 (nth 6 data))
                      (l3 (nth 7 data))
                      (proj-score 0))
                 (when (and l6-purpose (not (string= l6-purpose ""))) (setq proj-score (+ proj-score 20)))
                 (when (and l6-principle (not (string= l6-principle ""))) (setq proj-score (+ proj-score 20)))
                 (when (and l5 (not (string= l5 ""))) (setq proj-score (+ proj-score 30)))
                 (when (and l4 (not (string= l4 ""))) (setq proj-score (+ proj-score 20)))
                 (when (and l3 (not (string= l3 ""))) (setq proj-score (+ proj-score 10)))
                 (setq total-score (+ total-score (* proj-score action-count)))
                 (setq total-actions (+ total-actions action-count))))
             ;; No-project actions: only L3 possible
             (dolist (action no-project)
               (let ((l3 (nth 3 action)))
                 (when (and l3 (not (string= l3 "")))
                   (setq total-score (+ total-score 10)))
                 (setq total-actions (1+ total-actions))))
             ;; Calculate percentage
             (if (zerop total-actions)
                 100
               (/ (* total-score 100) (* total-actions 100))))))
      (with-current-buffer (get-buffer-create buffer-name)
        (setq buffer-read-only nil)
        (erase-buffer)
        (org-mode)
        (setq-local header-line-format
                    "Horizon View | 3=L3, 4=L4, 5=L5, 6=L6 | A=archive | RET=project actions | g=refresh | q=quit")

        (insert "#+TITLE: Horizon Alignment View\n\n")

        ;; Health dashboard with score
        (insert (format "Health: %d%%\n" health-score))
        (insert (format "%d Projects | %d Orphaned | %d Partial | %d Aligned | %d Multi | %d No-Project Actions\n\n"
                        total-proj orphaned partial-count aligned-count (length multi) (length no-project)))

        ;; Critical: No horizon
        (let ((heading-marker (copy-marker (point))))
          (insert "** Critical: Projects Without Any Horizon\n")
          (unless critical
            (push heading-marker empty-heading-markers))
          (insert "| Project | Total | Todo | Done | L6 Purpose | L6 Principle | L5 Vision | L4 Goal | L3 Area |\n")
          (insert "|---------+-------+------+------+------------+--------------+-----------+---------+---------|\n")
          (if (null critical)
              (insert "| (No entries) | | | | | | | | |\n")
            (dolist (proj critical)
              (full-gtd-horizons--insert-project-row proj)))
          (org-table-align)
          (insert "\n"))

        ;; Partial: L3 only
        (let ((heading-marker (copy-marker (point))))
          (insert "** Partial: Projects Missing Higher Horizons\n")
          (unless partial
            (push heading-marker empty-heading-markers))
          (insert "| Project | Total | Todo | Done | L6 Purpose | L6 Principle | L5 Vision | L4 Goal | L3 Area |\n")
          (insert "|---------+-------+------+------+------------+--------------+-----------+---------+---------|\n")
          (if (null partial)
              (insert "| (No entries) | | | | | | | | |\n")
            (dolist (proj partial)
              (full-gtd-horizons--insert-project-row proj)))
          (org-table-align)
          (insert "\n"))

        ;; Aligned: Complete
        (let ((heading-marker (copy-marker (point))))
          (insert "** Aligned Projects\n")
          (unless aligned
            (push heading-marker empty-heading-markers))
          (insert "| Project | Total | Todo | Done | L6 Purpose | L6 Principle | L5 Vision | L4 Goal | L3 Area |\n")
          (insert "|---------+-------+------+------+------------+--------------+-----------+---------+---------|\n")
          (if (null aligned)
              (insert "| (No entries) | | | | | | | | |\n")
            (dolist (proj aligned)
              (full-gtd-horizons--insert-project-row proj)))
          (org-table-align)
          (insert "\n"))

        ;; Multi-horizon
        (let ((heading-marker (copy-marker (point))))
          (insert "** Multi-Horizon Projects\n")
          (unless multi
            (push heading-marker empty-heading-markers))
          (insert "| Project | Total | Todo | Done | L6 Purpose | L6 Principle | L5 Vision | L4 Goal | L3 Area |\n")
          (insert "|---------+-------+------+------+------------+--------------+-----------+---------+---------|\n")
          (if (null multi)
              (insert "| (No entries) | | | | | | | | |\n")
            (dolist (proj multi)
              (full-gtd-horizons--insert-project-row proj)))
          (org-table-align)
          (insert "\n"))

        ;; No-project actions
        (let ((heading-marker (copy-marker (point))))
          (insert "** No-Project Actions (L3 Area Only)\n")
          (unless no-project
            (push heading-marker empty-heading-markers))
          (insert "| Headline | Status | Context | L3 Area |\n")
          (insert "|----------+--------+---------+---------|\n")
          (if (null no-project)
              (insert "| (No entries) | | | |\n")
            (dolist (action no-project)
              (full-gtd-horizons--insert-no-project-row action)))
          (org-table-align)
          (insert "\n"))

          ;; Fold empty sections so their headings collapse automatically.
          (dolist (marker empty-heading-markers)
            (when (marker-position marker)
              (goto-char marker)
              (outline-hide-subtree)
              (set-marker marker nil)))
          (setq buffer-read-only t)
          (goto-char (point-min))
          (full-gtd-ui--restore-point-anchor anchor))
      (pop-to-buffer buffer-name)
      (full-gtd-horizons-view-mode 1))))

(defun full-gtd-horizons--data-row-boundaries ()
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

(full-gtd-core-define-table-navigators
  "full-gtd-horizons"
  #'full-gtd-horizons--data-row-boundaries
  "| Project[ \t]*|")

(defun full-gtd-horizons--refresh ()
  "Refresh the horizon alignment view."
  (interactive)
  (full-gtd-horizons--view))

(defvar full-gtd-horizons-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "RET") #'full-gtd-horizons--goto-project-at-point)
    (define-key map (kbd "g") #'full-gtd-horizons--refresh)
    (define-key map (kbd "n") #'full-gtd-horizons--next-row)
    (define-key map (kbd "p") #'full-gtd-horizons--previous-row)
    (define-key map (kbd "j") #'full-gtd-horizons--next-row)
    (define-key map (kbd "k") #'full-gtd-horizons--previous-row)
    (define-key map (kbd "3") #'full-gtd-horizons--edit-area-at-point)
    (define-key map (kbd "4") #'full-gtd-horizons--edit-goal-at-point)
    (define-key map (kbd "5") #'full-gtd-horizons--edit-vision-at-point)
    (define-key map (kbd "6") #'full-gtd-horizons--edit-purpose-at-point)
    (define-key map (kbd "A") #'full-gtd-horizons--archive-project-at-point)
    map))

(define-minor-mode full-gtd-horizons-view-mode
  "Minor mode for horizon alignment matrix view."
  :init-value nil
  :lighter " Full-Horizons"
  :keymap full-gtd-horizons-view-mode-map
  :interactive nil)

(defun full-gtd-horizons--goto-project-at-point ()
  "Show project task sub-view for project at point."
  (interactive)
  (let ((project (full-gtd-horizons--get-project-at-point)))
    (when project
      (full-gtd-project-utils--show-project-tasks project))))

;; Horizon editing keybindings are now in full-gtd-horizons-view-mode-map

(defun full-gtd-horizons--sync-entry-horizons ()
  "Synchronize current entry's horizons with its project(s).
Current entry must be an Org entry with an ID, located in any Org buffer
\(typically action.org, inbox.org during processing, or someday.org during
activation).  Reads other actions from action.org, computes the
project-level horizon for each level via the domain layer, and updates
the current entry's L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE, and
L6_PRINCIPLE accordingly.

Single project → intersection of that project's other actions' values
\(actions lacking the level are ignored).  Multiple projects → union of
per-project horizons.  No derivable value removes the property.

Project membership is read from the current entry at call time, so call
this after PROJECT is set/removed but before moving the entry."
  (let* ((current-id (org-entry-get nil "ID"))
         (project-value (org-entry-get nil "PROJECT"))
         (action-file (expand-file-name "action.org" full-gtd-init-base-directory))
         (other-entries '()))
    (unless current-id
      (error "Internal: cannot sync horizons for entry without ID"))
    (org-back-to-heading)
    (let ((projects (full-gtd-core--split-values (or project-value ""))))
      (if (null projects)
          ;; No project: clear all horizon properties without scanning.
          (dolist (level '("L3_AREA" "L4_GOAL" "L5_VISION" "L6_PURPOSE" "L6_PRINCIPLE"))
            (org-delete-property level))
        (when (file-exists-p action-file)
          (with-temp-buffer
            (insert-file-contents action-file)
            (org-mode)
            (org-map-entries
             (lambda ()
               (let ((id (org-entry-get nil "ID"))
                     (proj (org-entry-get nil "PROJECT")))
                 (when (and id (not (string= id current-id)))
                   (push (cons (full-gtd-core--split-values (or proj ""))
                               (list (cons "L3_AREA" (org-entry-get nil "L3_AREA"))
                                     (cons "L4_GOAL" (org-entry-get nil "L4_GOAL"))
                                     (cons "L5_VISION" (org-entry-get nil "L5_VISION"))
                                     (cons "L6_PURPOSE" (org-entry-get nil "L6_PURPOSE"))
                                     (cons "L6_PRINCIPLE" (org-entry-get nil "L6_PRINCIPLE"))))
                         other-entries))))
             nil nil)))
        (let ((computed (full-gtd-domain--compute-entry-horizons
                         projects other-entries)))
          (dolist (level '("L3_AREA" "L4_GOAL" "L5_VISION" "L6_PURPOSE" "L6_PRINCIPLE"))
            (let ((value (cdr (assoc level computed))))
              (if value
                  (org-entry-put nil level value)
                (org-delete-property level)))))))))

(provide 'full-gtd-horizons)

;;; full-gtd-horizons.el ends here
