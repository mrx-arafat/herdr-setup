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
#   3. Downloads two scripts and six Quick Actions from this repo into the plugin config dir.
#   4. Links the `fleet` command into ~/.local/bin when that folder is on your PATH.
#   5. Binds prefix+up to Projects and prefix+down to Quick Actions in herdr's config.toml.
#   6. Reloads herdr and validates the config.
#
# Safe to re-run:
#   - It never overwrites a file that already exists.
#   - It backs up config.toml before touching it.
#   - It skips a key binding that is already in use, and a `fleet` command that already exists.
#
# Options:
#   --yes, -y    do not ask before installing the plugin
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

SCRIPTS="agent-tab.sh fleet.sh"
ACTIONS="claude-dangerously-skip-permission agy-dangerously-skip-permission codex-dangerously-skip-sandbox agent-grid-2x2 workers workers-custom"

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

# fetch <files/ path> <destination> [mode] - download one file, never overwriting
fetch() {
  if [ -e "$2" ]; then
    say "  left alone (exists): $2"
    return 0
  fi
  mkdir -p "$(dirname "$2")"
  tmp="$2.download.$$"
  if ! curl -fsSL "$BASE/$1" -o "$tmp" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    die "could not download $BASE/$1"
  fi
  mv "$tmp" "$2"
  if [ -n "${3:-}" ]; then chmod "$3" "$2"; fi
  say "  created: $2"
}

check_tools() {
  command -v herdr >/dev/null 2>&1 || die "herdr is not installed. Install it first: curl -fsSL https://herdr.dev/install.sh | sh"
  command -v jq >/dev/null 2>&1 || die "jq is not installed. macOS: brew install jq. Debian/Ubuntu: sudo apt install jq"
  command -v curl >/dev/null 2>&1 || die "curl is not installed"

  ver="$(herdr --version 2>/dev/null | awk '{print $NF}')"
  major="${ver%%.*}"
  rest="${ver#*.}"
  minor="${rest%%.*}"
  case "$major$minor" in
    "" | *[!0-9]*) say "warning: could not read the herdr version ('$ver'), continuing" ;;
    *)
      if [ "$major" -eq 0 ] && [ "$minor" -lt 7 ]; then
        die "herdr $ver is too old. herdr-plus needs 0.7.0 or newer. Run: herdr update"
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

link_fleet() {
  bin="$HOME/.local/bin"
  case ":$PATH:" in
    *":$bin:"*)
      if [ -L "$bin/fleet" ] && [ "$(readlink "$bin/fleet")" = "$CFG/scripts/fleet.sh" ]; then
        say "fleet: already linked in $bin"
      elif [ -e "$bin/fleet" ] || command -v fleet >/dev/null 2>&1; then
        say "fleet: skipped, a 'fleet' command already exists ($(command -v fleet))."
        say "       Use: alias fleet='sh $CFG/scripts/fleet.sh'"
      else
        mkdir -p "$bin"
        ln -s "$CFG/scripts/fleet.sh" "$bin/fleet"
        say "fleet: linked $bin/fleet"
      fi
      ;;
    *)
      say "fleet: $bin is not on your PATH. Add this line to your shell profile:"
      say "       alias fleet='sh $CFG/scripts/fleet.sh'"
      ;;
  esac
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

  ctrl+b then Down   Quick Actions. Type "claude", "agy", "codex", "grid" or "workers".
  ctrl+b then Up     Projects. Add your own first, see docs/GUIDE.md.
  fleet help         Run, delegate to, wait on, read, clear and close a group of agents.

Manual: https://mrx-arafat.github.io/herdr-setup/
EOF
}

main() {
  YES=0
  for arg in "$@"; do
    case "$arg" in
      --yes | -y) YES=1 ;;
      --help | -h) usage; exit 0 ;;
      *) die "unknown option '$arg'. See --help" ;;
    esac
  done
  check_tools
  install_plugin
  install_files
  link_fleet
  bind_keys
  finish
}

# Everything runs from here, after the whole file has arrived, so a cut-off download never runs half a script.
main "$@"
