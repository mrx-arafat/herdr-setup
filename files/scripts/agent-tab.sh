#!/bin/sh
# Open a new herdr tab in the workspace a herdr-plus quick action was launched
# from, start in that pane's directory, and type a command into it.
#
# Quick actions run through `sh -c` with no stdin, so an interactive TUI such as
# claude cannot run inside the picker itself. It needs a real herdr pane.
#
# Usage: agent-tab.sh <tab-label> <command...>
# Reads HERDR_PLUS_WORKSPACE_ID and HERDR_PLUS_WORKDIR, which herdr-plus exports.
# Set AGENT_TAB_FOCUS=0 to leave focus where it is.
set -eu

label="$1"
shift

herdr="${HERDR_BIN_PATH:-herdr}"
cwd="${HERDR_PLUS_WORKDIR:-$PWD}"
focus="--focus"
[ "${AGENT_TAB_FOCUS:-1}" = "0" ] && focus="--no-focus"

if [ -n "${HERDR_PLUS_WORKSPACE_ID:-}" ]; then
  out="$("$herdr" tab create --workspace "$HERDR_PLUS_WORKSPACE_ID" --cwd "$cwd" --label "$label" $focus)"
else
  out="$("$herdr" tab create --cwd "$cwd" --label "$label" $focus)"
fi

pane="$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')"
if [ -z "$pane" ]; then
  echo "agent-tab: no pane id in herdr response: $out" >&2
  exit 1
fi

"$herdr" pane run "$pane" "$*"
