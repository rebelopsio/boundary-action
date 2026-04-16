# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`boundary-action` is a GitHub **composite action** (not Docker, not JavaScript) that wraps the [`boundary`](https://github.com/rebelopsio/boundary) CLI tool for CI pipelines. It installs the `boundary` binary, runs `boundary check`, emits PR annotations for violations, writes a job summary, and exposes structured outputs.

The action is a **thin adapter** — all analytical intelligence lives in the `boundary` binary. This repo only handles: install, invoke, parse JSON output, and surface results to GitHub.

## Architecture

- `action.yml` — composite action definition with inputs, outputs, and 7 sequential steps
- `scripts/install.sh` — Linux/macOS binary installer (calls cargo-dist `boundary-installer.sh`)
- `scripts/install.ps1` — Windows binary installer (calls cargo-dist `boundary-installer.ps1`)
- `testdata/go-fixture/` — Go files with a deliberate domain-imports-infrastructure violation (triggers L001)
- `testdata/go-fixture-clean/` — Go files with no layer violations (used by `test-pass` job)
- `.github/workflows/test.yml` — three test jobs: `test-pass`, `test-fail`, `test-outputs`

## Key Design Decisions

- **Independent versioning** from the `boundary` binary; `boundary-version` input accepts exact tags only (no semver ranges)
- Uses cargo-dist installer scripts rather than manual download URL construction
- Step 3 (`boundary check`) runs with `continue-on-error: true`; Step 7 re-exits with code 1 if check failed
- Outputs are parsed from `boundary check --format json --compact` using `jq`
- Annotations map `boundary` severity directly to GitHub `::error`/`::warning` commands

## Testing

Tests run via `.github/workflows/test.yml` using `uses: ./` (local action reference) on `ubuntu-latest`:

```bash
# No local test runner — validation happens in GitHub Actions CI
# Push to a branch and open a PR to trigger the test workflow
```

## Installer Details (verified against v0.27.0)

The cargo-dist installer scripts do NOT accept version flags — the version is baked into each release's installer URL. Both installers auto-detect `$GITHUB_PATH` and add the install directory (`$HOME/.cargo/bin`) automatically. The wrapper scripts in `scripts/` simply download and execute the version-specific installer.

## `boundary check` JSON Schema

The action parses this structure from `boundary check --format json --compact`:

```
.score.overall        → score output (0-100)
.violations[]         → array with .severity, .location.file, .location.line, .location.column, .message, .suggestion
.check.passed         → boolean pass/fail
```

`location.file` already includes the `path` argument passed to `boundary check` (e.g., `testdata/go-fixture/internal/domain/user/bad_dep.go`), so no path prefix manipulation is needed in the annotations step.
