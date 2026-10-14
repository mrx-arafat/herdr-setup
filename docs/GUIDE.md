# Herdr setup guide: agent launchers and a worker fleet

This guide sets up [herdr](https://herdr.dev) with the [herdr-plus](https://github.com/cloudmanic/herdr-plus) plugin and a small command called `fleet`.
After setup you can start an AI coding agent in any project with three keystrokes.
You can run six agents side by side, hand each one a task, wait for them, read their answers, reset them and close them, all from one terminal.

You do not need to know herdr first.
Everything is explained from zero, and one installer does the setup for you.
For a short overview, see the [README](../README.md).
For a clickable tour, open the [interactive manual](https://mrx-arafat.github.io/herdr-setup/).

> [!WARNING]
> The launchers in this guide start agents with permission prompts or sandboxing turned **off**.
> Read [Safety notes](#safety-notes) before you use them on code or machines you care about.

## Contents

1. [What you get](#what-you-get)
2. [How herdr thinks in two minutes](#how-herdr-thinks-in-two-minutes)
3. [Before you start](#before-you-start)
4. [Step 1 - Install herdr](#step-1---install-herdr)
5. [Step 2 - Run the installer](#step-2---run-the-installer)
6. [Step 3 - Try it](#step-3---try-it)
7. [Step 4 - Add your projects](#step-4---add-your-projects)
8. [Run many workers](#run-many-workers)
9. [Delegate work to workers](#delegate-work-to-workers)
10. [Manage, maintain and clean up](#manage-maintain-and-clean-up)
11. [Command suggestions in the shell](#command-suggestions-in-the-shell)
12. [The working style this setup is built for](#the-working-style-this-setup-is-built-for)
13. [Daily cheat sheet](#daily-cheat-sheet)
14. [What the installer created](#what-the-installer-created)
15. [Bind the keys yourself](#bind-the-keys-yourself)
16. [Add your own launcher](#add-your-own-launcher)
17. [Optional: auto-layout for git worktrees](#optional-auto-layout-for-git-worktrees)
18. [Optional: keep agent integrations current](#optional-keep-agent-integrations-current)
19. [Verify everything works](#verify-everything-works)
20. [Troubleshooting](#troubleshooting)
21. [Safety notes](#safety-notes)
22. [Update and uninstall](#update-and-uninstall)
23. [Optional extras](#optional-extras)
24. [Reference links](#reference-links)
25. [What was tested](#what-was-tested)

---

## What you get

| You do | What happens |
| --- | --- |
| `ctrl+b` then `↓`, type `claude`, `Enter` | A new tab opens in your current folder and runs `claude --dangerously-skip-permissions`. |
| `ctrl+b` then `↓`, type `agy`, `Enter` | A new tab opens in your current folder and runs `agy --dangerously-skip-permissions`. |
| `ctrl+b` then `↓`, type `codex`, `Enter` | A new tab opens in your current folder and runs `codex --dangerously-bypass-approvals-and-sandbox`. |
| `ctrl+b` then `↓`, type `grid`, `Enter` | One tab with a balanced 2x2 grid: Claude, Codex, Agy and a plain shell. |
| `ctrl+b` then `↓`, type `workers`, pick a layout | 2 to 8 workers in one or more tabs, for example six workers as two tabs of three. |
| `ctrl+b` then `↓`, type `name`, `Enter` | Every worker renames itself after its task, like `w1` -> `pr6969-cool-fix`. |
| `ctrl+b` then `↓`, type `update`, `Enter` | A new tab runs `herdr-setup update` for herdr-plus, integrations and setup files. herdr itself needs a plain terminal. |
| `ctrl+b` then `↑`, pick a project, `Enter` | A new workspace opens for that project with a `claude` tab and a `terminal` tab. |
| `fleet send w2 "fix the failing test"` | Types that task into worker 2. `fleet wait`, `fleet read`, `fleet clear` and `fleet close` do the rest. |

`ctrl+b` is herdr's default "prefix" key.
You press it, let go, then press the next key.

The two pickers are fuzzy finders.
You type a few letters and the list narrows down.
`Esc` closes them without doing anything.

## How herdr thinks in two minutes

Herdr is a terminal workspace manager for AI coding agents.
It keeps your terminals running in the background and shows which agent needs you.

| Word | Meaning |
| --- | --- |
| Workspace | One project. Shows in the sidebar. Use one per repo or task. |
| Tab | A layout inside a workspace. For example `claude`, `server`, `workers`. |
| Pane | One real terminal. A tab can be split into several panes. |
| Agent | A coding agent that herdr recognizes in a pane (Claude, Codex, Agy and others). |
| Worker | In this guide, a pane labelled `w1`, `w2` and so on that `fleet` can address. |
| Prefix | The key you press first, default `ctrl+b`. The next key is a herdr command. |

The sidebar shows each agent as `working`, `blocked`, `done` or `idle`.
`blocked` means the agent is waiting for you.

Herdr runs as a background server plus a window (the client) you look through.
If you close the window or press `ctrl+b` then `q`, your agents keep running.
Run `herdr` again to come back.

Herdr is mouse friendly.
You can click tabs, panes and workspaces, and drag split borders.
The keyboard is optional.

## Before you start

You need:

1. macOS or Linux with a terminal.
   Windows is not covered by this guide.
2. At least one agent CLI installed and signed in: `claude`, `agy` or `codex`.
3. `jq`, a small JSON tool the scripts use, and `curl`.
4. Optional: `git`, if you plan to use git worktrees.

Check what you have:

```bash
for t in claude agy codex jq curl git; do
  printf '%-8s ' "$t"
  command -v "$t" || echo "not found"
done
```

Install `jq` if it is missing:

```bash
brew install jq            # macOS with Homebrew
sudo apt install jq        # Debian or Ubuntu
```

You only need the agents you actually use.
A launcher for an agent you do not have opens a tab that says `command not found`.
That is harmless, and you can delete that launcher later.

## Step 1 - Install herdr

On macOS or Linux:

```bash
curl -fsSL https://herdr.dev/install.sh | sh
```

Or with Homebrew:

```bash
brew install herdr
```

Check it:

```bash
herdr --version
```

You need version 0.7.0 or newer.
This guide was tested with 0.9.3.

Start herdr from a project folder:

```bash
cd ~/some-project
herdr
```

Herdr opens one workspace for you.
Press `ctrl+b` then `?` at any time to see every key binding.

If your shell cannot find `herdr`, restart the terminal or add the install folder to your `PATH`.

## Step 2 - Run the installer

One line does the whole setup:

```bash
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | sh
```

To skip every question:

```bash
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | sh -s -- --yes
```

To read the installer before you run it (recommended, and never run a script you have not read):

```bash
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh -o install.sh
less install.sh
sh install.sh
```

You can also read it on GitHub: [install.sh](../install.sh).

What the installer does, in order:

1. Checks that `herdr` (0.7.0 or newer), `jq` and `curl` are installed.
2. Installs the herdr-plus plugin with `herdr plugin install cloudmanic/herdr-plus`, after asking you.
   The question appears on your terminal even when the script is piped from `curl`.
   `--yes` skips it.
   If there is no terminal to ask on, the installer stops and tells you to rerun with `--yes`.
3. Downloads `agent-tab.sh`, `fleet.sh`, `herdr-setup.sh` and eight Quick Actions from the [`files/`](../files/) folder of this repo into the plugin's config folder.
   The folders are `scripts/` and `quick-actions/` inside `~/.config/herdr/plugins/config/cloudmanic.herdr-plus/`.
4. Links the `fleet` and `herdr-setup` commands into `~/.local/bin` when that folder is on your `PATH`.
   Otherwise it prints alias lines for you to copy.
5. Adds two key bindings to `~/.config/herdr/config.toml`: `prefix+up` for Projects and `prefix+down` for Quick Actions.
6. Reloads herdr and validates the config with `herdr config check`.

It is safe to run again.
It never overwrites a file that already exists.
It makes a timestamped backup of `config.toml` before it edits it.
It skips a key binding you already use, and it never replaces an existing `fleet` or `herdr-setup` command.
To bring an existing install up to date, use `herdr-setup update`, see [Update and uninstall](#update-and-uninstall).

To install from a different branch or tag, set `HERDR_SETUP_REF` (the default is `main`):

```bash
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | HERDR_SETUP_REF=some-branch-or-tag sh
```

> [!NOTE]
> Installing a plugin clones a GitHub repository and runs its build script.
> The herdr-plus build script uses Go if you have it, and otherwise downloads a prebuilt binary from the project's releases.
> You can read it first: <https://github.com/cloudmanic/herdr-plus/blob/main/scripts/build.sh>

If you prefer to do everything by hand, [What the installer created](#what-the-installer-created) lists every file, links to its source, and shows how to copy the files yourself.

## Step 3 - Try it

Open herdr inside any project folder.

### Try Quick Actions

1. Press `ctrl+b`, let go, then press `↓`.
2. A small overlay appears with a list of actions and a filter box.
3. Type `claude`.
   The list should shrink to **Claude Dangerously Skip Permission** at the top.
4. Press `Enter`.
5. A new tab named `claude` opens in the same folder and Claude Code starts.
   At the bottom of Claude's screen you should see `bypass permissions on`.

Press `ctrl+b` then `p` to go back to the previous tab, or click the tabs at the top.

Try `agy` and `codex` the same way.
Codex prints `permissions: YOLO mode` when it starts.

### Try workers

1. Press `ctrl+b` then `↓` and type `workers`.
2. Pick **Workers** and press `Enter`.
3. Pick **2 workers** and press `Enter`.
4. A tab named `workers` opens with two Claude panes labelled `w1` and `w2`.
5. In any other pane of the same workspace, run `fleet ls`.

[Run many workers](#run-many-workers) explains every layout and the `fleet` command.

### Try Projects

The Projects list is empty until you add projects.
Do [Step 4](#step-4---add-your-projects) first, then:

1. Press `ctrl+b`, let go, then press `↑`.
2. Type part of a project name.
3. Press `Enter`.
4. A new workspace opens with a `claude` tab and a `terminal` tab, both in the project folder.

In the Projects picker, `ctrl+g` opens the project as a git worktree instead.

## Step 4 - Add your projects

A project is one small TOML file.
The file name does not matter.
Add a file to add a project.
Delete the file to remove it.

Find the folder:

```bash
herdr plugin config-dir cloudmanic.herdr-plus
```

By default that is `~/.config/herdr/plugins/config/cloudmanic.herdr-plus`.
Project files go in its `projects/` subfolder.

Create your first project (change the name and path):

```bash
D="$(herdr plugin config-dir cloudmanic.herdr-plus)/projects"
mkdir -p "$D"
cat > "$D/my-app.toml" <<'EOF'
name = "my-app"
description = "~/code/my-app"
working_dir = "~/code/my-app"

[[tabs]]
name = "claude"
command = "claude --dangerously-skip-permissions"

[[tabs]]
name = "terminal"
EOF
```

| Field | Meaning |
| --- | --- |
| `name` | The name shown in the picker. |
| `description` | Optional grey text next to the name. |
| `working_dir` | Where every tab starts. `~` and `$VARS` expand. The folder must exist. |
| `[[tabs]]` | One tab. Tabs open in file order. |
| `name` (in a tab) | The tab label. |
| `command` (in a tab) | Typed into the tab's shell and run. Leave it out for an empty shell. |

New files show up the next time you open the picker.
There is no restart.

A tab can hold up to four panes with `[[tabs.panes]]` and `split = "right"` or `"down"`.
A tab can also set its own `working_dir`, relative to the project's.
Add `group = "Client name"` to cluster projects under a heading.

## Run many workers

A worker is a pane labelled `w1`, `w2`, `w3` and so on.
`fleet` builds the panes, starts an agent in each, and lets you address them by that label.

### Three ways to launch

1. **Pick a preset.**
   `ctrl+b` then `↓`, type `workers`, pick **Workers**, pick a layout.
2. **Type a layout.**
   Pick **Workers (custom)** instead and type `count tabs agents`, for example `6 2 claude,codex`.
3. **From a terminal.**
   In any pane of the workspace, run `fleet up 6 2 claude`.

### The layouts

`fleet up <count> [tabs] [agents]` spreads `count` workers evenly over `tabs` tabs.
Each tab gets a balanced grid with equal columns and rows.

| Command | Result |
| --- | --- |
| `fleet up 2` | 1 tab, 2 side by side |
| `fleet up 3` | 1 tab, 2 columns (2 on the left, 1 on the right) |
| `fleet up 4` | 1 tab, 2x2 |
| `fleet up 6` | 1 tab, 3x2 |
| `fleet up 6 2` | 2 tabs of 3 |
| `fleet up 6 3` | 3 tabs of 2 |
| `fleet up 8 2` | 2 tabs of 4, each 2x2 |
| `fleet up 9` | 1 tab, 3x3 |

The maximum is 12 workers per command.
Workers are numbered left to right, top to bottom.
Running `fleet up` again adds more workers and keeps counting, so a second `fleet up 2` adds `w7` and `w8`.

### Choosing agents

The third argument picks the agent.
It can be `claude`, `codex`, `agy` or `shell` (an empty terminal).
A comma list cycles through the workers:

```bash
fleet up 4 1 claude,codex          # w1 claude, w2 codex, w3 claude, w4 codex
fleet up 6 2 claude,codex,agy      # claude, codex, agy, claude, codex, agy
fleet up 3 1 shell                 # three empty terminals
```

`fleet up` returns only after every agent is ready for a task.
It uses herdr's own `agent start`, which waits for the agent to finish booting.
So a task you send right after `fleet up` is never typed into an agent that is still starting.

Each agent also gets a name you can use with plain herdr commands.
The name is the workspace name plus the worker label, for example `my-app-w1`.

### Keep the safety prompts

By default every worker starts with its own safety checks off.
To keep the prompts, override the flags for that run:

```bash
# Claude Code with its permission prompts
FLEET_CLAUDE_ARGS="" fleet up 4

# Codex with its sandbox and approval prompts on
FLEET_CODEX_ARGS="--sandbox workspace-write --ask-for-approval on-request" fleet up 2 1 codex
```

### Fleet settings

`fleet` reads these environment variables.
`fleet help` prints the same list.

| Variable | Meaning |
| --- | --- |
| `FLEET_CLAUDE_ARGS`, `FLEET_CODEX_ARGS`, `FLEET_AGY_ARGS` | Flags for that agent. The default turns its checks off. Set to an empty string to keep the prompts. |
| `FLEET_CLAUDE_CMD`, `FLEET_CODEX_CMD`, `FLEET_AGY_CMD` | Run this exact command instead of the default start. |
| `FLEET_FOCUS=0` | Build the workers without switching to the new tab. |
| `FLEET_TIMEOUT` | How long `wait` and `send --wait` block, in milliseconds. The default is 600000 (10 minutes). |
| `FLEET_START_MS` | How long `fleet wait` looks for a turn to start, in milliseconds. The default is 3000. |
| `FLEET_AUTONAME=0` | Send tasks exactly as typed, without asking workers to name themselves. |
| `FLEET_STATE_DIR` | Where renamed workers' numbers are kept. The default is `~/.local/state/fleet`. |

## Delegate work to workers

There are three ways to give workers tasks.

### 1. By hand

Click a worker and type, like any terminal.

### 2. With fleet

Run these from any pane in the same workspace, for example a `terminal` tab.

```bash
fleet send w1 "Add input validation to src/signup.ts and write a test for it"
fleet send w2 "Find why tests/api/orders.test.ts is flaky and fix it"
fleet send w3,w4 "Review the diff on this branch and list real bugs only"
fleet wait all                 # blocks until every busy worker settles
fleet read w2 120              # the last 120 lines from worker 2
```

| Target | Means |
| --- | --- |
| `w3` or `3` | One worker. |
| `pr6969-cool-fix` | One worker, by the name it got from its task. |
| `w1,w4` | Several workers. |
| `all` | Every worker in this workspace. |
| `idle` | Only workers that are idle or done right now. |

Each task also asks the worker to name itself after it, so `w2` becomes something like `fix-flaky-orders` and stays reachable as `w2`.
See [Name workers after their work](#name-workers-after-their-work).

`fleet send --wait <who> "<task>"` sends and then blocks until all of them finish.
Use it when you want one command that hands out work and returns with the results ready to read.

For a long answer, ask the worker to write it to a file and reply with the path, then open the file.

### 3. Ask your main agent to do it

`fleet` is a normal command, so an agent in another pane can drive it.
Tell your main Claude something like:

```text
Split this into three independent tasks.
Use fleet send to give one to each of w1, w2 and w3, then fleet wait all,
then fleet read each worker and summarize what they did.
```

Plain herdr works too, with the agent names `fleet up` printed:

```bash
herdr agent prompt my-app-w1 "Summarize the open TODOs in src/" --wait --timeout 300000
herdr agent read my-app-w1 --source recent-unwrapped --lines 120
```

After a worker is renamed, its herdr agent takes the new name, so use that name or the pane id.

### Avoid workers stepping on each other

Workers in one tab share one folder.
Give them tasks that touch different files, or give each task its own git worktree.
A worktree is a separate checkout on its own branch, and herdr opens each one as its own workspace:

```bash
cd ~/code/my-app
for task in login-form rate-limit audit-log; do
  herdr worktree create --cwd "$PWD" --branch "feat/$task" --no-focus
done
herdr worktree list
```

Pick branch names you want to keep.
With the optional [worktree auto-layout](#optional-auto-layout-for-git-worktrees), each new worktree opens with a `claude` tab ready.

## Manage, maintain and clean up

### See what is running

| Command or key | Shows |
| --- | --- |
| `fleet ls` | Every worker in this workspace with its number, name, agent, status, tab and pane. |
| `herdr agent list` | Every agent in every workspace, as JSON. |
| The sidebar | Each workspace's agents as `working`, `blocked`, `done` or `idle`. |
| `ctrl+b` then `g` | Jump to any agent or terminal. |
| `fleet focus w3` | Jump straight to worker 3. |

### Name workers after their work

Workers start as `w1`, `w2` and so on.
Once they have work, give each one a name you can spot, like `w1` -> `pr6969-cool-fix`.

```bash
fleet rename                       # every worker names itself after its current task
fleet rename w2 pr6969-cool-fix    # or name one yourself
```

A rename changes three things at once: the pane label, the herdr agent name, and the agent's own session name (`/rename`, which Claude, Codex and Agy all accept, even mid-task).
`fleet send` also asks each worker to name itself after the task it gets, so most workers are named without you doing anything.
Set `FLEET_AUTONAME=0` to send tasks exactly as typed.
In the Quick Actions picker, type `name` for the same thing as `fleet rename`.

A renamed worker keeps its number, so `fleet send w2 ...` and `fleet send pr6969-cool-fix ...` reach the same worker.
Fleet keeps that number in `~/.local/state/fleet`, so it survives a herdr restart.
Names use lowercase letters, digits, `-` and `_`, start with a letter, and are at most 32 characters; fleet tidies `PR #6969 Cool fix` into `pr-6969-cool-fix`.

An agent names its own pane with `fleet rename me <name>`.
Codex runs its commands from a shared background server, so it cannot always tell which pane it is in.
Then `rename me` refuses instead of guessing, and the agent uses the pane id that `fleet send` and `fleet rename` give it: `fleet rename w2:p4 <name>`.

### Reset a worker's memory

```bash
fleet clear w2      # one worker
fleet clear all     # every worker
```

Claude and Codex workers get `/clear`, which starts a fresh chat in the same session.
After it, Claude's context counter reads `0 tokens`.
Old text can still sit higher up in the scrollback, which is normal.
A shell worker gets its screen cleared.
Agy has no verified clear command yet, so close and relaunch an Agy worker instead.

### Close workers

```bash
fleet close w3            # one worker
fleet close all           # asks first, then closes every worker
fleet close all --yes     # no question, for scripts
```

Closing a worker ends its agent session.
When the last pane in a tab closes, the tab closes too.

### Close bigger things

| To close | Do |
| --- | --- |
| One pane | `ctrl+b` then `x` |
| A whole workspace | `ctrl+b` then `shift+d`, or `herdr workspace close <id>` |
| A worktree and its workspace | `herdr worktree remove --workspace <id>` |
| Everything, every agent | `herdr server stop` |

`ctrl+b` then `q` only detaches.
Everything keeps running and `herdr` brings it back.

### A maintenance routine

Once a week, or after an update:

```bash
herdr-setup update                             # newest herdr, herdr-plus, integrations, setup files, zsh completion
herdr integration status                       # are agent integrations current?
herdr config check                             # config still valid?
herdr plugin list                              # plugins installed and enabled?
herdr plugin log list --plugin cloudmanic.herdr-plus   # any failed runs?
```

In a repository with many worktrees, `herdr worktree list` marks checkouts whose folder is gone as prunable.
`git worktree prune` removes those stale records and leaves real checkouts alone.

## Command suggestions in the shell

Herdr panes run your normal shell.
Gray inline suggestions and tab-completion menus come from your shell setup, not from herdr.
Some terminals build them in.
In plain zsh you add them yourself.

On macOS with Homebrew:

```bash
brew install zsh-autosuggestions zsh-syntax-highlighting
mkdir -p ~/.zfunc && herdr completion zsh > ~/.zfunc/_herdr
```

Then add this block to the end of `~/.zshrc` and open a new pane:

```zsh
# --- Command suggestions, completion and shared history ---
# Gray inline suggestions come from zsh-autosuggestions: accept with the right arrow or End.
# Tab opens a completion menu. History is shared across herdr panes, so a command typed in
# one pane is suggested in every other pane.
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
fpath=("$HOME/.zfunc" $fpath)                  # herdr completion: ~/.zfunc/_herdr
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
_hb="${HOMEBREW_PREFIX:-/opt/homebrew}/share"
[ -r "$_hb/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$_hb/zsh-autosuggestions/zsh-autosuggestions.zsh"
# Syntax highlighting must load last.
[ -r "$_hb/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && source "$_hb/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset _hb
```

What you get:

1. As you type, the rest of a matching command appears in gray.
   Press `→` or `End` to accept it.
2. `Tab` opens a menu of completions, including every `herdr` subcommand and flag.
3. Commands turn green when they exist and red when they do not.
4. A command typed in one pane is suggested in every other pane, because history is shared.

On Linux, install the same two packages with your package manager, and change the two `source` paths to where it put them (often `/usr/share/zsh-autosuggestions` and `/usr/share/zsh-syntax-highlighting`).

## The working style this setup is built for

The launchers remove friction.
They do not replace good habits.
This is the working agreement the setup was designed around.
Take what fits and change the rest.

| Habit | How the setup supports it |
| --- | --- |
| One workspace per project, one tab per job | The Projects picker builds a `claude` tab and a `terminal` tab in one keypress. |
| Several agents in parallel when the work splits cleanly | `fleet up` builds the grid, `fleet send` hands out tasks, `fleet wait` collects them. |
| One git worktree per task or pull request | `herdr worktree create` makes the checkout. The optional layout fills it with tabs. |
| Run the real thing next to the agent | Every project has a `terminal` tab to reproduce a bug or check output yourself. |
| Keep sessions alive | Herdr runs in the background. Close the window and your agents keep going. |

### Why written rules matter more with these launchers

> [!IMPORTANT]
> With permission prompts off, nothing stops an agent from running a command except the rules you gave it, and git.
> Put your rules in the file your agent reads at startup.
> That file is `CLAUDE.md` for Claude Code and `AGENTS.md` for Codex and many other agents.
> Codex reads `~/.codex/AGENTS.md` plus `AGENTS.md` files from the project root down, so a rules file elsewhere in your home folder does not reach it.

A starter set you can paste into either file and edit:

```markdown
## Working agreement

* Work on the branch that is checked out. Never create, switch or delete branches unless I ask.
* Never run git add, commit, push, pull, merge, rebase, reset, stash or checkout unless I explicitly ask.
* When I ask for a new branch, push it with `git push -u` so it tracks the right remote.
* Never run destructive database commands (migrate:fresh, db:reset, DROP, TRUNCATE, DELETE without WHERE) without asking first. This applies to staging too.
* Reproduce a bug before fixing it, and write a failing test first.
* Run only the tests that cover the code you changed. CI runs the full suite.
* Verify any change to what a user sees in a real browser, not only with unit tests.
* Update the docs in the same change as the code.
* When testing permissions or security, use only credentials I supplied.
```

### One rules file for every agent

Keep your rules in one file, `~/AGENTS.md`, and copy them to the files the other agents read.
Claude Code reads `~/.claude/CLAUDE.md`, so make that a link:

```bash
ln -s ~/AGENTS.md ~/.claude/CLAUDE.md      # only if CLAUDE.md does not exist yet
```

Codex reads `~/.codex/AGENTS.md`, and Agy and Gemini read `~/.gemini/GEMINI.md`.
The optional [`sync-agent-rules`](../files/extras/sync-agent-rules) script copies `~/AGENTS.md` into both.
It writes inside a marked block that it owns, and everything else in those files is left alone.
It is not installed by default.

Install it from the root of a copy of this repo:

```bash
cp files/extras/sync-agent-rules ~/.local/bin/ && chmod +x ~/.local/bin/sync-agent-rules
```

Run it once now, and again after every edit to `~/AGENTS.md`:

```bash
sync-agent-rules
```

Check that an agent really sees the rules.
Run this from a folder with no project files of its own:

```bash
cd "$(mktemp -d)"
codex exec --skip-git-repo-check --ephemeral -s read-only \
  "From your loaded instructions only: quote the start of any rule about destructive database commands." </dev/null
agy --print "From your loaded instructions only: quote the start of any rule about destructive database commands." </dev/null
```

If another tool manages one of those files and removes the block, run `sync-agent-rules` again.

### The habits behind it

1. **Plan before large changes.**
   Ask for a plan, read it, then let the agent build.
2. **Reproduce first.**
   For a bug, recreate it the way a user would see it before touching code.
3. **Failing test, then fix.**
   The test is your proof the bug is gone.
4. **Focused tests.**
   Run the tests that cover your change, not the whole suite on every edit.
   Typecheck and build still run when types or bundling change.
5. **Look at the UI.**
   If a change is visible, open it in a browser and check it.
6. **You own git.**
   The agents edit files.
   You decide what is committed, pushed and merged.
7. **Review the diff.**
   Read what changed before it leaves your machine.

## Daily cheat sheet

Your keys:

| Keys | Opens |
| --- | --- |
| `ctrl+b` then `↓` | Quick Actions (launchers, grid, workers) |
| `ctrl+b` then `↑` | Projects |

Inside either picker:

| Key | Does |
| --- | --- |
| Type | Filters the list. |
| `↑` / `↓` | Moves the highlight. |
| `Enter` | Runs or opens the highlighted row. |
| `Esc` | Goes back one step, or closes the picker. |
| `ctrl+g` (Projects only) | Opens as a git worktree. |

Herdr keys (all start with `ctrl+b`):

| Keys | Does |
| --- | --- |
| `c` | New tab |
| `n` / `p` | Next / previous tab |
| `1` to `9` | Jump to tab |
| `v` | Split right |
| `-` | Split down |
| `h` `j` `k` `l` | Move between panes |
| `z` | Zoom the focused pane |
| `x` | Close pane |
| `w` | Workspace navigation |
| `shift+n` | New workspace |
| `shift+d` | Close workspace |
| `g` | Go to any agent or terminal |
| `[` | Copy mode |
| `q` | Detach (agents keep running) |
| `?` | Show every binding |

If you use the Herdr desktop app on macOS, it adds native shortcuts.
These are its defaults:

| Shortcut | Does |
| --- | --- |
| `⌘T` | New tab |
| `⌘⇧N` | New workspace |
| `⌘N` | New worktree |
| `⌘D` / `⌘⇧D` | Split right / split down |
| `⌘⌥` + arrow | Move between panes |
| `⌘⇧[` / `⌘⇧]` | Previous / next tab |
| `⌘1` to `⌘9` | Jump to tab |
| `⌘⇧↩` | Zoom the focused pane |
| `⌘W` / `⌘⇧W` | Close pane / close tab |
| `⌘P` | Workspace picker |
| `⌘⇧P` | Command palette |
| `⌘B` | Toggle sidebar |
| `⌘/` | Show shortcuts |

The fleet commands:

| Command | Does |
| --- | --- |
| `fleet up 6 2 claude` | Six Claude workers in two tabs of three. |
| `fleet ls` | List workers with agent, status, tab and pane. |
| `fleet send w2 "task"` | Type a task into worker 2. |
| `fleet send --wait all "task"` | Send to every worker and wait until all finish. |
| `fleet wait all` | Wait until busy workers settle. |
| `fleet read w2 120` | Last 120 lines from worker 2. |
| `fleet clear all` | Fresh chat in every Claude and Codex worker. |
| `fleet focus w3` | Jump to worker 3. |
| `fleet close all` | Close every worker (asks first). |
| `fleet help` | Everything above, plus the environment settings. |

To stop herdr and every pane for real:

```bash
herdr server stop
```

## What the installer created

You do not need this section to use the setup.
It is here so you can see, edit, or rebuild any piece by hand.

All plugin files live in herdr's managed plugin config folder:

```text
~/.config/herdr/plugins/config/cloudmanic.herdr-plus/
├── projects/                 your project templates (Step 4)
├── quick-actions/            what the Quick Actions picker lists
│   ├── claude-dangerously-skip-permission.toml
│   ├── agy-dangerously-skip-permission.toml
│   ├── codex-dangerously-skip-sandbox.toml
│   ├── agent-grid-2x2.toml
│   ├── workers.toml
│   ├── workers-custom.toml
│   ├── name-workers.toml
│   └── update-setup.toml
├── scripts/
│   ├── agent-tab.sh          opens one tab and runs one command
│   ├── fleet.sh              builds worker grids and drives the workers
│   └── herdr-setup.sh        checks for and installs updates
└── worktrees/                optional, see the git worktrees section
```

`~/.local/bin/fleet` is a link to `scripts/fleet.sh`, and `~/.local/bin/herdr-setup` a link to `scripts/herdr-setup.sh`.
Herdr keeps the plugin config folder across plugin updates and uninstalls.

The source of every file is in this repo:

| File | Source | What it does |
| --- | --- | --- |
| `scripts/agent-tab.sh` | [files/scripts/agent-tab.sh](../files/scripts/agent-tab.sh) | Opens one tab in the current workspace and runs one command in it. |
| `scripts/fleet.sh` | [files/scripts/fleet.sh](../files/scripts/fleet.sh) | Builds worker grids and drives the workers. |
| `scripts/herdr-setup.sh` | [files/scripts/herdr-setup.sh](../files/scripts/herdr-setup.sh) | `herdr-setup check` and `herdr-setup update`. |
| `quick-actions/claude-dangerously-skip-permission.toml` | [files/quick-actions/claude-dangerously-skip-permission.toml](../files/quick-actions/claude-dangerously-skip-permission.toml) | The Claude launcher. |
| `quick-actions/agy-dangerously-skip-permission.toml` | [files/quick-actions/agy-dangerously-skip-permission.toml](../files/quick-actions/agy-dangerously-skip-permission.toml) | The Agy launcher. |
| `quick-actions/codex-dangerously-skip-sandbox.toml` | [files/quick-actions/codex-dangerously-skip-sandbox.toml](../files/quick-actions/codex-dangerously-skip-sandbox.toml) | The Codex launcher. |
| `quick-actions/agent-grid-2x2.toml` | [files/quick-actions/agent-grid-2x2.toml](../files/quick-actions/agent-grid-2x2.toml) | One tab with Claude, Codex, Agy and a shell in a 2x2 grid. |
| `quick-actions/workers.toml` | [files/quick-actions/workers.toml](../files/quick-actions/workers.toml) | The **Workers** preset list. |
| `quick-actions/workers-custom.toml` | [files/quick-actions/workers-custom.toml](../files/quick-actions/workers-custom.toml) | The **Workers (custom)** form. |
| `quick-actions/name-workers.toml` | [files/quick-actions/name-workers.toml](../files/quick-actions/name-workers.toml) | **Name workers**: every worker renames itself after its task. |
| `quick-actions/update-setup.toml` | [files/quick-actions/update-setup.toml](../files/quick-actions/update-setup.toml) | **Update herdr setup**: runs `herdr-setup update` in a new tab. |
| `worktrees/default.toml` | [files/worktrees/default.toml](../files/worktrees/default.toml) | Optional. The installer does not create it. |

To copy the files yourself instead of running the installer, use a copy of this repo:

```bash
git clone https://github.com/mrx-arafat/herdr-setup
D="$(herdr plugin config-dir cloudmanic.herdr-plus)"
mkdir -p "$D/scripts" "$D/quick-actions" ~/.local/bin
cp herdr-setup/files/scripts/*.sh "$D/scripts/"
cp herdr-setup/files/quick-actions/*.toml "$D/quick-actions/"
chmod +x "$D/scripts/"*.sh
ln -s "$D/scripts/fleet.sh" ~/.local/bin/fleet
```

Then add the key bindings from [Bind the keys yourself](#bind-the-keys-yourself).

### Why there are helper scripts

A Quick Action is a shell command.
herdr-plus runs it with `sh -c`, with no keyboard attached.
An interactive program such as `claude` cannot work that way.

So each launcher calls a script.
The script asks herdr to create real tabs and panes, then starts the agent inside them.

### How scripts/fleet.sh builds a grid

1. It picks the number of columns as the square root of the worker count, rounded up.
2. It splits the first pane to the right once per extra column, giving each split the share that keeps columns equal.
3. It splits each column down the same way for its rows.
4. It labels every pane `w1`, `w2`, ... in reading order.
5. It starts every agent at once with `herdr agent start`, which returns when the agent is ready.

The header of the script lists every command and setting.

### Anatomy of a Quick Action

This is the whole Claude launcher:

```toml
# Type "claude" in the Quick Actions picker. Opens a new tab in the current
# workspace, in the directory you launched from, running claude with permission
# prompts off. Quick actions have no TTY, so scripts/agent-tab.sh makes the pane.
name = "Claude Dangerously Skip Permission"
description = "new tab here"
command = "sh \"$HOME/.config/herdr/plugins/config/cloudmanic.herdr-plus/scripts/agent-tab.sh\" claude 'claude --dangerously-skip-permissions'"
```

| Field | Meaning |
| --- | --- |
| `name` | What the picker shows. Also what you type to find it. |
| `description` | Optional grey text. Keep it short, see the tip below. |
| `command` | The shell command to run. |
| `type` | Optional. `command` (default), `select` (pick from a second list) or `form` (type a value). |
| `[[options]]` | For `select`: each row's `label`, `value` and `description`. A row with only `heading` is a group title. |
| `[form]` | For `form`: the `prompt` and `placeholder` of the text field. |

For `select` and `form` actions, the chosen value is added to the end of `command` as one quoted argument.
That is how **Workers** passes `6 2 claude` to `fleet.sh up`.
See [workers.toml](../files/quick-actions/workers.toml) for a `select` action and [workers-custom.toml](../files/quick-actions/workers-custom.toml) for a `form` action.

> [!TIP]
> Keep `description` short.
> The picker fuzzy-matches your typing against the name **and** the description together.
> With long descriptions, typing `agy` ranked "Search Google" above the Agy launcher, because the letters a, g and y appear in order in its text.
> Short descriptions fixed it.

### The key bindings in config.toml

Herdr's config file is `~/.config/herdr/config.toml`.
The installer appended these two blocks to it:

```toml
[[keys.command]]
key = "prefix+up"
type = "plugin_action"
command = "cloudmanic.herdr-plus.projects"
description = "herdr-plus: projects"

[[keys.command]]
key = "prefix+down"
type = "plugin_action"
command = "cloudmanic.herdr-plus.quick-actions"
description = "herdr-plus: quick actions"
```

`command` is `<plugin id>.<action id>`.
herdr-plus has these actions: `projects`, `quick-actions` and `ping` (a smoke test).

## Bind the keys yourself

Use this if the installer skipped the bindings because `prefix+up` or `prefix+down` was already in use, or if you want other keys.

1. Open `~/.config/herdr/config.toml` in any editor.
2. Add the two blocks above, changing `key` to whatever you like.
3. Reload and validate:

```bash
herdr server reload-config
herdr config check
```

A key can be `prefix+<key>` (press the prefix first) or a direct chord such as `ctrl+alt+p`.
Direct chords can be eaten by your terminal or operating system before herdr sees them.
`prefix+<key>` is the safest choice.

Without any binding, open a picker from any herdr pane:

```bash
herdr plugin action invoke quick-actions --plugin cloudmanic.herdr-plus
herdr plugin action invoke projects --plugin cloudmanic.herdr-plus
```

## Add your own launcher

Copy one of the launcher files, change the name and the command, and save it in `quick-actions/`.
The next time you open Quick Actions it is there.

```toml
name = "My Agent"
description = "new tab here"
command = "sh \"$HOME/.config/herdr/plugins/config/cloudmanic.herdr-plus/scripts/agent-tab.sh\" my-agent 'my-agent --some-flag'"
```

The word after `agent-tab.sh` (`my-agent` above) is the tab label.
The quoted text after it is the exact command typed into the new tab.

A fixed worker layout is one line too:

```toml
name = "Review squad"
description = "3 panes"
command = "sh \"$HOME/.config/herdr/plugins/config/cloudmanic.herdr-plus/scripts/fleet.sh\" up '3 1 claude,codex,claude'"
```

A repository can carry its own launchers in `<repo>/.herdr-plus/quick-actions/`.
They show up under a "Project" heading when you open Quick Actions from inside that repository.

To remove a launcher, delete its file.

## Optional: auto-layout for git worktrees

A git worktree is a second checkout of the same repository in its own folder, on its own branch.
By default herdr-plus does nothing special with a new worktree's workspace.
With a layout file it fills the workspace with your tabs the moment herdr creates or opens a worktree.

Create `worktrees/default.toml` in the plugin config folder.
A ready-made copy is in [files/worktrees/default.toml](../files/worktrees/default.toml).

```toml
# Auto-layout for every new git worktree that herdr creates or opens.
# herdr-plus fires on the worktree.created and worktree.opened events and fills
# the new workspace with these tabs. repo = "*" matches any repository that has
# no layout of its own. Delete this file to turn the feature off.
repo = "*"

[[tabs]]
name = "claude"
command = "claude --dangerously-skip-permissions"

[[tabs]]
name = "terminal"
```

| File says | Applies to |
| --- | --- |
| `repo = "*"` | Every repository that has no layout of its own. |
| `repo = "my-app"` | Worktrees of the repository whose folder is named `my-app`. |
| `repo = "my-app"` and `branch = "main"` | Only that repository and that branch. |

The most specific layout wins: repository plus branch, then repository, then wildcard plus branch, then wildcard.
A layout is skipped if the new workspace already has tabs.

> [!WARNING]
> This file starts Claude with permission prompts off in every new worktree.
> Delete `worktrees/default.toml` to turn the whole feature off.
> The installer does not create it.

If nothing happens, run `herdr plugin log list --plugin cloudmanic.herdr-plus` and look for a `worktree.created` entry.

## Optional: keep agent integrations current

Herdr detects agents by watching their terminals.
An integration adds a small hook inside the agent itself.
It lets herdr resume the same agent session after a server restart, and some agents also report their state directly.

```bash
herdr integration status                 # current, outdated or not installed
herdr integration install claude
herdr integration install codex
herdr integration install antigravity-cli
```

> [!NOTE]
> An integration edits the agent's own hook configuration, for example `~/.claude/settings.json`.
> Herdr overwrites only its own managed hook file and its own entries.
> Back up the file first if you keep that configuration under careful control.

## Verify everything works

1. `herdr plugin list` shows `cloudmanic.herdr-plus (Herdr Plus)` as `enabled`.
2. `herdr config check` prints `config: ok`.
3. `ctrl+b` then `↓` lists the launchers, **Agent Grid 2x2**, **Workers**, **Workers (custom)**, **Name workers** and **Update herdr setup**.
4. Typing `claude` and pressing `Enter` opens a `claude` tab that shows `bypass permissions on`.
5. `fleet help` prints the command list.
6. `fleet up 2` opens two workers and prints `ready` for both.
7. `fleet send --wait all "Reply with the word ready"` prints `done` for both, and `fleet read all` shows the reply.
8. `fleet close all --yes` closes them, and `fleet ls` says there are no workers.
9. `ctrl+b` then `↑` lists the projects you added.

## Troubleshooting

| Problem | Cause and fix |
| --- | --- |
| `ctrl+b` then an arrow does nothing | Run `herdr config check`, then `ctrl+b` `?`. If `herdr plugin action invoke quick-actions --plugin cloudmanic.herdr-plus` opens the picker, only the key is blocked, so pick another key. |
| I changed `config.toml` and nothing changed | Run `herdr server reload-config`. |
| `fleet: run this inside a herdr pane` | `fleet` needs the workspace herdr sets in every pane. Run it in a herdr pane, not in another terminal. |
| `fleet: command not found` | `~/.local/bin` is not on your `PATH`. Use `alias fleet='sh ~/.config/herdr/plugins/config/cloudmanic.herdr-plus/scripts/fleet.sh'`. |
| A worker says `not ready` after `fleet up` | The agent stopped at a startup question, for example "trust this folder". Click the worker, answer it, and it becomes ready. |
| A task sits in the input box unsent | It was typed by hand into an agent that was still booting. `fleet send` waits for readiness, so use it, or press `Enter` in that pane. |
| `fleet clear` ran but old text is still on screen | That is scrollback. Check that Claude's context counter reads `0 tokens`. |
| Typing `agy` shows another row first | A launcher description is too long. Shorten it. |
| A project is missing from the picker | `working_dir` must exist, and the TOML must be valid. |
| No gray suggestions in the shell | See [Command suggestions in the shell](#command-suggestions-in-the-shell), then open a new pane. |
| Something failed and there is no message | `herdr plugin log list --plugin cloudmanic.herdr-plus` shows each run with its status and exit code. |

## Safety notes

> [!WARNING]
> These launchers turn safety features off.
> Use them only in places where an agent making a mistake is acceptable.

| Launcher | Flag | Effect |
| --- | --- | --- |
| Claude | `--dangerously-skip-permissions` | Claude no longer asks before running commands or editing files. |
| Agy | `--dangerously-skip-permissions` | Agy auto-approves tool permission requests. |
| Codex | `--dangerously-bypass-approvals-and-sandbox` | Codex skips all confirmation prompts and runs commands without a sandbox. |

`grid` and `workers` start several of these at once.
For Codex, the CLI's own help text calls its flag "EXTREMELY DANGEROUS" and says it is intended solely for environments that are externally sandboxed.

Good practice:

1. Use these launchers in repositories under version control, with a clean working tree, so you can review and undo changes.
2. Keep secrets out of the folder you launch from, or use a disposable machine, container or VM for risky work.
3. Put your rules in `CLAUDE.md` and `AGENTS.md`, see [the working style section](#the-working-style-this-setup-is-built-for).
4. Use `FLEET_CLAUDE_ARGS=""` and friends to keep prompts on for a run.
5. Read any script before you run it, including `install.sh`.

Installing a herdr plugin runs code from that plugin's repository on your machine.
Install plugins only from authors you trust.

## Update and uninstall

One command keeps everything current: herdr itself, the herdr-plus plugin, herdr's agent integrations and this setup's scripts and Quick Actions.

```bash
herdr-setup check     # what is out of date, changes nothing
herdr-setup update    # update all of it
```

Run `update` in a plain terminal, not in a herdr pane: herdr refuses to update itself from inside herdr.
Inside a herdr pane, and from the Quick Actions picker (type `update`), it updates everything else and tells you that herdr itself is left for a plain terminal.
Both commands download the newest installer from this repo and run it, so the update logic is always current.

What `update` does:

1. Updates herdr the way it was installed, with the command herdr itself names: `herdr update` for herdr's own installer, `brew update && brew upgrade herdr` for Homebrew.
   For mise or Nix it tells you the command instead.
   `herdr update` runs without a terminal to answer it, so if a release ever needs the running server stopped, herdr declines rather than closing your panes.
2. Reinstalls herdr-plus when GitHub has a newer commit than yours. Its config folder, with your projects and Quick Actions, is kept.
3. Refreshes any installed agent integration that `herdr integration status` does not list as current.
4. Replaces each script or Quick Action from this repo that differs from the newest one, after copying yours to `~/.config/herdr/backups/herdr-setup-<time>/`.
   Your own extra files in those folders are never touched.
5. Refreshes `~/.zfunc/_herdr` if you use the optional zsh completion.

It never restarts herdr, so panes and agents keep running.
When the running server is older than the new binary, it says so.
New server features arrive after you restart: when no agent is mid-task, run `herdr server stop`, then start herdr again.

On an install from before `herdr-setup` existed, run the installer once with `--update` to get it:

```bash
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | sh -s -- --update
```

To remove the setup:

```bash
herdr plugin uninstall cloudmanic.herdr-plus    # remove the plugin
rm ~/.local/bin/fleet ~/.local/bin/herdr-setup  # remove the command links
```

After uninstalling, delete the two `[[keys.command]]` blocks that mention `cloudmanic.herdr-plus` from `~/.config/herdr/config.toml` and run `herdr server reload-config`.
Skip the `rm` for a command the installer printed an alias line for instead of linking it.
Herdr keeps the plugin's config folder when you uninstall, so your projects, launchers and scripts survive a reinstall.

## Optional extras

### Theme

```toml
[theme]
name = "rose-pine"
auto_switch = false
```

### A file viewer plugin

`herdr-file-viewer` is a read-only, git-aware file viewer that opens in a split pane.

```bash
herdr plugin install smarzban/herdr-file-viewer --yes
```

```toml
[[keys.command]]
key = "prefix+f"
type = "plugin_action"
command = "herdr-file-viewer.open-file-viewer"
description = "open file viewer in split"

[[keys.command]]
key = "prefix+shift+f"
type = "plugin_action"
command = "herdr-file-viewer.open-file-viewer-tab"
description = "open file viewer in tab"
```

## Reference links

- This repo: <https://github.com/mrx-arafat/herdr-setup>
- Interactive manual: <https://mrx-arafat.github.io/herdr-setup/>
- Herdr docs index: <https://herdr.dev/llms.txt>
- Install: <https://herdr.dev/docs/install/>
- Keyboard and the prefix: <https://herdr.dev/docs/keyboard/>
- Agent automation (agent start, prompt, wait): <https://herdr.dev/docs/agent-automation/>
- Plugins: <https://herdr.dev/docs/plugins/>
- herdr-plus: <https://github.com/cloudmanic/herdr-plus>

## What was tested

Everything below was run on one machine before this guide was published.

| Component | Version |
| --- | --- |
| herdr | 0.9.3 |
| herdr-plus plugin | 0.1.24 |
| Claude Code | 2.1.296 |
| Codex CLI | 0.162.1 |
| Antigravity CLI (`agy`) | 1.3.3 |
| zsh | 5.9 |
| OS | macOS 26.5 |

Verified:

1. Typing `claude`, `agy`, `codex`, `grid` and `workers` in Quick Actions puts the right entry first.
2. Each agent launcher opens a tab in the right folder and starts the agent.
   Claude shows `bypass permissions on` and Codex shows `permissions: YOLO mode`.
3. `fleet up` built 11 layouts, from 1 to 9 workers over 1 to 3 tabs, with equal columns and rows checked against herdr's own layout report.
4. Agents cycle in the right order (`claude,codex,agy`), and a second `fleet up` keeps counting.
5. With real Claude workers: `fleet up` returned only when both were ready, `fleet send --wait all` and `fleet send` plus `fleet wait` both came back with each worker's reply, `fleet clear` reset the context to `0 tokens`, and `fleet close all` removed them.
6. The **Workers** preset and **Workers (custom)** form both launch through the picker.
7. Projects open their workspace with a working `claude` tab and a `terminal` tab.
8. The wildcard worktree layout fired on `worktree.created` in a throwaway repository.
9. Shell suggestions work in a herdr pane: typing `herdr plu` showed a full gray suggestion, and `Tab` completed herdr subcommands.
10. The installer passed a sandbox suite ([tests/sandbox.sh](../tests/sandbox.sh), also run in CI) covering: a fresh run, a second run, an existing key binding, a config with no trailing newline, no `--yes` and no terminal to ask on, an old herdr, a missing `jq` or `herdr`, an existing `fleet` command, `~/.local/bin` missing from `PATH`, a run piped like `curl | sh -s -- --yes`, a failed download and an unknown option.
11. `sync-agent-rules` was run three times with identical results.
    Real Codex and Agy sessions were confirmed to read the synced rules: both quoted them from a neutral folder with no project files of its own.
12. `fleet.sh`, `agent-tab.sh` and `install.sh` pass `shellcheck`, and CI lints every shell script in the repo with it.
13. `fleet rename`, with Claude Code 2.1.299, Codex 0.162.1 and Agy 1.3.5 workers: each renamed its pane label, herdr agent name and own session after its task, both when asked by `fleet rename` and from the request `fleet send` adds, including while busy.
    A renamed worker kept its number through a second rename and a pane renamed by hand, `fleet close` removed its record, and duplicate or unusable names were refused.
    Inside Codex, `fleet rename me` refused instead of renaming the wrong pane, because Codex's commands carried another pane's `HERDR_PANE_ID`.
14. `herdr-setup update`, run from GitHub on a real install with 21 agents running.
    Inside a herdr pane it left herdr for a plain terminal, as herdr requires, and replaced the two changed setup files after backing them up.
    From a plain terminal it updated herdr 0.9.3 to 0.9.4, refreshed the Codex integration the new herdr flagged as stale, and advised a restart; the server stayed on 0.9.3 and all 21 agents kept running.
    A following `herdr-setup check` reported everything up to date.
    herdr-plus was already current, so its reinstall path is covered by the sandbox suite only.
    The sandbox suite covers check and update with a newer herdr, an older herdr-plus, a stale integration, a changed file (replaced, old copy backed up), a second run with nothing to do, a Homebrew herdr, and the `herdr-setup` command itself.

Not verified:

1. Linux and Windows.
   CI runs the installer sandbox tests on Linux and macOS, but herdr itself, the agents and `fleet` were only run on macOS.
2. The physical `ctrl+b` then arrow key presses, which were driven through herdr's CLI.
3. Whether Agy's own approval mode is fully off.
   Agy accepts the flag and starts, but its screen has no banner to confirm it.
4. A clear command for Agy workers.
5. A renamed worker's number across a real herdr server restart.
   Fleet keeps it on disk, since herdr saves pane labels and agent names but not pane metadata.
   No restart was run.
6. Typing `name` in the Quick Actions picker; the **Name workers** command line itself was run.
