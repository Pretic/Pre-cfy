# cfy Candidate Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve third-party candidate order, remove duplicate IPs, and retain the existing IPv4-default family selector.

**Architecture:** Keep download, parsing, and node rendering unchanged. Add one pure candidate-collection function between parsing and rendering, then cover it with a Bash fixture test.

**Tech Stack:** Bash, PowerShell repository checks, GitHub Actions

---

### Task 1: Add failing candidate behavior tests

**Files:**
- Create: `tests/test_candidate_selection.sh`

- [ ] Add a fixture containing ordered and duplicate IP/ISP pairs.
- [ ] Assert that `collect_unique_optimized_pairs` exists and returns first-occurrence order.
- [ ] Assert Enter, `2`, and `3` select IPv4, dual stack, and IPv6.
- [ ] Run `bash tests/test_candidate_selection.sh` and verify it fails because the collector does not exist.

### Task 2: Implement ordered deduplication

**Files:**
- Modify: `cfy.sh`

- [ ] Add `collect_unique_optimized_pairs` using a local associative `seen_edges` array.
- [ ] Replace `shuf` and the existing pair loop with the collector call.
- [ ] Run `bash tests/test_candidate_selection.sh` and verify it passes.

### Task 3: Publish and verify the contract

**Files:**
- Modify: `README.md`
- Modify: `.github/workflows/verify-scripts.yml`

- [ ] Document IPv4 as the Enter default, ordered candidates, and first-occurrence deduplication.
- [ ] Run the candidate test in GitHub Actions after Bash syntax validation.
- [ ] Run `tests/test_candidate_selection.sh`, the root protocol template test, and Bash syntax checks.
- [ ] Confirm no node URL rendering or tunnel configuration files changed.
- [ ] Commit, push `main`, and verify GitHub Actions succeeds.
