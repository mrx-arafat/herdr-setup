#!/bin/sh
# fleet - launch and drive a group of agent workers in the current herdr workspace.
#
#   fleet up <count> [tabs] [agents]   open <count> workers spread over [tabs] tabs
#   fleet ls                           list workers with agent, status, tab and pane
#   fleet send [--wait] <who> <task>   type a task into workers; --wait blocks until all finish
#   fleet wait [who]                   wait until busy workers settle (idle, done or blocked)
#   fleet read <who> [lines]           print a worker's recent output (default 60 lines)
#   fleet clear [who]                  fresh chat (/clear) in claude and codex workers
#   fleet focus <who>                  jump to a worker
#   fleet close <who> [--yes]          close workers and end their sessions
#
# <who>    w3, 3, a comma list like w1,w4, all, or idle
# agents   claude, codex, agy or shell, or a comma list that cycles: claude,codex
#
# Workers are panes labelled w1, w2, ... in this workspace. Tabs hold balanced grids:
# 2 side by side, 3 as two columns, 4 as 2x2, 6 as 3x2, 9 as 3x3. Agents start through
# herdr's agent start, so fleet up returns only when every agent can take a task.
#
# Environment:
#   FLEET_CLAUDE_ARGS, FLEET_CODEX_ARGS, FLEET_AGY_ARGS   agent flags (default: checks off)
#   FLEET_CLAUDE_CMD, FLEET_CODEX_CMD, FLEET_AGY_CMD      run this exact command instead
#   FLEET_FOCUS=0      build without switching to the new tab
#   FLEET_TIMEOUT      wait timeout in milliseconds (default 600000)
#   FLEET_START_MS     how long fleet wait looks for a turn to start (default 3000)
set -eu

herdr="${HERDR_BIN_PATH:-herdr}"
ws="${FLEET_WORKSPACE:-${HERDR_PLUS_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}}"
cwd="${HERDR_PLUS_WORKDIR:-$PWD}"
MAX_WORKERS=12

die() { echo "fleet: $*" >&2; exit 1; }
need_ws() { [ -n "$ws" ] || die "run this inside a herdr pane (HERDR_WORKSPACE_ID is not set)"; }
is_int() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }
command -v jq >/dev/null 2>&1 || die "jq is required. macOS: brew install jq"

valid_kind() { case "$1" in claude | codex | agy | shell) return 0 ;; *) return 1 ;; esac; }

kind_args() { # default flags turn each agent's own safety prompts off
  skip="--dangerously-skip-permissions"
  bypass="--dangerously-bypass-approvals-and-sandbox"
  case "$1" in
    claude) printf '%s' "${FLEET_CLAUDE_ARGS-$skip}" ;;
    codex) printf '%s' "${FLEET_CODEX_ARGS-$bypass}" ;;
    agy) printf '%s' "${FLEET_AGY_ARGS-$skip}" ;;
  esac
}

kind_cmd() { # an exact command that replaces agent start, if the user set one
  case "$1" in
    claude) printf '%s' "${FLEET_CLAUDE_CMD:-}" ;;
    codex) printf '%s' "${FLEET_CODEX_CMD:-}" ;;
    agy) printf '%s' "${FLEET_AGY_CMD:-}" ;;
  esac
}

# Workers in this workspace as a JSON array, ordered w1, w2, ...
workers_json() {
  "$herdr" pane list --workspace "$ws" |
    jq -c '[.result.panes[] | select((.label // "") | test("^w[0-9]+$"))]
           | sort_by(.label | ltrimstr("w") | tonumber)'
}

# targets <who>  ->  lines of "<pane-id> <label> <agent> <status>"
targets() {
  j="$(workers_json)"
  case "$1" in
    all) sel='.[]' ;;
    idle) sel='.[] | select(.agent_status == "idle" or .agent_status == "done")' ;;
    *)
      labels=""
      for t in $(printf '%s' "$1" | tr ',' ' '); do
        n="${t#w}"
        is_int "$n" || die "unknown worker '$t'. Use w3, 3, w1,w4, all or idle"
        labels="$labels\"w$n\","
      done
      sel=".[] | select(.label as \$l | [${labels%,}] | index(\$l))"
      ;;
  esac
  out="$(printf '%s' "$j" | jq -r "$sel | \"\\(.pane_id) \\(.label) \\(.agent // \"shell\") \\(.agent_status // \"-\")\"")"
  [ -n "$out" ] || die "no worker matches '$1'. See: fleet ls"
  printf '%s\n' "$out"
}

