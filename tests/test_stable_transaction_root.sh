#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/cfy.sh"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

extract_function() {
    sed -n "/^${1}() {/,/^}/p" "$script"
}

load_function() {
    local source
    source="$(extract_function "$1")"
    [[ -n "$source" ]] || fail "$1 is not implemented"
    source /dev/stdin <<< "$source"
}

transaction_functions=(
    clear_inherited_transaction_lock_state
    command_exists
    transaction_root_path
    transaction_expected_dir_mode
    transaction_expected_file_mode
    transaction_expected_gid
    validate_transaction_path_components
    validate_transaction_directory
    ensure_transaction_directory
    validate_transaction_regular_file
    ensure_transaction_regular_file
    write_transaction_schema_file
    ensure_stable_transaction_root
    stable_transaction_lock_path
    stable_transaction_lock_rank
    stable_transaction_lock_is_held
    stable_transaction_highest_rank
    stable_transaction_lock_hook
    legacy_transaction_lock_hook
    reset_stable_transaction_lock_state
    acquire_stable_transaction_lock
    release_stable_transaction_lock
    with_stable_transaction_lock
    validate_safe_legacy_lock
    acquire_safe_legacy_lock
    release_safe_legacy_lock
    acquire_transaction_lock_with_legacy
    release_transaction_lock_with_legacy
    with_transaction_lock_with_legacy
    with_subscription_lock
)
for function_name in "${transaction_functions[@]}"; do
    load_function "$function_name"
done

# The production default is asserted without creating or inspecting it.  All
# mutation below is redirected to this test-owned directory.
unset SING_BOX_TRANSACTION_ROOT SING_BOX_TRANSACTION_GROUP
[[ "$(transaction_root_path)" == /var/lib/sing-box-transactions ]] ||
    fail 'default stable transaction root changed'
SING_BOX_TRANSACTION_ROOT="${tmp_root}/transactions"
ensure_stable_transaction_root || fail 'override stable transaction root could not be initialized'

expected_uid="$(id -u)"
expected_gid="$(id -g)"
for dir in "$SING_BOX_TRANSACTION_ROOT" "$SING_BOX_TRANSACTION_ROOT/pending" "$SING_BOX_TRANSACTION_ROOT/recoveries"; do
    [[ "$(stat -c '%a:%u:%g' -- "$dir")" == "700:${expected_uid}:${expected_gid}" ]] ||
        fail "unexpected private transaction directory metadata: $dir"
done
for file in schema-version mutation.lock subscription.lock firewall.lock; do
    path="$SING_BOX_TRANSACTION_ROOT/$file"
    [[ "$(stat -c '%a:%u:%g:%h' -- "$path")" == "600:${expected_uid}:${expected_gid}:1" ]] ||
        fail "unexpected private transaction file metadata: $file"
done
[[ "$(cat "$SING_BOX_TRANSACTION_ROOT/schema-version")" == 1 ]] || fail 'schema version is not 1'
for kind in mutation subscription firewall; do
    [[ ! -s "$(stable_transaction_lock_path "$kind")" ]] || fail "$kind lock contains data"
done

inode_snapshot="$(stat -c '%d:%i' -- "$SING_BOX_TRANSACTION_ROOT/subscription.lock")"
ensure_stable_transaction_root || fail 'repeat root initialization failed'
[[ "$(stat -c '%d:%i' -- "$SING_BOX_TRANSACTION_ROOT/subscription.lock")" == "$inode_snapshot" ]] ||
    fail 'repeat initialization replaced the stable subscription inode'

chmod 755 "$SING_BOX_TRANSACTION_ROOT"
chmod 644 "$SING_BOX_TRANSACTION_ROOT/subscription.lock"
ensure_stable_transaction_root || fail 'safe metadata repair failed'
[[ "$(stat -c '%a' -- "$SING_BOX_TRANSACTION_ROOT")" == 700 ]] || fail 'root mode was not repaired'
[[ "$(stat -c '%a' -- "$SING_BOX_TRANSACTION_ROOT/subscription.lock")" == 600 ]] ||
    fail 'lock mode was not repaired'
[[ "$(stat -c '%d:%i' -- "$SING_BOX_TRANSACTION_ROOT/subscription.lock")" == "$inode_snapshot" ]] ||
    fail 'metadata repair replaced the stable inode'

