;;; test-pearl-gtd-horizons.el --- User stories: 6 Horizons  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for 6 Horizons of Focus.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-horizons-user-assigns-level-3-to-task
  "User assigns a task to Horizon 3 (Goals)."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task for goals\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Horizon" prompt) "3")
             (t "")))))
  :body (progn
         (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (goto-char (point-min))
         (pearl-gtd-horizons-assign-level))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":HORIZON: 3")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-horizons-user-views-projects-by-area
  "User views projects grouped by Horizon 4 (Areas of Responsibility)."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Project A\n:PROPERTIES:\n:HORIZON: 4\n:AREA: Health\n:END:\n* Project B\n:PROPERTIES:\n:HORIZON: 4\n:AREA: Career\n:END:\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Area" prompt) "Health")
             (t "")))))
  :body (pearl-gtd-horizons-view-by-area)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Health*"))
             (with-current-buffer "*Pearl-GTD: Health*"
               (should (search-forward "Project A" nil t))
               (should-not (search-forward "Project B" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Health*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-user-defines-purpose-horizon-1
  "User defines Horizon 1 (Purpose and Principles)."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Purpose" prompt) "Live intentionally")
             ((string-match "Principles" prompt) "Honesty, Growth, Service")
             (t "")))))
  :body (pearl-gtd-horizons-define-purpose)
  :asserts (progn
             (should (file-exists-p (expand-file-name "horizons.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "horizons.org" pearl-gtd-init-base-directory)
                      "* Horizon 1: Purpose"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "horizons.org" pearl-gtd-init-base-directory)
                      "Live intentionally")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-horizons-user-defines-vision-horizon-2
  "User defines Horizon 2 (Vision)."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Vision" prompt) "A life of freedom and impact")
             ((string-match "Future state" prompt) "Financial independence, strong relationships")
             (t "")))))
  :body (pearl-gtd-horizons-define-vision)
  :asserts (progn
             (should (file-exists-p (expand-file-name "horizons.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "horizons.org" pearl-gtd-init-base-directory)
                      "* Horizon 2: Vision"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "horizons.org" pearl-gtd-init-base-directory)
                      "A life of freedom and impact")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-horizons-user-views-projects-by-horizon-5
  "User views projects grouped by Horizon 5 (Projects)."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Project A\n:PROPERTIES:\n:HORIZON: 5\n:END:\n* Project B\n:PROPERTIES:\n:HORIZON: 5\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view-projects)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Horizon 5 Projects*"))
             (with-current-buffer "*Pearl-GTD: Horizon 5 Projects*"
               (should (search-forward "Project A" nil t))
               (should (search-forward "Project B" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Horizon 5 Projects*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-user-views-actions-by-horizon-6
  "User views actions grouped by Horizon 6 (Actions)."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task A\n:PROPERTIES:\n:HORIZON: 6\n:END:\n* Task B\n:PROPERTIES:\n:HORIZON: 6\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view-actions)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Horizon 6 Actions*"))
             (with-current-buffer "*Pearl-GTD: Horizon 6 Actions*"
               (should (search-forward "Task A" nil t))
               (should (search-forward "Task B" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Horizon 6 Actions*"))

(provide 'test-pearl-gtd-horizons)

;;; test-pearl-gtd-horizons.el ends here
