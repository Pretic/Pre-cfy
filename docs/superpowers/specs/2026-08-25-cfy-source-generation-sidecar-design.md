# cfy Source Generation Sidecar Design

## Goal

Bind every published `cfy-url.txt` generation to the exact `url.txt` bytes used to create it, so Sing-box never serves stale optimized nodes after the base subscription changes.

## Required baseline

This design depends on commit `a7e6404`, which provides the canonical `/etc/sing-box/.subscription.lock`, locked source reads, generation drift checks, same-directory staging, and rollback-capable multi-file publication. The public `main` branch does not yet provide that boundary, so the sidecar must not be merged without this prerequisite.

## Contract

- `CFY_SOURCE_GENERATION_FILE` defaults to `/etc/sing-box/cfy-source.generation`.
- The file contains one canonical line: `<lowercase sha256(url.txt)>:<byte count>`.
- It is a regular, non-symlink file with mode `0600`.
- A new `cfy-url.txt` and its sidecar are staged and committed under the same subscription lock and in the same rollback transaction as all derived subscription files.
- A normal combined-subscription refresh includes an existing `cfy-url.txt` only when the sidecar is trustworthy and matches the current base generation. Missing, malformed, stale, wrong-mode, or symlink sidecars degrade to base-only publication without changing either cfy-owned file.
- A long-running optimization whose recorded source generation no longer matches `url.txt` fails before publication and leaves the previous complete generation visible.
- `cfy -c` may still show the retained historical result; only public/combined outputs exclude an untrusted or stale generation.

## Data flow

1. `load_source_urls` reads `url.txt` while holding `.subscription.lock` and records its generation token.
2. Candidate generation runs without holding the lock.
3. `save_generated_urls` reacquires the lock and verifies the recorded token.
4. The result, sidecar, Base64 files, combined cleartext, and served subscription are fully staged.
5. A second generation check runs immediately before commit.
6. The existing rollback transaction renames all staged files or restores the previous generation.

## Safety and portability

The feature changes only local subscription files. It is independent of public ports, NAT, and IPv4/IPv6 availability. It requires the same `flock`, `sha256sum`, and regular-file checks already established by `a7e6404`; no network or host routing changes are involved.

## Tests

Offline tests cover trusted matching publication; missing, malformed, stale, wrong-mode, and symlink sidecars; `0600` mode; generation drift; staging failure; commit rollback; and preservation of cfy-owned files during base-only publication.
