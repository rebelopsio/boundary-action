# PRD: `boundary-action` — GitHub Action for Boundary Architecture Linter

**Repo:** `github.com/rebelopsio/boundary-action`  
**Boundary tool repo:** `github.com/rebelopsio/boundary`  
**Boundary version targeted by this spec:** `v0.27.0`

---

## Overview

`boundary-action` is a GitHub composite action that wraps the `boundary` CLI tool
(`boundary check`) for use in CI pipelines. It installs the correct `boundary` binary,
runs an architecture analysis, emits inline PR annotations for violations, writes a job
summary, and exposes structured outputs for downstream steps.

The action is a **thin adapter** — all analytical intelligence lives in the `boundary`
binary. The action's only responsibilities are: install the binary, invoke it, parse its
JSON output, and surface results to GitHub.

---

## Action Type

**Composite action.** Not Docker, not JavaScript.

Rationale: no Docker layer pull overhead, works across `ubuntu`, `macos`, and `windows`
runners natively, binary install is fast (~5s), no Node.js dependency chain to maintain.

---

## Repository Structure

```
boundary-action/
├── action.yml
├── README.md
├── scripts/
│   ├── install.sh          # Linux + macOS binary installer
│   └── install.ps1         # Windows binary installer
├── testdata/
│   └── go-fixture/
│       ├── .boundary.toml
│       └── internal/
│           ├── domain/
│           │   └── user.go          # clean domain type (no violations)
│           └── infrastructure/
│               └── bad_import.go    # deliberate layer violation (triggers L001)
└── .github/
    └── workflows/
        └── test.yml
```

---

## Versioning Model

The action uses **independent versioning** from the `boundary` binary.

- The action has its own semver release track (`v1`, `v1.0.0`, etc.)
- A `boundary-version` input controls which `boundary` release is installed
- The default value of `boundary-version` is pinned to a tested release and updated
  whenever a new action release is cut
- Users can override `boundary-version` to any exact release tag (e.g., downgrade from
  `0.27.1` to `0.27.0` if a regression is found)
- **No semver range resolution** — only exact tags are accepted; ranges would require
  GitHub API calls at runtime and break reproducibility

---

## `action.yml` Specification

### Inputs

| Input | Type | Default | Required | Description |
|---|---|---|---|---|
| `path` | string | `.` | no | Path to the project root to analyze |
| `fail-on` | string | `error` | no | Minimum severity to fail the check (`error` or `warning`) |
| `config` | string | `''` | no | Path to `.boundary.toml` config file |
| `languages` | string | `''` | no | Comma-separated languages to analyze (empty = auto-detect) |
| `track` | boolean | `false` | no | Save analysis snapshot for evolution tracking |
| `no-regression` | boolean | `false` | no | Fail if architecture score regresses from last snapshot |
| `incremental` | boolean | `false` | no | Use incremental analysis (cache unchanged files) |
| `per-service` | boolean | `false` | no | Analyze each service independently (monorepo mode) |
| `boundary-version` | string | `0.27.0` | no | Exact boundary release tag to install |

### Outputs

All outputs are derived from parsing `boundary check --format json --compact` stdout.

| Output | Type | Source expression | Description |
|---|---|---|---|
| `score` | string | `.score.overall // "0"` | Overall architecture score (0–100) |
| `violations` | string | `.violations \| length` | Total violation count |
| `errors` | string | `[.violations[] \| select(.severity == "error")] \| length` | Error-severity violation count |
| `warnings` | string | `[.violations[] \| select(.severity == "warning")] \| length` | Warning-severity violation count |
| `passed` | string | `.check.passed` | `"true"` or `"false"` |

---

## Steps (in order)

### Step 1 — Install boundary (Linux/macOS)

**Condition:** `runner.os != 'Windows'`

Invoke the cargo-dist-generated installer script for the pinned version:

```bash
curl -fsSL \
  "https://github.com/rebelopsio/boundary/releases/download/v${{ inputs.boundary-version }}/boundary-installer.sh" \
  | sh -s -- --version "${{ inputs.boundary-version }}"
```

