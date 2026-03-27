# Release process

This is the maintainer runbook for releasing the DocumentDB Kubernetes Operator in the current manifest-driven model.

For release policy and versioning guidance, see [docs/designs/release-strategy.md](docs/designs/release-strategy.md).

## Release model at a glance

The repository releases four runtime images:

- `operator`
- `sidecar`
- `documentdb`
- `gateway`

Maintainers should think in terms of one release interface and one source of truth:

- **Single release entrypoint:** `.github/workflows/release.yml`
- **Single canonical manifest:** `release/artifacts.yaml`

The build and promotion mechanics are still split internally by track, but the maintainer-facing flow is unified.

### Tracks and scopes

| Scope | What it releases | Typical use |
| --- | --- | --- |
| `operator` | `operator`, `sidecar`, and the Helm chart | Operator-only release |
| `database` | `documentdb` and `gateway` | Database image refresh without a new operator release |
| `full` | All four images plus the Helm chart | Coordinated release across both tracks |

## What you choose manually

For a normal release, choose the minimum set of inputs:

| Decision | Required when | Notes |
| --- | --- | --- |
| `scope` | Always | `operator`, `database`, or `full` |
| `operator_candidate_version` | `operator` or `full` | Candidate tag produced by `build_operator_images.yml` |
| `operator_version` | `operator` or `full` | Final operator release version |
| `database_candidate_version` | `database` or `full` | Candidate tag produced by `build_documentdb_images.yml` |
| `database_version` | `database` or `full` | Final database release version |
| `source_ref` | `operator` or `full` | Git ref used to package the Helm chart; prefer a tag or commit |
| `run_tests` | `operator` or `full` | Defaults to `true`; leave enabled unless you have an explicit exception |

### Manual work that is still expected

- Decide the release versions and `source_ref`.
- Trigger the candidate build workflow(s).
- Review the generated candidate bundle artifact(s).
- Start `release.yml`.
- Review and merge the auto-generated metadata PR.

### What not to do during a normal release

- Do **not** use `documentDbVersion` as the release mechanism.
- Do **not** manually edit `values.yaml` to point at released database images.
- Do **not** manually keep `Chart.yaml`, `values.yaml`, workflow defaults, and image refs in sync by hand.
- Do **not** treat the split track workflows as separate release systems unless you intentionally need an advanced path.

`documentDbVersion` remains only as a temporary compatibility shim. The normal release path is explicit image refs and digests synchronized from `release/artifacts.yaml`.

## Standard release flow

### 1. Prepare the release PR

If you use the release agent, it prepares the version bump PR for you:

| Type | Command | Example |
| --- | --- | --- |
| Patch release | `@release-agent cut a release` | `0.1.3` -> `0.1.4` |
| Minor release | `@release-agent cut a minor release` | `0.1.3` -> `0.2.0` |
| Major release | `@release-agent cut a major release` | `0.1.3` -> `1.0.0` |
| Specific version | `@release-agent release X.Y.Z` | `release 1.0.0` |

The release agent updates:

| File | Updates |
| --- | --- |
| `operator/documentdb-helm-chart/Chart.yaml` | `version` and `appVersion` |
| `CHANGELOG.md` | New release entry |

Then create the PR:

```text
@release-agent create PR
```

If the agent is unavailable, update `Chart.yaml` and `CHANGELOG.md` manually, open the release PR yourself, and then continue with the same promotion flow below.

> The release PR is not the place to hand-edit `release/artifacts.yaml` for final promoted refs. The release workflows sync release-controlled metadata during promotion.

### 2. Merge the release PR

After the release PR is approved and merged, use the workflow sequence below.

### 3. Build candidate artifacts

Run only the candidate build workflows needed for the selected scope:

| Needed scope | Workflow |
| --- | --- |
| `operator`, `full` | `RELEASE - Build Operator Candidate Images` (`.github/workflows/build_operator_images.yml`) |
| `database`, `full` | `RELEASE - Build DocumentDB Candidate Images` (`.github/workflows/build_documentdb_images.yml`) |

Expected artifacts:

- `operator-candidate-bundle`
- `database-candidate-bundle`

Use these artifacts to confirm the candidate tags, refs, and digests you are about to promote.

### 4. Run the top-level release orchestrator