SING_BOX_TRANSACTION_GROUP="$expected_gid"
ensure_stable_transaction_root || fail 'numeric trusted-group mode failed'
[[ "$(stat -c '%a:%g' -- "$SING_BOX_TRANSACTION_ROOT")" == "750:${expected_gid}" ]] ||
    fail 'trusted-group directory metadata is wrong'
[[ "$(stat -c '%a:%g' -- "$SING_BOX_TRANSACTION_ROOT/subscription.lock")" == "640:${expected_gid}" ]] ||
    fail 'trusted-group file metadata is wrong'
unset SING_BOX_TRANSACTION_GROUP
ensure_stable_transaction_root || fail 'return to private mode failed'

assert_root_contract_rc2() {
    local label="$1" status
    set +e
    ensure_stable_transaction_root >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 2 ]] || fail "$label returned $status, expected 2"
}

SING_BOX_TRANSACTION_ROOT=relative/path
assert_root_contract_rc2 'relative transaction root'
SING_BOX_TRANSACTION_ROOT=$'/tmp/bad\nroot'
assert_root_contract_rc2 'newline transaction root'

unsafe_parent="${tmp_root}/unsafe-parent"
mkdir "$unsafe_parent"
ln -s "$unsafe_parent" "${tmp_root}/unsafe-link"
SING_BOX_TRANSACTION_ROOT="${tmp_root}/unsafe-link/root"
assert_root_contract_rc2 'symlink parent'

SING_BOX_TRANSACTION_ROOT="${tmp_root}/unsafe-objects"
ensure_stable_transaction_root || fail 'unsafe-object fixture root failed'
printf 'backing\n' > "$SING_BOX_TRANSACTION_ROOT/backing"
rm -f "$SING_BOX_TRANSACTION_ROOT/subscription.lock"
ln "$SING_BOX_TRANSACTION_ROOT/backing" "$SING_BOX_TRANSACTION_ROOT/subscription.lock"
assert_root_contract_rc2 'hard-linked stable lock'
[[ "$(cat "$SING_BOX_TRANSACTION_ROOT/backing")" == backing ]] || fail 'hard-link referent was changed'
rm -f "$SING_BOX_TRANSACTION_ROOT/subscription.lock"
ln -s "$SING_BOX_TRANSACTION_ROOT/backing" "$SING_BOX_TRANSACTION_ROOT/subscription.lock"
assert_root_contract_rc2 'symlink stable lock'
[[ -L "$SING_BOX_TRANSACTION_ROOT/subscription.lock" ]] || fail 'symlink lock was replaced'

SING_BOX_TRANSACTION_ROOT="${tmp_root}/bad-schema"
ensure_stable_transaction_root || fail 'schema fixture root failed'
printf '2\n' > "$SING_BOX_TRANSACTION_ROOT/schema-version"
chmod 600 "$SING_BOX_TRANSACTION_ROOT/schema-version"
assert_root_contract_rc2 'foreign schema'
[[ "$(cat "$SING_BOX_TRANSACTION_ROOT/schema-version")" == 2 ]] || fail 'foreign schema was overwritten'
printf '1\n\n' > "$SING_BOX_TRANSACTION_ROOT/schema-version"
chmod 600 "$SING_BOX_TRANSACTION_ROOT/schema-version"
assert_root_contract_rc2 'schema with trailing data'

SING_BOX_TRANSACTION_ROOT="${tmp_root}/ordered"
ensure_stable_transaction_root || fail 'ordered lock fixture failed'
reset_stable_transaction_lock_state
[[ "$(stable_transaction_lock_rank mutation)" == 1 ]] || fail 'mutation rank changed'
[[ "$(stable_transaction_lock_rank subscription)" == 2 ]] || fail 'subscription rank changed'
[[ "$(stable_transaction_lock_rank firewall)" == 3 ]] || fail 'firewall rank changed'

(
    reset_stable_transaction_lock_state
    acquire_stable_transaction_lock mutation 1
    release_stable_transaction_lock mutation
) || fail 'BASHPID fd validation failed in a subshell'

