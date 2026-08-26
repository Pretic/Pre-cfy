#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/cfy.sh"
tmp_root="$(mktemp -d)"
original_path="$PATH"
real_flock="$(type -P flock 2>/dev/null || true)"
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

for function_name in \
    command_exists \
    transaction_root_path \
    transaction_expected_dir_mode \
    transaction_expected_file_mode \
    transaction_expected_gid \
    validate_transaction_path_components \
    validate_transaction_directory \
    ensure_transaction_directory \
    validate_transaction_regular_file \
    ensure_transaction_regular_file \
    write_transaction_schema_file \
    ensure_stable_transaction_root \
    stable_transaction_lock_path \
    stable_transaction_lock_rank \
    stable_transaction_lock_is_held \
    stable_transaction_highest_rank \
    stable_transaction_lock_hook \
    legacy_transaction_lock_hook \
    reset_stable_transaction_lock_state \
    acquire_stable_transaction_lock \
    release_stable_transaction_lock \
    with_stable_transaction_lock \
    validate_safe_legacy_lock \
    acquire_safe_legacy_lock \
    release_safe_legacy_lock \
    acquire_transaction_lock_with_legacy \
    release_transaction_lock_with_legacy \
    with_transaction_lock_with_legacy \
    atomic_write_file \
    write_text_file \
    with_subscription_lock \
    get_subscription_source_generation \
    read_strict_subscription_generation_file \
    read_cfy_source_generation_file \
    select_existing_cfy_subscription_source_locked \
    verify_subscription_source_generation_locked \
    encode_subscription_source \
    publish_subscriptions_locked \
    sync_combined_subscription \
    save_generated_urls_locked \
    save_generated_urls \
    finalize_generated_urls \
    normalize_url_candidate \
    add_url_candidate \
    load_urls_from_file \
    load_source_urls_locked \
    load_source_urls \
    main; do
    load_function "$function_name"
done

fixture_dir="${tmp_root}/sing-box"
mkdir -p "$fixture_dir"
URL_FILE="${fixture_dir}/url.txt"
RESULT_FILE="${fixture_dir}/cfy-url.txt"
SUB_FILE="${fixture_dir}/cfy-sub.txt"
COMBINED_URL_FILE="${fixture_dir}/all-url.txt"
COMBINED_SUB_FILE="${fixture_dir}/all-sub.txt"
SERVED_SUB_FILE="${fixture_dir}/sub.txt"
SUBSCRIPTION_LOCK_FILE="${fixture_dir}/.subscription.lock"
SING_BOX_TRANSACTION_ROOT="${tmp_root}/transactions"
unset SING_BOX_TRANSACTION_GROUP
CFY_SOURCE_GENERATION_FILE="${fixture_dir}/cfy-source.generation"
BASE_SUB_FILE="${fixture_dir}/base-sub.txt"

: > "$SUBSCRIPTION_LOCK_FILE"
chmod 600 "$SUBSCRIPTION_LOCK_FILE"

printf '%s\n' \
    'vless://base-a' \
    'vless://shared' \
    'vless://same-fields#one' > "$URL_FILE"
printf '%s\r\n' \
    'vless://shared' \
    'vless://cfy-b' \
    'vless://same-fields#two' \
    'vless://cfy-b' > "$RESULT_FILE"
initial_generation="$(get_subscription_source_generation "$URL_FILE")"
printf '%s\n' "$initial_generation" > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"

flock() { return 0; }
sync_combined_subscription || fail 'cfy subscription publication failed'
load_source_urls || fail 'cfy could not record the initial template generation'

expected=$'vless://base-a\nvless://shared\nvless://same-fields#one\nvless://cfy-b\nvless://same-fields#two'
actual="$(cat "$COMBINED_URL_FILE")"
[[ "$actual" == "$expected" ]] || fail 'combined URLs were not deduplicated in first-seen order'
cmp -s "$COMBINED_URL_FILE" <(base64 -d "$COMBINED_SUB_FILE") || \
    fail 'all-sub.txt was not generated from all-url.txt'
cmp -s "$COMBINED_URL_FILE" <(base64 -d "$SERVED_SUB_FILE") || \
    fail 'served sub.txt was not generated from all-url.txt'

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
        for internal in "$URL_FILE" "$RESULT_FILE" "$CFY_SOURCE_GENERATION_FILE" "$SUB_FILE" "$COMBINED_URL_FILE" "$COMBINED_SUB_FILE"; do
            [[ "$(stat -c '%a' "$internal")" == 600 ]] || fail "$(basename "$internal") is not mode 600"
        done
        [[ "$(stat -c '%a' "$SERVED_SUB_FILE")" == 644 ]] || fail 'sub.txt is not mode 644'
        [[ "$(stat -c '%a' "$SUBSCRIPTION_LOCK_FILE")" == 600 ]] || \
            fail 'subscription lock is not mode 600'
        ;;
