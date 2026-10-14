#!/bin/sh
# Sandbox tests for install.sh.
#
# Every case runs the installer with a fake HOME and a stub `herdr`, and downloads
# files/ from this checkout through file:// URLs. Nothing touches your real setup.
#
#   sh tests/sandbox.sh
set -u

# Run the same inside a herdr pane as in CI: the installer behaves differently inside herdr.
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_BIN_PATH

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

# ---------------------------------------------------------------- stubs: herdr, git
# The stubs keep their state in the fake HOME and log every call to $HOME/.stub-log.
mkdir -p "$SB/bin"
cat >"$SB/bin/herdr" <<'EOF'
#!/bin/sh
echo "herdr $*" >>"$HOME/.stub-log"
ver="$(cat "$HOME/.stub-version" 2>/dev/null || echo "${STUB_VERSION:-0.9.3}")"
case "$1 ${2:-}" in
  "--version "*) echo "herdr $ver" ;;
  "update ") echo "${STUB_NEW_VERSION:-0.9.4}" >"$HOME/.stub-version"; echo "updated" ;;
  "status --json") printf '{"client":{"version":"%s"},"server":{"running":true,"version":"%s"},"update":{"restart_needed":false}}\n' "$ver" "${STUB_SERVER:-0.9.3}" ;;
  "plugin list")
    if [ ! -f "$HOME/.stub-installed" ]; then
      if [ "${3:-}" = --json ]; then echo '{"result":{"plugins":[]}}'; fi
    elif [ "${3:-}" = --json ]; then
      printf '{"result":{"plugins":[{"plugin_id":"cloudmanic.herdr-plus","source":{"kind":"github","resolved_commit":"%s"}}]}}\n' "$(cat "$HOME/.stub-installed")"
    else
      echo "cloudmanic.herdr-plus (Herdr Plus) enabled"
    fi
    ;;
  "plugin install") echo "${STUB_REMOTE_COMMIT:-bbbbbbbbbbbb}" >"$HOME/.stub-installed"; echo "installed" ;;
  "plugin config-dir") echo "$HOME/.config/herdr/plugins/config/$3" ;;
  "integration status") cat "$HOME/.stub-integrations" 2>/dev/null || echo "claude: current (v10) (/x)" ;;
  "integration install") echo "$3: current (v8) (/x)" >"$HOME/.stub-integrations" ;;
  "completion zsh") echo "#compdef herdr" ;;
  "server reload-config") echo '{"result":{"status":"applied"}}' ;;
  "config check") echo "config: ok" ;;
  *) echo "stub: unhandled: $*" >&2; exit 2 ;;
esac
EOF
cat >"$SB/bin/git" <<'EOF'
#!/bin/sh
echo "git $*" >>"$HOME/.stub-log"
if [ "$1" = ls-remote ]; then printf '%s\tHEAD\n' "${STUB_REMOTE_COMMIT:-bbbbbbbbbbbb}"; fi
EOF
chmod +x "$SB/bin/herdr" "$SB/bin/git"
# The newest herdr release, where github.com/.../releases/latest would redirect.
mkdir -p "$SB/releases/tag" && : >"$SB/releases/tag/v0.9.4"
export HERDR_SETUP_RELEASES_URL="file://$SB/releases/tag/v0.9.4"

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
for f in scripts/agent-tab.sh scripts/fleet.sh scripts/herdr-setup.sh \
  quick-actions/claude-dangerously-skip-permission.toml quick-actions/agy-dangerously-skip-permission.toml \
  quick-actions/codex-dangerously-skip-sandbox.toml quick-actions/agent-grid-2x2.toml quick-actions/workers.toml \
  quick-actions/workers-custom.toml quick-actions/name-workers.toml quick-actions/update-setup.toml; do
  cmp -s "$ROOT/files/$f" "$H1/$CFG_REL/$f" || all_same=1
