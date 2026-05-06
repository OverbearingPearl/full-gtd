;;; test-pearl-gtd-planning.el --- User stories: Natural Planning  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for Natural Planning Model.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-planning-user-starts-from-blank-slate
  "User creates a new project from scratch with natural planning."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Project name" prompt) "Launch new website")
             ((string-match "Purpose" prompt) "Establish online presence")
             ((string-match "Principles" prompt) "Keep it simple, mobile-first")
             ((string-match "Vision" prompt) "Modern responsive site with blog")
             ((string-match "Brainstorm" prompt) "done")
             (t ""))))
         ((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Outcome" prompt) "Website live with 5 posts")
             (t "")))))
  :body (pearl-gtd-planning-start-project)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "* Launch new website"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      ":PURPOSE: Establish online presence"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      ":VISION: Modern responsive site with blog")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-planning-user-brainstorms-ideas
  "User brainstorms ideas for existing project."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Existing project\n:PROPERTIES:\n:CREATED: 2026-04-30\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Brainstorm idea" prompt) "Use Hugo static generator")
             ((string-match "Another idea" prompt) "done")
             (t "")))))
  :body (pearl-gtd-planning-brainstorm "Existing project")
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "** Brainstorming"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "- Use Hugo static generator")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-planning-user-organizes-brainstorm-results
  "User organizes brainstormed ideas into actionable components."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Project X\n** Brainstorming\n- Idea 1\n- Idea 2\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Organize" prompt) "group_by_topic")
             (t "")))))
  :body (pearl-gtd-planning-organize-ideas "Project X")
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "** Components")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-planning-user-defines-success-criteria
  "User defines specific success criteria for project."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Project Y\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Success criteria" prompt) "1000 monthly visitors")
             ((string-match "Another criteria" prompt) "done")
             (t "")))))
  :body (pearl-gtd-planning-define-success "Project Y")
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "** Success Criteria"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "- 1000 monthly visitors")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-planning-user-cancels-mid-brainstorm
  "User cancels during brainstorming session."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Project Z\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (if (string-match "Brainstorm" prompt)
                (signal 'quit nil)
              ""))))
  :body (progn
         (condition-case err
             (pearl-gtd-planning-brainstorm "Project Z")
           (quit (setq test-pearl-gtd-caught-error err))))
  :asserts (progn
             (should (eq (car test-pearl-gtd-caught-error) 'quit))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                          "** Brainstorming")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-planning-user-creates-multi-level-project-structure
  "User creates project with sub-projects and nested components."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Project name" prompt) "Website Redesign")
             ((string-match "Sub-project" prompt) "Visual Design")
             ((string-match "Component" prompt) "Color palette")
             ((string-match "Another component" prompt) "done")
             (t ""))))
         ((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Create sub-project" prompt) "yes")
             ((string-match "Add component" prompt) "yes")
             (t "")))))
  :body (pearl-gtd-planning-create-complex-project)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "* Website Redesign"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "** Visual Design"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "projects.org" pearl-gtd-init-base-directory)
                      "*** Color palette")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-planning-user-links-task-to-multiple-projects
  "User links single task to multiple projects via tags."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Project Alpha\n* Project Beta\n")
          ("actions.org" "* Shared task\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Select projects" prompt) "Alpha,Beta")
             (t "")))))
  :body (progn
         (with-current-buffer (find-file-noselect (expand-file-name "actions.org" pearl-gtd-init-base-directory))
           (goto-char (point-min))
           (pearl-gtd-planning-link-to-projects)
           (save-buffer)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":PROJECT:Alpha,Beta:")))
  :teardown nil)

(provide 'test-pearl-gtd-planning)

;;; test-pearl-gtd-planning.el ends here
