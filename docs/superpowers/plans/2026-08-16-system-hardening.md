# Pre-cfy System Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cfy repeatable, quality-first and transaction-safe while preserving its lightweight on-demand operation and Sing-box-Pre compatibility.

**Architecture:** Keep one portable Bash script, but separate installation, input selection, candidate validation, health probing and publication into testable functions. Publish through the same lock and permission contract as Sing-box; no new daemon or runtime proxy layer is introduced.

**Tech Stack:** Bash, jq, curl, base64, flock or mkdir-lock fallback, shell regression tests.

---

## File map

- Modify: `cfy.sh` — installer, validation, selection, probing, publication and cleanup.
- Modify: `README.md` — quality defaults, source priority, lock/permissions and environment limits.
- Create: `tests/test_install_update_atomic.sh` — process-substitution install, syntax validation and rollback.
- Create: `tests/test_source_priority.sh` — base-first and fallback-only template selection.
- Create: `tests/test_edge_validation.sh` — strict host, IPv4, IPv6 and port validation.
- Modify: `tests/test_edge_health_probe.sh` — default one-pass quality behavior and systemic failure.
- Create: `tests/test_publish_transaction.sh` — shared lock, concurrent publish and permissions.
- Create: `tests/test_cleanup_and_history.sh` — signal cleanup, numeric clamping and rotation.

### Task 1: Atomic self-install/update without a second download

**Files:**
- Modify: `cfy.sh` installation block, `install_from_remote`, `update_self`.
- Create: `tests/test_install_update_atomic.sh`.

- [ ] **Step 1: Write the failing installer test**

Run a readable fixture through a simulated `/dev/fd/*` path, mock curl to count calls, and assert installation copies the executing bytes without invoking curl. Feed a downloaded script with a syntax error to update and assert the existing installed SHA-256 is unchanged. Assert the installed mode is 755 and `sub.txt` content is untouched.

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test_install_update_atomic.sh
```

Expected: failure because process substitution currently downloads Raw main again or syntax-invalid content can replace the installed script.

- [ ] **Step 3: Implement one atomic installer primitive**

Add:

```bash
validate_cfy_script() {
    local candidate="$1"
    [ -s "$candidate" ] && bash -n "$candidate" &&
        grep -q '^INSTALL_PATH="/usr/local/bin/cfy"' "$candidate"
}

install_validated_script() {
    local candidate="$1" target="${2:-$INSTALL_PATH}" target_dir tmp
    target_dir=$(dirname "$target")
    tmp=$(mktemp "${target_dir}/.cfy.install.XXXXXX") || return 1
    cp "$candidate" "$tmp" && validate_cfy_script "$tmp" && chmod 755 "$tmp" &&
        mv -f "$tmp" "$target"
}
```

If `$0` is readable, copy it to a temporary candidate and validate it. Only stdin execution without readable bytes may call `install_from_remote`. Use the same primitive for `--update`; preserve the old target on any failure.

- [ ] **Step 4: Verify Task 1**

```bash
bash tests/test_install_update_atomic.sh
bash -n cfy.sh
```

Expected: both exit 0.

- [ ] **Step 5: Commit Task 1**

```bash
git add cfy.sh tests/test_install_update_atomic.sh
git commit -m "fix: install and update cfy atomically"
```

### Task 2: Strict edge validation and bounded numeric settings

**Files:**
- Modify: `cfy.sh` configuration initialization, `is_valid_edge_address`, port parsing and health settings.
- Create: `tests/test_edge_validation.sh`.

- [ ] **Step 1: Write the failing validation matrix**

Assert valid: `104.17.0.1`, `104.17.0.1:443`, `[2606:4700::1111]:443`, `edge.example.com:8443`. Assert invalid: `999.1.1.1`, `1.2.3.4:0`, `1.2.3.4:65536`, `[2606:4700:::1]`, `edge..example.com`, `-edge.example.com`, `edge.example.com:`.

Set `CFY_HEALTH_PROBE_ATTEMPTS=999999`, `CFY_HEALTH_MAX_TIME=-1`, `CFY_HISTORY_LIMIT=text`; assert normalization returns attempts 1–5, timeout 1–30 seconds, and history 1–100.

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test_edge_validation.sh
```