done
check "T1 all 11 files installed byte for byte" [ "$all_same" -eq 0 ]
check "T1 fleet.sh is executable" [ -x "$H1/$CFG_REL/scripts/fleet.sh" ]
check "T1 agent-tab.sh is executable" [ -x "$H1/$CFG_REL/scripts/agent-tab.sh" ]
check "T1 fleet linked into ~/.local/bin" [ "$(readlink "$H1/.local/bin/fleet")" = "$H1/$CFG_REL/scripts/fleet.sh" ]
check "T1 herdr-setup linked into ~/.local/bin" [ "$(readlink "$H1/.local/bin/herdr-setup")" = "$H1/$CFG_REL/scripts/herdr-setup.sh" ]
check "T1 both key bindings added" [ "$(grep -c 'cloudmanic.herdr-plus\.' "$H1/.config/herdr/config.toml")" -eq 2 ]
check "T1 plugin install was requested" [ -f "$H1/.stub-installed" ]
check "T1 no download temp files left" [ -z "$(find "$H1/$CFG_REL" -name '*.download.*')" ]

# ---------------------------------------------------------------- T2 re-run is a no-op
cp "$H1/.config/herdr/config.toml" "$SB/t2.before"
run "$H1" --yes >"$SB/t2.log" 2>&1
check "T2 re-run exits 0" [ "$?" -eq 0 ]
check "T2 config.toml unchanged" cmp -s "$SB/t2.before" "$H1/.config/herdr/config.toml"
check "T2 every file left alone" [ "$(grep -c 'left alone (exists)' "$SB/t2.log")" -eq 11 ]
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

# ---------------------------------------------------------------- T14 --check reports and changes nothing
H14="$(home 14)"
run "$H14" --yes >"$SB/t14-install.log" 2>&1
echo aaaaaaaaaaaa >"$H14/.stub-installed"                  # an older herdr-plus
echo "codex: outdated (v7) (/x)" >"$H14/.stub-integrations" # a stale integration
echo "# my edit" >>"$H14/$CFG_REL/scripts/fleet.sh"         # a file the user changed
cp "$H14/$CFG_REL/scripts/fleet.sh" "$SB/t14.fleet"
: >"$H14/.stub-log"
run "$H14" --check >"$SB/t14.log" 2>&1
check "T14 check exits 0" [ "$?" -eq 0 ]
check "T14 newer herdr reported" grep -q 'herdr: 0.9.3 installed, 0.9.4 available' "$SB/t14.log"
check "T14 newer plugin reported" grep -q 'aaaaaaa installed, bbbbbbb available' "$SB/t14.log"
check "T14 stale integration reported" grep -q 'codex is not current' "$SB/t14.log"
check "T14 changed file reported" grep -q 'differs: .*scripts/fleet.sh' "$SB/t14.log"
check "T14 total reported" grep -q '4 update(s) available' "$SB/t14.log"
# shellcheck disable=SC2016 # $1 expands inside the inner sh, on purpose
check "T14 nothing updated" sh -c '! grep -Eq "^herdr (update|plugin install|integration install)" "$1"' _ "$H14/.stub-log"
check "T14 changed file kept" cmp -s "$SB/t14.fleet" "$H14/$CFG_REL/scripts/fleet.sh"

# ---------------------------------------------------------------- T15 --update brings everything current
: >"$H14/.stub-log"
run "$H14" --update >"$SB/t15.log" 2>&1
check "T15 update exits 0" [ "$?" -eq 0 ]
check "T15 herdr update ran" grep -qx 'herdr update' "$H14/.stub-log"
check "T15 herdr version reported" grep -q 'herdr: 0.9.3 -> 0.9.4' "$SB/t15.log"
check "T15 plugin reinstalled" grep -qx 'herdr plugin install cloudmanic/herdr-plus --yes' "$H14/.stub-log"
check "T15 stale integration refreshed" grep -qx 'herdr integration install codex' "$H14/.stub-log"
check "T15 changed file replaced" cmp -s "$ROOT/files/scripts/fleet.sh" "$H14/$CFG_REL/scripts/fleet.sh"
# shellcheck disable=SC2016 # $1 and $2 expand inside the inner sh, on purpose
check "T15 old copy backed up" sh -c 'cmp -s "$1" "$2"/.config/herdr/backups/herdr-setup-*/scripts/fleet.sh' _ "$SB/t14.fleet" "$H14"
check "T15 restart advised for the old server" grep -q 'running herdr server is 0.9.3' "$SB/t15.log"
check "T15 no download temp files left" [ -z "$(find "$H14/$CFG_REL" -name '*.download.*')" ]

