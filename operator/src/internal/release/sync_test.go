// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package release

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSyncRepositoryFromManifestKeepsTrackedFilesStable(t *testing.T) {
	root := findRepoRoot(t)
	manifestPath := filepath.Join(root, "release", "artifacts.yaml")

	manifest, err := LoadManifest(manifestPath)
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}

	relativeFiles := []string{
		"release/artifacts.yaml",
		"operator/documentdb-helm-chart/Chart.yaml",
		"operator/documentdb-helm-chart/values.yaml",
		".github/workflows/build_operator_images.yml",
		".github/workflows/release_operator.yml",
		".github/workflows/build_documentdb_images.yml",
		".github/workflows/release_documentdb_images.yml",
		".github/workflows/release.yml",
		".github/workflows/test-upgrade-and-rollback.yml",
		".github/dockerfiles/Dockerfile_gateway_public_image",
	}

	tempRoot := t.TempDir()
	for _, relativePath := range relativeFiles {
		sourcePath := filepath.Join(root, relativePath)
		targetPath := filepath.Join(tempRoot, relativePath)
		if err := os.MkdirAll(filepath.Dir(targetPath), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", targetPath, err)
		}
		content, err := os.ReadFile(sourcePath)
		if err != nil {
			t.Fatalf("read %s: %v", sourcePath, err)
		}
		if err := os.WriteFile(targetPath, content, 0o644); err != nil {
			t.Fatalf("write %s: %v", targetPath, err)
		}
	}

	if err := SyncRepositoryFromManifest(tempRoot, filepath.Join(tempRoot, "release", "artifacts.yaml"), manifest); err != nil {
		t.Fatalf("sync repository: %v", err)
	}

	for _, relativePath := range relativeFiles {
		original, err := os.ReadFile(filepath.Join(root, relativePath))
		if err != nil {
			t.Fatalf("read original %s: %v", relativePath, err)
		}
		synced, err := os.ReadFile(filepath.Join(tempRoot, relativePath))
		if err != nil {
			t.Fatalf("read synced %s: %v", relativePath, err)
		}
		if string(synced) != string(original) {
			t.Fatalf("sync changed %s unexpectedly", relativePath)
		}
	}
}

func TestSyncRepositoryFromManifestPropagatesDigests(t *testing.T) {
	root := findRepoRoot(t)
	manifestPath := filepath.Join(root, "release", "artifacts.yaml")

	manifest, err := LoadManifest(manifestPath)
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}

	updatedManifest, err := manifest.WithOverrides(OverrideOptions{
		OperatorDigest:   "sha256:1111111111111111111111111111111111111111111111111111111111111111",
		SidecarDigest:    "sha256:2222222222222222222222222222222222222222222222222222222222222222",
		DocumentDBDigest: "sha256:3333333333333333333333333333333333333333333333333333333333333333",
		GatewayDigest:    "sha256:4444444444444444444444444444444444444444444444444444444444444444",
		PostgresDigest:   "sha256:5555555555555555555555555555555555555555555555555555555555555555",
	})
	if err != nil {
		t.Fatalf("override manifest: %v", err)
	}

	relativeFiles := []string{
		"release/artifacts.yaml",
		"operator/documentdb-helm-chart/Chart.yaml",
		"operator/documentdb-helm-chart/values.yaml",
		".github/workflows/build_operator_images.yml",
		".github/workflows/release_operator.yml",
		".github/workflows/build_documentdb_images.yml",
		".github/workflows/release_documentdb_images.yml",
		".github/workflows/release.yml",
		".github/workflows/test-upgrade-and-rollback.yml",
		".github/dockerfiles/Dockerfile_gateway_public_image",
	}

	tempRoot := t.TempDir()
	for _, relativePath := range relativeFiles {
		sourcePath := filepath.Join(root, relativePath)
		targetPath := filepath.Join(tempRoot, relativePath)
		if err := os.MkdirAll(filepath.Dir(targetPath), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", targetPath, err)
		}
		content, err := os.ReadFile(sourcePath)
		if err != nil {
			t.Fatalf("read %s: %v", sourcePath, err)
		}
		if err := os.WriteFile(targetPath, content, 0o644); err != nil {
			t.Fatalf("write %s: %v", targetPath, err)
		}
	}

	if err := SyncRepositoryFromManifest(tempRoot, filepath.Join(tempRoot, "release", "artifacts.yaml"), updatedManifest); err != nil {
		t.Fatalf("sync repository: %v", err)
	}

	var syncedManifest Manifest
	loadYAML(t, filepath.Join(tempRoot, "release", "artifacts.yaml"), &syncedManifest)
	if syncedManifest.Images.Operator.Digest != updatedManifest.Images.Operator.Digest {
		t.Fatalf("operator digest = %q, want %q", syncedManifest.Images.Operator.Digest, updatedManifest.Images.Operator.Digest)
	}
	if syncedManifest.Postgres.Digest != updatedManifest.Postgres.Digest {
		t.Fatalf("postgres digest = %q, want %q", syncedManifest.Postgres.Digest, updatedManifest.Postgres.Digest)
	}

	var values chartValues
	loadYAML(t, filepath.Join(tempRoot, "operator", "documentdb-helm-chart", "values.yaml"), &values)
	if values.Image.Operator.Ref != updatedManifest.Images.Operator.Ref {
		t.Fatalf("operator ref = %q, want %q", values.Image.Operator.Ref, updatedManifest.Images.Operator.Ref)
	}
	if values.Image.Operator.Digest != updatedManifest.Images.Operator.Digest {
		t.Fatalf("operator digest = %q, want %q", values.Image.Operator.Digest, updatedManifest.Images.Operator.Digest)
	}
	if values.Image.Sidecar.Digest != updatedManifest.Images.Sidecar.Digest {
		t.Fatalf("sidecar digest = %q, want %q", values.Image.Sidecar.Digest, updatedManifest.Images.Sidecar.Digest)
	}
	if values.RuntimeDefaults.DocumentDB.Digest != updatedManifest.Images.DocumentDB.Digest {
		t.Fatalf("documentdb digest = %q, want %q", values.RuntimeDefaults.DocumentDB.Digest, updatedManifest.Images.DocumentDB.Digest)
	}
	if values.RuntimeDefaults.Gateway.Digest != updatedManifest.Images.Gateway.Digest {
		t.Fatalf("gateway digest = %q, want %q", values.RuntimeDefaults.Gateway.Digest, updatedManifest.Images.Gateway.Digest)
	}
	if values.RuntimeDefaults.Postgres.Digest != updatedManifest.Postgres.Digest {
		t.Fatalf("postgres digest = %q, want %q", values.RuntimeDefaults.Postgres.Digest, updatedManifest.Postgres.Digest)
	}
}