Start `RELEASE - Orchestrate Artifact Release` (`.github/workflows/release.yml`).

This is the default maintainer entrypoint.

#### Scope behavior

- **`scope=operator`**
  - Calls `release_operator.yml`
  - Promotes `operator` and `sidecar`
  - Publishes the Helm chart
  - Creates the metadata PR from the operator-track workflow

- **`scope=database`**
  - Calls `release_documentdb_images.yml`
  - Promotes `documentdb` and `gateway`
  - Creates the metadata PR from the database-track workflow

- **`scope=full`**
  - Runs the database release first
  - Runs the operator release second, packaging the chart with the selected database defaults
  - Creates one consolidated metadata PR from `release.yml`

### 5. Let automation validate and promote

Automation owns the mechanical parts of the release:

1. Builds multi-architecture candidate images.
2. Signs and verifies candidate image manifests.
3. Produces machine-readable candidate bundle artifacts.
4. Validates workflow inputs for the selected scope.
5. Retags candidate images to release tags.
6. Runs operator-track pre-release tests when `run_tests=true`.
7. Packages and publishes the Helm chart for operator releases.
8. Resolves promoted image digests.
9. Synchronizes repository metadata from `release/artifacts.yaml`.
10. Opens the metadata PR when repository files changed.

During promotion, the sync step updates release-controlled files for you. Depending on scope, that includes:

- `release/artifacts.yaml`
- `operator/documentdb-helm-chart/Chart.yaml`
- `operator/documentdb-helm-chart/values.yaml`
- workflow defaults that track released versions
- upgrade baseline references used by release validation workflows
- the public gateway Dockerfile source-image default for the database track

### 6. Review the metadata PR

After promotion, review the auto-generated PR.

Verify that:

- versions match the release you intended
- `release/artifacts.yaml` contains the correct refs and digests
- Helm chart metadata and default image refs are synchronized
- workflow defaults moved to the expected released values

For `scope=full`, expect one PR that combines both tracks. For single-track releases, expect the track workflow to open the PR.

### 7. Merge the metadata PR

Merge the PR after review. That merge becomes the repository record of the released artifact set.

## Workflow order

Use this order unless you intentionally need an advanced exception path:

1. Prepare and merge the release PR
2. Run `build_operator_images.yml` and/or `build_documentdb_images.yml`
3. Review candidate bundle artifact(s)
4. Run `release.yml`
5. Review the generated metadata PR
6. Merge the metadata PR

## Advanced path: direct track workflows

Use the track-specific release workflows directly only when you intentionally want that behavior:

- `.github/workflows/release_operator.yml`
- `.github/workflows/release_documentdb_images.yml`

They remain part of the implementation, but they are not the primary maintainer interface anymore. In normal operation, use `release.yml`.

## Rollback and audit

Treat `release/artifacts.yaml` as the rollback and audit anchor.

If a release has critical issues:

1. Start a patch release immediately.
2. Consider yanking problematic container images if appropriate.
3. Mark the GitHub release as problematic.
4. Communicate in GitHub Discussions or the usual maintainer channel.
5. Use the previous merged release-metadata PR and its `release/artifacts.yaml` snapshot as the source of truth for refs and digests.

## Security releases

For security vulnerabilities:

1. Do not disclose details publicly until the fix is released.
2. Create the fix on a private branch or through the private security process.
3. Follow the same promotion flow in this document.
4. Publish the security advisory after release.
5. Request a CVE if applicable.

## Troubleshooting

### Release agent validation errors

- Ensure the new version is greater than the current version.
- Use semantic versioning: `X.Y.Z`.

### CI failures on a release branch

```bash
cd operator/src
go mod tidy
make manifests generate
```

### Helm chart issues

```bash
cd operator/documentdb-helm-chart
helm lint .
helm template . --debug
```

## Current verification status

This release model was remotely verified successfully on branch `copilot/release-flow-verification-20260327-1526` at commit `8b15aea1e1aa014dd79cad70c8606e9a7b1a7f70`.

Verified workflows:

- backup and restore
- upgrade and rollback

That verification confirms the explicit-runtime, manifest-driven release path described in this runbook.

## Reference

- [Release Agent](.github/agents/release-agent.md)
- [Release Strategy](docs/designs/release-strategy.md)
- [CHANGELOG.md](CHANGELOG.md)
