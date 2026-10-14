#!/bin/sh
# Sandbox tests for install.sh.
#
# Every case runs the installer with a fake HOME and a stub `herdr`, and downloads
# files/ from this checkout through file:// URLs. Nothing touches your real setup.
#
#   sh tests/sandbox.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/herdr-setup-test.XXXXXX")"
BASE="file://$ROOT/files"
CFG_REL=".config/herdr/plugins/config/cloudmanic.herdr-plus"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }
check() { # check <name> <command...>
  name="$1"
  shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}

# ---------------------------------------------------------------- stub herdr
mkdir -p "$SB/bin"
cat >"$SB/bin/herdr" <<'EOF'
#!/bin/sh
case "$1 ${2:-}" in
  "--version "*) echo "herdr ${STUB_VERSION:-0.9.3}" ;;
  "plugin list") [ -f "$HOME/.stub-installed" ] && echo "cloudmanic.herdr-plus (Herdr Plus) enabled" ;;
  "plugin install") touch "$HOME/.stub-installed"; echo "installed" ;;
  "plugin config-dir") echo "$HOME/.config/herdr/plugins/config/$3" ;;
  "server reload-config") echo '{"result":{"status":"applied"}}' ;;
  "config check") echo "config: ok" ;;
  *) echo "stub: unhandled: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$SB/bin/herdr"

home() { h="$SB/home-$1"; mkdir -p "$h/.local/bin"; printf '%s' "$h"; }
SYS_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
# run <home> <installer args...>  (stdin is /dev/null, so there is never a terminal to ask on)
run() {
  h="$1"
  shift
  HOME="$h" PATH="$h/.local/bin:$SB/bin:$SYS_PATH" HERDR_SETUP_BASE="$BASE" sh "$ROOT/install.sh" "$@" </dev/null
}

# ---------------------------------------------------------------- T1 fresh install
H1="$(home 1)"
run "$H1" --yes >"$SB/t1.log" 2>&1
check "T1 fresh install exits 0" [ "$?" -eq 0 ]
all_same=0
for f in scripts/agent-tab.sh scripts/fleet.sh quick-actions/claude-dangerously-skip-permission.toml \
  quick-actions/agy-dangerously-skip-permission.toml quick-actions/codex-dangerously-skip-sandbox.toml \
  quick-actions/agent-grid-2x2.toml quick-actions/workers.toml quick-actions/workers-custom.toml \
  quick-actions/name-workers.toml; do
  cmp -s "$ROOT/files/$f" "$H1/$CFG_REL/$f" || all_same=1
done
check "T1 all 9 files installed byte for byte" [ "$all_same" -eq 0 ]
check "T1 fleet.sh is executable" [ -x "$H1/$CFG_REL/scripts/fleet.sh" ]
check "T1 agent-tab.sh is executable" [ -x "$H1/$CFG_REL/scripts/agent-tab.sh" ]
check "T1 fleet linked into ~/.local/bin" [ "$(readlink "$H1/.local/bin/fleet")" = "$H1/$CFG_REL/scripts/fleet.sh" ]
check "T1 both key bindings added" [ "$(grep -c 'cloudmanic.herdr-plus\.' "$H1/.config/herdr/config.toml")" -eq 2 ]
check "T1 plugin install was requested" [ -f "$H1/.stub-installed" ]
check "T1 no download temp files left" [ -z "$(find "$H1/$CFG_REL" -name '*.download.*')" ]

# ---------------------------------------------------------------- T2 re-run is a no-op
cp "$H1/.config/herdr/config.toml" "$SB/t2.before"
run "$H1" --yes >"$SB/t2.log" 2>&1
check "T2 re-run exits 0" [ "$?" -eq 0 ]
check "T2 config.toml unchanged" cmp -s "$SB/t2.before" "$H1/.config/herdr/config.toml"
check "T2 every file left alone" [ "$(grep -c 'left alone (exists)' "$SB/t2.log")" -eq 9 ]
check "T2 fleet already linked" grep -q 'fleet: already linked' "$SB/t2.log"

# ---------------------------------------------------------------- T3 existing key is never clobbered
H3="$(home 3)"
mkdir -p "$H3/.config/herdr"
printf '[[keys.command]]\nkey = "prefix+up"\ntype = "plugin_action"\ncommand = "x"\n' >"$H3/.config/herdr/config.toml"
cp "$H3/.config/herdr/config.toml" "$SB/t3.before"
run "$H3" --yes >"$SB/t3.log" 2>&1
check "T3 key conflict reported" grep -q 'skipped: prefix+up or prefix+down' "$SB/t3.log"
check "T3 config.toml untouched" cmp -s "$SB/t3.before" "$H3/.config/herdr/config.toml"

