#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cfy.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
export TEST_CFY_SCRIPT="$test_dir/stream.sh" TEST_INSTALL_PATH="$test_dir/cfy"
# Redirect only the install target. The actual bootstrap code and entry path run.
sed "s|^INSTALL_PATH=.*|INSTALL_PATH=\"$TEST_INSTALL_PATH\"|" "$script" > "$TEST_CFY_SCRIPT"
# Ensure the producer has data outstanding when the bootstrap exits.
for ((i=0; i<12000; i++)); do printf '# trailing script data %s\n' "$i" >> "$TEST_CFY_SCRIPT"; done
cat > "$test_dir/bin/id" <<'SH'
#!/bin/bash
echo 0
SH
cat > "$test_dir/bin/curl" <<'SH'
#!/bin/bash
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then cp "$TEST_CFY_SCRIPT" "$2"; exit; fi
    shift
done
exit 1
SH
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH"
export SERVED_SUB_FILE="$test_dir/nonexistent-sub"

# Test the documented bash <(curl ...) --update path without network access.
producer() {
    local rc=0
    cat "$TEST_CFY_SCRIPT" || rc=$?
    printf '%s\n' "$rc" > "$test_dir/producer-status"
}
bash <(producer) --update >"$test_dir/process-output" 2>&1
wait
[[ "$(cat "$test_dir/producer-status")" == 0 ]] || {
    echo 'FAIL: process-substitution installer closes its download pipe early' >&2; exit 1;
}
if ! cat "$TEST_CFY_SCRIPT" | bash -s -- --update >"$test_dir/stdin-output" 2>&1; then
    echo 'FAIL: stdin installer closes its download pipe early' >&2; exit 1;
fi
[[ -x "$TEST_INSTALL_PATH" ]] || { echo 'FAIL: bootstrap did not install the script' >&2; exit 1; }
echo 'Bootstrap stream consumption tests passed.'
