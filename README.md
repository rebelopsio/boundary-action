# boundary-action

A GitHub Action that runs [boundary](https://github.com/rebelopsio/boundary) architecture analysis on your codebase. It installs the `boundary` CLI, runs `boundary check`, emits inline PR annotations for violations, writes a job summary, and exposes structured outputs for downstream steps.

## Usage

```yaml
- uses: rebelopsio/boundary-action@v1
  with:
    path: '.'
    fail-on: 'error'
```

### With outputs

```yaml
- uses: rebelopsio/boundary-action@v1
  id: boundary
  with:
    fail-on: error

- name: Comment on PR
  if: steps.boundary.outputs.passed == 'false'
  run: |
    echo "Architecture score: ${{ steps.boundary.outputs.score }}/100"
    echo "Errors: ${{ steps.boundary.outputs.errors }}"
```

### Monorepo

```yaml
- uses: rebelopsio/boundary-action@v1
  with:
    path: services/api
    per-service: true
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `path` | `.` | Path to the project root to analyze |
| `fail-on` | `error` | Minimum severity to fail the check (`error` or `warning`) |
| `config` | | Path to `.boundary.toml` config file |
| `languages` | | Comma-separated languages to analyze (empty = auto-detect) |
| `track` | `false` | Save analysis snapshot for evolution tracking |
| `no-regression` | `false` | Fail if architecture score regresses from last snapshot |
| `incremental` | `false` | Use incremental analysis (cache unchanged files) |
| `per-service` | `false` | Analyze each service independently (monorepo mode) |
| `boundary-version` | `0.27.0` | Exact boundary release tag to install |

## Outputs

| Output | Description |
|---|---|
| `score` | Overall architecture score (0-100) |
| `violations` | Total violation count |
| `errors` | Error-severity violation count |
| `warnings` | Warning-severity violation count |
| `passed` | `"true"` or `"false"` |

## Platform Support

The action runs on `ubuntu`, `macos`, and `windows` runners. It uses the cargo-dist installer from each boundary release to handle OS/architecture detection automatically.