acquire_stable_transaction_lock mutation 1 || fail 'mutation lock failed'
acquire_stable_transaction_lock subscription 1 || fail 'subscription after mutation failed'
acquire_stable_transaction_lock firewall 1 || fail 'firewall after subscription failed'
set +e
release_stable_transaction_lock mutation
order_status=$?
set -e
[[ "$order_status" -eq 2 ]] || fail "out-of-order release returned $order_status"
release_stable_transaction_lock firewall || fail 'firewall release failed'
release_stable_transaction_lock subscription || fail 'subscription release failed'
release_stable_transaction_lock mutation || fail 'mutation release failed'

# Same-kind re-entry is allowed only while that kind remains the highest rank.
mutation_path="$(stable_transaction_lock_path mutation)"
subscription_path="$(stable_transaction_lock_path subscription)"
acquire_stable_transaction_lock mutation 1 || fail 'mutation for cross-rank re-entry failed'
acquire_stable_transaction_lock subscription 1 || fail 'subscription for cross-rank re-entry failed'
mutation_depth_before=${STABLE_TX_MUTATION_DEPTH:-}
mutation_fd_before=${STABLE_TX_MUTATION_FD:-}
subscription_depth_before=${STABLE_TX_SUBSCRIPTION_DEPTH:-}
subscription_fd_before=${STABLE_TX_SUBSCRIPTION_FD:-}
set +e
acquire_stable_transaction_lock mutation 1
order_status=$?
set -e
[[ "$order_status" -eq 2 ]] || fail "mutation re-entry below subscription returned $order_status"
[[ "${STABLE_TX_MUTATION_DEPTH:-}" == "$mutation_depth_before" && \
   "${STABLE_TX_MUTATION_FD:-}" == "$mutation_fd_before" ]] ||
    fail 'rejected mutation re-entry changed mutation state'
[[ "${STABLE_TX_SUBSCRIPTION_DEPTH:-}" == "$subscription_depth_before" && \
   "${STABLE_TX_SUBSCRIPTION_FD:-}" == "$subscription_fd_before" ]] ||
    fail 'rejected mutation re-entry changed subscription state'
release_stable_transaction_lock subscription || fail 'subscription release after rejected re-entry failed'
release_stable_transaction_lock mutation || fail 'mutation release after rejected re-entry failed'
flock -n "$subscription_path" -c true || fail 'rejected re-entry leaked subscription kernel lock'
flock -n "$mutation_path" -c true || fail 'rejected re-entry leaked mutation kernel lock'

acquire_stable_transaction_lock subscription 1 || fail 'standalone subscription lock failed'
set +e
acquire_stable_transaction_lock mutation 1
order_status=$?
set -e
[[ "$order_status" -eq 2 ]] || fail "descending lock acquire returned $order_status"
release_stable_transaction_lock subscription || fail 'standalone subscription release failed'

subscription_path="$(stable_transaction_lock_path subscription)"
subscription_identity="$(stat -c '%d:%i:%s' -- "$subscription_path")"
acquire_stable_transaction_lock subscription 1 || fail 'nested subscription level 1 failed'
acquire_stable_transaction_lock subscription 1 || fail 'nested subscription level 2 failed'
release_stable_transaction_lock subscription || fail 'nested subscription release 1 failed'
stable_transaction_lock_is_held subscription || fail 'nested release unlocked too early'
flock -n "$subscription_path" -c true && fail 'another process acquired nested lock'
release_stable_transaction_lock subscription || fail 'nested subscription release 2 failed'
flock -n "$subscription_path" -c true || fail 'final release leaked kernel lock'
[[ "$(stat -c '%d:%i:%s' -- "$subscription_path")" == "$subscription_identity" ]] ||
    fail 'lock lifecycle changed the stable inode'

flock -x "$subscription_path" -c 'sleep 1' & holder_pid=$!
sleep 0.1
set +e
acquire_stable_transaction_lock subscription 0
timeout_status=$?
set -e
wait "$holder_pid"
[[ "$timeout_status" -eq 1 ]] || fail "stable contention returned $timeout_status, expected 1"

for callback_status_expected in 0 1 2 37; do
    locked_callback() { return "$callback_status_expected"; }
    set +e
    with_stable_transaction_lock subscription locked_callback
    callback_status=$?
    set -e
    [[ "$callback_status" -eq "$callback_status_expected" ]] ||
        fail "callback status $callback_status_expected changed to $callback_status"
    stable_transaction_lock_is_held subscription && fail 'callback leaked stable state'
