# Combined Subscription Deduplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove exact duplicate links from the combined cfy subscription while preserving first-occurrence order and every node connection field.

**Architecture:** Keep `sync_combined_subscription` as the single publishing boundary. Replace its two raw `sed` appends with one ordered loop over the base and cfy result files, using a local Bash associative array keyed by the complete link text after removing a trailing CR.

**Tech Stack:** Bash, PowerShell repository checks, GitHub Actions

---

### Task 1: Create a recovery checkpoint

**Files:**
- Backup: `../docs/backups/pre-cfy-combined-dedup-<timestamp>/Pre-cfy.bundle`
- Backup: `../docs/backups/pre-cfy-combined-dedup-<timestamp>/Pre-cfy-head.zip`

- [ ] **Step 1: Verify the repository is clean**

Run:

```powershell
git status --short
```

Expected: no output.

- [ ] **Step 2: Create and verify the bundle and source ZIP**

Run `git bundle create`, `git archive`, `git bundle verify`, and `Get-FileHash` against the timestamped backup directory. Expected: the bundle records complete history and both files have SHA-256 hashes.

### Task 2: Add the failing combined-subscription test

**Files:**
- Create: `tests/test_subscription_dedup.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

source <(extract_function sync_combined_subscription)

fixture_dir="$(mktemp -d)"
trap 'rm -rf "${fixture_dir}"' EXIT

URL_FILE="${fixture_dir}/url.txt"
RESULT_FILE="${fixture_dir}/cfy-url.txt"
COMBINED_URL_FILE="${fixture_dir}/all-url.txt"
COMBINED_SUB_FILE="${fixture_dir}/all-sub.txt"
SERVED_SUB_FILE="${fixture_dir}/sub.txt"

write_base64_file() { return 0; }

printf '%s\n' \
    'vless://base-a' \
    'vless://shared' \
    '' \
    'vless://same-fields#remark-one' > "${URL_FILE}"

printf '%s\r\n' \
    'vless://shared' \
    'vless://result-b' \
    'vless://same-fields#remark-two' \
    'vless://result-b' > "${RESULT_FILE}"

sync_combined_subscription

expected=$'vless://base-a\nvless://shared\nvless://same-fields#remark-one\nvless://result-b\nvless://same-fields#remark-two'
actual="$(cat "${COMBINED_URL_FILE}")"

if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL: combined subscription was not deduplicated in first-occurrence order\nExpected:\n%s\nActual:\n%s\n' "${expected}" "${actual}" >&2
    exit 1
fi

echo 'Combined subscription deduplication tests passed.'
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash tests/test_subscription_dedup.sh
```

Expected: FAIL because the current `sync_combined_subscription` publishes `vless://shared` and `vless://result-b` more than once.

### Task 3: Implement exact ordered link deduplication

**Files:**
- Modify: `cfy.sh:309-329`
- Test: `tests/test_subscription_dedup.sh`

- [ ] **Step 1: Replace raw concatenation with the minimal ordered collector**

```bash
sync_combined_subscription() {
    local tmp_file combined_dir source_file line
    declare -A seen_urls=()

    combined_dir=$(dirname "$COMBINED_URL_FILE")
    mkdir -p "$combined_dir" "$(dirname "$COMBINED_SUB_FILE")" "$(dirname "$SERVED_SUB_FILE")" || return 1
    tmp_file=$(mktemp "${combined_dir}/.tmp.$(basename "$COMBINED_URL_FILE").XXXXXX") || return 1

    for source_file in "$URL_FILE" "$RESULT_FILE"; do
        [ -s "$source_file" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            [ -n "${line//[[:space:]]/}" ] || continue
            if [[ -n "${seen_urls[$line]+x}" ]]; then
                continue
            fi
            seen_urls["$line"]=1
            printf '%s\n' "$line" >> "$tmp_file"
        done < "$source_file"
    done

    if [ -s "$tmp_file" ]; then
        chmod 644 "$tmp_file" 2>/dev/null || true
        mv -f "$tmp_file" "$COMBINED_URL_FILE" || { rm -f "$tmp_file"; return 1; }
        write_base64_file "$COMBINED_URL_FILE" "$COMBINED_SUB_FILE" || return 1
        write_base64_file "$COMBINED_URL_FILE" "$SERVED_SUB_FILE" || return 1
    else
        rm -f "$tmp_file"
    fi
}
```

- [ ] **Step 2: Run the focused test and verify GREEN**

Run:

```bash
bash tests/test_subscription_dedup.sh
```

Expected: `Combined subscription deduplication tests passed.`

### Task 4: Publish the regression contract

**Files:**
- Modify: `.github/workflows/verify-scripts.yml`
- Modify: `README.md`

- [ ] **Step 1: Add the focused test to GitHub Actions**

Add after the candidate-selection test:

```yaml
      - name: Verify combined subscription deduplication
        shell: bash
        run: bash tests/test_subscription_dedup.sh
```

- [ ] **Step 2: Document exact-link behavior**

Add to the synchronization section of `README.md`:

```markdown
* 合并基础节点与 cfy 优选节点时，会按首次出现顺序移除完全相同的链接；不同备注或不同连接字段的节点不会被合并。
```

### Task 5: Verify, commit, push, and check CI

**Files:**
- Modify: `../tests/test_protocol_templates.ps1`
- Verify: `cfy.sh`
- Verify: `tests/test_candidate_selection.sh`
- Verify: `tests/test_subscription_dedup.sh`

- [ ] **Step 1: Update the root static contract**

Require `declare -A seen_urls=()` and reject the old direct `sed ... >> "$tmp_file"` concatenation in the root protocol test.

- [ ] **Step 2: Run all local verification**

Run Bash syntax checks, both focused Bash tests, the root PowerShell protocol test, workflow YAML parsing, `git diff --check`, and the normalized `update_vless_url` hash comparison. Expected: every command exits 0 and the URL renderer hash matches the pre-change commit.

- [ ] **Step 3: Commit the implementation**

```bash
git add cfy.sh README.md .github/workflows/verify-scripts.yml tests/test_subscription_dedup.sh docs/superpowers/plans/2026-07-12-combined-subscription-dedup.md
git commit -m "Deduplicate combined subscription links"
```

- [ ] **Step 4: Push and verify GitHub Actions**

Push `main`, then query `verify-scripts.yml` for the new commit. Expected: `status=completed` and `conclusion=success`.