err_code() { jq -r '.error.code // .error.message // empty' 2>/dev/null || true; }
status_of() { jq -r '([.. | .agent_status? // empty] | first) // .error.code // "unknown"' 2>/dev/null || echo unknown; }

ratio() { awk -v n="$1" 'BEGIN { printf "%.4f", 1 / n }'; }

split() { # split <pane> <right|down> <ratio>  -> new pane id
  "$herdr" pane split --pane "$1" --direction "$2" --ratio "$3" --cwd "$cwd" --no-focus |
    jq -r '.result.pane.pane_id // empty'
}

# build_tab <label> <count> <--focus|--no-focus>  ->  pane ids in reading order
# POSIX sh has no arrays, so top_<col>, cell_<col>_<row> and rows_<col> are set and read via eval.
# shellcheck disable=SC2034,SC2154
build_tab() {
  out="$("$herdr" tab create --workspace "$ws" --cwd "$cwd" --label "$1" "$3")"
  root="$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')"
  [ -n "$root" ] || die "could not create a tab: $out"
  k="$2"
  cols=$(awk -v k="$k" 'BEGIN { c = int(sqrt(k)); if (c * c < k) c++; print c }')
  base=$((k / cols))
  extra=$((k % cols))

  top_1="$root"
  cur="$root"
  c=1
  while [ "$c" -lt "$cols" ]; do
    new="$(split "$cur" right "$(ratio $((cols - c + 1)))")"
    [ -n "$new" ] || die "could not split a column"
    c=$((c + 1))
    eval "top_$c=\$new"
    cur="$new"
  done

  maxrows=$base
  [ "$extra" -gt 0 ] && maxrows=$((base + 1))
  c=1
  while [ "$c" -le "$cols" ]; do
    rows=$base
    [ "$c" -le "$extra" ] && rows=$((base + 1))
    eval "cur=\$top_$c"
    eval "cell_${c}_1=\$cur"
    r=1
    while [ "$r" -lt "$rows" ]; do
      new="$(split "$cur" down "$(ratio $((rows - r + 1)))")"
      [ -n "$new" ] || die "could not split a row"
      r=$((r + 1))
      eval "cell_${c}_${r}=\$new"
      cur="$new"
    done
    eval "rows_$c=$rows"
    c=$((c + 1))
  done

  r=1
  while [ "$r" -le "$maxrows" ]; do
    c=1
    while [ "$c" -le "$cols" ]; do
      eval "rc=\$rows_$c"
      if [ "$r" -le "$rc" ]; then eval "printf '%s\n' \"\$cell_${c}_${r}\""; fi
      c=$((c + 1))
    done
    r=$((r + 1))
  done
}

# agent names must match [a-z][a-z0-9_-]{0,31} and be unique among live agents
name_prefix() {
  p="$("$herdr" workspace get "$ws" | jq -r '.result.workspace.label // empty' |
    tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g; s/^[^a-z]*//' | cut -c1-20)"
  live="$("$herdr" agent list | jq -r '.result.agents[].name // empty')"
  if [ -z "$p" ] || printf '%s\n' "$live" | grep -q "^$p-w"; then
    p="$p$(printf '%s' "$ws" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
    case "$p" in [a-z]*) ;; *) p="ws$p" ;; esac
  fi
  printf '%s' "$p"
}

