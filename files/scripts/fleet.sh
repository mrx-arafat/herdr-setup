#!/bin/sh
# fleet - launch and drive a group of agent workers in the current herdr workspace.
#
#   fleet up <count> [tabs] [agents]   open <count> workers spread over [tabs] tabs
#   fleet ls                           list workers with agent, status, tab and pane
#   fleet send [--wait] <who> <task>   type a task into workers; --wait blocks until all finish.
#                                      The task asks each worker to name its pane after it.
#   fleet wait [who]                   wait until busy workers settle (idle, done or blocked)
#   fleet read <who> [lines]           print a worker's recent output (default 60 lines)
#   fleet clear [who]                  fresh chat (/clear) in claude and codex workers
#   fleet focus <who>                  jump to a worker
#   fleet close <who> [--yes]          close workers and end their sessions
#   fleet rename [who]                 ask workers to name themselves after their current task
#   fleet rename <who> <name>          name one worker: its pane, agent and session together
#   fleet rename me <name>             the same, for the pane you run it in (agents use this)
#   fleet rename <pane-id> <name>      the same, for any pane, such as w2:p4
#
# <who>    w3, 3, a worker's name, a comma list like w1,w4, all, or idle
# agents   claude, codex, agy or shell, or a comma list that cycles: claude,codex
#
# Workers start as panes labelled w1, w2, ... in this workspace. Tabs hold balanced grids:
# 2 side by side, 3 as two columns, 4 as 2x2, 6 as 3x2, 9 as 3x3. Agents start through
# herdr's agent start, so fleet up returns only when every agent can take a task.
# A renamed worker keeps its number, so w3 and its new name both reach it.
#
# Environment:
#   FLEET_CLAUDE_ARGS, FLEET_CODEX_ARGS, FLEET_AGY_ARGS   agent flags (default: checks off)
#   FLEET_CLAUDE_CMD, FLEET_CODEX_CMD, FLEET_AGY_CMD      run this exact command instead
#   FLEET_FOCUS=0      build without switching to the new tab
#   FLEET_TIMEOUT      wait timeout in milliseconds (default 600000)
#   FLEET_START_MS     how long fleet wait looks for a turn to start (default 3000)
#   FLEET_STATE_DIR    where renamed workers' numbers are kept (default ~/.local/state/fleet)
#   FLEET_AUTONAME=0   send tasks as typed, without the naming request
set -eu

herdr="${HERDR_BIN_PATH:-herdr}"
ws="${FLEET_WORKSPACE:-${HERDR_PLUS_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}}"
cwd="${HERDR_PLUS_WORKDIR:-$PWD}"
state_dir="${FLEET_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/fleet}"
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

