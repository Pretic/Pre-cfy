# cfy Source Generation Sidecar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Atomically bind optimized cfy results to the exact base subscription generation and hide stale results from combined/public output.

**Architecture:** Extend the `a7e6404` locked multi-file publisher. Validate an existing sidecar before admitting `cfy-url.txt`, and stage a fresh result plus sidecar as two cfy-owned targets in the same rollback transaction.

**Tech Stack:** Bash, util-linux `flock`, GNU `sha256sum`, coreutils, offline shell tests.

---

### Task 1: Specify stale-result admission and atomic sidecar publication

**Files:**
- Modify: `tests/test_subscription_contract.sh`
- Modify: `tests/test_subscription_dedup.sh`
- Modify: `tests/test_secure_output_permissions.sh`

- [ ] Add test fixtures for `CFY_SOURCE_GENERATION_FILE` and load the new sidecar reader/selector functions.
- [ ] Assert missing, malformed, stale, wrong-mode, and symlink sidecars produce base-only combined/public outputs while preserving cfy-owned files.
- [ ] Assert a matching sidecar admits cfy results, and a successful fresh result writes the canonical generation with mode `0600`.
- [ ] Inject staging and commit failures and assert neither the prior result nor its prior sidecar is exposed or partially replaced.
- [ ] Run `bash tests/test_subscription_contract.sh` and verify the new assertions fail because sidecar support is absent.

### Task 2: Implement the minimal sidecar contract

**Files:**
- Modify: `cfy.sh`

- [ ] Add `CFY_SOURCE_GENERATION_FILE="${CFY_SOURCE_GENERATION_FILE:-/etc/sing-box/cfy-source.generation}"`.
- [ ] Add a strict reader that accepts only a regular non-symlink `0600` file matching `^[0-9a-f]{64}:[0-9]+$`.
- [ ] Add a lock-only selector that returns `RESULT_FILE` only when the strict sidecar equals the current `url.txt` generation; otherwise return `/dev/null`.
- [ ] Extend `publish_subscriptions_locked` so fresh publications stage the sidecar beside `cfy-url.txt`, generate all derived files from the staged result, and include both cfy-owned targets in the existing backup/commit/rollback arrays.
- [ ] Keep base-only refresh fail-safe: untrusted sidecars do not fail publication and are never repaired or rewritten by Sing-box-style refreshes.
- [ ] Run the focused tests and verify all sidecar assertions pass.

### Task 3: Document and verify the interoperability contract

**Files:**
- Modify: `README.md`

- [ ] Document the sidecar path, format, mode, stale-result behavior, and `a7e6404` dependency.
- [ ] Run `bash -n cfy.sh tests/*.sh`.
- [ ] Run ShellCheck at the repository's enforced error severity.
- [ ] Run every offline test under `tests/` and confirm zero failures.
- [ ] Review the staged diff, commit only intended files, and record both the prerequisite and sidecar commit hashes.
