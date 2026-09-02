;;; full-gtd-project-utils.el --- Project archive and project task view utilities  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: DeepSeek:deepseek-v4-flash
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Shared utilities for archiving projects and viewing project tasks.
;; Used by both full-gtd-horizons and full-gtd-review to avoid
;; circular dependencies.
;; The project task sub-view provides row navigation (n/p/j/k),
;; column navigation (f/b/h/l), source jump (RET), and quit (q) via
;; `full-gtd-project-utils-view-mode'.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'full-gtd-init)
(require 'full-gtd-core)
(require 'full-gtd-state)
(require 'full-gtd-table)

(defun full-gtd-project-utils--collect-project-entries (proj-name)
  "Collect all entries from action.org belonging to PROJ-NAME.
PROJ-NAME is a string naming the project to search for.
Returns list of entry lists suitable for table display."
  (let* ((file-path (expand-file-name "action.org" full-gtd-init-base-directory))
         (entries (full-gtd-core-filter-entries file-path nil)))
    (mapcar (lambda (e)
              (list (nth 0 e) (nth 7 e) (nth 8 e)
                    (or (nth 2 e) "") (or (nth 3 e) "") (or (nth 9 e) "")
                    (or (nth 10 e) "") (or (nth 4 e) "") proj-name
                    (or (nth 6 e) "")))
            (cl-remove-if-not
             (lambda (e)
               (let ((proj (nth 5 e)))
                 (and proj (member proj-name (full-gtd-core--split-values proj)))))
             entries))))

(defun full-gtd-project-utils--archive-project (project)
  "Archive PROJECT from action.org to archive.org.
Archiving is allowed only when all actions of PROJECT are DONE and no
action belongs to any other project alongside PROJECT."
  (let ((action-file (expand-file-name "action.org" full-gtd-init-base-directory))
        (archive-file (expand-file-name "archive.org" full-gtd-init-base-directory)))
    (unless (file-exists-p action-file)
      (error "File action.org not found"))
    (let ((archive-buffer (find-file-noselect archive-file)))
      ;; Ensure archive.org has an Org-mode project heading for PROJECT.
      (with-current-buffer archive-buffer
        (org-mode)
        (goto-char (point-min))
        (if (re-search-forward (format "^\\* %s[ \t]*$" (regexp-quote project)) nil t)
            ;; Project heading exists: move to the end of its subtree.
            (progn
              (let ((end (save-excursion (org-end-of-subtree))))
                (goto-char end)
                (when (and (not (bolp)) (not (looking-back "\n" (line-beginning-position))))
                  (insert "\n"))))
          ;; Project heading does not exist: create it at the end.
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "* %s\n" project))))
      ;; Process action.org.
      (full-gtd-state--with-file-buffer action-file
        (let ((positions '())
              (blocked nil))
          ;; First pass: validate and collect all matching entries.
          (org-map-entries
           (lambda ()
             (let ((proj (org-entry-get nil "PROJECT"))
                   (todo-state (org-get-todo-state)))
               (when (and proj (not (string= proj "")))
                 (let ((projects (full-gtd-core--split-values proj)))
                   (when (member project projects)
                     ;; Must be exclusive to this project.
                     (unless (and (= (length projects) 1)
                                  (string= (car projects) project))
                       (setq blocked t))
                     ;; If it is a TODO item, it must already be DONE.
                     (when todo-state
                       (unless (member todo-state org-done-keywords)
                         (setq blocked t)))
                     (push (point) positions))))))
           nil nil)
          (when blocked
            (error "Project %s cannot be archived: it has uncompleted actions or actions shared with other projects" project))
          (unless positions
            (error "No actions found for project %s" project))
          ;; Second pass: cut subtrees from bottom to top and paste them
          ;; under the project heading in archive.org.
          (dolist (pos positions)
            (goto-char pos)
            (org-cut-subtree)
            (with-current-buffer archive-buffer
              ;; Move to correct paste location.
              (goto-char (point-min))
              (re-search-forward (format "^\\* %s[ \t]*$" (regexp-quote project)) nil t)
              (org-end-of-subtree)
              (when (and (not (bolp)) (not (looking-back "\n" (line-beginning-position))))
                (insert "\n"))
              (org-paste-subtree 2)
              (set-buffer-modified-p t)))
          (save-buffer)))
      ;; Save archive.org.
      (with-current-buffer archive-buffer
        (save-buffer)
        (set-buffer-modified-p nil)))
    (message "Project %s archived to archive.org" project)))

(defun full-gtd-project-utils--show-project-tasks (proj-name)
  "Display all tasks for PROJ-NAME in a dedicated buffer.
PROJ-NAME is a string naming the project to display.
Creates and pops to buffer *Full-GTD Project: PROJ-NAME*."
  (let* ((buffer-name (format "*Full-GTD Project: %s*" proj-name))
         (entries (full-gtd-project-utils--collect-project-entries proj-name))
         (parent-buffer (current-buffer)))
    (with-current-buffer (get-buffer-create buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      ;; Set after `org-mode', which clears ordinary buffer-local variables.
      (setq-local full-gtd-project-utils--parent-buffer parent-buffer)
      (insert (format "* %s\n" proj-name))
      (full-gtd-table-insert-header
       '("Headline" "Status" "Scheduled" "Deadline" "Context"
         "Delegated" "Project" "Created"))
      (if (null entries)
          (insert "| (No entries) | | | | | | | |\n")
        (dolist (entry entries)
          (let ((head (nth 0 entry))
                (id (nth 1 entry))
                (file (or (nth 2 entry) "action.org"))
                (fields (nthcdr 3 entry)))
            (full-gtd-table-insert-row head id file fields nil))))
      (org-table-align)
      (setq buffer-read-only t)
      (setq-local full-gtd-review--current-view-type 'project)
      (setq-local full-gtd-review--current-project proj-name)
      (setq-local header-line-format
                  "Project Tasks | n/p/j/k: rows | f/b/h/l: columns | RET: jump | q: return")
      ;; Enable after `org-mode': changing major mode resets buffer-local
      ;; minor mode variables.
      (full-gtd-project-utils-view-mode 1)
      (goto-char (point-min)))
    (pop-to-buffer buffer-name)))

(defun full-gtd-project-utils--collect-project-statistics ()
  "Collect all unique project names from action.org with their stats.
Returns list of (PROJECT-NAME TOTAL TODO DONE L6-PURPOSE L6-PRINCIPLE L5 L4 L3)."
  (let ((file-path (expand-file-name "action.org" full-gtd-init-base-directory))
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
                 (l6-purpose (org-entry-get nil "L6_PURPOSE"))
                 (l6-principle (org-entry-get nil "L6_PRINCIPLE")))
             (when proj
               (dolist (p (full-gtd-core--split-values proj))
                 (let ((data (or (gethash p projects)
                                 (puthash p (list 0 0 0 nil nil nil nil nil) projects))))
                   (cl-incf (nth 0 data))  ; Total
                   (cond
                    ((member todo-state org-done-keywords) (cl-incf (nth 2 data)))
                    ((member todo-state org-not-done-keywords) (cl-incf (nth 1 data))))
                   ;; Store first non-empty horizon value
                   (unless (nth 3 data) (setf (nth 3 data) (and l6-purpose (not (string= l6-purpose "")) l6-purpose)))
                   (unless (nth 4 data) (setf (nth 4 data) (and l6-principle (not (string= l6-principle "")) l6-principle)))
                   (unless (nth 5 data) (setf (nth 5 data) (and l5 (not (string= l5 "")) l5)))
                   (unless (nth 6 data) (setf (nth 6 data) (and l4 (not (string= l4 "")) l4)))
                   (unless (nth 7 data) (setf (nth 7 data) (and l3 (not (string= l3 "")) l3))))))))
         nil nil)))
    ;; Convert hash to list
    (let (result)
      (maphash (lambda (k v)
                 (push (cons k v) result))
               projects)
      result)))

(defun full-gtd-project-utils--collect-no-project-actions ()
  "Collect TODO actions without project.
Returns list of entry lists, as returned by `full-gtd-core-filter-entries'."
  (let* ((file-path (expand-file-name "action.org" full-gtd-init-base-directory))
         (entries (full-gtd-core-filter-entries file-path (list #'full-gtd-core-entry-todo-p))))
    (cl-remove-if-not
     (lambda (e)
       (let ((proj (nth 5 e)))
         (or (null proj) (string= proj ""))))
     entries)))

;;;; Project task sub-view mode

(defvar-local full-gtd-project-utils--parent-buffer nil
  "Buffer from which the current project task sub-view was opened.")

(defun full-gtd-project-utils--goto-task-at-point ()
  "Jump to the task at point in its source file."
  (interactive)
  (let ((entry (full-gtd-table-entry-at-point)))
    (when entry
      (let ((id (car entry))
            (file (cdr entry)))
        (find-file (expand-file-name file full-gtd-init-base-directory))
        (goto-char (point-min))
        (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
          (org-back-to-heading))))))

(defun full-gtd-project-utils--quit-or-return ()
  "Kill the project sub-view buffer and return to its parent view."
  (interactive)
  (let ((parent-buffer full-gtd-project-utils--parent-buffer))
    (kill-buffer)
    (when (buffer-live-p parent-buffer)
      (pop-to-buffer parent-buffer))))

(full-gtd-table-define-navigators "full-gtd-project-utils")

(defvar full-gtd-project-utils-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'full-gtd-project-utils--quit-or-return)
    (define-key map (kbd "n") #'full-gtd-project-utils--next-row)
    (define-key map (kbd "p") #'full-gtd-project-utils--previous-row)
    (define-key map (kbd "j") #'full-gtd-project-utils--next-row)
    (define-key map (kbd "k") #'full-gtd-project-utils--previous-row)
    (define-key map (kbd "f") #'full-gtd-project-utils--next-column)
    (define-key map (kbd "l") #'full-gtd-project-utils--next-column)
    (define-key map (kbd "b") #'full-gtd-project-utils--previous-column)
    (define-key map (kbd "h") #'full-gtd-project-utils--previous-column)
    (define-key map (kbd "RET") #'full-gtd-project-utils--goto-task-at-point)
    map)
  "Keymap for `full-gtd-project-utils-view-mode'.")

(define-minor-mode full-gtd-project-utils-view-mode
  "Minor mode for the project task sub-view."
  :init-value nil
  :lighter " Full-Project"
  :keymap full-gtd-project-utils-view-mode-map
  :interactive nil)

(provide 'full-gtd-project-utils)

;;; full-gtd-project-utils.el ends here