esac

assert_cfy_sync_base_only() {
    local expected_base="$1"
    local old_result_checksum="$2"
    local old_sidecar_checksum="${3:-}"

    [[ "$(cat "$COMBINED_URL_FILE")" == "$expected_base" ]] || \
        fail 'untrusted existing cfy data leaked into all-url.txt'
    [[ "$(base64 -d "$SERVED_SUB_FILE")" == "$expected_base" ]] || \
        fail 'untrusted existing cfy data leaked into the served subscription'
    [[ "$(cksum < "$RESULT_FILE")" == "$old_result_checksum" ]] || \
        fail 'base-only publication changed the retained cfy result'
    if [[ -n "$old_sidecar_checksum" ]]; then
        [[ "$(cksum < "$CFY_SOURCE_GENERATION_FILE")" == "$old_sidecar_checksum" ]] || \
            fail 'base-only publication changed the retained cfy sidecar'
    fi
}

base_only_expected=$'vless://base-a\nvless://shared\nvless://same-fields#one'
retained_result_checksum="$(cksum < "$RESULT_FILE")"

rm -f "$CFY_SOURCE_GENERATION_FILE"
sync_combined_subscription || fail 'missing cfy sidecar did not degrade to base-only publication'
assert_cfy_sync_base_only "$base_only_expected" "$retained_result_checksum"

printf '%s\n' 'malformed-generation' > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"
malformed_sidecar_checksum="$(cksum < "$CFY_SOURCE_GENERATION_FILE")"
sync_combined_subscription || fail 'malformed cfy sidecar did not degrade to base-only publication'
assert_cfy_sync_base_only "$base_only_expected" "$retained_result_checksum" "$malformed_sidecar_checksum"

printf '%064d:%d\n' 0 1 > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"
stale_sidecar_checksum="$(cksum < "$CFY_SOURCE_GENERATION_FILE")"
sync_combined_subscription || fail 'stale cfy sidecar did not degrade to base-only publication'
assert_cfy_sync_base_only "$base_only_expected" "$retained_result_checksum" "$stale_sidecar_checksum"

printf '%s\n' "$initial_generation" > "$CFY_SOURCE_GENERATION_FILE"
chmod 644 "$CFY_SOURCE_GENERATION_FILE"
wrong_mode_checksum="$(cksum < "$CFY_SOURCE_GENERATION_FILE")"
sync_combined_subscription || fail 'wrong-mode cfy sidecar did not degrade to base-only publication'
assert_cfy_sync_base_only "$base_only_expected" "$retained_result_checksum" "$wrong_mode_checksum"
[[ "$(stat -c '%a' "$CFY_SOURCE_GENERATION_FILE")" == 644 ]] || \
    fail 'base-only publication rewrote the cfy-owned sidecar mode'

sidecar_target="${fixture_dir}/sidecar-target"
printf '%s\n' "$initial_generation" > "$sidecar_target"
chmod 600 "$sidecar_target"
rm -f "$CFY_SOURCE_GENERATION_FILE"
ln -s "$sidecar_target" "$CFY_SOURCE_GENERATION_FILE"
sync_combined_subscription || fail 'symlink cfy sidecar did not degrade to base-only publication'
assert_cfy_sync_base_only "$base_only_expected" "$retained_result_checksum"
[[ -L "$CFY_SOURCE_GENERATION_FILE" ]] || fail 'base-only publication replaced an untrusted sidecar symlink'

rm -f "$CFY_SOURCE_GENERATION_FILE"
printf '%s\n' "$initial_generation" > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"
sync_combined_subscription || fail 'matching cfy sidecar was rejected'
[[ "$(cat "$COMBINED_URL_FILE")" == "$expected" ]] || fail 'matching cfy result was not merged'

matching_sidecar_checksum="$(cksum < "$CFY_SOURCE_GENERATION_FILE")"
printf '%s\n' 'vless://base-after-mutation' > "$URL_FILE"
sync_combined_subscription || fail 'base mutation with stale cfy metadata did not publish safely'
assert_cfy_sync_base_only 'vless://base-after-mutation' "$retained_result_checksum" "$matching_sidecar_checksum"

printf '%s\n' \
    'vless://base-a' \
    'vless://shared' \
    'vless://same-fields#one' > "$URL_FILE"
