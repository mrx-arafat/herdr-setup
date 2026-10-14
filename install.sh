#!/bin/sh
# herdr-setup installer
#
# One-shot setup for herdr + herdr-plus: one-key agent launchers and the `fleet`
# command for running several AI coding agents side by side.
#
#   curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/mrx-arafat/herdr-setup/main/install.sh | sh -s -- --yes
#
# What it does:
#   1. Checks that herdr (0.7.0 or newer), jq and curl are installed.
#   2. Installs the herdr-plus plugin (cloudmanic/herdr-plus) after asking you.
#   3. Downloads three scripts and eight Quick Actions from this repo into the plugin config dir.
#   4. Links the `fleet` and `herdr-setup` commands into ~/.local/bin when that folder is on your PATH.
#   5. Binds prefix+up to Projects and prefix+down to Quick Actions in herdr's config.toml.
#   6. Reloads herdr and validates the config.
#
# Safe to re-run:
#   - It never overwrites a file that already exists (only --update replaces, with a backup).
#   - It backs up config.toml before touching it.
#   - It skips a key binding that is already in use, and a command name that already exists.
#
# Keep it current with `herdr-setup update`, or: curl ... | sh -s -- --update
#
# Options:
#   --yes, -y    do not ask before installing the plugin
#   --check      show what is out of date: herdr, herdr-plus, agent integrations, these files
#   --update     update all of those. Never restarts herdr. Replaced files are backed up first
#   --help, -h   show this help
#
# Environment:
#   HERDR_SETUP_REF    branch or tag to install from (default: main)
#   HERDR_SETUP_BASE   where to download files/ from (default: this repo on GitHub)

set -eu

REPO="mrx-arafat/herdr-setup"
REF="${HERDR_SETUP_REF:-main}"
BASE="${HERDR_SETUP_BASE:-https://raw.githubusercontent.com/$REPO/$REF/files}"
PLUGIN="cloudmanic/herdr-plus"
PLUGIN_ID="cloudmanic.herdr-plus"
KEYS_FILE="$HOME/.config/herdr/config.toml"

RELEASES_URL="${HERDR_SETUP_RELEASES_URL:-https://github.com/herdrdev/herdr/releases/latest}"

SCRIPTS="agent-tab.sh fleet.sh herdr-setup.sh"
ACTIONS="claude-dangerously-skip-permission agy-dangerously-skip-permission codex-dangerously-skip-sandbox agent-grid-2x2 workers workers-custom name-workers update-setup"
MODE=install

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0" 2>/dev/null || say "See https://github.com/$REPO"; }

# ask <question> - yes/no on the real terminal, which still works when this script is piped from curl
ask() {
  [ "$YES" -eq 1 ] && return 0
  if ! (exec </dev/tty) 2>/dev/null; then
    die "no terminal to ask on. Rerun with --yes, for example: curl -fsSL <url> | sh -s -- --yes"
  fi
  printf '%s [y/N] ' "$1" >/dev/tty
  ans=n
  read -r ans </dev/tty || ans=n
  case "$ans" in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
}

# download <files/ path> <to> - one file, with no half-written file left on failure
download() {
  if ! curl -fsSL --connect-timeout 20 --max-time 120 --retry 2 "$BASE/$1" -o "$2" || [ ! -s "$2" ]; then
    rm -f "$2"
    die "could not download $BASE/$1"
  fi
}

# fetch <files/ path> <destination> [mode] - install one file.
# A plain install never overwrites. --update replaces a file that differs, after copying
# yours to $BACKUP. --check only reports.
fetch() {
  if [ -e "$2" ] && [ "$MODE" = install ]; then
    say "  left alone (exists): $2"
    return 0
  fi
  mkdir -p "$(dirname "$2")"
  tmp="$2.download.$$"
  download "$1" "$tmp"
  if [ ! -e "$2" ]; then
    if [ "$MODE" = check ]; then
      rm -f "$tmp"
      say "  missing: $2"
      CHANGES=$((CHANGES + 1))
      return 0
    fi
    mv "$tmp" "$2"
    if [ -n "${3:-}" ]; then chmod "$3" "$2"; fi
    say "  created: $2"
  elif cmp -s "$tmp" "$2"; then
    rm -f "$tmp"
    say "  up to date: $2"
  elif [ "$MODE" = check ]; then
    rm -f "$tmp"
    say "  differs: $2"
    CHANGES=$((CHANGES + 1))
  else
    mkdir -p "$BACKUP/$(dirname "$1")"
    cp -p "$2" "$BACKUP/$1"
    BACKED_UP=1
    mv "$tmp" "$2" # a new file, so a script that is running keeps reading its old copy
    if [ -n "${3:-}" ]; then chmod "$3" "$2"; fi
    say "  updated: $2 (your old copy: $BACKUP/$1)"
  fi
}