# ---------------------------------------------------------------- T16 a second --update has nothing to do
mkdir -p "$H14/.zfunc" && : >"$H14/.zfunc/_herdr"
: >"$H14/.stub-log"
run "$H14" --update >"$SB/t16.log" 2>&1
check "T16 second update exits 0" [ "$?" -eq 0 ]
# shellcheck disable=SC2016 # $1 expands inside the inner sh, on purpose
check "T16 herdr update not run again" sh -c '! grep -qx "herdr update" "$1"' _ "$H14/.stub-log"
# shellcheck disable=SC2016
check "T16 plugin not reinstalled" sh -c '! grep -q "plugin install" "$1"' _ "$H14/.stub-log"
# shellcheck disable=SC2016
check "T16 no file replaced" sh -c '! grep -q "updated: " "$1"' _ "$SB/t16.log"
check "T16 zsh completion refreshed" grep -q compdef "$H14/.zfunc/_herdr"
# shellcheck disable=SC2016
check "T16 no backup claimed" sh -c '! grep -q "old copies" "$1"' _ "$SB/t16.log"

# ---------------------------------------------------------------- T17 a Homebrew herdr updates through brew
H17="$(home 17)"
run "$H17" --yes >/dev/null 2>&1
mkdir -p "$SB/brew/Cellar/herdr/0.9.3/bin" "$SB/brewbin"
cp "$SB/bin/herdr" "$SB/brew/Cellar/herdr/0.9.3/bin/herdr"
ln -sf "$SB/brew/Cellar/herdr/0.9.3/bin/herdr" "$SB/brewbin/herdr"
# shellcheck disable=SC2016 # the stub expands $* and $HOME when it runs
printf '#!/bin/sh\necho "brew $*" >>"$HOME/.stub-log"\n' >"$SB/brewbin/brew"
chmod +x "$SB/brewbin/brew"
: >"$H17/.stub-log"
HOME="$H17" PATH="$H17/.local/bin:$SB/brewbin:$SB/bin:$SYS_PATH" HERDR_SETUP_BASE="$BASE" \
  sh "$ROOT/install.sh" --update </dev/null >"$SB/t17.log" 2>&1
check "T17 brew update ran first" grep -qx 'brew update' "$H17/.stub-log"
check "T17 brew upgrade herdr ran" grep -qx 'brew upgrade herdr' "$H17/.stub-log"
# shellcheck disable=SC2016
check "T17 herdr update not used" sh -c '! grep -qx "herdr update" "$1"' _ "$H17/.stub-log"

# ---------------------------------------------------------------- T19 inside a herdr pane herdr is left for a plain terminal
H19="$(home 19)"
run "$H19" --yes >/dev/null 2>&1
echo aaaaaaaaaaaa >"$H19/.stub-installed"
: >"$H19/.stub-log"
(HERDR_ENV=1 run "$H19" --update >"$SB/t19.log" 2>&1)
check "T19 update inside herdr exits 0" [ "$?" -eq 0 ]
# shellcheck disable=SC2016
check "T19 herdr update not run inside herdr" sh -c '! grep -qx "herdr update" "$1"' _ "$H19/.stub-log"
check "T19 told to use a plain terminal" grep -q 'Open a plain terminal' "$SB/t19.log"
check "T19 plugin still updated" grep -qx 'herdr plugin install cloudmanic/herdr-plus --yes' "$H19/.stub-log"
check "T19 summary names the gap" grep -q 'except herdr itself' "$SB/t19.log"

# ---------------------------------------------------------------- T18 the herdr-setup command runs the newest installer
HOME="$H14" PATH="$H14/.local/bin:$SB/bin:$SYS_PATH" HERDR_SETUP_BASE="$BASE" \
  HERDR_SETUP_INSTALLER_URL="file://$ROOT/install.sh" herdr-setup check </dev/null >"$SB/t18.log" 2>&1
check "T18 herdr-setup check runs the installer" grep -q 'Everything is up to date' "$SB/t18.log"
HOME="$H14" PATH="$H14/.local/bin:$SB/bin:$SYS_PATH" herdr-setup bogus </dev/null >"$SB/t18b.log" 2>&1
check "T18 unknown herdr-setup command exits 2" [ "$?" -eq 2 ]

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
printf 'logs: %s\n' "$SB"
[ "$FAIL" -eq 0 ]