printf '%s\n' "$initial_generation" > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"
sync_combined_subscription || fail 'could not restore the matching cfy fixture'

printf '%s\n' 'old-served-generation' > "$SERVED_SUB_FILE"
base64() { return 1; }
if sync_combined_subscription >/dev/null 2>&1; then
    fail 'publication succeeded after both base64 encoders failed'
fi
unset -f base64
[[ "$(cat "$SERVED_SUB_FILE")" == old-served-generation ]] || \
    fail 'a staging failure replaced the old served subscription'

printf '%s\n' 'vless://old-result' > "$RESULT_FILE"
printf '%s\n' 'old-served-generation' > "$SERVED_SUB_FILE"
printf '%s\n' "$initial_generation" > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"
old_sidecar_checksum="$(cksum < "$CFY_SOURCE_GENERATION_FILE")"
generated_urls=('vless://new-result')
RESULT_DIR="${tmp_root}/history"
GREEN=''
RED=''
NC=''
base64() { return 1; }
if save_generated_urls >/dev/null 2>&1; then
    fail 'cfy source publication succeeded after base64 failure'
fi
unset -f base64
[[ "$(cat "$RESULT_FILE")" == 'vless://old-result' ]] || \
    fail 'cfy committed its new source before the served generation was staged'
[[ "$(cat "$SERVED_SUB_FILE")" == old-served-generation ]] || \
    fail 'a cfy source staging failure replaced the old served generation'
[[ "$(cksum < "$CFY_SOURCE_GENERATION_FILE")" == "$old_sidecar_checksum" ]] || \
    fail 'a cfy staging failure replaced the old source generation sidecar'

load_source_urls || fail 'could not capture generation for successful sidecar publication'
generated_urls=('vless://fresh-cfy-result')
save_generated_urls || fail 'cfy could not publish a fresh result with its generation sidecar'
published_generation="$(get_subscription_source_generation "$URL_FILE")"
[[ "$(cat "$CFY_SOURCE_GENERATION_FILE")" == "$published_generation" ]] || \
    fail 'successful publication did not atomically record the canonical source generation'
[[ "$(stat -c '%a' "$CFY_SOURCE_GENERATION_FILE")" == 600 ]] || \
    fail 'successful publication did not secure its generation sidecar'
[[ "$(cat "$COMBINED_URL_FILE")" == $'vless://base-a\nvless://shared\nvless://same-fields#one\nvless://fresh-cfy-result' ]] || \
    fail 'fresh cfy result and sidecar did not publish as one generation'

transaction_targets=(
    "$RESULT_FILE"
    "$CFY_SOURCE_GENERATION_FILE"
    "$BASE_SUB_FILE"
    "$SUB_FILE"
    "$COMBINED_URL_FILE"
    "$COMBINED_SUB_FILE"
    "$SERVED_SUB_FILE"
)
for fail_index in "${!transaction_targets[@]}"; do
    snapshot_dir="${tmp_root}/snapshot-${fail_index}"
    mkdir -p "$snapshot_dir"
    for snapshot_index in "${!transaction_targets[@]}"; do
        cp -p -- "${transaction_targets[$snapshot_index]}" "${snapshot_dir}/${snapshot_index}"
    done
    load_source_urls || fail "could not capture source generation before commit failure ${fail_index}"
    generated_urls=("vless://commit-failure-${fail_index}")
    FAIL_TARGET="${transaction_targets[$fail_index]}"
    FAIL_TRIGGERED=0
    mv() {
        local source_arg="${@: -2:1}"
        local target_arg="${@: -1}"
        if [[ "$FAIL_TRIGGERED" -eq 0 && "$target_arg" == "$FAIL_TARGET" && \
              "$source_arg" == *'/.tmp.'* && "$source_arg" != *'.rollback.'* ]]; then
            FAIL_TRIGGERED=1
            return 1
        fi
        command mv "$@"
    }
    set +e
    save_generated_urls >/dev/null 2>&1
    commit_failure_status=$?
    set -e
    unset -f mv
    [[ "$commit_failure_status" -eq 1 ]] || \
        fail "commit failure ${fail_index} returned ${commit_failure_status}, expected rollback status 1"
    [[ "$FAIL_TRIGGERED" -eq 1 ]] || fail "commit failure ${fail_index} was not injected"
    for snapshot_index in "${!transaction_targets[@]}"; do
        cmp -s "${transaction_targets[$snapshot_index]}" "${snapshot_dir}/${snapshot_index}" || \
            fail "commit failure ${fail_index} did not roll back target ${snapshot_index}"
    done