done

stable_transaction_lock_hook() { [[ "${1:-}" != released ]]; }
locked_success() { return 0; }
set +e
with_stable_transaction_lock subscription locked_success
release_failure_status=$?
set -e
[[ "$release_failure_status" -eq 2 ]] || fail "release uncertainty returned $release_failure_status"
stable_transaction_lock_hook() { :; }

# Replacement between opening the descriptor and post-flock validation must be
# fatal and must not leak in-process lock state.
real_flock="$(type -P flock)"
race_path="$subscription_path"
race_old="${subscription_path}.replaced"
race_once=1
flock() {
    if [[ "$race_once" -eq 1 && "${1:-}" == -x ]]; then
        race_once=0
        mv "$race_path" "$race_old"
        : > "$race_path"
        chmod 600 "$race_path"
    fi
    "$real_flock" "$@"
}
set +e
acquire_stable_transaction_lock subscription 1
race_status=$?
set -e
unset -f flock
[[ "$race_status" -eq 2 ]] || fail "stable path/fd replacement returned $race_status"
stable_transaction_lock_is_held subscription && fail 'replacement race leaked stable state'
rm -f "$race_old"
ensure_stable_transaction_root || fail 'replacement race fixture could not be repaired'

legacy_dir="${tmp_root}/legacy"
mkdir "$legacy_dir"
legacy_lock="$legacy_dir/.subscription.lock"
: > "$legacy_lock"
chmod 600 "$legacy_lock"
bridge_log="$tmp_root/bridge.log"
: > "$bridge_log"
stable_transaction_lock_hook() { printf 'stable:%s\n' "$1" >> "$bridge_log"; }
legacy_transaction_lock_hook() { printf 'legacy:%s\n' "$1" >> "$bridge_log"; }
acquire_transaction_lock_with_legacy subscription "$legacy_lock" 1 || fail 'bridge acquire failed'
[[ "$(sed -n '1p' "$bridge_log")" == stable:acquired ]] || fail 'stable lock was not first'
[[ "$(sed -n '2p' "$bridge_log")" == legacy:acquired ]] || fail 'legacy lock was not second'
release_transaction_lock_with_legacy subscription || fail 'bridge release failed'
[[ "$(sed -n '3p' "$bridge_log")" == legacy:released ]] || fail 'legacy lock was not released first'
[[ "$(sed -n '4p' "$bridge_log")" == stable:released ]] || fail 'stable lock was not released second'
stable_transaction_lock_hook() { :; }
legacy_transaction_lock_hook() { :; }

absent_legacy="$legacy_dir/.absent.lock"
acquire_transaction_lock_with_legacy subscription "$absent_legacy" 1 || fail 'absent legacy bridge failed'
[[ ! -e "$absent_legacy" && ! -L "$absent_legacy" ]] || fail 'absent legacy lock was created'
release_transaction_lock_with_legacy subscription || fail 'absent legacy release failed'

assert_unsafe_legacy_rc2() {
    local label="$1" path="$2" status
    set +e
    acquire_transaction_lock_with_legacy subscription "$path" 1
    status=$?
    set -e
    [[ "$status" -eq 2 ]] || fail "$label legacy lock returned $status, expected 2"
    if stable_transaction_lock_is_held subscription; then
        fail "$label leaked stable state"
    fi
    return 0
}
unsafe_target="$legacy_dir/unsafe-target"
: > "$unsafe_target"
chmod 600 "$unsafe_target"
ln -s "$unsafe_target" "$legacy_dir/symlink.lock"
assert_unsafe_legacy_rc2 symlink "$legacy_dir/symlink.lock"
ln "$unsafe_target" "$legacy_dir/hardlink.lock"
assert_unsafe_legacy_rc2 hardlink "$legacy_dir/hardlink.lock"
: > "$legacy_dir/wide.lock"
chmod 666 "$legacy_dir/wide.lock"
assert_unsafe_legacy_rc2 wide-mode "$legacy_dir/wide.lock"

flock -x "$legacy_lock" -c 'sleep 1' & legacy_holder_pid=$!
sleep 0.1
set +e
acquire_safe_legacy_lock subscription "$legacy_lock" 0
legacy_timeout_status=$?
set -e
wait "$legacy_holder_pid"
[[ "$legacy_timeout_status" -eq 1 ]] || fail "legacy contention returned $legacy_timeout_status"

