# Full-GTD

A complete [Getting Things Done](https://gettingthingsdone.com/) implementation for Emacs org-mode, covering the full David Allen framework — including the Natural Planning Model and the Six Horizons of Focus.

<pre>
                   FULL-GTD: FIVE WORKFLOWS

  ANYTIME
  ═══════
  ┌───────────────────┐            ┌─────────────────────────┐
  │      CAPTURE      │───────────▶│         PROCESS         │
  │ full-gtd-capture  │ inbox full │ full-gtd-process-inbox  │
  └───────────────────┘            └─────────────────────────┘


  WHEN STARTING A PROJECT
  ═══════════════════════
  ┌───────────────────────────────────────────────────────────────────┐
  │                            PLANNING                               │
  │                    full-gtd-planning-start                        │
  │                                                                   │
  │ Purpose&Principle → Vision → Brainstorm → Organize → Next Actions │
  └───────────────────────────────────────────────────────────────────┘


  EVERY MORNING
  ═════════════
  ┌────────────────────────────────────────────┐
  │               DAILY REVIEW                 │
  │           full-gtd-review-daily            │
  │                                            │
  │   inbox → calendar → completed → actions   │
  └────────────────────────────────────────────┘


  EVERY WEEKEND
  ══════════════
  ┌────────────────────────────────────────────────────────────────────┐
  │                         WEEKLY REVIEW                              │
  │                     full-gtd-review-weekly                         │
  │                                                                    │
  │ inbox → overdue → deadlines → completed → delegated → next actions │
  │       → stuck projects → active projects → no-project actions      │
  │       → someday/maybe                                              │
  └────────────────────────────────────────────────────────────────────┘


  WHEN WORKING / FEELING LOST
  ═══════════════════════════
  ┌─────────────────────────────┐    ┌──────────────────────────────┐
  │           ENGAGE            │    │           HORIZONS           │
  │        full-gtd-do          │    │    full-gtd-horizons-view    │
  │                             │    │                              │
  │  single-card execution      │    │  L6 Purpose                  │
  │  system pushes optimal task │    │    → L5 Vision               │
  │  based on your conditions   │    │      → L4 Goals              │
  │  (context, time, energy)    │    │        → L3 Area             │
  │                             │    │          → Projects/Actions  │
  └─────────────────────────────┘    └──────────────────────────────┘
</pre>

See it in action: [Watch demo](https://github.com/user-attachments/assets/194d80d7-f561-4c60-bff8-e427d3f6c49b)

## Why Full-GTD?

Existing Emacs GTD packages handle lists and agendas well, but omit two pillars of Allen's original model:

| Feature                    | org-gtd | Full-GTD |
|----------------------------|---------|----------|
| Inbox processing           | ✅     | ✅      |
| Projects & Next Actions    | ✅     | ✅      |
| Natural Planning Model     | ❌     | ✅      |
| Six Horizons of Focus      | ❌     | ✅      |
| Daily/Weekly Review cycles | Partial | ✅      |

Unlike traditional tools that show long lists for you to browse, Full-GTD uses **single-card push mode** during execution: it scores actions by urgency, horizon alignment, and context match, then pushes the single optimal task. You simply act or skip—no decision fatigue, no list paralysis.

This package is for you if you've read the book and want your tool to match the theory.

## Quick Start

By default, data is stored in `~/.full-gtd/`. You can customize this with `full-gtd-init-base-directory`, e.g. `(setq full-gtd-init-base-directory "~/org/gtd/")`. Before first use, run `M-x full-gtd-init-initialize` to create the directory and skeleton files. When using `use-package`, you can call that function automatically in `:config`.

```elisp
(use-package full-gtd
  :ensure t
  :custom
  (full-gtd-init-base-directory "~/.full-gtd/")
  :config
  (full-gtd-init-initialize)
  :bind (("C-c g c" . full-gtd-capture)
         ("C-c g i" . full-gtd-process-inbox)
         ("C-c g p" . full-gtd-planning-start)
         ("C-c g r" . full-gtd-review-weekly)
         ("C-c g d" . full-gtd-review-daily)
         ("C-c g e" . full-gtd-do)
         ("C-c g h" . full-gtd-horizons-view)))
```

1. `C-c g c` — Capture anything to inbox
2. `C-c g i` — Process inbox (clarify & organize items)
3. `C-c g p` — Plan a project using the Natural Planning Model
4. `C-c g r` — Run the Weekly Review
5. `C-c g d` — Run the Daily Review
6. `C-c g e` — Start a Do session (Engage/Execute)
7. `C-c g h` — View the Six Horizons hierarchy

## A Day with Full-GTD

**Morning:**

1. `full-gtd-review-daily` — Check today's calendar and next actions

**Throughout the day:**

2. `full-gtd-capture` — Dump anything into inbox
3. `full-gtd-do` — Start a Do session; the system will ask for your current context, available time, and energy level, then push the optimal task

**When inbox piles up:**

4. `full-gtd-process-inbox` — Clarify and organize each item

**Starting a new project:**

5. `full-gtd-planning-start` — Run the Natural Planning Model

**Feeling lost:**

6. `full-gtd-horizons-view` — Check vertical alignment: see which projects lack higher-level horizons, and verify actions connect to purpose

**Weekend:**

7. `full-gtd-review-weekly` — Full system review

## Core Features

### 1. Capture & Inbox Processing
One‑key capture (`full-gtd-capture`) with automatic timestamp and unique ID. 
Inbox processing (`full-gtd-process-inbox`) presents a **staging table** with visual highlighting, using **single‑key destination selection** (`a`ction/`r`ef/`s`omeday/`t`rash/e`x`ecute/`c`larify) with an **optional clarify step** (rename + notes) and **hybrid date input** (`a`/`t`/`w` shortcuts or free‑form). Contexts complete from existing values with **inheritance across the session**.

### 2. Natural Planning Model
`M‑x full-gtd-planning-start` enforces David Allen’s five‑step project thinking:

1. **Purpose** (L6) – Why are we doing this?
2. **Principle** (L6) – What standards must we keep? (Optional: press RET to skip)
3. **Vision** (L5) – What does success look like?
4. **Brainstorming** – Dump all ideas into a temporary buffer
5. **Organizing** – Force‑complete every brainstorm item via **staging buffer** with visual highlighting and **single‑key selection** (`n`ext/`r`ef/`s`omeday/`t`rash/`c`larify). The optional **clarify** step (`c`) allows renaming and adding notes before final classification. A **session‑wide default context** is set once and auto‑applied to all Next Actions; if omitted, context is prompted per‑item using the same completion flow as inbox processing.
6. **Next Actions** – At least one physical next action is required

The workflow cannot be skipped; it ensures every project has a clear outcome and at least one concrete next step.

### 3. Six Horizons of Focus
Horizons are stored as Org properties (`L3_AREA` … `L6_PURPOSE`) and obey strict dependencies:

- **L3 Area** – Ongoing responsibilities (e.g., "Health", "Career")
- **L4 Goal** – 1‑2 year objectives
- **L5 Vision** – 3‑5 year picture
- **L6 Purpose & Principle** – Life purpose and guiding principles

Horizons flow from high levels down: Purpose (L6) → Vision (L5) → Goals (L4) → Areas (L3) → Projects → Actions. The horizon view (`full‑gtd‑horizons‑view`) displays a **matrix alignment view**:

- **Rows**: Projects grouped by alignment status (Critical/Partial/Aligned/Multi-Horizon)
- **Columns**: L6 Purpose → L5 Vision → L4 Goal → L3 Area
- **Empty cells**: Indicate gaps in vertical alignment
- **No-project actions**: Shown separately with L3 Area only

This matrix format makes it easy to spot "orphaned" projects (no horizon alignment) and incomplete vertical chains at a glance.

Navigation in the horizon view uses the same keys as review mode: `n`/`p` or `j`/`k` to move between rows, `RET` to view project tasks, `g` to refresh, `q` to quit. Press `3`–`6` to edit the corresponding horizon level (L3–L6, where `6` edits both Purpose and Principle sequentially). Press `A` to archive the project with the same rules as in Review (all actions DONE, no shared projects).

### 4. Review Cycles
- **Daily Review** (`full-gtd-review-daily`) – Today’s scheduled tasks, completed today, next actions, and inbox.
- **Weekly Review** (`full-gtd-review-weekly`) – Comprehensive 10‑section review: inbox, overdue, upcoming deadlines, completed, delegated, next actions, stuck/active projects, no‑project actions, and someday/maybe.

Both reviews use a unified table interface with keyboard shortcuts for navigation, editing properties, marking tasks complete, and jumping to source entries. Shortcuts: `c` (context), `D` (delegated), `s` (scheduled), `d` (deadline), `r` (rename), `P` (project), `C` (complete), `a` (activate a someday/maybe entry in weekly review), `A` (archive project), `e` (edit notes), and `3`-`6` (horizons L3-L6, where `6` edits both Purpose and Principle sequentially). Archiving (`A`) moves a project to `archive.org` only when all its actions are DONE and no action belongs to other projects.

Project task sub-views (opened with `RET` on a project row) share the same navigation keys: `n`/`p` or `j`/`k` to move between rows, `RET` to jump to the source entry, and `q` to return to the parent view (weekly review or horizon view).

### 5. Do/Work Phase
The Do phase uses **single-card execution** (`full-gtd-do`). Instead of browsing a long list, you tell the system your current conditions—**context** (e.g., @office, @home), **available time** (minutes), and **energy level** (high/normal/low)—and it **pushes the single most optimal task** based on a scoring algorithm:

- **Urgency** – deadline proximity, scheduled today, task age
- **Importance** – horizon alignment (L6 Purpose → L3 Area), project association
- **Context match** – bonus when action context matches your current context

**Constraint awareness**: The system scores tasks based on your declared context, available time, and energy level. Time and energy filters help narrow the candidate pool before scoring.

**Continuous loop design**: The session encourages you to stay in flow. After you complete or skip a task, the next optimal task is automatically pushed. When no tasks match your current conditions, you're prompted to either adjust your conditions (new context/time/energy) or quit. No need to kill buffers or restart.

Session commands:

| Key | Action |
|-----|--------|
| `C` | Mark current card done and push next |
| `s` | Skip (push next without state change) |
| `z` | Snooze to tomorrow |
| `r` | Rename current task |
| `RET` | Jump to source entry |
| `c` | Change conditions (context/time/energy) |
| `q` | Quit session |
| `?` | Show command help |

This design eliminates decision fatigue—you don't choose from a list, the system tells you what to do next based on your constraints and the task priority scores.

### 6. Technical Foundation
- **ID‑based tracking** – Every entry receives a unique `:ID:` property that persists across moves and renames.
- **Property system** – All GTD metadata (context, delegated, scheduled, deadline, project, horizons) are standard Org properties.
- **Table‑driven UI** – Staging, review, and work views are built on Org tables with text‑property navigation.
- **Input sanitization** – Newlines, control characters, and pipe symbols are escaped to maintain Org syntax integrity.
- **Hybrid date input** – Schedule and deadline dates accept `t` (today), `T` (tomorrow), `w` (next week), `h` (next hour, schedule only), or free‑form `YYYY-MM-DD`.

## Design Philosophy

> “Your mind is for having ideas, not holding them.” — David Allen

Most GTD software becomes a todo‑list app with extra steps. Full-GTD stays close to the book because **Allen designed GTD as a complete system, not a feature set**:

- **Capture must be frictionless** – One key, no categorization, no thinking.
- **The Natural Planning Model is not optional** – It’s how projects actually get done.
- **Horizons are not tags** – They are a hierarchy. L4 goals must connect to L2 projects. If a goal has no projects, it’s a fantasy. Horizons can be edited directly in review views using `3`-`6` keys (L6 Purpose and Principle are edited together via key `6`).
- **Review is the engine** – Without weekly review, GTD decays into a mess of stale lists. The tool enforces the habit.
- **Engage needs focus** – A long next-actions list is overwhelming. Single-card execution with smart prioritization helps you pick the right next thing and finish the session with momentum.

Emacs is the right host because GTD is fundamentally **text and structure**. Org‑mode gives us outlines, tags, links, and agenda views. Full-GTD adds the **workflow layer** on top.

## Installation

### From MELPA

Ensure MELPA is in your `package-archives`:

```elisp
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
```

Then install:

```
M‑x package‑install RET full-gtd RET
```

For configuration, see [Quick Start](#quick-start).

### Manual installation

Clone the repository and add to your `load‑path`:

```bash
git clone https://github.com/OverbearingPearl/full-gtd.git /path/to/full-gtd
```

```elisp
(add-to-list 'load-path "/path/to/full-gtd")
(require 'full-gtd)
```

## Contributing

Issues and PRs welcome. If you find a place where Full‑GTD deviates from Allen’s model, that’s a bug.

## License

MIT