done

printf '%s\n' 'vless://old-result-before-rollback' > "$RESULT_FILE"
generated_urls=('vless://rollback-test')
rollback_log="${tmp_root}/cfy-rollback.log"
mv() {
    local source_arg="${@: -2:1}"
    local target_arg="${@: -1}"
    if [[ "$target_arg" == "$COMBINED_SUB_FILE" && \
          "$source_arg" == "${fixture_dir}/.tmp.all-sub.txt."* ]]; then
        return 1
    fi
    if [[ "$target_arg" == "$RESULT_FILE" && \
          "$source_arg" == "${fixture_dir}/.tmp.cfy-url.txt.rollback."* ]]; then
        return 1
    fi
    command mv "$@"
}
set +e
# The failure-injection mock is declared later; the production definition was
# already loaded above, so this is not a call-before-definition at runtime.
# shellcheck disable=SC2218
save_generated_urls 2> "$rollback_log"
rollback_status=$?
set -e
unset -f mv
[[ "$rollback_status" -eq 2 ]] || \
    fail "rollback restoration failure returned ${rollback_status}, expected fatal status 2"
compgen -G "${fixture_dir}/.tmp.cfy-url.txt.rollback.*" >/dev/null || \
    fail 'rollback restoration failure deleted the unrecovered cfy backup'
grep -Fq 'rollback' "$rollback_log" || \
    fail 'rollback restoration failure did not report preserved cfy recovery material'

rm -f "$COMBINED_SUB_FILE"
mkdir "$COMBINED_SUB_FILE"
if sync_combined_subscription >/dev/null 2>&1; then
    fail 'publisher accepted a non-regular existing target'
fi
rmdir "$COMBINED_SUB_FILE"

rm -f "$SUBSCRIPTION_LOCK_FILE"
mkdir "$SUBSCRIPTION_LOCK_FILE"
if with_subscription_lock true >/dev/null 2>&1; then
    fail 'publisher accepted a non-regular existing lock path'
fi
rmdir "$SUBSCRIPTION_LOCK_FILE"

# Old cfy results and derived publications must never become future templates.
printf '%s\n' 'vless://base-template' > "$URL_FILE"
printf '%s\n' 'vless://old-result' > "$RESULT_FILE"
printf '%s\n' 'vless://derived-cleartext' > "$COMBINED_URL_FILE"
printf '%s' 'vless://derived-served' | base64 > "$SERVED_SUB_FILE"
load_source_urls
[[ "${#urls[@]}" -eq 1 && "${urls[0]}" == 'vless://base-template' ]] || \
    fail 'cfy fed an old result or a derived publication back into template selection'

FLOCK_ACQUIRE_CALLS=0
flock() {
    if [[ "${1:-}" == -x ]]; then
        FLOCK_ACQUIRE_CALLS=$((FLOCK_ACQUIRE_CALLS + 1))
    fi
    return 0
}
nested_subscription_callback() { with_subscription_lock true; }
with_subscription_lock nested_subscription_callback || fail 'nested lock callback failed'
[[ "$FLOCK_ACQUIRE_CALLS" -eq 1 ]] || fail 'a lock-held callback attempted to acquire the lock again'

unset -f flock
no_flock_path="${tmp_root}/no-flock"
mkdir -p "$no_flock_path"
PATH="$no_flock_path"
if with_subscription_lock true >/dev/null 2>&1; then
    fail 'the publisher did not fail closed when flock was unavailable'
fi
PATH="$original_path"

if [[ -n "$real_flock" ]]; then
    lock_log="${tmp_root}/lock.log"
    : > "$lock_log"
    subscription_probe() {
        printf 'start-%s\n' "$1" >> "$lock_log"
        sleep 0.2
        printf 'end-%s\n' "$1" >> "$lock_log"
    }
    with_subscription_lock subscription_probe one & first_pid=$!
    with_subscription_lock subscription_probe two & second_pid=$!
    wait "$first_pid"
    wait "$second_pid"
    lock_order="$(paste -sd, "$lock_log")"
    case "$lock_order" in
        start-one,end-one,start-two,end-two|start-two,end-two,start-one,end-one) ;;
        *) fail "concurrent publishers overlapped: ${lock_order}" ;;
    esac

    printf '%s\n' 'vless://old-reader-generation' > "$URL_FILE"
    reader_ready="${tmp_root}/reader.ready"
    reader_output="${tmp_root}/reader.out"
    slow_base_writer() {
        printf '%s\n' 'vless://new-reader-first' > "$URL_FILE"
        : > "$reader_ready"
        sleep 0.3
        printf '%s\n' 'vless://new-reader-second' >> "$URL_FILE"
    }
    load_and_dump_source_urls() {
        load_source_urls
        printf '%s\n' "${urls[@]}" > "$reader_output"
    }
    with_subscription_lock slow_base_writer & writer_pid=$!
    for _ in {1..100}; do
        [[ -e "$reader_ready" ]] && break
        sleep 0.01
    done
    [[ -e "$reader_ready" ]] || fail 'concurrent cfy reader fixture did not reach its staging point'
    load_and_dump_source_urls & reader_pid=$!
    wait "$writer_pid"
    wait "$reader_pid"
    [[ "$(cat "$reader_output")" == $'vless://new-reader-first\nvless://new-reader-second' ]] || \
        fail 'cfy template loading observed a half-written Sing-box base source'