Expected: current regex accepts invalid IPv4 octets or ports.

- [ ] **Step 3: Implement strict validators**

Split host and optional port before validation. Validate IPv4 octets arithmetically, IPv6 with `python3 ipaddress` when available and a conservative hextet parser fallback, domains label-by-label, and ports with the 1–65535 rule.

Add:

```bash
clamp_uint() {
    local value="$1" default="$2" minimum="$3" maximum="$4"
    [[ "$value" =~ ^[0-9]+$ ]] || value="$default"
    [ "$value" -lt "$minimum" ] && value="$minimum"
    [ "$value" -gt "$maximum" ] && value="$maximum"
    printf '%s\n' "$value"
}
```

Normalize all attempts, limits and timeouts once before main execution.

- [ ] **Step 4: Verify Task 2 and existing selection tests**

```bash
bash tests/test_edge_validation.sh
bash tests/test_candidate_selection.sh
bash tests/test_candidate_default_limit.sh
```

Expected: all pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add cfy.sh tests/test_edge_validation.sh
git commit -m "fix: validate cfy candidates and numeric limits"
```

### Task 3: Base-first template source selection

**Files:**
- Modify: `cfy.sh` `load_source_urls`, template selection and source hints.
- Create: `tests/test_source_priority.sh`.

- [ ] **Step 1: Write failing source-priority tests**

Create `url.txt` with one valid VLESS-WS-TLS-Argo template and `cfy-url.txt/all-url.txt/sub.txt` with old optimized templates. Assert only the base template is returned. Then replace `url.txt` with Reality-only content and assert the deduplicated fallback templates are returned in `all-url`, `cfy-url`, then `sub.txt` order.

Change the base UUID/domain and rerun; assert no old optimized node appears in the selectable template list.

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test_source_priority.sh
```

Expected: failure because current `load_source_urls` always aggregates every source.

- [ ] **Step 3: Implement two-phase loading**

Implement `load_primary_templates` that reads only `URL_FILE` and returns success only when it contains an eligible VLESS/VMess template. Implement `load_fallback_templates` for `COMBINED_URL_FILE`, `RESULT_FILE`, and Base64 `SERVED_SUB_FILE`. `load_source_urls` must clear `urls`, call primary, and call fallback only on failure.

Hints must state whether primary or fallback was used; do not print full node URLs in diagnostic errors.

- [ ] **Step 4: Verify Task 3**

```bash
bash tests/test_source_priority.sh
bash tests/test_subscription_dedup.sh
```

Expected: both pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add cfy.sh tests/test_source_priority.sh
git commit -m "fix: avoid reusing old optimized templates"
```

### Task 4: Quality-first bounded health probing and stack selection

**Files:**
- Modify: `cfy.sh` defaults, `choose_ip_version_scope`, `get_all_optimized_ips`, `probe_vless_edge_candidate` and generation loop.
- Modify: `tests/test_edge_health_probe.sh`.
- Modify: `tests/test_ip_scope_detection.sh`.

- [ ] **Step 1: Extend health and stack tests**

Assert defaults are `CFY_HEALTH_PROBE=1`, attempts 1 and minimum success 1. Mock one candidate returning HTTP 400 and one timeout; only the first is generated. Mock all candidates failing while the origin control request also fails; assert a distinct “无法执行可靠健康检查” error and no new publication.

Assert IPv4-only selects up to 5 per operator, IPv6-only selects up to 5, dual selects up to 3 per operator/family with every IPv4 entry before IPv6, and sparse healthy data is not padded.

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test_edge_health_probe.sh
bash tests/test_ip_scope_detection.sh
```

Expected: failure because health probing defaults off or systemic failure is indistinguishable.

- [ ] **Step 3: Implement bounded probing**

Set default probe/attempt/minimum to `1/1/1`. Before candidate probes, make one short control request through the original host; if it cannot establish the baseline, return a dedicated detection-failed status and preserve old results. Probe only ranked candidates already selected by operator/family/RTT. A failed candidate is skipped; never add lower-quality placeholders solely to reach the quota.

Keep probe concurrency at one for deterministic low resource use. Do not download a speed-test body; retain the WS/TLS HTTP status probe only.

- [ ] **Step 4: Verify Task 4**

