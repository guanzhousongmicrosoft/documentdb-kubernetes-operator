# Release Instructions

This document provides instructions for releasing a new version of the DocumentDB Kubernetes Operator.

For the complete release strategy, support policy, and versioning scheme, see [docs/designs/release-strategy.md](docs/designs/release-strategy.md).

---

## Prerequisites

- Maintainer access to the repository
- GitHub CLI (`gh`) installed and authenticated (for PR creation)

---

## Release Types

| Type | Command | Example |
|------|---------|---------|
| Patch Release | `@release-agent cut a release` | `0.1.3` → `0.1.4` |
| Minor Release | `@release-agent cut a minor release` | `0.1.3` → `0.2.0` |
| Major Release | `@release-agent cut a major release` | `0.1.3` → `1.0.0` |
| Specific Version | `@release-agent release X.Y.Z` | `release 1.0.0` |

---

## Automated Release Process

This project uses a **release agent** to automate release preparation. The agent handles:

1. Reading current version from `operator/documentdb-helm-chart/Chart.yaml`
2. Bumping version numbers
3. Generating changelog entries from git commits
4. Creating the release PR

### Step 1: Invoke the Release Agent

```
@release-agent cut a release
```

Or for specific version types:
```
@release-agent cut a minor release
@release-agent release 0.2.0
```

### Step 2: Review Changes

The agent will update:

| File | Updates |
|------|---------|
| `operator/documentdb-helm-chart/Chart.yaml` | `version` and `appVersion` |
| `CHANGELOG.md` | New version entry at top |

> **Note:** The agent does NOT modify `values.yaml` or `release/artifacts.yaml` directly. The release workflows now sync those release-controlled files from the canonical manifest during promotion.
>
> **Artifact manifest:** `release/artifacts.yaml` is now the canonical inventory for chart metadata and default runtime image references. Any PR that changes chart metadata or default image references should keep this file in sync. Phase 1 validation checks it against `Chart.yaml`, `values.yaml`, operator defaults, and sidecar defaults.

### Step 3: Create PR

After reviewing the changes:
```
@release-agent create PR
```

This creates a branch `release/v{version}` and opens a PR.

### Step 4: Merge and Trigger Release Workflows

After the PR is approved and merged:

#### Preferred path: top-level release orchestrator

1. Build the candidate images you need:
   - **Operator track**: run **"RELEASE - Build Operator Candidate Images"** (`build_operator_images.yml`)
   - **Database track**: run **"RELEASE - Build DocumentDB Candidate Images"** (`build_documentdb_images.yml`)
2. Review the uploaded candidate bundle artifact from the build workflow:
   - `operator-candidate-bundle`
   - `database-candidate-bundle`
   - each bundle includes candidate image refs and digests
3. Run **"RELEASE - Orchestrate Artifact Release"** (`release.yml`) with:
   - `scope=operator` for operator + sidecar + Helm only
   - `scope=database` for documentdb + gateway only
   - `scope=full` for both tracks with a single metadata PR
4. Provide the required versions:
   - `operator_candidate_version` / `operator_version`
   - `database_candidate_version` / `database_version`
   - `source_ref` for Helm packaging when releasing the operator track
5. Let the workflow create the release-metadata PR:
   - operator-only and database-only releases let the track workflow create the PR
   - full releases create a single consolidated PR from `release.yml`
   - the PR now syncs promoted image digests into `release/artifacts.yaml` and Helm defaults when available

#### Advanced path: track-specific release workflows

- **Operator track**: `release_operator.yml`
- **Database track**: `release_documentdb_images.yml`

Use these directly only when you intentionally want a single-track release without the top-level orchestration layer.

> **Note:** The deprecated combined workflows (`build_images.yml`, `release_images.yml`) are still available but will be removed in a future release.

---

## Manual Release (If Agent Unavailable)

If the release agent is unavailable, follow these manual steps:

### 1. Update Chart.yaml

Edit `operator/documentdb-helm-chart/Chart.yaml`:
```yaml
version: X.Y.Z
appVersion: "X.Y.Z"
```

### 2. Update Changelog

Add entry to top of `CHANGELOG.md`:
```markdown
## [X.Y.Z] - YYYY-MM-DD

### Major Features
- Feature descriptions

### Bug Fixes
- Fix descriptions

### Enhancements & Fixes
- Other changes
```

### 3. Create PR

```bash
git checkout -b release/vX.Y.Z
git add operator/documentdb-helm-chart/Chart.yaml CHANGELOG.md release/artifacts.yaml
git commit -m "chore: prepare release X.Y.Z"
git push origin release/vX.Y.Z
gh pr create --title "chore: release vX.Y.Z" --base main
```

### 4. Trigger Release Workflows

After merge, follow the preferred orchestrated flow above. In normal releases, `release/artifacts.yaml` and its downstream synchronized files should be updated by the release workflows, not by hand.

---


## Security Release Process

For security vulnerabilities:

1. **Do not** disclose details publicly until fix is released
2. Create fix on a private branch
3. Follow release process
4. Publish security advisory on GitHub after release
5. Request CVE if applicable

---

## Rollback Procedure

If a release has critical issues:

1. Immediately start work on a patch release
2. Consider yanking problematic container images
3. Update GitHub release to mark as problematic
4. Communicate in GitHub Discussions
5. Use the previous merged release-metadata PR (and its `release/artifacts.yaml` snapshot) as the rollback source of truth for image refs and digests

---

## Troubleshooting

### Release Agent Errors

If the agent reports version validation errors:
- Ensure new version is greater than current version
- Use semantic versioning format: `X.Y.Z`

### CI Failures on Release Branch

```bash
cd operator/src
go mod tidy
make manifests generate
```

### Helm Chart Issues

```bash
cd operator/documentdb-helm-chart
helm lint .
helm template . --debug
```

---

## Reference

- [Release Agent](.github/agents/release-agent.md) - Agent configuration
- [Release Strategy](docs/designs/release-strategy.md) - Complete release policy
- [CHANGELOG.md](CHANGELOG.md) - Version history
