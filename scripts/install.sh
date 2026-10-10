#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d dist/Producktive.app ]]; then scripts/build-app.sh; fi
application_dir="${APPLICATION_DIR:-$HOME/Applications}"
mkdir -p "$application_dir"
if [[ -e "$application_dir/Producktive.app" ]]; then
  printf 'Existing app left untouched: %s/Producktive.app\n' "$application_dir" >&2
  exit 1
fi
cp -R dist/Producktive.app "$application_dir/"
printf 'Installed: %s/Producktive.app\n' "$application_dir"
if [[ $# -eq 0 ]]; then
  printf 'Select agent skills (space-separated: codex claude cursor; blank skips): '
  read -r -a selected_agents
else
  selected_agents=("$@")
fi
if [[ ${#selected_agents[@]} -gt 0 ]]; then
  "$application_dir/Producktive.app/Contents/Resources/bin/producktive-cli" install-skills --resources "$application_dir/Producktive.app/Contents/Resources" "${selected_agents[@]}"
fi
