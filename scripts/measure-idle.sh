#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  printf 'Usage: scripts/measure-idle.sh PID\n' >&2
  exit 1
fi
/usr/bin/top -pid "$1" -l 3 -s 10 -stats pid,cpu,mem,threads,idlew,power,time
