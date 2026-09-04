;;; full-gtd-map.el --- Focused star-shaped map view for Full-GTD  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: DeepSeek:deepseek-v4-flash
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Provides a single-project "star map" layout used inside the horizon
;; view.  It replaces the old project table.  The center is the project
;; name; horizon levels are listed above it, actions below it.  All
;; relations are rendered as left-aligned column edges.  Layout is
;; deliberately not a tree: only each node's relation to the central
;; project is displayed.  Each block is drawn inside a frame of top
;; and bottom rules plus a left rule, so consecutive projects are
;; clearly separated.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'full-gtd-domain)
(require 'full-gtd-table)

(defconst full-gtd-map-prop-kind 'full-gtd-map-kind
  "Text property key for the row kind on map rows.")

(defconst full-gtd-map-prop-level 'full-gtd-map-level
  "Text property key for the horizon level symbol on map rows.")

(defface full-gtd-map-done-face
  '((t :strike-through t))
  "Face for DONE actions in the star map."
  :group 'full-gtd)

(defun full-gtd-map--action-done-p (action)
  "Return non-nil if ACTION alist is done."
  (cdr (assq 'done-p action)))

(defun full-gtd-map--todo-count (actions)
  "Return number of non-done entries in ACTIONS."
  (cl-count-if-not #'full-gtd-map--action-done-p actions))

(defun full-gtd-map--close-tree-lines (n &optional indent)
  "Return closing tree prefixes for N consecutive rows.
The first line uses ├── because the project line above continues
into the branch, middle lines use ├──, and the last line closes
the block with └──.  For N=1, uses └── (a single leaf).  For
N<=0, returns the empty list.  Each prefix is indented by INDENT
spaces (default 2)."
  (let ((pad (make-string (or indent 2) ?\s)))
    (cond
     ((<= n 0) '())
     ((= n 1) (list (concat pad "└── ")))
     (t (append (make-list (1- n) (concat pad "├── "))
                (list (concat pad "└── ")))))))

(defun full-gtd-map--open-tree-lines (n &optional indent)
  "Return open-ended tree prefixes for N consecutive rows.
First line uses ┌── and every following line uses ├──; the branch
is never closed with └── because the project line continues the
block below the horizons.  For N=1, returns a single ┌── line.
For N<=0, returns the empty list.  Each prefix is indented by
INDENT spaces (default 2)."
  (let ((pad (make-string (or indent 2) ?\s)))
    (cond
     ((<= n 0) '())
     ((= n 1) (list (concat pad "┌── ")))
     (t (cons (concat pad "┌── ")
              (make-list (1- n) (concat pad "├── ")))))))

(defun full-gtd-map--horizon-row (prefix cell)
  "Build a row cons with PREFIX for horizon CELL.
CELL is a (LABEL VALUE KIND) list; KIND is a level symbol
\(e.g. `area')."
  (let ((text (format "%s%-14s%s"
                      prefix (nth 0 cell) (nth 1 cell))))
    (cons text (list :kind 'horizon :level (nth 2 cell)))))

(defun full-gtd-map--horizon-lines (stats)
  "Return map rows for horizon STATS.
STATS is the (TOTAL TODO DONE L6P L6PR L5 L4 L3) list as produced by
`full-gtd-project-utils--collect-project-statistics'.  For each
level, one row per value is emitted; empty levels are omitted.
All horizon rows of one project form an open branch: the first row
uses ┌── and every other row uses ├──; the branch is not closed
because the project line continues below.  The returned collection
is (TEXT . PROPS) pairs."
  (let ((cells '()))
    (dolist (lv (list (list "L6 Purpose" 'purpose (or (nth 3 stats) ""))
                      (list "L6 Principle" 'principle (or (nth 4 stats) ""))
                      (list "L5 Vision" 'vision (or (nth 5 stats) ""))
                      (list "L4 Goal" 'goal (or (nth 6 stats) ""))
                      (list "L3 Area" 'area (or (nth 7 stats) ""))))
      (dolist (value (full-gtd-domain--split-values (nth 2 lv)))
        (push (list (nth 0 lv) value (nth 1 lv)) cells)))
    (setq cells (nreverse cells))
    (when cells
      (cl-mapcar #'full-gtd-map--horizon-row
                 (full-gtd-map--open-tree-lines (length cells))
                 cells))))

(defun full-gtd-map--action-row (prefix action)
  "Build a row cons with PREFIX for ACTION.
ACTION is an action alist as produced by
`full-gtd-domain--group-actions-by-project'."
  (let* ((status (or (cdr (assq 'status action)) ""))
         (headline (or (cdr (assq 'headline action)) ""))
         (context (or (cdr (assq 'context action)) ""))
         (text (format "%s%-7s%s%s"
                       prefix status headline
                       (if (string-blank-p context) "" (concat " " context)))))
    (cons text
          (list :kind 'action
                :done (full-gtd-map--action-done-p action)
                :id (cdr (assq 'id action))))))

(defun full-gtd-map--action-lines (actions fold)
  "Return visible rows for ACTIONS according to FOLD state.
FOLD is `collapsed', `todo' or `all'.  The semantics:
    collapsed -> a single `└── …' ellipsis row
    todo      -> all non-DONE actions
    all       -> all actions.
Action rows are indented deeper than horizon rows."
  (if (or (null actions)
          (eq fold 'collapsed))
      (list (cons "    └── …" (list :kind 'ellipsis)))
    (let* ((visible (if (eq fold 'todo)
                        (cl-remove-if #'full-gtd-map--action-done-p actions)
                      actions))
           (prefixes (full-gtd-map--close-tree-lines (length visible) 4)))
      (cl-mapcar #'full-gtd-map--action-row prefixes visible))))

(defun full-gtd-map--frame-row (row)
  "Return ROW with the left frame rule `│ ' prepended to its text."
  (cons (concat "│ " (car row)) (cdr row)))

(defun full-gtd-map--render-block (name stats actions fold)
  "Render a complete star-map block for project NAME.
STATS is the project statistics list (TOTAL TODO DONE L6P L6PR L5
L4 L3).  ACTIONS is a list of action alists (see
`full-gtd-domain--group-actions-by-project').  FOLD is `collapsed',
`todo' or `all'.  Return (ROWS . NAME), where ROWS is a list of
\\(TEXT . PROPS) elements.  The block is framed by a rounded top
rule `╭─...', a bottom rule `╰─...' and a left rule `│ ' spanning
horizons through actions, so consecutive project blocks stay
clearly separated."
  (let* ((horizon-rows (full-gtd-map--horizon-lines stats))
         (action-rows (if (and (eq fold 'todo)
                               (= (full-gtd-map--todo-count actions) 0))
                          (full-gtd-map--action-lines actions 'all)
                        (full-gtd-map--action-lines actions fold)))
         (project-text (format "Project: %s (%d/%d done)"
                               name (nth 2 stats) (nth 0 stats)))
         ;; Frame width follows the widest row in the block, not just
         ;; the project line, so long horizon values stay inside.
         (rule (make-string
                (+ 4 (apply #'max (string-width project-text)
                            (mapcar (lambda (row) (string-width (car row)))
                                    (append horizon-rows action-rows))))
                ?─))
         (line-rows (append
                     (list (cons (concat "╭" rule) '()))
                     (mapcar #'full-gtd-map--frame-row
                             (append horizon-rows
                                     (list (cons project-text
                                                 (list :kind 'project)))
                                     action-rows))
                     (list (cons (concat "╰" rule) '())))))
    (cons line-rows name)))

(defun full-gtd-map--insert-block (block)
  "Insert BLOCK (from `full-gtd-map--render-block') at point.
Attaches `full-gtd-table-prop-project', `full-gtd-map-prop-kind',
`full-gtd-map-prop-level' and ID/done properties to each line."
  (let ((project-name (cdr block)))
    (dolist (row (car block))
      (let* ((text (car row))
             (props (cdr row))
             (start (point)))
        (insert text "\n")
        (let ((end (line-end-position)))
          (put-text-property start end full-gtd-table-prop-project project-name)
          (when props
            (when-let ((kind (plist-get props :kind)))
              (put-text-property start end full-gtd-map-prop-kind kind))
            (when-let ((lv (plist-get props :level)))
              (put-text-property start end full-gtd-map-prop-level lv))
            (when-let ((id (plist-get props :id)))
              (put-text-property start end full-gtd-table-prop-id id)
              (put-text-property start end full-gtd-table-prop-file "action.org"))
            (when (plist-get props :done)
              (add-face-text-property start end 'full-gtd-map-done-face))))))))

(defun full-gtd-map-kind-at-point ()
  "Return the current line's map kind, or nil.
The kind is one of `horizon', `project', `action' or `ellipsis'."
  (get-text-property (point) full-gtd-map-prop-kind))

(defun full-gtd-map-level-at-point ()
  "Return the current horizon level symbol, or nil."
  (get-text-property (point) full-gtd-map-prop-level))

(defun full-gtd-map--anchor-at-point ()
  "Return (PROJECT KIND) for the current line, or nil."
  (let ((project (full-gtd-table-project-at-point))
        (kind (full-gtd-map-kind-at-point)))
    (when (and project kind)
      (list project kind))))

(defun full-gtd-map--goto-anchor (anchor)
  "Restore point to ANCHOR (PROJECT KIND), if present."
  (let ((project (nth 0 anchor))
        (kind (nth 1 anchor)))
    (full-gtd-table--goto-row
     (lambda (pos)
       (and (equal (get-text-property pos full-gtd-table-prop-project) project)
            (eq (get-text-property pos full-gtd-map-prop-kind) kind))))))

(provide 'full-gtd-map)

;;; full-gtd-map.el ends here