flock -x "$legacy_lock" -c 'sleep 1' & legacy_holder_pid=$!
sleep 0.1
stable_transaction_lock_hook() { [[ "${1:-}" != released ]]; }
set +e
acquire_transaction_lock_with_legacy subscription "$legacy_lock" 0
legacy_cleanup_status=$?
set -e
stable_transaction_lock_hook() { :; }
wait "$legacy_holder_pid"
[[ "$legacy_cleanup_status" -eq 2 ]] ||
    fail "legacy contention plus stable release failure returned $legacy_cleanup_status"
[[ "${STABLE_TX_SUBSCRIPTION_DEPTH:-0}" -eq 0 && -z "${STABLE_TX_SUBSCRIPTION_FD:-}" ]] ||
    fail 'failed bridge cleanup leaked stable subscription state'
[[ "${LEGACY_TX_SUBSCRIPTION_DEPTH:-0}" -eq 0 && -z "${LEGACY_TX_SUBSCRIPTION_FD:-}" ]] ||
    fail 'failed bridge cleanup leaked legacy subscription state'
flock -n "$(stable_transaction_lock_path subscription)" -c true ||
    fail 'failed bridge cleanup leaked the stable kernel lock'

# Public subscription wrapper must provide dynamic reentrancy and preserve all
# callback statuses; release uncertainty is fatal rc=2.
SUBSCRIPTION_LOCK_FILE="$legacy_lock"
for callback_status_expected in 0 1 2 37; do
    subscription_callback() {
        [[ "${SUBSCRIPTION_LOCK_HELD:-0}" == 1 ]] || return 88
        return "$callback_status_expected"
    }
    set +e
    with_subscription_lock subscription_callback
    callback_status=$?
    set -e
    [[ "$callback_status" -eq "$callback_status_expected" ]] ||
        fail "subscription callback status $callback_status_expected changed to $callback_status"
done
stable_transaction_lock_hook() { [[ "${1:-}" != released ]]; }
set +e
with_subscription_lock true
subscription_release_status=$?
set -e
[[ "$subscription_release_status" -eq 2 ]] ||
    fail "subscription release uncertainty returned $subscription_release_status"
stable_transaction_lock_hook() { :; }

# Execute the real cfy -c entry with forged inherited bookkeeping while the
# stable subscription lock is held elsewhere. The entry must clear the forged
# state and return bounded contention instead of reading the template callback.
grep -Fq 'clear_inherited_transaction_lock_state || exit 2' "$script" ||
    fail 'top-level cfy entry does not clear inherited transaction state'
entry_dir="$tmp_root/entry"
mkdir "$entry_dir"
entry_script="$entry_dir/cfy"
sed "s|^INSTALL_PATH=\"/usr/local/bin/cfy\"|INSTALL_PATH=\"${entry_script}\"|" "$script" > "$entry_script"
chmod 700 "$entry_script"
entry_url="$entry_dir/url.txt"
printf '%s\n' 'vless://00000000-0000-0000-0000-000000000000@example.com:443?security=tls&type=ws&host=example.com&sni=example.com&path=%2F#polluted-entry' > "$entry_url"
entry_ready="$entry_dir/holder.ready"
(
    exec 9>>"$subscription_path"
    flock -x 9
    : > "$entry_ready"
    sleep 1
) & entry_holder_pid=$!
for _ in {1..100}; do [[ -e "$entry_ready" ]] && break; sleep 0.01; done
[[ -e "$entry_ready" ]] || fail 'polluted cfy entry holder did not start'
set +e
env \
    SUBSCRIPTION_LOCK_HELD=1 \
    STABLE_TX_MUTATION_DEPTH=9 STABLE_TX_MUTATION_FD=91 \
    STABLE_TX_SUBSCRIPTION_DEPTH=9 STABLE_TX_SUBSCRIPTION_FD=92 \
    STABLE_TX_FIREWALL_DEPTH=9 STABLE_TX_FIREWALL_FD=93 \
    LEGACY_TX_MUTATION_DEPTH=9 LEGACY_TX_MUTATION_FD=94 LEGACY_TX_MUTATION_PATH=/tmp/forged-mutation \
    LEGACY_TX_SUBSCRIPTION_DEPTH=9 LEGACY_TX_SUBSCRIPTION_FD=95 LEGACY_TX_SUBSCRIPTION_PATH=/tmp/forged-subscription \
    LEGACY_TX_FIREWALL_DEPTH=9 LEGACY_TX_FIREWALL_FD=96 LEGACY_TX_FIREWALL_PATH=/tmp/forged-firewall \
    SING_BOX_TRANSACTION_ROOT="$SING_BOX_TRANSACTION_ROOT" \
    SUBSCRIPTION_LOCK_FILE="$entry_dir/absent-legacy.lock" \
    SUBSCRIPTION_LOCK_TIMEOUT_SECONDS=0 \
    URL_FILE="$entry_url" RESULT_FILE="$entry_dir/missing-result.txt" \
    SUB_FILE="$entry_dir/cfy-sub.txt" COMBINED_URL_FILE="$entry_dir/all-url.txt" \
    COMBINED_SUB_FILE="$entry_dir/all-sub.txt" SERVED_SUB_FILE="$entry_dir/sub.txt" \
    CFY_SOURCE_GENERATION_FILE="$entry_dir/source.generation" RESULT_DIR="$entry_dir/results" \
    bash "$entry_script" -c > "$entry_dir/output" 2>&1