# A renamed worker loses its w<n> label, so its number is kept in a small record:
# one JSON file per pane, {pane, n, label, agent}. herdr keeps labels and agent names
# across a server restart but not pane metadata, which is why the record lives on disk.
record_file() { printf '%s/%s' "$state_dir" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"; }
records_json() {
  { cat "$state_dir"/* 2>/dev/null | jq -s -c 'map({(.pane): .}) | add // {}' 2>/dev/null; } || echo '{}'
}

prune_records() { # forget renamed workers whose pane has left this workspace
  live="$("$herdr" pane list --workspace "$ws" | jq -r '.result.panes[].pane_id')"
  for f in "$state_dir"/*; do
    [ -f "$f" ] || continue
    p="$(jq -r '.pane // empty' "$f" 2>/dev/null || true)"
    case "$p" in "$ws":*) printf '%s\n' "$live" | grep -qxF "$p" || rm -f "$f" ;; esac
  done
}

# Workers in this workspace as a JSON array ordered by number. Each pane gains
# n, id (w<n>), name (its label, or the id) and agent_name. A pane is a worker when it is
# labelled w<n>, when its record still matches its label or agent name, or when its agent
# still has the <prefix>-w<n> name fleet up gave it (a pane renamed by hand).
workers_json() {
  names="$("$herdr" agent list | jq -c '[.result.agents[] | {(.pane_id): .name}] | add // {}')"
  "$herdr" pane list --workspace "$ws" |
    jq -c --argjson recs "$(records_json)" --argjson names "$names" '
      [.result.panes[]
       | .agent_name = $names[.pane_id]
       | ($recs[.pane_id] // {}) as $r
       | .n = (if ((.label // "") | test("^w[0-9]+$")) then (.label | ltrimstr("w") | tonumber)
               elif $r.n != null and ((.label != null and .label == $r.label)
                                      or (.agent_name != null and .agent_name == $r.agent)) then $r.n
               elif ((.agent_name // "") | test("-w[0-9]+$")) then
                 (.agent_name | capture("-w(?<n>[0-9]+)$").n | tonumber)
               else null end)
       | select(.n != null)
       | .id = "w\(.n)"
       | .name = (.label // .id)]
      | sort_by(.n)'
}

# targets <who>  ->  lines of "<pane-id> <id> <agent> <status> <name>"
targets() {
  out="$(workers_json | jq -r --arg who "$1" '
    ($who | split(",") | map(if test("^w?[0-9]+$") then "w" + ltrimstr("w") else . end)) as $keys
    | .[]
    | if $who == "all" then .
      elif $who == "idle" then select(.agent_status == "idle" or .agent_status == "done")
      else select([.id, .label, .agent_name] | any(. as $v | $v != null and ($keys | index($v))))
      end
    | "\(.pane_id) \(.id) \(.agent // "shell") \(.agent_status // "-") \(.name)"')"
  [ -n "$out" ] || die "no worker matches '$1'. Use w3, 3, a name, w1,w4, all or idle. See: fleet ls"
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
  if ! { is_int "$count" && [ "$count" -ge 1 ] && [ "$count" -le "$MAX_WORKERS" ]; }; then
    die "count must be 1 to $MAX_WORKERS. Example: fleet up 6 2 claude"
  fi
  if ! { is_int "$tabs" && [ "$tabs" -ge 1 ] && [ "$tabs" -le "$count" ]; }; then
    die "tabs must be 1 to $count"
  fi
  nkinds=0
  for a in $(printf '%s' "$agents" | tr ',' ' '); do
    valid_kind "$a" || die "unknown agent '$a'. Use claude, codex, agy or shell"
    nkinds=$((nkinds + 1))
  done
  [ "$nkinds" -gt 0 ] || die "no agents given"

  prune_records
  last="$(workers_json | jq -r 'map(.n) | max // 0')"
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
  echo "started $count worker(s) in $tabs tab(s). Next: fleet send w$((last + 1)) \"<task>\""
}

cmd_ls() {
  need_ws
  j="$(workers_json)"
  if [ "$(printf '%s' "$j" | jq 'length')" -eq 0 ]; then
    echo "no workers in this workspace. Start some: fleet up 4"
    return 0
  fi
  tabmap="$("$herdr" tab list --workspace "$ws" | jq -c '[.result.tabs[] | {(.tab_id): .label}] | add')"
  # The NAME column is as wide as the longest name.
  printf '%s' "$j" | jq -r --argjson tabs "$tabmap" \
    '["ID", "NAME", "AGENT", "STATUS", "TAB", "PANE"],
     (.[] | [.id, .name, (.agent // "shell"), (if .agent then (.agent_status // "-") else "-" end),
             ($tabs[.tab_id] // .tab_id), .pane_id]) | @tsv' |
    awk -F'\t' '{ row[NR] = $0; if (length($2) > w) w = length($2) }
      END { for (i = 1; i <= NR; i++) { split(row[i], f, "\t")
              printf "%-4s %-" w "s  %-7s %-8s %-11s %s\n", f[1], f[2], f[3], f[4], f[5], f[6] } }'
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
    while read -r p _ a s l; do
      if [ "$a" = "shell" ]; then
        echo "skip  $l: no agent detected. Wait for it to start, or for a shell run: herdr pane run $p '<command>'"
        continue
      fi
      (
        ready_wait "$p" "$a" "$s"
        task="$text"
        # Slash commands such as /review stay untouched.
        if [ "${FLEET_AUTONAME:-1}" != "0" ]; then
          case "$text" in
            /*) ;;
            *) task="$text

(Before you start, name this pane after this task so the user can find it: $(name_hint "$p").)" ;;
          esac
        fi
        if [ "$block" -eq 1 ]; then
          # herdr's --wait waits for the turn to start, then for it to settle.
          r="$("$herdr" agent prompt "$p" "$task" --wait --timeout "${FLEET_TIMEOUT:-600000}" 2>&1)" || true
          echo "$l $(printf '%s' "$r" | status_of)"
        elif e="$("$herdr" agent prompt "$p" "$task" 2>&1 >/dev/null)"; then
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
    while read -r p _ a _ l; do
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
  printf '%s\n' "$list" | while read -r p _ a _ l; do
    echo "== $l ($a) =="
    "$herdr" pane read "$p" --source recent-unwrapped --lines "$lines" </dev/null
    echo
  done
}

cmd_clear() {
  need_ws
  list="$(targets "${1:-all}")"
  printf '%s\n' "$list" | while read -r p _ a _ l; do
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
  line="$(targets "$1" | head -n 1)"
  read -r p _ a _ l <<EOF
$line
EOF
  "$herdr" tab focus "$("$herdr" pane get "$p" | jq -r '.result.pane.tab_id')" >/dev/null
  if [ "$a" != "shell" ]; then "$herdr" agent focus "$p" >/dev/null 2>&1 || true; fi
  echo "focused $l"
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
  printf '%s\n' "$list" | while read -r p _ a _ l; do
    "$herdr" pane close "$p" >/dev/null </dev/null && rm -f "$(record_file "$p")" && echo "closed $l ($a)"
  done
}

# A name herdr accepts for both a pane label and an agent: [a-z][a-z0-9_-]{0,31}.
# "PR #6969 Cool fix" becomes pr-6969-cool-fix.
clean_name() {
  n="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed 's/[^a-z0-9_-]/-/g; s/--*/-/g; s/^-//' | cut -c1-32 | sed 's/-$//')"
  case "$n" in
    [a-z]*) printf '%s' "$n" ;;
    *) die "'$1' is not a usable name. Start with a letter, like pr6969-cool-fix" ;;
  esac
}

