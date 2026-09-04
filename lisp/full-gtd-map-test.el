;;; full-gtd-map-test.el --- Unit tests for full-gtd-map  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for the star-map rendering module.

;;; Code:

(require 'ert)
(require 'full-gtd-map)

(defun full-gtd-map-test--stats (&optional l6p l3)
  "Build a stats list (TOTAL TODO DONE L6P L6PR L5 L4 L3).
L6P and L3 override the horizon slots.  Counts are integers, matching
`full-gtd-project-utils--collect-project-statistics'."
  (list 2 1 1 (or l6p "Purpose") "" "Vision" "Goal" (or l3 "Work")))

(defun full-gtd-map-test--action (status done-p headline id &optional context)
  "Build an action alist shaped like the domain grouping output.
STATUS is the todo keyword string and DONE-P marks completion.
HEADLINE is the display text, ID the entry identifier, and
CONTEXT is the optional context tag."
  (list (cons 'status status)
        (cons 'done-p done-p)
        (cons 'headline headline)
        (cons 'id id)
        (cons 'context (or context ""))))

(ert-deftest full-gtd-map-test-render-structure ()
  "Horizon rows appear above the project line, actions below."
  (let* ((actions (list (full-gtd-map-test--action "TODO" nil "买跑鞋" "i1" "@home")
                        (full-gtd-map-test--action "DONE" t "查资料" "i2")))
         (block (full-gtd-map--render-block
                 "P" (full-gtd-map-test--stats) actions 'collapsed))
         (rows (car block))
         (text (mapconcat #'car rows "\n")))
    (should (string-match-p "Project: P" text))
    (should (string-match-p "L6 Purpose" text))
    (should (string-match-p "…" text))))

(ert-deftest full-gtd-map-test-horizon-multi-value ()
  "Multiple horizon values split into separate rows."
  (let* ((stats (list 1 1 0 "Purpose1" "" "Vision1; Vision2" "Goal" "Area"))
         (rows (full-gtd-map--horizon-lines stats)))
    (should (= 5 (length rows)))
    (should (string-match-p "Purpose1" (caar rows)))
    (should (string-match-p "Vision1" (car (nth 1 rows))))
    (should (string-match-p "Vision2" (car (nth 2 rows))))))

(ert-deftest full-gtd-map-test-action-fold-collapsed ()
  "Collapsed actions show only a single ellipsis row."
  (let* ((actions (list (full-gtd-map-test--action "TODO" nil "A" "i1")))
         (rows (full-gtd-map--action-lines actions 'collapsed)))
    (should (= 1 (length rows)))
    (should (string-match-p "…" (caar rows)))
    (should (eq (plist-get (cdar rows) :kind) 'ellipsis))))

(ert-deftest full-gtd-map-test-action-fold-todo-filters-done ()
  "Todo fold hides DONE rows."
  (let* ((actions (list (full-gtd-map-test--action "DONE" t "A" "i1")
                        (full-gtd-map-test--action "TODO" nil "B" "i2")))
         (rows (full-gtd-map--action-lines actions 'todo)))
    (should (= 1 (length rows)))
    (should (string-match-p "B" (caar rows)))))

(ert-deftest full-gtd-map-test-fold-todo-with-only-done-shows-all ()
  "Todo fold falls back to all rows when no action is pending."
  (let* ((actions (list (full-gtd-map-test--action "DONE" t "A" "i1")))
         (block (full-gtd-map--render-block
                 "P" (full-gtd-map-test--stats) actions 'todo))
         (rows (car block))
         (text (mapconcat #'car rows "\n")))
    (should (string-match-p "A" text))
    (should-not (string-match-p "…" text))))

(ert-deftest full-gtd-map-test-line-props ()
  "Inserted block carries project, kind and id text properties."
  (with-temp-buffer
    (let ((block (full-gtd-map--render-block
                  "Proj"
                  (full-gtd-map-test--stats)
                  (list (full-gtd-map-test--action "TODO" nil "Do" "act-1"))
                  'todo)))
      (full-gtd-map--insert-block block)
      (goto-char (point-min))
      (search-forward "Proj")
      (should (equal (full-gtd-table-project-at-point) "Proj"))
      (should (eq (full-gtd-map-kind-at-point) 'project))
      (goto-char (point-min))
      (let ((case-fold-search nil))
        (search-forward "Do"))
      (should (eq (full-gtd-map-kind-at-point) 'action))
      (should (equal (full-gtd-table--prop-at-point full-gtd-table-prop-id)
                     "act-1")))))

(ert-deftest full-gtd-map-test-horizon-level-prop ()
  "Horizon rows carry their level symbol."
  (with-temp-buffer
    (let ((block (full-gtd-map--render-block
                  "Proj" (full-gtd-map-test--stats) nil 'collapsed)))
      (full-gtd-map--insert-block block)
      (goto-char (point-min))
      (search-forward "L6 Purpose")
      (should (eq (full-gtd-map-kind-at-point) 'horizon))
      (should (eq (full-gtd-map-level-at-point) 'purpose)))))

(ert-deftest full-gtd-map-test-horizon-single-tree-across-levels ()
  "All horizon rows form an open branch: ┌ first, ├ for the rest.
The branch never closes with └──; actions keep the closed form."
  (let* ((stats (list 1 1 0 "P" "" "V" "G" "A1; A2"))
         (rows (full-gtd-map--horizon-lines stats)))
    (should (= 5 (length rows)))
    (should (string-match-p "┌──" (car (nth 0 rows))))
    (should (string-match-p "├──" (car (nth 1 rows))))
    (should (string-match-p "├──" (car (nth 2 rows))))
    (should (string-match-p "├──" (car (nth 3 rows))))
    (should (string-match-p "├──" (car (nth 4 rows))))
    (should-not (string-match-p "└──" (mapconcat #'car rows "\n")))
    (let ((single (full-gtd-map--horizon-lines
                   (list 1 1 0 "" "" "" "" "Only"))))
      (should (= 1 (length single)))
      (should (string-match-p "┌──" (car (car single)))))))

(ert-deftest full-gtd-map-test-action-indent-deeper-than-horizon ()
  "Action tree lines are indented deeper than horizon tree lines."
  (let* ((horizon-row
          (car (full-gtd-map--horizon-lines
                (list 1 1 0 "P" "" "V" "G" "A"))))
         (action-row
          (car (full-gtd-map--action-lines
                (list (full-gtd-map-test--action "TODO" nil "A" "i1"))
                'all)))
         (horizon-glyph (string-match-p "[┌├└]" (car horizon-row)))
         (action-glyph (string-match-p "[┌├└]" (car action-row))))
    (should (< horizon-glyph action-glyph))))

(ert-deftest full-gtd-map-test-block-framing ()
  "Block is framed: top rule, left rule on content rows, bottom rule."
  (let* ((block (full-gtd-map--render-block
                 "P" (full-gtd-map-test--stats)
                 (list (full-gtd-map-test--action "TODO" nil "A" "i1"))
                 'todo))
         (rows (car block))
         (text (mapconcat #'car rows "\n")))
    (should (string-prefix-p "╭─" (car (car rows))))
    (should (string-prefix-p "╰─" (car (car (reverse rows)))))
    (should-not (string-match-p "\n[^│╭╰]" text))))

(ert-deftest full-gtd-map-test-frame-closed-right ()
  "Block frame is closed on all four sides with equal row widths.
Rule lines end with the rounded corners, content rows end with the
right rule, and every line shares the same display width so CJK
text cannot misalign the right edge."
  (let* ((stats (list 2 1 1 "长目的 Purpose" "" "Vision" "Goal" "Work"))
         (block (full-gtd-map--render-block
                 "P" stats
                 (list (full-gtd-map-test--action "TODO" nil "A" "i1"))
                 'todo))
         (lines (mapcar #'car (car block))))
    (should (string-suffix-p "╮" (car lines)))
    (should (string-suffix-p "╯" (car (last lines))))
    (dolist (line (cdr (butlast lines)))
      (should (string-suffix-p "│" line)))
    (let ((w (string-width (car lines))))
      (dolist (line lines)
        (should (= w (string-width line)))))))

(ert-deftest full-gtd-map-test-action-branch-closes-with-tee ()
  "Action rows form a closing branch: ├── first, └── last.
The first action continues from the project line, so it uses ├──
instead of ┌──."
  (let* ((actions (list (full-gtd-map-test--action "TODO" nil "A" "i1")
                        (full-gtd-map-test--action "TODO" nil "B" "i2")
                        (full-gtd-map-test--action "TODO" nil "C" "i3")))
         (rows (full-gtd-map--action-lines actions 'all)))
    (should (= 3 (length rows)))
    (should (string-match-p "├──" (car (nth 0 rows))))
    (should (string-match-p "├──" (car (nth 1 rows))))
    (should (string-match-p "└──" (car (nth 2 rows))))
    (should-not (string-match-p "┌──" (mapconcat #'car rows "\n")))
    (let ((single (full-gtd-map--action-lines
                   (list (full-gtd-map-test--action "TODO" nil "A" "i1"))
                   'all)))
      (should (= 1 (length single)))
      (should (string-match-p "└──" (car (car single)))))))

(provide 'full-gtd-map-test)

;;; full-gtd-map-test.el ends here