check_tools() {
  command -v herdr >/dev/null 2>&1 || die "herdr is not installed. Install it first: curl -fsSL https://herdr.dev/install.sh | sh"
  command -v jq >/dev/null 2>&1 || die "jq is not installed. macOS: brew install jq. Debian/Ubuntu: sudo apt install jq"
  command -v curl >/dev/null 2>&1 || die "curl is not installed"

  ver="$(herdr_version)"
  major="${ver%%.*}"
  rest="${ver#*.}"
  minor="${rest%%.*}"
  case "$major$minor" in
    "" | *[!0-9]*) say "warning: could not read the herdr version ('$ver'), continuing" ;;
    *)
      if [ "$major" -eq 0 ] && [ "$minor" -lt 7 ] && [ "$MODE" = install ]; then
        die "herdr $ver is too old. herdr-plus needs 0.7.0 or newer. Run: herdr update, or this installer with --update"
      fi
      ;;
  esac
  say "herdr $ver, jq and curl found"
}

install_plugin() {
  if herdr plugin list 2>/dev/null | grep -q "$PLUGIN_ID"; then
    say "plugin: $PLUGIN_ID already installed"
    return 0
  fi
  say "plugin: about to install $PLUGIN from GitHub."
  say "herdr clones that repo and runs its build script (scripts/build.sh)."
  ask "Continue?" || die "cancelled"
  herdr plugin install "$PLUGIN" --yes
}

install_files() {
  CFG="$(herdr plugin config-dir "$PLUGIN_ID")"
  [ -n "$CFG" ] || die "could not find the plugin config dir"
  if [ "$CFG" != "$HOME/.config/herdr/plugins/config/$PLUGIN_ID" ]; then
    say "warning: the plugin config dir is $CFG, not the default location."
    say "         The Quick Actions point at the default path. Edit their command lines."
  fi
  say "files: from $BASE"
  for s in $SCRIPTS; do fetch "scripts/$s" "$CFG/scripts/$s" 755; done
  for a in $ACTIONS; do fetch "quick-actions/$a.toml" "$CFG/quick-actions/$a.toml"; done
}

# link_cmd <command> <script> - put a command on the PATH through ~/.local/bin
link_cmd() {
  bin="$HOME/.local/bin"
  case ":$PATH:" in
    *":$bin:"*)
      if [ -L "$bin/$1" ] && [ "$(readlink "$bin/$1")" = "$CFG/scripts/$2" ]; then
        say "$1: already linked in $bin"
      elif [ -e "$bin/$1" ] || command -v "$1" >/dev/null 2>&1; then
        say "$1: skipped, a '$1' command already exists ($(command -v "$1"))."
        say "       Use: alias $1='sh $CFG/scripts/$2'"
      else
        mkdir -p "$bin"
        ln -s "$CFG/scripts/$2" "$bin/$1"
        say "$1: linked $bin/$1"
      fi
      ;;
    *)
      say "$1: $bin is not on your PATH. Add this line to your shell profile:"
      say "       alias $1='sh $CFG/scripts/$2'"
      ;;
  esac
}

link_cmds() {
  link_cmd fleet fleet.sh
  link_cmd herdr-setup herdr-setup.sh
}

herdr_version() { herdr --version 2>/dev/null | awk '{ print $NF }'; }

# ver_lt <a> <b> - true when version a is older than b, like 0.9.3 and 0.9.4
ver_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); k = n > m ? n : m
    for (i = 1; i <= k; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }
    exit 1 }'
}

# How herdr was installed decides how it updates. herdr update is only for herdr's own installer.
herdr_kind() {
  bin="$(command -v herdr)"
  real="$(readlink -f "$bin" 2>/dev/null || printf '%s' "$bin")"
  case "$real" in
    */Cellar/* | /opt/homebrew/* | /home/linuxbrew/*) echo brew ;;
    */mise/*) echo mise ;;
    /nix/*) echo nix ;;
    *) echo direct ;;
  esac
}

# github.com redirects releases/latest to releases/tag/v<version>. Reading where it lands
# needs no API call, so GitHub's 60-an-hour API limit for anonymous users never applies.
latest_herdr() {
  u="$(curl -fsSIL -o /dev/null -w '%{url_effective}' --connect-timeout 10 --max-time 20 "$RELEASES_URL" 2>/dev/null || true)"
  case "$u" in */tag/v[0-9]*) printf '%s' "${u##*/tag/v}" ;; esac
}