polluted_entry_status=$?
set -e
wait "$entry_holder_pid"
[[ "$polluted_entry_status" -eq 1 ]] ||
    fail "polluted real cfy entry returned $polluted_entry_status, expected stable contention rc=1"
if grep -Fq 'vless://' "$entry_dir/output"; then
    fail 'polluted real cfy entry executed the template callback without the stable lock'
fi

# Verify real, bidirectional process serialization against the adjacent
# Sing-box implementation when the integration worktree is present.
sb_script="${SING_BOX_REFERENCE_SCRIPT:-${repo_root}/../sing-box-integration/sing-box.sh}"
if [[ -f "$sb_script" ]]; then
    sb_bundle="$tmp_root/sb-lock-functions.sh"
    : > "$sb_bundle"
    for function_name in "${transaction_functions[@]:0:28}"; do
        [[ "$function_name" == with_subscription_lock ]] && continue
        sed -n "/^${function_name}() {/,/^}/p" "$sb_script" >> "$sb_bundle"
    done
    grep -q '^acquire_stable_transaction_lock()' "$sb_bundle" || fail 'Sing-box lock bundle missing'
    ready="$tmp_root/holder.ready"

    bash -c 'source "$1"; SING_BOX_TRANSACTION_ROOT="$2"; reset_stable_transaction_lock_state; acquire_stable_transaction_lock subscription 2; : > "$3"; sleep 0.5; release_stable_transaction_lock subscription' _ "$sb_bundle" "$SING_BOX_TRANSACTION_ROOT" "$ready" &
    sb_holder=$!
    for _ in {1..100}; do [[ -e "$ready" ]] && break; sleep 0.01; done
    [[ -e "$ready" ]] || fail 'Sing-box holder did not start'
    set +e
    acquire_stable_transaction_lock subscription 0
    cross_status=$?
    set -e
    wait "$sb_holder"
    [[ "$cross_status" -eq 1 ]] || fail "cfy did not contend with Sing-box holder: $cross_status"

    rm -f "$ready"
    (
        reset_stable_transaction_lock_state
        acquire_stable_transaction_lock subscription 2
        : > "$ready"
        sleep 0.5
        release_stable_transaction_lock subscription
    ) & cfy_holder=$!
    for _ in {1..100}; do [[ -e "$ready" ]] && break; sleep 0.01; done
    [[ -e "$ready" ]] || fail 'cfy holder did not start'
    set +e
    bash -c 'source "$1"; SING_BOX_TRANSACTION_ROOT="$2"; reset_stable_transaction_lock_state; acquire_stable_transaction_lock subscription 0' _ "$sb_bundle" "$SING_BOX_TRANSACTION_ROOT"
    cross_status=$?
    set -e
    wait "$cfy_holder"
    [[ "$cross_status" -eq 1 ]] || fail "Sing-box did not contend with cfy holder: $cross_status"
else
    printf 'SKIP: adjacent Sing-box worktree is unavailable; cross-project flock test not run.\n'
fi

printf 'cfy stable transaction root tests passed.\n'
