# herdr-setup

One command sets up [herdr](https://herdr.dev) for AI coding agents.
You get one-key launchers for Claude Code, Codex and Agy, and a `fleet` command that runs and drives several agents at once.

![Interactive manual](docs/manual.png)

Herdr is a terminal workspace manager for AI coding agents.
It keeps your terminals running in the background and shows which agent needs you.
This repo adds the [herdr-plus](https://github.com/cloudmanic/herdr-plus) plugin, six ready-made Quick Actions and `fleet`.
You do not need to know herdr first.

## Install in one line

```sh
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | sh
```

The installer asks before it installs the plugin.
It asks on your terminal, even when the script is piped from `curl`.

No questions:

```sh
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | sh -s -- --yes
```

Read it first (recommended):

```sh
curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh -o install.sh
less install.sh
sh install.sh
```

What the installer does, in order:

1. Checks that herdr 0.7.0 or newer, `jq` and `curl` are installed.
2. Installs the herdr-plus plugin with `herdr plugin install cloudmanic/herdr-plus`, after asking.
3. Downloads `agent-tab.sh`, `fleet.sh` and six Quick Actions from [`files/`](files/) into the plugin's config folder (`~/.config/herdr/plugins/config/cloudmanic.herdr-plus/`).
4. Links `fleet` into `~/.local/bin` when that folder is on your `PATH`, otherwise prints an alias line.
5. Adds `prefix+up` (Projects) and `prefix+down` (Quick Actions) to `~/.config/herdr/config.toml`.
6. Reloads herdr and runs `herdr config check`.

It is safe to run again.
It never overwrites a file that exists, never replaces an existing `fleet` command, skips keys you already use, and makes a timestamped backup of `config.toml` before it edits it.
To install from another branch or tag, set `HERDR_SETUP_REF` (default `main`).

> [!WARNING]
> The launchers start agents with permission prompts or the sandbox turned **off**.
> Use them only in git repositories you can review and undo, and read [Safety notes](docs/GUIDE.md#safety-notes) first.
> To keep the prompts for a fleet run, set the flags to nothing: `FLEET_CLAUDE_ARGS="" fleet up 4`.
> For a single launcher, edit its command in `quick-actions/` inside the plugin config folder.

## What you get

`ctrl+b` is herdr's default prefix key.
You press it, let go, then press the next key.

| You do | What happens |
| --- | --- |
| `ctrl+b` then `↓`, type `claude`, `Enter` | A new tab opens in your current folder and runs `claude --dangerously-skip-permissions`. |
| `ctrl+b` then `↓`, type `agy`, `Enter` | A new tab opens in your current folder and runs `agy --dangerously-skip-permissions`. |
| `ctrl+b` then `↓`, type `codex`, `Enter` | A new tab opens in your current folder and runs `codex --dangerously-bypass-approvals-and-sandbox`. |
| `ctrl+b` then `↓`, type `grid`, `Enter` | One tab with a balanced 2x2 grid: Claude, Codex, Agy and a plain shell. |
| `ctrl+b` then `↓`, type `workers`, pick a layout | 2 to 8 workers in one or more tabs, for example six workers as two tabs of three. |
| `ctrl+b` then `↑`, pick a project, `Enter` | A new workspace opens for that project with a `claude` tab and a `terminal` tab. |
| `fleet send w2 "fix the failing test"` | Types that task into worker 2. `fleet wait`, `fleet read`, `fleet clear` and `fleet close` do the rest. |

Both pickers are fuzzy finders.
Type a few letters to narrow the list, and press `Esc` to close one without doing anything.

## Requirements

1. macOS or Linux with a terminal.
   Windows is not covered.
2. herdr 0.7.0 or newer.
3. `jq` and `curl`.
4. At least one agent CLI installed and signed in: `claude`, `agy` or `codex`.

Install herdr and `jq` if you do not have them:

```sh
curl -fsSL https://herdr.dev/install.sh | sh     # or: brew install herdr
brew install jq                                   # Debian or Ubuntu: sudo apt install jq
herdr --version
```

## Quick start

1. Install herdr and `jq` as shown above.
2. Run the [one-line installer](#install-in-one-line).
3. Open herdr in a project folder, press `ctrl+b` then `↓`, type `claude` and press `Enter`.

```sh
cd ~/some-project
herdr
```

A tab named `claude` opens in the same folder.
At the bottom of Claude's screen you should see `bypass permissions on`.
Press `ctrl+b` then `?` at any time to see every herdr key.

## Run many agents with fleet

A worker is a pane labelled `w1`, `w2` and so on.
`fleet` builds the panes, starts an agent in each, and lets you address them by label.
Run it from any pane inside a herdr workspace.

| Command | Does |
| --- | --- |
| `fleet up 6 2 claude` | Six Claude workers in two tabs of three. |
| `fleet ls` | List workers with agent, status, tab and pane. |
| `fleet send w2 "task"` | Type a task into worker 2. |
| `fleet send --wait all "task"` | Send to every worker and wait until all finish. |
| `fleet wait all` | Wait until busy workers settle. |
| `fleet read w2 120` | Show the last 120 lines from worker 2. |
| `fleet clear all` | Start a fresh chat in every Claude and Codex worker. |
| `fleet close all` | Close every worker (asks first). |

Targets are `w3` or `3`, a list like `w1,w4`, `all`, or `idle`.

Three examples:

```sh
# 1. Four Claude workers in a 2x2 grid
fleet up 4

# 2. Six mixed workers in two tabs: claude, codex, agy, claude, codex, agy
fleet up 6 2 claude,codex,agy

# 3. Hand out different tasks, wait for all of them, then read the answers
fleet send w1 "Add input validation to src/signup.ts and write a test for it"
fleet send w2 "Find why tests/api/orders.test.ts is flaky and fix it"
fleet wait all
fleet read all 80
```

The full story (layouts, agent choices, environment settings, working in separate git worktrees) is in [Run many workers](docs/GUIDE.md#run-many-workers).

## Docs

1. [Interactive manual](https://mrx-arafat.github.io/herdr-setup/) - a clickable tour of the keys, launchers and `fleet`.
2. [docs/GUIDE.md](docs/GUIDE.md) - the full beginner guide, from "what is a pane" to uninstalling.

## Update and uninstall

Update herdr:

```sh
herdr update
```

To refresh a file from this repo, delete your copy of it and run the installer again.
The installer never overwrites a file that exists.

To remove everything:

```sh
herdr plugin uninstall cloudmanic.herdr-plus
rm ~/.local/bin/fleet
```

Then delete the two `[[keys.command]]` blocks that mention `cloudmanic.herdr-plus` from `~/.config/herdr/config.toml`, and reload:

```sh
herdr server reload-config
```

Skip the `rm` if the installer printed an alias line instead of linking `fleet`.
Herdr keeps the plugin's config folder when you uninstall, so your projects and launchers survive a reinstall.

## What is in this repo

- [`install.sh`](install.sh) - the one-line installer.
- [`files/scripts/`](files/scripts/) - `agent-tab.sh` (opens one tab and runs one command) and `fleet.sh` (builds and drives workers).
- [`files/quick-actions/`](files/quick-actions/) - the six Quick Actions: Claude, Agy and Codex launchers, `agent-grid-2x2`, `workers` and `workers-custom`.
- [`files/worktrees/default.toml`](files/worktrees/default.toml) - optional auto-layout for git worktrees, not installed by default.
- [`files/extras/sync-agent-rules`](files/extras/sync-agent-rules) - optional script that keeps one rules file for every agent.
- [`docs/index.html`](docs/index.html) - the interactive manual, served by GitHub Pages.
- [`docs/GUIDE.md`](docs/GUIDE.md) and `docs/manual.png` - the written guide and the screenshot above.
- [`tests/sandbox.sh`](tests/sandbox.sh) - installer tests, run in CI.
- [`.github/workflows/check.yml`](.github/workflows/check.yml) - CI: shellcheck and the sandbox tests.
- [`LICENSE`](LICENSE) - MIT.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `ctrl+b` then an arrow does nothing | Run `herdr config check`. If `herdr plugin action invoke quick-actions --plugin cloudmanic.herdr-plus` opens the picker, only the key is blocked, so bind another key. |
| I changed `config.toml` and nothing changed | Run `herdr server reload-config`. |
| `fleet: run this inside a herdr pane` | Run `fleet` in a pane inside herdr, not in another terminal. |
| `fleet: command not found` | `~/.local/bin` is not on your `PATH`. Use the alias line the installer printed. |
| A worker says `not ready` after `fleet up` | The agent stopped at a startup question, for example "trust this folder". Click the worker and answer it. |

More fixes are in the [Troubleshooting](docs/GUIDE.md#troubleshooting) section of the guide.

## Credits and license

Built on [herdr](https://herdr.dev) and the [herdr-plus](https://github.com/cloudmanic/herdr-plus) plugin by cloudmanic.
Released under the MIT license, see [LICENSE](LICENSE).
