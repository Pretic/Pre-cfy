#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cfy.sh"
source <(sed -n '/^update_self() {/,/^}/p' "$script")
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
RED='' GREEN='' YELLOW='' NC=''
REMOTE_URL=https://example.invalid/cfy.sh
INSTALL_PATH="$test_dir/cfy"
id() { printf '0\n'; }
check_update_dependencies() { return 0; }
repair_served_subscription_file() { return 0; }
show_update_done() { printf 'updated\n'; }
printf '#!/bin/bash\necho old\n' > "$INSTALL_PATH"
original=$(sha256sum "$INSTALL_PATH")
fixture="$test_dir/download"
mode=ok
curl() {
    [[ "$mode" != fail ]] || return 22
    local output=''
    while (($#)); do
        if [[ "$1" == -o ]]; then shift; output=$1; fi
        shift
    done
    cp "$fixture" "$output"
}
assert_unchanged() { [[ "$(sha256sum "$INSTALL_PATH")" == "$original" ]]; }
printf '#!/bin/bash\nINSTALL_PATH="/usr/local/bin/cfy"\nif then\n' > "$fixture"
if update_self >/dev/null 2>&1; then echo 'invalid Bash accepted' >&2; exit 1; fi
assert_unchanged
printf '<html>not a script</html>\n' > "$fixture"
if update_self >/dev/null 2>&1; then echo 'HTML accepted' >&2; exit 1; fi
assert_unchanged
: > "$fixture"
if update_self >/dev/null 2>&1; then echo 'empty download accepted' >&2; exit 1; fi
assert_unchanged
printf '#!/bin/bash\nINSTALL_PATH="/usr/local/bin/cfy"\necho new\n' > "$fixture"
mode=fail
if update_self >/dev/null 2>&1; then echo 'network failure accepted' >&2; exit 1; fi
assert_unchanged
mode=ok
CFY_UPDATE_SHA256=$(printf '%064d' 0)
if update_self >/dev/null 2>&1; then echo 'checksum mismatch accepted' >&2; exit 1; fi
assert_unchanged
CFY_UPDATE_SHA256=$(sha256sum "$fixture"); CFY_UPDATE_SHA256=${CFY_UPDATE_SHA256%% *}
update_self >/dev/null
cmp -s "$fixture" "$INSTALL_PATH"
printf '#!/bin/bash\necho old\n' > "$test_dir/expected-old"
cmp -s "$test_dir/expected-old" "$test_dir/.cfy-previous"
[[ -x "$INSTALL_PATH" ]]
[[ -f "$test_dir/.cfy-update.lock" ]]
[[ -z "$(find "$test_dir" -maxdepth 1 -name '.cfy-*.??????' -print)" ]]
rm "$INSTALL_PATH"
ln -s "$test_dir/expected-old" "$INSTALL_PATH"
if update_self >/dev/null 2>&1; then echo 'symlink target accepted' >&2; exit 1; fi
cmp -s "$test_dir/expected-old" "$test_dir/.cfy-previous"
echo 'Atomic cfy update validation tests passed.'
