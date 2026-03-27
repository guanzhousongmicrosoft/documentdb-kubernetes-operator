# Container Image Management

This document describes how the DocumentDB Kubernetes Operator manages, builds, versions, and releases container images.

## Table of Contents

- [Overview](#overview)
- [Image Inventory](#image-inventory)
- [Version Tracks](#version-tracks)
- [How the Operator Resolves Images at Runtime](#how-the-operator-resolves-images-at-runtime)
- [Helm Chart Configuration](#helm-chart-configuration)
- [Build Pipelines](#build-pipelines)
- [Release Pipelines](#release-pipelines)
- [Test Pipelines](#test-pipelines)
- [Local Development](#local-development)
- [Version Synchronization Points](#version-synchronization-points)
- [Architecture Support](#architecture-support)
- [Security](#security)

---

## Overview

The project manages **5 container images** across two independent version tracks:

- **Operator track**: images built from Go source code in this repository
- **Database track**: images built from `.deb` packages produced by the upstream [`documentdb/documentdb`](https://github.com/documentdb/documentdb) repository

All images are published to **GitHub Container Registry (GHCR)** under `ghcr.io/documentdb/documentdb-kubernetes-operator/`. A sixth image (PostgreSQL) comes from the CloudNative-PG project and is consumed as-is.

---

## Canonical Release Manifest

The repository now includes `release/artifacts.yaml` as the **canonical artifact manifest** for:

- chart name, version, and appVersion
- active runtime images: `operator`, `sidecar`, `documentdb`, and `gateway`
- track versions for the operator and database release streams
- the default PostgreSQL base image consumed by the operator

The manifest shape is described by `release/artifacts.schema.json`.

### Ownership and Update Policy

- Any pull request that changes released chart metadata or default runtime image references should update `release/artifacts.yaml` in the same change.
- During this first migration phase, runtime and workflow consumers still read legacy sources such as `Chart.yaml`, `values.yaml`, operator constants, and sidecar defaults.
- CI validation in `operator/src/internal/release/artifacts_test.go` keeps the manifest synchronized with those legacy sources until later phases migrate them to consume the manifest directly.

### Digest Strategy

- The manifest stores a required `ref` field using `repository:tag`.
- A separate optional `digest` field records the promoted manifest digest for each released image.
- Helm image rendering prefers `ref@digest` when a digest is present, so release packaging can deploy immutable image identities while keeping readable tags in metadata.

### Rollback Guidance

- Treat each merged release-metadata PR as a rollback anchor.
- To reconstruct a prior release, use the corresponding historical snapshot of `release/artifacts.yaml` plus the synced chart defaults in that PR.
- Once digest fields are populated, the manifest snapshot is sufficient to identify the exact promoted image manifests for operator, sidecar, documentdb, and gateway.

---

## Image Inventory

### Operator Track — Built from This Repository

| Image | GHCR Path | Source | Dockerfile | Purpose |
|-------|-----------|--------|------------|---------|
| **operator** | `.../operator` | `operator/src/` (Go) | `operator/src/Dockerfile` | Main reconciliation controller for DocumentDB CRDs |
| **sidecar** | `.../sidecar` | `operator/cnpg-plugins/sidecar-injector/` (Go) | `operator/cnpg-plugins/sidecar-injector/Dockerfile` | CNPG plugin that injects the gateway sidecar into database pods |
| **wal-replica** | `.../wal-replica` | `operator/cnpg-plugins/wal-replica/` (Go) | *(planned)* | WAL-based read replica plugin (feature-flagged, disabled by default) |

### Database Track — Built from External Source

| Image | GHCR Path | Source | Dockerfile | Purpose |
|-------|-----------|--------|------------|---------|
| **documentdb** | `.../documentdb` | Public `deb13` PostgreSQL 18 package from `documentdb/documentdb` releases | `.github/dockerfiles/Dockerfile_extension` | DocumentDB PostgreSQL extension files for CNPG ImageVolume mode |
| **gateway** | `.../gateway` | Public gateway payload copied from `ghcr.io/documentdb/documentdb/documentdb-local:pg17-<version>` | `.github/dockerfiles/Dockerfile_gateway_public_image` | MongoDB wire-protocol gateway binary (Rust) |

### External Image (Not Built Here)

| Image | Full Reference | Source | Purpose |
|-------|---------------|--------|---------|
| **PostgreSQL** | `ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie` | CloudNative-PG project | Base PostgreSQL server image for CNPG clusters |

---

## Version Tracks

The two version tracks are **independent** — they follow different release cadences and use different version numbering.

| Aspect | Operator Track | Database Track |
|--------|---------------|----------------|
| **Images** | operator, sidecar, wal-replica | documentdb, gateway |
| **Source repo** | This repo (Go) | `documentdb/documentdb` (C + Rust) |
| **Version source** | `release/artifacts.yaml` → `channels.operatorTrack` / `chart.appVersion` | `release/artifacts.yaml` → `channels.databaseTrack` |
| **Current version** | `0.2.0` | `0.109.0` |
| **Build workflow** | `build_operator_images.yml` | `build_documentdb_images.yml` |
| **Release workflow** | `release.yml` (preferred) or `release_operator.yml` | `release.yml` (preferred) or `release_documentdb_images.yml` |
| **Tag example** | `ghcr.io/.../operator:0.2.0` | `ghcr.io/.../documentdb:0.109.0` |

### Why Two Tracks?

The DocumentDB extension and gateway are developed in a separate repository (`documentdb/documentdb`) and iterate at a different cadence than the Kubernetes operator. Decoupling allows:

- Operator bug fixes without rebuilding database images (~2 min vs ~15+ min)
- Database upgrades without a full operator release
- Image tags that reflect actual component versions
- Independent testing and promotion pipelines

---

## How the Operator Resolves Images at Runtime

The operator binary determines which database images to use through a priority chain. This logic lives in `operator/src/internal/utils/util.go`.

### DocumentDB Extension Image (`GetDocumentDBImageForInstance()`)

```
Priority (highest → lowest):
1. spec.documentDBImage          ← CR field: full image URI override
2. spec.documentDBVersion        ← CR field: used as tag with hardcoded repo
3. env DEFAULT_DOCUMENTDB_IMAGE  ← explicit runtime default from Helm values
4. env DOCUMENTDB_VERSION        ← deprecated compatibility path from Helm values
5. ChangeStreams feature gate    ← temporary override for changestream images
6. reconciliation error          ← operator requires explicit config if no default is available
```

### Gateway Image (`GetGatewayImageForDocumentDB()`)

```
Priority (highest → lowest):
1. spec.gatewayImage             ← CR field: full image URI override
2. spec.documentDBVersion        ← CR field: used as tag with hardcoded repo
3. env DEFAULT_GATEWAY_IMAGE     ← explicit runtime default from Helm values
4. env DOCUMENTDB_VERSION        ← deprecated compatibility path from Helm values
5. ChangeStreams feature gate    ← temporary override for changestream images
6. reconciliation error          ← operator requires explicit config if no default is available
```

### PostgreSQL Image

Set via `spec.postgresImage` in the DocumentDB CR. The chart now carries an explicit `runtimeDefaults.postgres.ref` value for the intended default, but the active runtime default still comes from the CRD schema (`ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie`) until a later phase removes that schema-level default.

### How Images Flow into Pods

```
DocumentDB CR spec
    │
    ▼
Operator controller (documentdb_controller.go)
    ├── Resolves documentdbImage via GetDocumentDBImageForInstance()
    ├── Resolves gatewayImage via GetGatewayImageForDocumentDB()
    │
    ▼
CNPG Cluster spec (cnpg_cluster.go)
    ├── documentdbImage → ImageVolumeSource (mounted as read-only volume)
    ├── gatewayImage → passed as plugin parameter to sidecar-injector
    │
    ▼
Sidecar Injector Plugin (lifecycle.go)
    └── Reads gatewayImage from plugin parameters
        └── Injects gateway container with that image into each database pod
```

---

## Helm Chart Configuration

The Helm chart (`operator/documentdb-helm-chart/`) coordinates deployment of operator-track images and passes database version configuration to the operator.

### Chart.yaml

```yaml
version: 0.2.0           # Chart version
appVersion: "0.2.0"      # Default tag for operator/sidecar/wal-replica images
```

### values.yaml

```yaml
# Deprecated compatibility field
documentDbVersion: "0.109.0"

image:
  documentdbk8soperator:
    ref: ghcr.io/documentdb/documentdb-kubernetes-operator/operator:0.2.0
    digest: ""
    repository: ghcr.io/documentdb/documentdb-kubernetes-operator/operator
    pullPolicy: Always
  sidecarinjector:
    ref: ghcr.io/documentdb/documentdb-kubernetes-operator/sidecar:0.2.0
    digest: ""
    repository: ghcr.io/documentdb/documentdb-kubernetes-operator/sidecar
    pullPolicy: Always
  walreplica:
    ref: ""
    digest: ""
    repository: ghcr.io/documentdb/documentdb-kubernetes-operator/wal-replica
    pullPolicy: Always

runtimeDefaults:
  documentdb:
    ref: ghcr.io/documentdb/documentdb-kubernetes-operator/documentdb:0.109.0
    digest: ""
  gateway:
    ref: ghcr.io/documentdb/documentdb-kubernetes-operator/gateway:0.109.0
    digest: ""
  postgres:
    ref: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
    digest: ""
```

### Image Tag Resolution in Templates

**Operator-track deployment images** now default to explicit released refs from `values.yaml`, and use immutable `ref@digest` when a digest is present:
```yaml
image: "{{ .Values.image.documentdbk8soperator.ref | default (printf "%s:%s" .Values.image.documentdbk8soperator.repository .Chart.AppVersion) }}"
```

**Runtime defaults** are passed to the operator as explicit image refs:
```yaml
- name: DEFAULT_DOCUMENTDB_IMAGE
  value: "{{ .Values.runtimeDefaults.documentdb.ref }}"
- name: DEFAULT_GATEWAY_IMAGE
  value: "{{ .Values.runtimeDefaults.gateway.ref }}"
```

During the compatibility window, the chart still also passes `DOCUMENTDB_VERSION` when `documentDbVersion` is set so older callers continue to work, but release workflows and test workflows should prefer the explicit runtime default refs.

---

## Build Pipelines

### Operator Image Build (`build_operator_images.yml`)

Builds operator and sidecar images from this repo's Go source.

| Aspect | Details |
|--------|---------|
| **Trigger** | `workflow_dispatch`, `workflow_call`, `push` to `main` (operator source paths) |
| **Images** | operator, sidecar |
| **Dockerfiles** | `operator/src/Dockerfile`, `operator/cnpg-plugins/sidecar-injector/Dockerfile` |
| **Tag pattern** | `{version}-test` (candidate), `{version}-test-{arch}` (per-arch) |
| **Build time** | ~2 minutes |
| **Multi-arch** | amd64 + arm64 → multi-arch manifest |
| **Signing** | cosign keyless (OIDC) |
| **Outputs** | Multi-arch candidate images plus `operator-candidate-bundle` artifact (refs + digests) |

### Database Image Build (`build_documentdb_images.yml`)

Builds documentdb extension and gateway images from public DocumentDB release artifacts.

| Aspect | Details |
|--------|---------|
| **Trigger** | `workflow_dispatch`, `workflow_call`, `repository_dispatch` (from upstream) |
| **Images** | documentdb, gateway |
| **Dockerfiles** | `.github/dockerfiles/Dockerfile_extension`, `.github/dockerfiles/Dockerfile_gateway_public_image` |
| **Tag pattern** | `{documentdb_version}-build-{run_id}-{attempt}-{sha}` (candidate) |
| **Build time** | ~5 minutes (public artifact download + image build) |
| **Multi-arch** | amd64 + arm64 → multi-arch manifest |
| **Signing** | cosign keyless (OIDC) |
| **Version detection** | Workflow input / repository dispatch payload (defaults to released `0.109.0`) |
| **Outputs** | Multi-arch candidate images plus `database-candidate-bundle` artifact (refs + digests) |

The build process:
1. Resolves the released DocumentDB version to package
2. Downloads the public `deb13` PostgreSQL 18 extension package from `documentdb/documentdb` release assets
3. Verifies the public multi-arch `documentdb-local:pg17-<version>` image exists
4. Builds `Dockerfile_extension` using the public extension `.deb` (installs pg_cron, pgvector, postgis alongside)
5. Builds `Dockerfile_gateway_public_image` by copying the gateway binary and runtime files from the public upstream image

### Dockerfile Details

#### Operator (`operator/src/Dockerfile`)
- **Base**: `mcr.microsoft.com/oss/go/microsoft/golang:1.25-azurelinux3.0` → `scratch`
- **Multi-stage**: 2 stages (builder → scratch)
- **Entrypoint**: `/manager`

#### Sidecar (`operator/cnpg-plugins/sidecar-injector/Dockerfile`)
- **Base**: Same Go Azure Linux image → `scratch`
- **Multi-stage**: 2 stages
- **Entrypoint**: `/app/bin/cnpg-i-sidecar-injector`

#### DocumentDB Extension (`.github/dockerfiles/Dockerfile_extension`)
- **Base**: `ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie` → `scratch`
- **Multi-stage**: 2 stages
- **No entrypoint** — this is an ImageVolume source, not a runnable container
- Follows the [cloudnative-pg/postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers) pattern
- Installs DocumentDB extension + pg_cron + pgvector + PostGIS
- Copies only extension artifacts (`.so`, `.control`, `.sql`, bitcode) and required system libraries
- Resolves Debian-alternatives symlinks (they break in ImageVolume mode)

#### Gateway (`.github/dockerfiles/Dockerfile_gateway_public_image`)
- **Base**: `debian:trixie-slim`
- **Multi-stage**: public `documentdb-local` source image → slim runtime image
- **Entrypoint**: `/bin/bash /home/documentdb/gateway/scripts/gateway_entrypoint.sh`
- Runs as non-root `documentdb` user (UID 1000)
- Copies `documentdb_gateway`, `SetupConfiguration.json`, and `utils.sh` from the upstream public image

---

## Release Pipelines

### Top-Level Orchestrator (`release.yml`)

Preferred entrypoint for maintainers. It coordinates track-specific releases and creates a single metadata PR for `scope=full`.

```
Inputs:
  scope: operator | database | full
  operator_candidate_version: "0.2.0-test"
  operator_version: "0.2.0"
  database_candidate_version: "0.111.0-build-123456789-1-deadbee"
  database_version: "0.111.0"
  source_ref: <git tag or commit>   ← required for operator/full
  run_tests: true

Flow:
  1. Validate requested inputs for the selected scope
  2. Run database release first for scope=full
  3. Run operator release (with optional database-track override for chart packaging)
  4. Create one consolidated metadata PR for scope=full
```

### Operator Release (`release_operator.yml`)

Promotes operator/sidecar candidate images and publishes the Helm chart.

```
Inputs:
  candidate_version: "0.2.0-test"   ← source tag
  version: "0.2.0"                  ← target release tag
  source_ref: <git tag or commit>   ← for Helm chart packaging
  database_version: "0.111.0"       ← optional override when packaging a full release
  update_release_metadata: true

Flow:
  1. Test Gate (optional, parallel)
     ├── test-E2E.yml
     ├── test-integration.yml
     └── test-backup-and-restore.yml
  
   2. Promote Images
      └── docker buildx imagetools create
          -t .../operator:0.2.0  .../operator:0.2.0-test
          -t .../sidecar:0.2.0   .../sidecar:0.2.0-test
   
   3. Publish Helm Chart
      ├── Sync chart metadata from release/artifacts.yaml
      ├── helm package + helm push to oci://ghcr.io/{owner}
      └── Publish to GitHub Pages (Helm repo index)

   4. Optional Metadata PR
      └── Sync release/artifacts.yaml, chart defaults, workflow defaults, and promoted digests
```

### Database Image Release (`release_documentdb_images.yml`)

Promotes documentdb/gateway candidate images and auto-creates a PR to update defaults.

```
Inputs:
  candidate_version: "0.111.0-build-123456789-1-deadbee"   ← source tag
  version: "0.111.0"                  ← target release tag
  update_defaults: true               ← create PR to bump versions

Flow:
  1. Promote Images
     └── docker buildx imagetools create
         -t .../documentdb:0.111.0  .../documentdb:0.111.0-test
         -t .../gateway:0.111.0     .../gateway:0.111.0-test
  
   2. Update Defaults (auto-PR)
      ├── values.yaml: runtimeDefaults.documentdb.ref / runtimeDefaults.gateway.ref
      ├── values.yaml: documentDbVersion (compatibility field)
      ├── release/artifacts.yaml: databaseTrack + image refs/digests
      ├── release.yml / build_documentdb_images.yml / release_documentdb_images.yml defaults
      ├── test-upgrade-and-rollback.yml: released baseline
      ├── Dockerfile_gateway_public_image: SOURCE_IMAGE ARG default
      └── Opens PR: "chore: bump DocumentDB images to 0.111.0"
```

---

## Test Pipelines

### Test Build (`test-build-and-package.yml`)

Reusable workflow that builds ALL images (operator + database) locally for test validation. Called by all test workflows when no external `image_tag` is provided.

- All images share a single test tag: `{version}-test-{run_id}-{arch}`
- Images are built with `--load` and saved as `.tar` artifacts (not pushed to GHCR)
- Also produces arch-specific Helm chart packages

### Test Workflows

| Workflow | Trigger | Special Image Logic |
|----------|---------|---------------------|
| `test-E2E.yml` | push/PR/schedule/dispatch | Standard — local build or external images |
| `test-integration.yml` | push/PR/dispatch | Standard — local build or external images |
| `test-backup-and-restore.yml` | push/PR/schedule/dispatch | Reads explicit runtime default refs for external mode |
| `test-upgrade-and-rollback.yml` | push/PR/schedule/dispatch | Old/new image comparison; combined image for chart ≤0.1.3 |
| `test-unit.yml` | push/PR | No container images |

### Image Loading (`setup-test-environment` action)

The `.github/actions/setup-test-environment/action.yml` composite action handles loading images into Kind clusters:

- **Local build path**: `docker load` from `.tar` → `kind load docker-image`
- **External image path**: `docker pull` from GHCR → `kind load docker-image`
- Supports separate `documentdb-image-tag` for independent database image versioning in tests
- Falls back to `image-tag` (operator tag) for backward compatibility

---

## Local Development

### Makefile Targets (`operator/src/Makefile`)

```bash
make docker-build    # Build operator image: docker build -t ${IMG} .
make docker-push     # Push operator image
make docker-buildx   # Multi-platform build and push
```

### Deploy Script (`operator/src/scripts/development/deploy.sh`)

```bash
# Defaults
REGISTRY=localhost:5001
OPERATOR_IMAGE=${REGISTRY}/operator
PLUGIN_IMAGE=${REGISTRY}/sidecar-injector
TAG=0.1.1

# Usage: builds and deploys to a local Kind cluster
DEPLOY=true DEPLOY_CLUSTER=true ./scripts/development/deploy.sh
```

The script uses `kind_with_registry.sh` to set up a `registry:2` container on `localhost:5001`, connected to the Kind cluster's network.

---

## Version Synchronization Points

When bumping database image versions, the following locations are synchronized from `release/artifacts.yaml` by `go run ./cmd/release-manifest sync` (typically invoked by `release_documentdb_images.yml` or `release.yml`):

| File | Field | Example |
|------|-------|---------|
| `operator/documentdb-helm-chart/values.yaml` | `runtimeDefaults.documentdb.ref`, `runtimeDefaults.documentdb.digest` | `...documentdb:0.109.0`, `sha256:...` |
| `operator/documentdb-helm-chart/values.yaml` | `runtimeDefaults.gateway.ref`, `runtimeDefaults.gateway.digest` | `...gateway:0.109.0`, `sha256:...` |
| `operator/documentdb-helm-chart/values.yaml` | `documentDbVersion` (compatibility) | `"0.109.0"` |
| `release/artifacts.yaml` | `channels.databaseTrack`, image refs/digests | `0.109.0`, `...documentdb:0.109.0`, `sha256:...` |
| `.github/workflows/test-upgrade-and-rollback.yml` | `RELEASED_DATABASE_VERSION` | `0.109.0` |
| `.github/workflows/build_documentdb_images.yml` | `DEFAULT_DOCUMENTDB_VERSION`, input default | `0.109.0` |
| `.github/workflows/release_documentdb_images.yml` | Input default | `0.109.0` |
| `.github/workflows/release.yml` | `database_version` default | `0.109.0` |
| `.github/dockerfiles/Dockerfile_gateway_public_image` | `SOURCE_IMAGE` ARG default | `...pg17-0.109.0` |

When bumping operator versions, the following locations are synchronized from `release/artifacts.yaml` by `go run ./cmd/release-manifest sync`:

| File | Field | Example |
|------|-------|---------|
| `operator/documentdb-helm-chart/Chart.yaml` | `version`, `appVersion` | `0.2.0` |
| `release/artifacts.yaml` | `chart.version`, `chart.appVersion`, `channels.operatorTrack`, image refs/digests | `0.2.0`, `.../operator:0.2.0`, `sha256:...` |
| `operator/documentdb-helm-chart/values.yaml` | `image.documentdbk8soperator.ref`, `image.documentdbk8soperator.digest` | `.../operator:0.2.0`, `sha256:...` |
| `operator/documentdb-helm-chart/values.yaml` | `image.sidecarinjector.ref`, `image.sidecarinjector.digest` | `.../sidecar:0.2.0`, `sha256:...` |
| `.github/workflows/build_operator_images.yml` | Input default, `env.VERSION`, `env.IMAGE_TAG` | `0.2.0`, `0.2.0-test` |
| `.github/workflows/release_operator.yml` | Candidate/default inputs | `0.2.0-test`, `0.2.0` |
| `.github/workflows/release.yml` | `operator_candidate_version`, `operator_version` defaults | `0.2.0-test`, `0.2.0` |
| `CHANGELOG.md` | New version entry | `## [0.1.3]` |

> **Note**: Runtime image defaults are no longer maintained via compiled operator/sidecar constants. The canonical release source is `release/artifacts.yaml`, and the sync tool keeps the chart and workflow defaults aligned with it.

---

## Architecture Support

All images support multi-architecture builds:

| Platform | CI Runner | Notes |
|----------|-----------|-------|
| `linux/amd64` | `ubuntu-22.04` | Primary architecture |
| `linux/arm64` | `ubuntu-22.04-arm` | ARM support |

Build workflows produce per-arch images with `-amd64`/`-arm64` suffixes, then create multi-arch manifests using `docker manifest create --amend`.

---

## Security

| Aspect | Implementation |
|--------|---------------|
| **Image signing** | cosign keyless (OIDC-based) during build workflows |
| **Signature verification** | Certificate identity matching in the same workflow |
| **Minimal images** | Operator/sidecar use `scratch`; extension uses `scratch`; gateway uses `debian:trixie-slim` |
| **Non-root execution** | Gateway: UID 1000 (`documentdb`); operator/sidecar: from `scratch` with no shell |
| **No pull secrets** | GHCR public packages; no `imagePullSecrets` in chart |

---

## Deprecated Workflows

The following workflows are deprecated and will be removed in a future release:

| Deprecated | Replaced By |
|-----------|-------------|
| `build_images.yml` | `build_operator_images.yml` + `build_documentdb_images.yml` |
| `release_images.yml` | `release_operator.yml` + `release_documentdb_images.yml` |

The deprecated workflows built and released all 4 images together, coupling the operator and database version tracks. The new split workflows allow independent release cycles.