After install, add the binary location to `$GITHUB_PATH`. cargo-dist installs to
`$HOME/.cargo/bin` — **verify this path against the actual installer before implementation**
by inspecting `boundary-installer.sh` from the v0.27.0 release.

### Step 2 — Install boundary (Windows)

**Condition:** `runner.os == 'Windows'`

```powershell
$version = "${{ inputs.boundary-version }}"
$url = "https://github.com/rebelopsio/boundary/releases/download/v${version}/boundary-installer.ps1"
Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\boundary-installer.ps1"
& "$env:TEMP\boundary-installer.ps1" -Version $version
```

Add the install path to `$env:GITHUB_PATH`. Verify the actual install path from the `.ps1`
script before hardcoding it.

### Step 3 — Run boundary check

Build the command conditionally from inputs. Always pass `--format json --compact` so
output is machine-parseable. Write stdout to `${{ runner.temp }}/boundary-output.json`.

Set `continue-on-error: true` on this step. Record the step outcome for use in Step 5.

The full command shape:

```
boundary check {path} \
  --format json \
  --compact \
  --fail-on {fail-on} \
  [--config {config}]        # omit if input is empty string
  [--languages {languages}]  # omit if input is empty string
  [--track]                  # omit if input is 'false'
  [--no-regression]          # omit if input is 'false'
  [--incremental]            # omit if input is 'false'
  [--per-service]            # omit if input is 'false'
```

### Step 4 — Parse outputs

Use `jq` to extract values from `boundary-output.json` and write them to `$GITHUB_OUTPUT`:

```bash
SCORE=$(jq -r '.score.overall // "0"' boundary-output.json)
VIOLATIONS=$(jq -r '.violations | length' boundary-output.json)
ERRORS=$(jq -r '[.violations[] | select(.severity == "error")] | length' boundary-output.json)
WARNINGS=$(jq -r '[.violations[] | select(.severity == "warning")] | length' boundary-output.json)
PASSED=$(jq -r '.check.passed' boundary-output.json)

echo "score=$SCORE" >> "$GITHUB_OUTPUT"
echo "violations=$VIOLATIONS" >> "$GITHUB_OUTPUT"
echo "errors=$ERRORS" >> "$GITHUB_OUTPUT"
echo "warnings=$WARNINGS" >> "$GITHUB_OUTPUT"
echo "passed=$PASSED" >> "$GITHUB_OUTPUT"
```

### Step 5 — Emit annotations

Iterate over violations in `boundary-output.json`. Map `boundary` severity to GitHub
annotation commands:

- `"error"` → `::error`
- `"warning"` → `::warning`

Annotation format:

```
::{severity} file={location.file},line={location.line},col={location.column}::{message}. {suggestion}
```

`suggestion` field is optional — only append if non-null/non-empty.

### Step 6 — Write job summary

Write a markdown table to `$GITHUB_STEP_SUMMARY`:

```markdown
## Boundary Architecture Check

| Metric | Value |
|--------|-------|
| Overall Score | {score}/100 |
| Status | ✅ Passed / ❌ Failed |
| Errors | {errors} |
| Warnings | {warnings} |
| Total Violations | {violations} |
| boundary version | v{boundary-version} |
```

If `passed == 'false'`, add a violations detail section listing each error-severity
violation with file and line.

### Step 7 — Propagate exit code

If Step 3 outcome was `failure`, exit with code 1. This is required because Step 3 uses
`continue-on-error: true` — without explicit re-exit, a failing check would appear green.

---

## Release Asset Naming Convention

Confirmed from `gh release view v0.27.0 --repo rebelopsio/boundary --json assets`:

```
boundary-aarch64-apple-darwin.tar.xz
boundary-aarch64-apple-darwin.tar.xz.sha256
boundary-aarch64-unknown-linux-gnu.tar.xz
boundary-aarch64-unknown-linux-gnu.tar.xz.sha256
boundary-x86_64-apple-darwin.tar.xz
boundary-x86_64-apple-darwin.tar.xz.sha256
boundary-x86_64-pc-windows-msvc.zip
boundary-x86_64-pc-windows-msvc.zip.sha256
boundary-x86_64-unknown-linux-gnu.tar.xz
boundary-x86_64-unknown-linux-gnu.tar.xz.sha256
boundary-installer.sh
boundary-installer.ps1
sha256.sum
source.tar.gz
dist-manifest.json
```