```bash
bash tests/test_edge_health_probe.sh
bash tests/test_ip_scope_detection.sh
bash tests/test_candidate_selection.sh
bash tests/test_candidate_default_limit.sh
```

Expected: all pass.

- [ ] **Step 5: Commit Task 4**

```bash
git add cfy.sh tests/test_edge_health_probe.sh tests/test_ip_scope_detection.sh
git commit -m "fix: prefer verified Cloudflare edge candidates"
```

### Task 5: Shared locked publication with full rollback

**Files:**
- Modify: `cfy.sh` `atomic_write_file`, `sync_combined_subscription`, `save_generated_urls`.
- Create: `tests/test_publish_transaction.sh`.

- [ ] **Step 1: Write failing publication tests**

Run two publishers concurrently with different fixture generations. Assert each final file decodes to the same complete generation, contains no duplicates, and has modes `all-url=600`, `all-sub=600`, `sub=644`. Inject failure before each rename and assert the three old files remain byte-for-byte intact.

Assert the lock path equals `/etc/sing-box/.subscription.lock`, matching the Sing-box contract test. Assert an empty cfy result preserves valid base subscription content.

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test_publish_transaction.sh
```

Expected: failure due no shared lock or cross-file partial publication.

- [ ] **Step 3: Implement lock plus staged generation**

Add `with_subscription_lock` with `flock -x` and a bounded mkdir-lock fallback. Under the lock, create a staging directory inside `/etc/sing-box`, deduplicate `URL_FILE` plus `RESULT_FILE` into staged `all-url.txt`, generate both Base64 files from it, apply modes, then rename all three. On any error delete staging and leave old production files intact.

Write cfy-owned `RESULT_FILE` and `SUB_FILE` as 600 before entering publication. Always release the lock through the common cleanup trap.

- [ ] **Step 4: Verify publication and permissions**

```bash
bash tests/test_publish_transaction.sh
bash tests/test_secure_output_permissions.sh
bash tests/test_subscription_dedup.sh
```

Expected: all pass.

- [ ] **Step 5: Commit Task 5**

```bash
git add cfy.sh tests/test_publish_transaction.sh
git commit -m "fix: publish cfy subscriptions transactionally"
```

### Task 6: Signal cleanup, bounded history and final documentation

**Files:**
- Modify: `cfy.sh` temporary-file lifecycle and history creation.
- Create: `tests/test_cleanup_and_history.sh`.
- Modify: `README.md`.
- Modify: `.github/workflows/test.yml` if necessary.

- [ ] **Step 1: Write failing cleanup/history tests**

Register three temporary files, send INT and TERM to the fixture process, and assert files are removed and exit codes are 130/143. Pre-create 25 history files with `CFY_HISTORY_LIMIT=20`, save a new result, and assert only the newest 20 remain. Assert a publish lock is released on signal.

Add README grep assertions for base-first source priority, default health probe, 3+3/5 count rules, shared lock, permission contract and non-resident resource cost.

- [ ] **Step 2: Run and verify RED**

```bash
bash tests/test_cleanup_and_history.sh
```

Expected: failure because no unified signal cleanup or history cap exists.

- [ ] **Step 3: Implement cleanup registry and rotation**

Maintain a Bash array of owned temporary paths. `cleanup_cfy_resources` removes only paths in that array and releases the mkdir lock if owned. Install EXIT, INT and TERM handlers without replacing a transaction-specific rollback handler; INT/TERM call cleanup then exit 130/143.

After a successful history copy, sort history files newest-first and delete entries after the normalized limit. Never remove non-matching files from `RESULT_DIR`.

Update README with the exact environment defaults, disabling health probe, stack/count behavior, fallback semantics, file ownership and no-runtime-overhead statement. Ensure CI runs every `tests/test_*.sh` file on Linux with jq/curl/base64.

- [ ] **Step 4: Run fresh full verification**

```bash
bash -n cfy.sh
git diff --check
for test_file in tests/test_*.sh; do echo "RUN $test_file"; bash "$test_file" || exit 1; done
```

Expected: syntax and diff checks exit 0 and every test passes.

- [ ] **Step 5: Commit Task 6**

```bash
git add cfy.sh README.md .github/workflows tests
git commit -m "fix: clean cfy state and bound result history"
```