# in_pane <pane>: true when this process descends from that pane's shell. HERDR_PANE_ID
# alone is not proof: codex runs its commands from a shared background server whose
# environment came from whichever pane started it first.
in_pane() {
  root="$("$herdr" pane process-info --pane "$1" 2>/dev/null | jq -r '.result.process_info.shell_pid // empty')"
  [ -n "$root" ] || return 1
  pid=$$
  while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
    [ "$pid" = "$root" ] && return 0
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
  done
  return 1
}

# The command an agent in another pane runs to reach this script. Prefer plain
# "fleet" when that is this same script, since agents' shells have no aliases.
self_cmd() {
  case "$0" in /*) self="$0" ;; *) self="$PWD/$0" ;; esac
  on_path="$(command -v fleet 2>/dev/null || true)"
  if [ -n "$on_path" ] && cmp -s "$on_path" "$self"; then
    printf 'fleet'
  else
    printf "sh '%s'" "$self"
  fi
}

# rename_one <who|me> <name>: pane label, herdr agent name and the agent's own session
# name (/rename, which claude, codex and agy all accept, even mid-task).
rename_one() {
  name="$(clean_name "$2")"
  case "$1" in
    me)
      p="${HERDR_PANE_ID:-}"
      if [ -z "$p" ] || ! in_pane "$p"; then
        die "cannot tell which pane this runs in (HERDR_PANE_ID=${p:-unset} does not host it). Use the pane id: fleet rename <pane-id> $name"
      fi
      ;;
    *:*) p="$1" ;;
    *)
      need_ws
      line="$(targets "$1")"
      [ "$(printf '%s\n' "$line" | wc -l | tr -d ' ')" -eq 1 ] ||
        die "a name fits one worker. Example: fleet rename w2 $name"
      p="${line%% *}"
      ;;
  esac

  pane="$("$herdr" pane get "$p" 2>/dev/null | jq -c '.result.pane // empty')"
  [ -n "$pane" ] || die "no pane $p. See: fleet ls"
  # The pane's own workspace, which can differ from the caller's environment.
  ws="$(printf '%s' "$pane" | jq -r '.workspace_id')"
  kind="$(printf '%s' "$pane" | jq -r '.agent // empty')"
  status="$(printf '%s' "$pane" | jq -r '.agent_status // "-"')"
  old="$(printf '%s' "$pane" | jq -r '.label // .pane_id')"
  n="$(workers_json | jq -r --arg p "$p" '.[] | select(.pane_id == $p) | .n')"

  # Agent names are unique per herdr server, so check every pane, not just this workspace.
  taken="$("$herdr" pane list | jq -r --arg p "$p" --arg n "$name" \
    '.result.panes[] | select(.pane_id != $p and .label == $n) | .pane_id' | head -n 1)"
  [ -n "$taken" ] || taken="$("$herdr" agent list | jq -r --arg p "$p" --arg n "$name" \
    '.result.agents[] | select(.pane_id != $p and .name == $n) | .pane_id' | head -n 1)"
  [ -z "$taken" ] || die "'$name' is already used by pane $taken. Pick another name"

  # Save the record first: until the label changes, the w<n> label still identifies the worker.
  if [ -n "$n" ]; then
    mkdir -p "$state_dir"
    agent_name="$name"
    [ -n "$kind" ] || agent_name=""
    # Write a hidden temp file, then move it, so a reader never sees half a record.
    jq -n -c --arg p "$p" --argjson n "$n" --arg l "$name" --arg a "$agent_name" \
      '{pane: $p, n: $n, label: $l, agent: (if $a == "" then null else $a end)}' >"$state_dir/.new.$$"
    mv "$state_dir/.new.$$" "$(record_file "$p")"
    [ "$old" = "w$n" ] || old="$old (w$n)"
  fi

  "$herdr" pane rename "$p" "$name" >/dev/null
  done_list="pane"
  if [ -n "$kind" ]; then
    if "$herdr" agent rename "$p" "$name" >/dev/null 2>&1; then done_list="$done_list, agent"; fi
    case "$kind:$status" in
      *:blocked) echo "note: $name is waiting for an answer, so its session keeps the old name" ;;
      claude:* | codex:* | agy:*)
        if "$herdr" agent prompt "$p" "/rename $name" >/dev/null 2>&1 </dev/null; then
          done_list="$done_list, session"
        fi
        ;;
    esac
  fi
  echo "renamed $old -> $name ($done_list)"
}

# name_hint <pane>: how an agent names its own pane. The pane id is spelled out because
# an agent cannot always tell which pane it runs in (see in_pane).
name_hint() {
  printf '%s' "pick a short name like pr6969-cool-fix (lowercase letters, digits and dashes, starting with a letter, at most 32 characters) and run this command with it: $(self_cmd) rename $1 <name>"
}

# ask_rename <who>: each agent picks a name for its task and renames its own pane.
ask_rename() {
  need_ws
  list="$(targets "$1")"
  printf '%s\n' "$list" | {
    while read -r p _ a s l; do
      case "$a:$s" in
        shell:*) echo "skip  $l: no agent to ask. Name it yourself: fleet rename $l <name>" ;;
        *:blocked) echo "skip  $l ($a): waiting for an answer. Run fleet focus $l" ;;
        *)
          (
            ready_wait "$p" "$a" "$s"
            ask="Name this pane after your current task, or the last one you finished, so the user can find it: $(name_hint "$p"). If you have not had any task yet, do nothing. Then carry on."
            if e="$("$herdr" agent prompt "$p" "$ask" 2>&1 >/dev/null)"; then
              echo "asked $l ($a)"
            else
              echo "skip  $l ($a): $(printf '%s' "$e" | err_code)"
            fi
          ) </dev/null &
          ;;
      esac
    done
    wait
  }
}

cmd_rename() {
  case $# in
    0) ask_rename all ;;
    1)
      [ "$1" != "me" ] || die "usage: fleet rename me <name>"
      ask_rename "$1"
      ;;
    2) rename_one "$1" "$2" ;;
    *) die "usage: fleet rename [who] [name]. Names have no spaces, like pr6969-cool-fix" ;;
  esac
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
  rename) cmd_rename "$@" ;;
  help | -h | --help) usage ;;
  *) die "unknown command '$sub'. See: fleet help" ;;
esac
