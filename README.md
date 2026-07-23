# Pearl-GTD

[English](README.md) | [中文](README_zh.md)

A complete [Getting Things Done](https://gettingthingsdone.com/) implementation for Emacs org-mode, covering the full David Allen framework — including the Natural Planning Model and the Six Horizons of Focus.

```
                          PEARL-GTD: FIVE WORKFLOWS

  ANYTIME
  =======
  +------------------+        +------------------+
  |    CAPTURE       |------->|     PROCESS      |
  | pearl-gtd-capture| inbox  |pearl-gtd-process |
  |                  | full   |    -inbox        |
  +------------------+        +------------------+


  WHEN STARTING A PROJECT
  =======================
  +-----------------------------------------------+
  |                   PLANNING                    |
  |          pearl-gtd-planning-start             |
  |                                               |
  |  Purpose -> Principle -> Vision -> Brainstorm |
  |         -> Organize -> Next Actions           |
  +-----------------------------------------------+


  EVERY MORNING
  =============
  +-----------------------------------------------+
  |                DAILY REVIEW                   |
  |           pearl-gtd-review-daily              |
  |                                               |
  |   inbox -> calendar -> completed -> actions   |
  +-----------------------------------------------+


  EVERY WEEKEND
  ==============
  +-------------------------------------------------------------------------+
  |                            WEEKLY REVIEW                                |
  |                       pearl-gtd-review-weekly                           |
  |                                                                         |
  |  inbox -> overdue -> deadlines -> completed -> delegated -> next actions|
  |         -> stuck projects -> active projects -> no-project actions      |
  |         -> someday/maybe                                                |
  +-------------------------------------------------------------------------+


  WHEN WORKING / FEELING LOST
  ===========================
  +------------------------+    +------------------------+
  |        ENGAGE          |    |       HORIZONS         |
  | pearl-gtd-do-view-all  |    | pearl-gtd-horizons-view|
  |      -actions          |    |                        |
  |                        |    |  L6 Purpose            |
  |  all next actions      |    |    -> L5 Vision        |
  |  filter by context     |    |      -> L4 Goals       |
  |  delegated tracking    |    |        -> L3 Area      |
  |                        |    |          -> Projects/  |
  |                        |    |             Actions    |
  +------------------------+    +------------------------+
  ```

## Why Pearl-GTD?

Existing Emacs GTD packages handle lists and agendas well, but omit two pillars of Allen's original model:

| Feature                    | org-gtd | Pearl-GTD |
|----------------------------|---------|-----------|
| Inbox processing           | ✅      | ✅       |
| Projects & Next Actions    | ✅      | ✅       |
| Natural Planning Model     | ❌      | ✅       |
| Six Horizons of Focus      | ❌      | ✅       |
| Daily/Weekly Review cycles | Partial | ✅       |

This package is for you if you've read the book and want your tool to match the theory.

## Quick Start

```elisp
(use-package pearl-gtd
  :ensure t
  :bind (("C-c g c" . pearl-gtd-capture)
         ("C-c g i" . pearl-gtd-process-inbox)
         ("C-c g p" . pearl-gtd-planning-start)
         ("C-c g r" . pearl-gtd-review-weekly)
         ("C-c g d" . pearl-gtd-review-daily)
         ("C-c g a" . pearl-gtd-do-view-all-actions)
         ("C-c g h" . pearl-gtd-horizons-view)))
```

1. `C-c g c` — Capture anything to inbox
2. `C-c g i` — Process inbox (clarify & organize items)
3. `C-c g p` — Plan a project using the Natural Planning Model
4. `C-c g r` — Run the Weekly Review
5. `C-c g d` — Run the Daily Review
6. `C-c g a` — View all next actions
7. `C-c g h` — View the Six Horizons hierarchy

## Core Features

### 1. Capture & Inbox Processing
One‑key capture (`pearl-gtd-capture`) with automatic timestamp and unique ID. 
The inbox processing buffer (`pearl-gtd-process-inbox`) guides you through the 
GTD clarify‑and‑organize workflow with a staging table, visual highlighting, 
and immediate property application.

### 2. Natural Planning Model
`M‑x pearl‑gtd‑planning‑start` enforces David Allen’s five‑step project thinking:

1. **Purpose** (L6) – Why are we doing this?
2. **Principle** (L6) – What standards must we keep?
3. **Vision** (L5) – What does success look like?
4. **Brainstorming** – Dump all ideas into a temporary buffer
5. **Organizing** – Force‑complete every brainstorm item (Next Action, Reference, Someday, or Trash)
6. **Next Actions** – At least one physical next action is required

The workflow cannot be skipped; it ensures every project has a clear outcome and at least one concrete next step.

### 3. Six Horizons of Focus
Horizons are stored as Org properties (`L3_AREA` … `L6_PURPOSE`) and obey strict dependencies:

- **L3 Area** – Ongoing responsibilities (e.g., “Health”, “Career”)
- **L4 Goal** – 1‑2 year objectives
- **L5 Vision** – 3‑5 year picture (requires L4 Goal)
- **L6 Purpose** – Life purpose (requires L5 Vision)
- **L6 Principle** – Guiding principles (requires L6 Purpose)

Horizons are inherited from projects to their actions. The horizon view (`pearl‑gtd‑horizons‑view`) shows the full hierarchy from Purpose down to individual tasks.

### 4. Review Cycles
- **Daily Review** (`pearl‑gtd‑review‑daily`) – Today’s scheduled tasks, completed today, next actions, and inbox.
- **Weekly Review** (`pearl‑gtd‑review‑weekly`) – Comprehensive 10‑section review: inbox, overdue, upcoming deadlines, completed, delegated, next actions, stuck/active projects, no‑project actions, and someday/maybe.

Both reviews use a unified table interface with keyboard shortcuts for navigation, editing properties, marking tasks complete, and jumping to source entries.

### 5. Do/Work Phase
Context‑filtered action views (`pearl‑gtd‑do‑view‑by‑context`), delegated tasks, today’s scheduled actions, and a global “All Actions” table. Each view is a read‑only Org table with live navigation (`n`/`p`/`j`/`k`), completion (`C`), renaming (`r`), and jump‑to‑source (`RET`).

### 6. Technical Foundation
- **ID‑based tracking** – Every entry receives a unique `:ID:` property that persists across moves and renames.
- **Property system** – All GTD metadata (context, delegated, scheduled, deadline, project, horizons) are standard Org properties.
- **Table‑driven UI** – Staging, review, and work views are built on Org tables with text‑property navigation.
- **Input sanitization** – Newlines, control characters, and pipe symbols are escaped to maintain Org syntax integrity.

## Design Philosophy

> “Your mind is for having ideas, not holding them.” — David Allen

Most GTD software becomes a todo‑list app with extra steps. Pearl‑GTD stays close to the book because **Allen designed GTD as a complete system, not a feature set**:

- **Capture must be frictionless** – One key, no categorization, no thinking.
- **The Natural Planning Model is not optional** – It’s how projects actually get done.
- **Horizons are not tags** – They are a hierarchy. L4 goals must connect to L3 areas, which must connect to L2 projects. If a goal has no projects, it’s a fantasy.
- **Review is the engine** – Without weekly review, GTD decays into a mess of stale lists. The tool enforces the habit.

Emacs is the right host because GTD is fundamentally **text and structure**. Org‑mode gives us outlines, tags, links, and agenda views. Pearl‑GTD adds the **workflow layer** on top.

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
M‑x package‑install RET pearl‑gtd RET
```

Or with `use‑package`:

```elisp
(use-package pearl-gtd
  :ensure t
  :bind (("C-c g c" . pearl-gtd-capture)
         ("C-c g p" . pearl-gtd-planning-start)
         ("C-c g r" . pearl-gtd-review-weekly)
         ("C-c g d" . pearl-gtd-review-daily)
         ("C-c g a" . pearl-gtd-do-view-all-actions)
         ("C-c g h" . pearl-gtd-horizons-view)))
```

### Manual installation

Clone the repository and add to your `load‑path`:

```bash
git clone https://github.com/OverbearingPearl/pearl-gtd.git /path/to/pearl-gtd
```

```elisp
(add-to-list 'load-path "/path/to/pearl-gtd")
(require 'pearl-gtd)
```

## Contributing

Issues and PRs welcome. If you find a place where Pearl‑GTD deviates from Allen’s model, that’s a bug.

## License

MIT