else
    printf 'SKIP: util-linux flock is unavailable; real concurrency check requires Linux CI.\n'
fi

grep -Fq 'SUBSCRIPTION_LOCK_FILE="${SUBSCRIPTION_LOCK_FILE:-/etc/sing-box/.subscription.lock}"' "$script" || \
    fail 'cfy does not default to the canonical subscription lock'
deps_source="$(extract_function check_deps)"
grep -Fq 'flock' <<< "$deps_source" || fail 'cfy dependency preflight does not require flock'
grep -Fq 'util-linux' <<< "$deps_source" || fail 'cfy does not provide a Debian/Alpine util-linux hint'
grep -Fq 'sha256sum' <<< "$deps_source" || fail 'cfy dependency preflight does not require a reliable source fingerprint'

printf '%s\n' 'vless://generation-a' > "$URL_FILE"
printf '%s\n' 'vless://old-generated' > "$RESULT_FILE"
sync_combined_subscription || fail 'could not prepare the generation-drift fixture'
load_source_urls || fail 'could not record the generation-drift source token'
old_result_checksum="$(cksum < "$RESULT_FILE")"
old_drift_served_checksum="$(cksum < "$SERVED_SUB_FILE")"
old_drift_sidecar_checksum="$(cksum < "$CFY_SOURCE_GENERATION_FILE")"
replace_base_generation() { printf '%s\n' 'vless://generation-b' > "$URL_FILE"; }
with_subscription_lock replace_base_generation || fail 'could not simulate a concurrent Sing-box base update'
generated_urls=('vless://stale-generated-result')
set +e
drift_output="$(finalize_generated_urls 1 2>&1)"
drift_status=$?
set -e
[[ "$drift_status" -ne 0 ]] || fail 'cfy published results generated from an obsolete source generation'
[[ "$(cksum < "$RESULT_FILE")" == "$old_result_checksum" ]] || \
    fail 'source-generation drift replaced the previous cfy result'
[[ "$(cksum < "$SERVED_SUB_FILE")" == "$old_drift_served_checksum" ]] || \
    fail 'source-generation drift replaced the previous served subscription'
[[ "$(cksum < "$CFY_SOURCE_GENERATION_FILE")" == "$old_drift_sidecar_checksum" ]] || \
    fail 'source-generation drift replaced the previous cfy generation sidecar'
if grep -Fq '生成完毕' <<< "$drift_output"; then
    fail 'cfy printed final success after source-generation drift'
fi
grep -Fq '源已变化' <<< "$drift_output" || fail 'cfy did not explain the source-generation drift failure'

save_generated_urls() { return 37; }
GREEN=''
RED=''
NC=''
set +e
finalize_output="$(finalize_generated_urls 9 2>&1)"
finalize_status=$?
set -e
[[ "$finalize_status" -eq 37 ]] || \
    fail "main publication failure was masked as status ${finalize_status}"
if grep -Fq '生成完毕' <<< "$finalize_output"; then
    fail 'cfy printed the final success message after publication failed'
fi
grep -Fq '发布失败' <<< "$finalize_output" || \
    fail 'cfy did not clearly report a publication failure'
main_source="$(extract_function main)"
grep -Fq 'finalize_generated_urls "$num_to_generate" || return $?' <<< "$main_source" || \
    fail 'cfy main does not propagate final publication failure'

# Stable-lock initialization failures are contract failures (rc=2), not an
# ordinary missing-template result (rc=1).
eval 'load_source_urls() { return 2; }'
set +e
main >/dev/null 2>&1
main_lock_status=$?
set -e
[[ "$main_lock_status" -eq 2 ]] || \
    fail "cfy main folded an initial lock failure into status ${main_lock_status}"

printf 'cfy subscription contract tests passed.\n'