update_herdr() {
  have="$(herdr_version)"
  latest="$(latest_herdr)"
  kind="$(herdr_kind)"
  if [ -n "$latest" ] && ! ver_lt "$have" "$latest"; then
    say "herdr: $have, up to date"
    return 0
  fi
  if [ "$MODE" = check ]; then
    if [ -z "$latest" ]; then
      say "herdr: $have (could not reach GitHub to check for a newer one)"
    else
      say "herdr: $have installed, $latest available ($kind install)"
      CHANGES=$((CHANGES + 1))
    fi
    return 0
  fi
  # The update commands are the ones herdr's own update code names for each kind of install.
  case "$kind" in
    direct)
      if [ "${HERDR_ENV:-}" = 1 ]; then
        # herdr refuses to update itself from inside a herdr pane.
        say "herdr: ${latest:-a newer version} is available, but herdr only updates itself outside herdr."
        say "       Open a plain terminal (not a herdr pane) and run: herdr-setup update"
        HERDR_SKIPPED=1
        return 0
      fi
      # No terminal on stdin: if a release ever needs the running server stopped, herdr
      # declines instead of asking, so this can never close your panes.
      herdr update </dev/null || die "herdr update failed. Run it on its own to see why: herdr update"
      ;;
    brew) { brew update && brew upgrade herdr; } || die "brew upgrade herdr failed" ;;
    mise)
      say "herdr: installed with mise, so update it with: mise upgrade herdr"
      return 0
      ;;
    nix)
      say "herdr: installed with Nix, so update it with nix profile upgrade, or update your flake input"
      return 0
      ;;
  esac
  now="$(herdr_version)"
  if [ "$now" = "$have" ]; then say "herdr: $now, up to date"; else say "herdr: $have -> $now"; fi
}

plugin_json() {
  herdr plugin list --json 2>/dev/null |
    jq -c --arg id "$PLUGIN_ID" '.result.plugins[]? | select(.plugin_id == $id)' 2>/dev/null || true
}

update_plugin() {
  info="$(plugin_json)"
  if [ -z "$info" ]; then
    if [ "$MODE" = check ]; then
      say "plugin: $PLUGIN_ID is not installed"
      CHANGES=$((CHANGES + 1))
    else
      install_plugin
    fi
    return 0
  fi
  if [ "$(printf '%s' "$info" | jq -r '.source.kind // empty')" != github ]; then
    say "plugin: $PLUGIN_ID is not a GitHub install (linked from a folder?), left alone"
    return 0
  fi
  have="$(printf '%s' "$info" | jq -r '.source.resolved_commit // empty')"
  want="$(git ls-remote "https://github.com/$PLUGIN" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"
  if [ -z "$want" ]; then
    say "plugin: could not reach github.com/$PLUGIN, left as it is"
  elif [ "$have" = "$want" ]; then
    say "plugin: $PLUGIN_ID $(printf '%.7s' "$have"), up to date"
  elif [ "$MODE" = check ]; then
    say "plugin: $PLUGIN_ID $(printf '%.7s' "$have") installed, $(printf '%.7s' "$want") available"
    CHANGES=$((CHANGES + 1))
  else
    # Installing again replaces herdr's managed checkout. Its config folder is kept.
    herdr plugin install "$PLUGIN" --yes || die "could not update $PLUGIN"
    say "plugin: $PLUGIN_ID $(printf '%.7s' "$have") -> $(printf '%.7s' "$want")"
  fi
}

# herdr's hooks inside Claude, Codex and others report agent status. A herdr update can
# make them stale, so refresh every installed one that is not current.
update_integrations() {
  stale="$(herdr integration status 2>/dev/null |
    awk -F': ' 'NF > 1 && $2 !~ /^(current|not installed)/ { print $1 }' || true)"
  if [ -z "$stale" ]; then
    say "integrations: current"
    return 0
  fi
  for name in $stale; do
    if [ "$MODE" = check ]; then
      say "integrations: $name is not current"
      CHANGES=$((CHANGES + 1))
    elif herdr integration install "$name" >/dev/null 2>&1; then
      say "integrations: refreshed $name"
    else
      say "warning: could not refresh the $name integration. Run: herdr integration install $name"
    fi
  done
}

