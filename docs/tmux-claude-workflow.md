# Daily workflow: tmux + Claude Code

This guide shows how to run many Claude Code conversations in tmux without losing them.

## Three words

- **Task**: one piece of work, for example a ticket. A task can touch more than one repo.
- **Session**: a tmux session. Use one session for each task.
- **Conversation**: a Claude Code conversation. It runs inside a session.

Give the session and the conversation the same name as the task. Then you can always find both.

The tmux prefix is `Ctrl+A`. "`Ctrl+A`, `d`" means: press `Ctrl+A`, release it, then press `d`.

## Check your setup (one time)

```bash
dotfiles tmux check
```

All lines must show `PASS`. If a line shows `FAIL`, run `dotfiles tmux update`.

## Start a task

**If you are not in tmux:**

1. Go to the folder of the main repo: `cd ~/code/airflow`
2. Start a session with the task name: `tmux new -s data-8130`
3. Start Claude with the same name: `claude -n data-8130`

**If you are already in tmux:**

1. Press `Ctrl+A`, `Shift+T` to open the picker.
2. Type part of the folder name, for example `airflow`.
3. Press `Enter`. sesh starts a new session in that folder.
4. Press `Ctrl+A`, `$` and type the task name to rename the session.
5. Start Claude: `claude -n data-8130`

Do not type `tmux new` inside tmux. tmux does not start a session inside a session.

## Change to a different task

1. Press `Ctrl+A`, `Shift+T`.
2. Type part of the task name.
3. Press `Enter`.

The picker shows your sessions first, then your recent folders. Claude keeps working in the session that you left.

## Leave and come back

To leave tmux, press `Ctrl+A`, `d`. All sessions continue to run, and Claude continues to work.

To come back, open Ghostty and type:

```bash
tmux attach
```

This opens your last session. Then use the picker to go to a different task.

If you close the Ghostty window, the sessions also continue to run. Use `tmux attach` to come back.

## Work on more than one repo

Claude can only change files in the folder where you started it. To give it access to more repos, add them when you start Claude:

```bash
claude -n data-8130 --add-dir ~/code/dbt-analytics --add-dir ~/code/snowflake-cicd
```

In a conversation that is already open, type `/add-dir ~/code/dbt-analytics`.

Each repo keeps its own `CLAUDE.md`. You do not need to copy or move these files.

## Two conversations in the same repo

Two conversations that change the same folder can overwrite their changes. Give each conversation its own worktree:

```bash
cd ~/code/airflow
gwtree data-8257
```

This creates the folder `../wt/data-8257` on its own branch. Start the second session and conversation in that folder.

## Use two panes

A good layout: Claude on the left, a shell on the right.

1. Press `Ctrl+A`, `|` to split the window.
2. Use the right pane for `git`, `lazygit`, or tests.
3. Click a pane to select it.
4. Press `Ctrl+A`, `m` to make a pane full size. Press it again to go back.

## After a restart or a crash

tmux saves your sessions every 15 minutes. It saves the windows, panes, and folders. It does not save Claude itself. You must start Claude again.

1. Open Ghostty and type `tmux`. tmux restores your saved sessions.
2. Press `Ctrl+A`, `Shift+T` and select your task.
3. In the pane where Claude was, continue the conversation:

```bash
claude -c
```

`claude -c` continues the last conversation in this folder. If the folder had more than one conversation, use `claude -r data-8130`. This opens a list that shows only matches for that name.

The `tmux` command in step 1 also makes one new, empty session. You can close it with `exit`.

## Finish a task

1. Type `/exit` in Claude.
2. Close the session: `tmux kill-session -t data-8130`

Do this only when you complete the task. `kill-session` stops everything in that session, including a Claude that is still working.

If you used `gwtree`, remove the worktree after you merge the branch: `git worktree remove ../wt/data-8257`

## Keep a short note for long tasks

`/compact` makes the conversation smaller, but it can lose details. For a long task, ask Claude to write a short note in the repo or in your notes. The note must contain the goal, the repos, the decisions, and the next steps.

## Quick reference

| You want to | Do this |
|---|---|
| Start a task (outside tmux) | `tmux new -s <task>`, then `claude -n <task>` |
| Start a task (inside tmux) | `Ctrl+A`, `Shift+T`, select a folder, then `Ctrl+A`, `$` |
| Change to a different task | `Ctrl+A`, `Shift+T` |
| Leave tmux | `Ctrl+A`, `d` |
| Come back | `tmux attach` |
| Show all sessions | `tmux ls` |
| Rename a session | `Ctrl+A`, `$` |
| Split the window | `Ctrl+A`, `\|` (side by side) or `Ctrl+A`, `-` (top and bottom) |
| Make a pane full size | `Ctrl+A`, `m` |
| Continue Claude after a restart | `claude -c` or `claude -r <task>` |
| Finish a task | `/exit`, then `tmux kill-session -t <task>` |

## If something is wrong

| Problem | Do this |
|---|---|
| `Ctrl+A` does nothing | Run `dotfiles tmux check`. If it shows a `WARN` for the running server, press `Ctrl+B`, `:` and type `source-file ~/.tmux.conf`. |
| The picker does not open | Run `dotfiles tmux check`. sesh must show `PASS`. |
| No theme or no saved sessions | Run `dotfiles tmux update`. It installs the plugins. |
| `tmux attach` says "no sessions" | No session is running. Type `tmux` to restore the saved sessions. |