cmd_up() {
  need_ws
  # Accept one quoted spec, fleet up "6 2 claude", by splitting it on purpose.
  # shellcheck disable=SC2086
  [ $# -eq 1 ] && set -- $1
  count="${1:-}"
  tabs="${2:-1}"
  agents="${3:-claude}"
  is_int "$count" && [ "$count" -ge 1 ] && [ "$count" -le "$MAX_WORKERS" ] ||
    die "count must be 1 to $MAX_WORKERS. Example: fleet up 6 2 claude"
  is_int "$tabs" && [ "$tabs" -ge 1 ] && [ "$tabs" -le "$count" ] ||
    die "tabs must be 1 to $count"
  nkinds=0
  for a in $(printf '%s' "$agents" | tr ',' ' '); do
    valid_kind "$a" || die "unknown agent '$a'. Use claude, codex, agy or shell"
    nkinds=$((nkinds + 1))
  done
  [ "$nkinds" -gt 0 ] || die "no agents given"

  last="$(workers_json | jq -r 'map(.label | ltrimstr("w") | tonumber) | max // 0')"
  prefix="$(name_prefix)"

  # Phase 1: build every tab and label every pane. This part is quick.
  n=$last
  plan=""
  focus="--focus"
  [ "${FLEET_FOCUS:-1}" = "0" ] && focus="--no-focus"
  per=$((count / tabs))
  rem=$((count % tabs))
  t=1
  while [ "$t" -le "$tabs" ]; do
    k=$per
    [ "$t" -le "$rem" ] && k=$((per + 1))
    label="workers"
    [ "$tabs" -gt 1 ] && label="workers-$t"
    panes="$(build_tab "$label" "$k" "$focus")"
    focus="--no-focus"
    for p in $panes; do
      n=$((n + 1))
      kind="$(printf '%s' "$agents" | awk -F, -v i=$((n - last - 1)) '{ print $((i % NF) + 1) }')"
      "$herdr" pane rename "$p" "w$n" >/dev/null
      plan="$plan$p $n $kind $label
"
    done
    t=$((t + 1))
  done

  # Phase 2: start every agent at once. agent start returns when the agent is ready.
  printf '%s' "$plan" | {
    while read -r p n kind label; do
      [ -n "$p" ] || continue
      if [ "$kind" = "shell" ]; then
        printf 'w%-3s %-7s %-10s ready\n' "$n" shell "$label"
        continue
      fi
      custom="$(kind_cmd "$kind")"
      if [ -n "$custom" ]; then
        "$herdr" pane run "$p" "$custom" >/dev/null
        printf 'w%-3s %-7s %-10s started (custom command)\n' "$n" "$kind" "$label"
        continue
      fi
      (
        # Agent flags are split into separate arguments on purpose.
        # shellcheck disable=SC2046
        if r="$("$herdr" agent start "$prefix-w$n" --kind "$kind" --pane "$p" \
          --timeout "${FLEET_START_TIMEOUT:-60000}" -- $(kind_args "$kind") 2>&1)"; then
          printf 'w%-3s %-7s %-10s ready  (%s)\n' "$n" "$kind" "$label" "$prefix-w$n"
        else
          printf 'w%-3s %-7s %-10s not ready: %s\n' "$n" "$kind" "$label" "$(printf '%s' "$r" | err_code)"
        fi
      ) </dev/null &
    done
    wait
  }
  echo "started $count worker(s) in $tabs tab(s). Next: fleet send w1 \"<task>\""
}

cmd_ls() {
  need_ws
  j="$(workers_json)"
  if [ "$(printf '%s' "$j" | jq 'length')" -eq 0 ]; then
    echo "no workers in this workspace. Start some: fleet up 4"
    return 0
  fi
  tabmap="$("$herdr" tab list --workspace "$ws" | jq -c '[.result.tabs[] | {(.tab_id): .label}] | add')"
  printf '%-5s %-8s %-9s %-12s %s\n' NAME AGENT STATUS TAB PANE
  printf '%s' "$j" | jq -r --argjson tabs "$tabmap" \
    '.[] | [.label, (.agent // "shell"), (if .agent then (.agent_status // "-") else "-" end),
            ($tabs[.tab_id] // .tab_id), .pane_id] | @tsv' |
    awk -F'\t' '{ printf "%-5s %-8s %-9s %-12s %s\n", $1, $2, $3, $4, $5 }'
}

# A worker that is still starting reads as "unknown". Give claude and agy a moment to become
# ready so a task is never typed into an agent that is still booting. Codex can read as
# unknown even when ready, so it is not held back.
ready_wait() { # ready_wait <pane> <agent> <status>
  case "$2:$3" in
    claude:unknown | agy:unknown)
      "$herdr" agent wait "$1" --until idle --until "done" --until blocked \
        --timeout "${FLEET_READY_MS:-30000}" >/dev/null 2>&1 </dev/null || true
      ;;
  esac
}

cmd_send() {
  need_ws
  block=0
  if [ "${1:-}" = "--wait" ]; then
    block=1
    shift
  fi
  [ $# -ge 2 ] || die "usage: fleet send [--wait] <who> <task...>"
  who="$1"
  shift
  text="$*"
  list="$(targets "$who")"
  printf '%s\n' "$list" | {
    while read -r p l a s; do
      if [ "$a" = "shell" ]; then
        echo "skip  $l: no agent detected. Wait for it to start, or for a shell run: herdr pane run $p '<command>'"
        continue
      fi
      (
        ready_wait "$p" "$a" "$s"
        if [ "$block" -eq 1 ]; then
          # herdr's --wait waits for the turn to start, then for it to settle.
          r="$("$herdr" agent prompt "$p" "$text" --wait --timeout "${FLEET_TIMEOUT:-600000}" 2>&1)" || true
          echo "$l $(printf '%s' "$r" | status_of)"
        elif e="$("$herdr" agent prompt "$p" "$text" 2>&1 >/dev/null)"; then
          echo "sent  $l ($a)"
        else
          echo "skip  $l ($a): $(printf '%s' "$e" | err_code)"
        fi
      ) </dev/null &
    done
    wait
  }
}

cmd_wait() {
  need_ws
  list="$(targets "${1:-all}")"
  printf '%s\n' "$list" | {
    while read -r p l a _; do
      [ "$a" = "shell" ] && continue
      # A worker prompted a moment ago can still read as idle, so first give it
      # up to FLEET_START_MS to start working, then wait for it to settle.
      (
        "$herdr" agent wait "$p" --until working --until blocked \
          --timeout "${FLEET_START_MS:-3000}" >/dev/null 2>&1 || true
        echo "$l $("$herdr" agent wait "$p" --timeout "${FLEET_TIMEOUT:-600000}" 2>&1 | status_of)"
      ) </dev/null &
    done
    wait
  }
}

cmd_read() {
  need_ws
  [ $# -ge 1 ] || die "usage: fleet read <who> [lines]"
  lines="${2:-60}"
  is_int "$lines" || die "lines must be a number"
  list="$(targets "$1")"
  printf '%s\n' "$list" | while read -r p l a _; do
    echo "== $l ($a) =="
    "$herdr" pane read "$p" --source recent-unwrapped --lines "$lines" </dev/null
    echo
  done
}

cmd_clear() {
  need_ws
  list="$(targets "${1:-all}")"
  printf '%s\n' "$list" | while read -r p l a _; do
    case "$a" in
      claude | codex)
        if e="$("$herdr" agent prompt "$p" "/clear" 2>&1 >/dev/null </dev/null)"; then
          echo "cleared $l ($a)"
        else
          echo "skip    $l ($a): $(printf '%s' "$e" | err_code)"
        fi
        ;;
      shell) "$herdr" pane send-keys "$p" ctrl+l >/dev/null </dev/null && echo "cleared $l (screen)" ;;
      *) echo "skip    $l ($a): no verified clear command. Close and relaunch it instead" ;;
    esac
  done
}