# ---------------------------------------------------------------- T4 config without trailing newline
H4="$(home 4)"
mkdir -p "$H4/.config/herdr"
printf 'onboarding = false' >"$H4/.config/herdr/config.toml"
run "$H4" --yes >"$SB/t4.log" 2>&1
# shellcheck disable=SC2016 # $1 expands inside the inner sh, on purpose
check "T4 backup made" sh -c 'ls "$1" | grep -q config.toml.bak-' _ "$H4/.config/herdr"
check "T4 original line kept on its own line" grep -qx 'onboarding = false' "$H4/.config/herdr/config.toml"

# ---------------------------------------------------------------- T5 no --yes and no terminal: refuse, install nothing
H5="$(home 5)"
run "$H5" >"$SB/t5.log" 2>&1
check "T5 exits non-zero" [ "$?" -ne 0 ]
check "T5 tells you to use --yes" grep -q 'Rerun with --yes' "$SB/t5.log"
check "T5 plugin not installed" [ ! -f "$H5/.stub-installed" ]

# ---------------------------------------------------------------- T6 to T8 missing or old tools
H6="$(home 6)"
# Subshell: in POSIX sh a VAR=value prefix on a function call outlives the call.
(STUB_VERSION=0.6.2 run "$H6" --yes >"$SB/t6.log" 2>&1)
check "T6 old herdr refused" grep -q 'too old' "$SB/t6.log"
mkdir -p "$SB/nojq"
for t in sh awk grep cat cp mkdir dirname date mv rm chmod ln readlink curl printf sed; do
  p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$SB/nojq/$t"
done
HOME="$H6" PATH="$SB/bin:$SB/nojq" HERDR_SETUP_BASE="$BASE" "$SB/nojq/sh" "$ROOT/install.sh" --yes </dev/null >"$SB/t7.log" 2>&1
check "T7 missing jq reported" grep -q 'jq is not installed' "$SB/t7.log"
HOME="$H6" PATH="$SYS_PATH" HERDR_SETUP_BASE="$BASE" sh "$ROOT/install.sh" --yes </dev/null >"$SB/t8.log" 2>&1
check "T8 missing herdr reported" grep -q 'herdr is not installed' "$SB/t8.log"

# ---------------------------------------------------------------- T9 existing fleet command is never replaced
H9="$(home 9)"
printf '#!/bin/sh\necho other\n' >"$H9/.local/bin/fleet"
chmod +x "$H9/.local/bin/fleet"
run "$H9" --yes >"$SB/t9.log" 2>&1
check "T9 existing fleet kept" grep -q 'echo other' "$H9/.local/bin/fleet"
check "T9 alias suggested" grep -q "alias fleet=" "$SB/t9.log"

# ---------------------------------------------------------------- T10 ~/.local/bin not on PATH
H10="$(home 10)"
HOME="$H10" PATH="$SB/bin:$SYS_PATH" HERDR_SETUP_BASE="$BASE" sh "$ROOT/install.sh" --yes </dev/null >"$SB/t10.log" 2>&1
check "T10 alias printed when ~/.local/bin is not on PATH" grep -q 'is not on your PATH' "$SB/t10.log"

# ---------------------------------------------------------------- T11 piped like curl | sh -s -- --yes
H11="$(home 11)"
HOME="$H11" PATH="$H11/.local/bin:$SB/bin:$SYS_PATH" HERDR_SETUP_BASE="$BASE" sh -s -- --yes <"$ROOT/install.sh" >"$SB/t11.log" 2>&1
check "T11 piped install exits 0" [ "$?" -eq 0 ]
check "T11 piped install wrote fleet.sh" [ -x "$H11/$CFG_REL/scripts/fleet.sh" ]

# ---------------------------------------------------------------- T12 download failure is clear and leaves no half files
H12="$(home 12)"
HOME="$H12" PATH="$H12/.local/bin:$SB/bin:$SYS_PATH" HERDR_SETUP_BASE="file://$SB/does-not-exist" sh "$ROOT/install.sh" --yes </dev/null >"$SB/t12.log" 2>&1
check "T12 exits non-zero" [ "$?" -ne 0 ]
check "T12 names the failed download" grep -q 'could not download' "$SB/t12.log"
check "T12 no partial files" [ -z "$(find "$H12/$CFG_REL" -type f 2>/dev/null)" ]

# ---------------------------------------------------------------- T13 unknown option
run "$H1" --bogus >"$SB/t13.log" 2>&1
check "T13 unknown option rejected" grep -q "unknown option '--bogus'" "$SB/t13.log"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
printf 'logs: %s\n' "$SB"
[ "$FAIL" -eq 0 ]
