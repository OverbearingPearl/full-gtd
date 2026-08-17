;;; pearl-gtd-project-utils.el --- Project archive and project task view utilities  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: DeepSeek:deepseek-v4-flash
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Shared utilities for archiving projects and viewing project tasks.
;; Used by both pearl-gtd-horizons and pearl-gtd-review to avoid
;; circular dependencies.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)
(require 'pearl-gtd-state)
(require 'pearl-gtd-ui)

(defun pearl-gtd-project-utils--collect-project-entries (proj-name)
  "Collect all entries from action.org belonging to PROJ-NAME.
PROJ-NAME is a string naming the project to search for.
Returns list of entry lists suitable for table display."
  (let* ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
         (entries (pearl-gtd-core-filter-entries file-path nil)))
    (mapcar (lambda (e)
              (list (nth 0 e) (nth 7 e) (nth 8 e)
                    (or (nth 2 e) "") (or (nth 3 e) "") (or (nth 9 e) "")
                    (or (nth 10 e) "") (or (nth 4 e) "") proj-name
                    (or (nth 6 e) "")))
            (cl-remove-if-not
             (lambda (e)
               (let ((proj (nth 5 e)))
                 (and proj (member proj-name (pearl-gtd-core--split-values proj)))))
             entries))))

(defun pearl-gtd-project-utils--archive-project (project)
  "Archive PROJECT from action.org to archive.org.
Archiving is allowed only when all actions of PROJECT are DONE and no
action belongs to any other project alongside PROJECT."
  (let ((action-file (expand-file-name "action.org" pearl-gtd-init-base-directory))
        (archive-file (expand-file-name "archive.org" pearl-gtd-init-base-directory)))
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
      (pearl-gtd-state--with-file-buffer action-file
        (let ((positions '())
              (blocked nil))
          ;; First pass: validate and collect all matching entries.
          (org-map-entries
           (lambda ()
             (let ((proj (org-entry-get nil "PROJECT"))
                   (todo-state (org-get-todo-state)))
               (when (and proj (not (string= proj "")))
                 (let ((projects (pearl-gtd-core--split-values proj)))
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

(defun pearl-gtd-project-utils--show-project-tasks (proj-name)
  "Display all tasks for PROJ-NAME in a dedicated buffer.
PROJ-NAME is a string naming the project to display.
Creates and pops to buffer *Pearl-GTD Project: PROJ-NAME*."
  (let* ((buffer-name (format "*Pearl-GTD Project: %s*" proj-name))
         (entries (pearl-gtd-project-utils--collect-project-entries proj-name))
         (header "| Headline | Status | Scheduled | Deadline | Context | Delegated | Project | Created |\n")
         (sep "|----------+--------+-----------+----------+---------+-----------+---------+---------|\n"))
    (with-current-buffer (get-buffer-create buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (insert (format "* %s\n" proj-name))
      (insert header)
      (insert sep)
      (if (null entries)
          (insert "| (No entries) | | | | | | | |\n")
        (dolist (entry entries)
          (let ((head (nth 0 entry))
                (id (nth 1 entry))
                (file (or (nth 2 entry) "action.org"))
                (fields (nthcdr 3 entry)))
            (pearl-gtd-ui--insert-table-row head id file fields nil))))
      (org-table-align)
      (setq buffer-read-only t)
      (setq-local pearl-gtd-review--current-view-type 'project)
      (setq-local pearl-gtd-review--current-project proj-name)
      (goto-char (point-min)))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-project-utils--collect-project-names ()
  "Return list of all unique project names from action.org."
  (let ((actions-file (expand-file-name "action.org" pearl-gtd-init-base-directory))
        (projects '()))
    (when (file-exists-p actions-file)
      (with-temp-buffer
        (insert-file-contents actions-file)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (dolist (p (pearl-gtd-core--split-values proj))
                 (cl-pushnew p projects :test #'string=)))))
         nil nil)))
    (nreverse projects)))

(defun pearl-gtd-project-utils--collect-project-statistics ()
  "Collect all unique project names from action.org with their stats.
Returns list of (PROJECT-NAME TOTAL TODO DONE L6-PURPOSE L6-PRINCIPLE L5 L4 L3)."
  (let ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
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
               (dolist (p (pearl-gtd-core--split-values proj))
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

(defun pearl-gtd-project-utils--collect-no-project-actions ()
  "Collect TODO actions without project.
Returns list of entry lists, as returned by `pearl-gtd-core-filter-entries'."
  (let* ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
         (entries (pearl-gtd-core-filter-entries file-path (list #'pearl-gtd-core-entry-todo-p))))
    (cl-remove-if-not
     (lambda (e)
       (let ((proj (nth 5 e)))
         (or (null proj) (string= proj ""))))
     entries)))

(defun pearl-gtd-project-utils--collect-project-names ()
  "Return list of all unique project names from action.org."
  (let ((actions-file (expand-file-name "action.org" pearl-gtd-init-base-directory))
        (projects '()))
    (when (file-exists-p actions-file)
      (with-temp-buffer
        (insert-file-contents actions-file)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (dolist (p (pearl-gtd-core--split-values proj))
                 (cl-pushnew p projects :test #'string=)))))
         nil nil)))
    (nreverse projects)))

(defun pearl-gtd-project-utils--collect-project-statistics ()
  "Collect all unique project names from action.org with their stats.
Returns list of (PROJECT-NAME TOTAL TODO DONE L6-PURPOSE L6-PRINCIPLE L5 L4 L3)."
  (let ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
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
               (dolist (p (pearl-gtd-core--split-values proj))
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

(defun pearl-gtd-project-utils--collect-no-project-actions ()
  "Collect TODO actions without project.
Returns list of entry lists, as returned by `pearl-gtd-core-filter-entries'."
  (let* ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
         (entries (pearl-gtd-core-filter-entries file-path (list #'pearl-gtd-core-entry-todo-p))))
    (cl-remove-if-not
     (lambda (e)
       (let ((proj (nth 5 e)))
         (or (null proj) (string= proj ""))))
     entries)))

(provide 'pearl-gtd-project-utils)

;;; pearl-gtd-project-utils.el ends here
