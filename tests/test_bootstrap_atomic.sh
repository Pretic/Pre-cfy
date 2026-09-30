#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
INSTALL_PATH="$d/cfy"; SERVED_SUB_FILE="$d/sub"
printf '#!/bin/bash\necho old\n' > "$INSTALL_PATH"
printf '#!/bin/bash\necho new\n' > "$d/new"
cp "$INSTALL_PATH" "$d/old"
(
 install() { printf 'partial' > "${*: -1}"; return 1; }
 if install_validated_script "$d/new"; then exit 1; fi
)
cmp "$INSTALL_PATH" "$d/old"
printf '#!/bin/bash\nif then\n' > "$d/bad"
if install_validated_script "$d/bad" 2>/dev/null; then exit 1; fi
cmp "$INSTALL_PATH" "$d/old"
rm "$INSTALL_PATH"; ln -s "$d/old" "$INSTALL_PATH"
if install_validated_script "$d/new"; then echo 'symlink install accepted'; exit 1; fi
[[ $(cat "$d/old") == $'#!/bin/bash\necho old' ]]
rm "$INSTALL_PATH"; cp "$d/old" "$INSTALL_PATH"
install_validated_script "$d/new"
cmp "$INSTALL_PATH" "$d/new"; cmp "$d/.cfy-previous" "$d/old"
[[ $(stat -c %a "$INSTALL_PATH") == 755 ]]
printf private > "$d/private"; chmod 600 "$d/private"; ln -s "$d/private" "$SERVED_SUB_FILE"
if repair_served_subscription_file; then echo 'served symlink accepted'; exit 1; fi
[[ $(stat -c %a "$d/private") == 600 ]]
echo 'Atomic bootstrap failure/backup and installed/served symlink checks passed.'
