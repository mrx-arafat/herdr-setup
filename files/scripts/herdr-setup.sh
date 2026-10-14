#!/bin/sh
# herdr-setup - keep herdr, herdr-plus and this setup up to date.
#
#   herdr-setup check     show what is out of date. Changes nothing.
#   herdr-setup update    update herdr, herdr-plus, herdr's agent integrations and this
#                         setup's scripts and Quick Actions. Replaced files are backed up.
#
# Both download the newest installer from GitHub and run it, so the update logic is
# always current. Neither restarts herdr: running panes and agents keep going, and
# the update says when a restart would bring in new server features.
#
# Environment:
#   HERDR_SETUP_REF             branch or tag to update from (default: main)
#   HERDR_SETUP_INSTALLER_URL   the installer to run (default: install.sh on that branch)
set -eu

url="${HERDR_SETUP_INSTALLER_URL:-https://raw.githubusercontent.com/mrx-arafat/herdr-setup/${HERDR_SETUP_REF:-main}/install.sh}"

case "${1:-help}" in
  check) mode="--check" ;;
  update) mode="--update" ;;
  help | -h | --help)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    exit 0
    ;;
  *)
    echo "herdr-setup: unknown command '$1'. Use: herdr-setup check, or herdr-setup update" >&2
    exit 2
    ;;
esac

tmp="$(mktemp "${TMPDIR:-/tmp}/herdr-setup.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
if ! curl -fsSL --connect-timeout 20 --max-time 120 --retry 2 "$url" -o "$tmp" || [ ! -s "$tmp" ]; then
  echo "herdr-setup: could not download $url" >&2
  exit 1
fi
sh "$tmp" "$mode"
