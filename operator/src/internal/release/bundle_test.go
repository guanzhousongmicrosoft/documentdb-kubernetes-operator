// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package release

import (
	"encoding/json"
	"path/filepath"
	"testing"
)

func TestManifestWithOverridesRetagsImages(t *testing.T) {
	root := findRepoRoot(t)
	manifest, err := LoadManifest(filepath.Join(root, "release", "artifacts.yaml"))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}

	updated, err := manifest.WithOverrides(OverrideOptions{
		OperatorTrack: "0.3.0",
		DatabaseTrack: "0.110.0",
	})
	if err != nil {
		t.Fatalf("apply overrides: %v", err)
	}

	if updated.Chart.Version != "0.3.0" {
		t.Fatalf("chart.version = %q, want %q", updated.Chart.Version, "0.3.0")
	}
	if updated.Chart.AppVersion != "0.3.0" {
		t.Fatalf("chart.appVersion = %q, want %q", updated.Chart.AppVersion, "0.3.0")
	}
	if updated.Images.Operator.Ref != "ghcr.io/documentdb/documentdb-kubernetes-operator/operator:0.3.0" {
		t.Fatalf("operator ref = %q", updated.Images.Operator.Ref)
	}
	if updated.Images.Sidecar.Ref != "ghcr.io/documentdb/documentdb-kubernetes-operator/sidecar:0.3.0" {
		t.Fatalf("sidecar ref = %q", updated.Images.Sidecar.Ref)
	}
	if updated.Images.DocumentDB.Ref != "ghcr.io/documentdb/documentdb-kubernetes-operator/documentdb:0.110.0" {
		t.Fatalf("documentdb ref = %q", updated.Images.DocumentDB.Ref)
	}
	if updated.Images.Gateway.Ref != "ghcr.io/documentdb/documentdb-kubernetes-operator/gateway:0.110.0" {
		t.Fatalf("gateway ref = %q", updated.Images.Gateway.Ref)
	}
}

func TestBuildBundleIncludesCandidateImages(t *testing.T) {
	root := findRepoRoot(t)
	manifest, err := LoadManifest(filepath.Join(root, "release", "artifacts.yaml"))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}

	bundle, err := BuildBundle(manifest, "operator", "release/artifacts.yaml", "refs/heads/main", &BundleCandidate{
		Images: ImageBundle{
			Operator: Artifact{
				Ref:    "ghcr.io/example/operator:0.2.0-test",
				Digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			},
			Sidecar: Artifact{
				Ref:    "ghcr.io/example/sidecar:0.2.0-test",
				Digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			},
		},
	})
	if err != nil {
		t.Fatalf("build bundle: %v", err)
	}

	if bundle.Scope != "operator" {
		t.Fatalf("scope = %q, want operator", bundle.Scope)
	}
	if bundle.SourceRef != "refs/heads/main" {
		t.Fatalf("sourceRef = %q, want refs/heads/main", bundle.SourceRef)
	}
	if bundle.Candidate == nil {
		t.Fatal("candidate bundle is nil")
	}
	if bundle.Candidate.Images.Operator.Ref != "ghcr.io/example/operator:0.2.0-test" {
		t.Fatalf("candidate operator ref = %q", bundle.Candidate.Images.Operator.Ref)
	}
	if bundle.Candidate.Images.Sidecar.Digest != "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" {
		t.Fatalf("candidate sidecar digest = %q", bundle.Candidate.Images.Sidecar.Digest)
	}
}

func TestBuildBundleJSONUsesCanonicalFieldNames(t *testing.T) {
	root := findRepoRoot(t)
	manifest, err := LoadManifest(filepath.Join(root, "release", "artifacts.yaml"))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}

	bundle, err := BuildBundle(manifest, "full", "release/artifacts.yaml", "refs/heads/main", &BundleCandidate{
		Images: ImageBundle{
			Operator: Artifact{
				Ref:    "ghcr.io/example/operator:0.2.0-test",
				Digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			},
			Sidecar: Artifact{
				Ref:    "ghcr.io/example/sidecar:0.2.0-test",
				Digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			},
			DocumentDB: Artifact{
				Ref:    "ghcr.io/example/documentdb:0.109.0-build-1",
				Digest: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
			},
			Gateway: Artifact{
				Ref:    "ghcr.io/example/gateway:0.109.0-build-1",
				Digest: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
			},
		},
	})
	if err != nil {
		t.Fatalf("build bundle: %v", err)
	}

	data, err := json.Marshal(bundle)
	if err != nil {
		t.Fatalf("marshal bundle: %v", err)
	}

	var payload map[string]any
	if err := json.Unmarshal(data, &payload); err != nil {
		t.Fatalf("unmarshal bundle json: %v", err)
	}

	releasePayload, ok := payload["release"].(map[string]any)
	if !ok {
		t.Fatalf("release payload missing or wrong type: %#v", payload["release"])
	}
	channelsPayload, ok := releasePayload["channels"].(map[string]any)
	if !ok {
		t.Fatalf("channels payload missing or wrong type: %#v", releasePayload["channels"])
	}
	if channelsPayload["operatorTrack"] != "0.2.0" {
		t.Fatalf("operatorTrack = %#v, want 0.2.0", channelsPayload["operatorTrack"])
	}
}