The action uses `boundary-installer.sh` / `boundary-installer.ps1` rather than
constructing download URLs manually. This delegates OS/arch detection and checksum
verification to the cargo-dist-generated installer.

---

## `boundary check` JSON Output Schema

Violations in the JSON output have this shape (confirmed from source):

```json
{
  "kind": { "LayerBoundary": { "from_layer": "Domain", "to_layer": "Infrastructure" } },
  "severity": "error",
  "location": { "file": "internal/domain/user/bad_dep.go", "line": 3, "column": 0 },
  "message": "domain layer depends on infrastructure layer",
  "suggestion": "Introduce a port interface in the domain layer."
}
```

Top-level check output shape:

```json
{
  "score": { "overall": 60.0, "..." : "..." },
  "violations": [...],
  "component_count": 5,
  "dependency_count": 3,
  "check": {
    "passed": false,
    "fail_on": "error",
    "failing_violation_count": 1
  }
}
```

The `location.file` field contains a relative path from the analyzed project root. GitHub
annotation `file=` expects a path relative to the repo root — these should be equivalent
when `path` input is `.` but may need prefixing when `path` points to a subdirectory.

---

## Test Fixture (`testdata/go-fixture/`)

A minimal Go module that produces at least one `L001` (layer boundary) violation.

**`.boundary.toml`** should define:
- Layer patterns matching `internal/domain/**` → `domain`
- Layer patterns matching `internal/infrastructure/**` → `infrastructure`

**`internal/domain/user.go`** — a clean exported domain struct with no imports that
would violate layer rules.

**`internal/infrastructure/bad_import.go`** — a file that imports from the domain layer
AND contains a deliberate reverse dependency (e.g., domain importing infrastructure),
ensuring at least one `error`-severity violation is produced.

The fixture must produce:
- At least 1 `error`-severity violation (to test fail path)
- A non-zero `score.overall` (to test score output parsing)

---

## `.github/workflows/test.yml`

Three jobs. All run on `ubuntu-latest`. All use `uses: ./` (local action).

### `test-pass`

Run the action against the fixture with `fail-on: warning` on a path that has no
violations (or use `fail-on: error` against a clean sub-path). Assert:

- Job succeeds
- `steps.boundary.outputs.score` is non-empty and not `"0"`
- `steps.boundary.outputs.passed` is `"true"`

### `test-fail`

Run the action against the fixture with `fail-on: error` against the path containing
the deliberate violation. Use `continue-on-error: true` on the step. Assert:

- `steps.boundary.outputs.passed` is `"false"`
- `steps.boundary.outputs.errors` is `> 0`
- Step outcome is `failure`

### `test-outputs`

Verify output types are well-formed (non-empty strings, numeric values parse as
integers). This catches regressions in the `jq` parsing logic.

---

## Verification Steps Before Writing Any Code

Claude Code **must** complete these checks before implementing:

1. **Inspect `boundary-installer.sh`** from the v0.27.0 release to confirm:
   - The `--version` flag syntax is correct
   - The install path (likely `$HOME/.cargo/bin`) so `$GITHUB_PATH` is set correctly

2. **Inspect `boundary-installer.ps1`** from the v0.27.0 release to confirm:
   - The `-Version` parameter name
   - The Windows install path

3. **Verify `location.file` is relative** by running `boundary check . --format json`
   against the test fixture and confirming paths in violation objects do not include
   absolute prefixes.

4. **Confirm `jq` is available** on GitHub-hosted runners (it is on `ubuntu-latest` and
   `macos-latest`; Windows may need explicit install or use of PowerShell JSON parsing
   instead).

---

## Out of Scope (v1)

- Binary caching via `actions/cache` (install time is acceptable for v1; add in v2 if
  needed)
- `boundary-lsp` installation (separate binary, separate concern)
- SARIF output format for GitHub Code Scanning integration (possible v2 feature)
- Support for `boundary analyze` command (action targets `boundary check` only)
- ARM64 Windows runner support (not in GitHub-hosted runner matrix yet)
