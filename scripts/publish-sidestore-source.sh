#!/bin/sh
# Overwrite the rolling SideStore catalog. The source URL never changes:
#   https://github.com/KikeMartinG93/wf-schedule-app/releases/download/latest/apps.json
set -e
cd "$(dirname "$0")/.."
gh release upload latest store/apps.json --clobber
curl -fsS "https://purge.jsdelivr.net/gh/KikeMartinG93/wf-schedule-app@main/store/apps.json" >/dev/null || true
curl -fsS "https://purge.jsdelivr.net/gh/KikeMartinG93/wf-schedule-app@latest/store/apps.json" >/dev/null || true
echo "Published SideStore catalog."