cmd_focus() {
  need_ws
  [ $# -eq 1 ] || die "usage: fleet focus <who>"
  line="$(targets "$1")"
  # Split "<pane> <label> <agent> <status>" into positional parameters on purpose.
  # shellcheck disable=SC2046
  set -- $(printf '%s\n' "$line" | head -n 1)
  "$herdr" tab focus "$("$herdr" pane get "$1" | jq -r '.result.pane.tab_id')" >/dev/null
  if [ "$3" != "shell" ]; then "$herdr" agent focus "$1" >/dev/null 2>&1 || true; fi
  echo "focused $2"
}

cmd_close() {
  need_ws
  [ $# -ge 1 ] || die "usage: fleet close <who> [--yes]"
  list="$(targets "$1")"
  total="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
  if [ "${2:-}" != "--yes" ] && [ "${2:-}" != "-y" ] && [ -t 0 ]; then
    printf 'Close %s worker(s) and end their sessions? [y/N] ' "$total"
    ans=n
    read -r ans || ans=n
    case "$ans" in y | Y | yes) ;; *) die "cancelled" ;; esac
  fi
  printf '%s\n' "$list" | while read -r p l a _; do
    "$herdr" pane close "$p" >/dev/null </dev/null && echo "closed $l ($a)"
  done
}

usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

sub="${1:-help}"
[ $# -gt 0 ] && shift
case "$sub" in
  up) cmd_up "$@" ;;
  ls | list) cmd_ls ;;
  send) cmd_send "$@" ;;
  wait) cmd_wait "$@" ;;
  read) cmd_read "$@" ;;
  clear) cmd_clear "$@" ;;
  focus) cmd_focus "$@" ;;
  close) cmd_close "$@" ;;
  help | -h | --help) usage ;;
  *) die "unknown command '$sub'. See: fleet help" ;;
esac