# The zsh completion from docs/GUIDE.md goes stale with herdr. Refresh it if it is there.
update_completion() {
  f="$HOME/.zfunc/_herdr"
  [ -f "$f" ] || return 0
  if herdr completion zsh >"$f.new.$$" 2>/dev/null && [ -s "$f.new.$$" ]; then
    mv "$f.new.$$" "$f"
    say "completion: refreshed $f"
  else
    rm -f "$f.new.$$"
  fi
}

# Updating never restarts herdr. Say so when the running server is older than the binary.
report_restart() {
  st="$(herdr status --json 2>/dev/null || true)"
  [ -n "$st" ] || return 0
  client="$(printf '%s' "$st" | jq -r '.client.version // empty' 2>/dev/null || true)"
  server="$(printf '%s' "$st" | jq -r 'if .server.running then .server.version // empty else empty end' 2>/dev/null || true)"
  need="$(printf '%s' "$st" | jq -r '.update.restart_needed // false' 2>/dev/null || true)"
  if [ -n "$server" ] && { [ "$need" = true ] || [ "$server" != "$client" ]; }; then
    say "restart: the running herdr server is $server and the new binary is $client."
    say "         Panes and agents keep running on the old server. New server features arrive"
    say "         after a restart: when no agent is mid-task, run herdr server stop, then start herdr."
  fi
}

bind_keys() {
  say "keys: $KEYS_FILE"
  mkdir -p "$(dirname "$KEYS_FILE")"
  if [ -f "$KEYS_FILE" ] && grep -q "$PLUGIN_ID.projects" "$KEYS_FILE"; then
    say "  left alone: herdr-plus keybindings already present"
    return 0
  fi
  if [ -f "$KEYS_FILE" ] && grep -Eq 'key[[:space:]]*=[[:space:]]*"prefix\+(up|down)"' "$KEYS_FILE"; then
    say "  skipped: prefix+up or prefix+down is already bound in your config."
    say "  Bind the actions yourself, see 'Bind the keys yourself' in docs/GUIDE.md."
    return 0
  fi
  if [ -f "$KEYS_FILE" ]; then
    backup="$KEYS_FILE.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$KEYS_FILE" "$backup"
    say "  backup: $backup"
  fi
  cat >>"$KEYS_FILE" <<'EOF'

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
EOF
  say "  added: prefix+up (Projects), prefix+down (Quick Actions)"
}

finish() {
  herdr server reload-config >/dev/null 2>&1 || say "note: could not reload a running herdr. Restart herdr to pick up the keys."
  herdr config check
  cat <<'EOF'

Done.

  ctrl+b then Down   Quick Actions. Type "claude", "agy", "codex", "grid", "workers", "name" or "update".
  ctrl+b then Up     Projects. Add your own first, see docs/GUIDE.md.
  fleet help         Run, delegate to, wait on, read, rename, clear and close a group of agents.
  herdr-setup update Newest herdr, herdr-plus and these files. herdr-setup check only looks.

Manual: https://mrx-arafat.github.io/herdr-setup/
EOF
}

main() {
  YES=0
  for arg in "$@"; do
    case "$arg" in
      --yes | -y) YES=1 ;;
      --check) MODE=check ;;
      --update) MODE=update ;;
      --help | -h) usage; exit 0 ;;
      *) die "unknown option '$arg'. See --help" ;;
    esac
  done
  CHANGES=0
  BACKED_UP=0
  HERDR_SKIPPED=0
  BACKUP="$HOME/.config/herdr/backups/herdr-setup-$(date +%Y%m%d-%H%M%S)-$$"
  check_tools
  case "$MODE" in
    install)
      install_plugin
      install_files
      link_cmds
      bind_keys
      finish
      ;;
    check)
      update_herdr
      update_plugin
      update_integrations
      if [ -n "$(plugin_json)" ]; then install_files; fi
      report_restart
      if [ "$CHANGES" -eq 0 ]; then say "Everything is up to date."; else say "$CHANGES update(s) available. Run: herdr-setup update"; fi
      ;;
    update)
      update_herdr
      update_plugin
      update_integrations
      install_files
      link_cmds
      update_completion
      herdr server reload-config >/dev/null 2>&1 || true
      herdr config check
      report_restart
      done_msg="Updated."
      [ "$HERDR_SKIPPED" -eq 0 ] || done_msg="Updated everything except herdr itself, see above."
      if [ "$BACKED_UP" -eq 1 ]; then done_msg="$done_msg Your old copies of replaced files are in $BACKUP"; fi
      say "$done_msg"
      ;;
  esac
}

# Everything runs from here, after the whole file has arrived, so a cut-off download never runs half a script.
main "$@"
