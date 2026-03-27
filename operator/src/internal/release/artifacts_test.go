// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package release

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	util "github.com/documentdb/documentdb-operator/internal/utils"
	"go.yaml.in/yaml/v3"
)

type chartMetadata struct {
	Name       string `yaml:"name"`
	Version    string `yaml:"version"`
	AppVersion string `yaml:"appVersion"`
}

type imageOverrideValue struct {
	Ref        string `yaml:"ref"`
	Digest     string `yaml:"digest"`
	Repository string `yaml:"repository"`
	Tag        string `yaml:"tag"`
}

type runtimeDefaultValue struct {
	Ref    string `yaml:"ref"`
	Digest string `yaml:"digest"`
}

type chartValues struct {
	DocumentDBVersion string `yaml:"documentDbVersion"`
	RuntimeDefaults   struct {
		DocumentDB runtimeDefaultValue `yaml:"documentdb"`
		Gateway    runtimeDefaultValue `yaml:"gateway"`
		Postgres   runtimeDefaultValue `yaml:"postgres"`
	} `yaml:"runtimeDefaults"`
	Image struct {
		Operator imageOverrideValue `yaml:"documentdbk8soperator"`
		Sidecar  imageOverrideValue `yaml:"sidecarinjector"`
	} `yaml:"image"`
}

func TestReleaseManifestIsValid(t *testing.T) {
	root := findRepoRoot(t)

	manifest, err := LoadManifest(filepath.Join(root, "release", "artifacts.yaml"))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}

	if manifest.Chart.Name != "documentdb-operator" {
		t.Fatalf("unexpected chart name: %s", manifest.Chart.Name)
	}
}

func TestReleaseManifestMatchesChartAndDefaults(t *testing.T) {
	root := findRepoRoot(t)

	manifest, err := LoadManifest(filepath.Join(root, "release", "artifacts.yaml"))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}

	var chart chartMetadata
	loadYAML(t, filepath.Join(root, "operator", "documentdb-helm-chart", "Chart.yaml"), &chart)

	var values chartValues
	loadYAML(t, filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), &values)

	if manifest.Chart.Name != chart.Name {
		t.Fatalf("manifest chart name %q != chart name %q", manifest.Chart.Name, chart.Name)
	}
	if manifest.Chart.Version != chart.Version {
		t.Fatalf("manifest chart version %q != Chart.yaml version %q", manifest.Chart.Version, chart.Version)
	}
	if manifest.Chart.AppVersion != chart.AppVersion {
		t.Fatalf("manifest appVersion %q != Chart.yaml appVersion %q", manifest.Chart.AppVersion, chart.AppVersion)
	}
	if manifest.Channels.OperatorTrack != chart.AppVersion {
		t.Fatalf("manifest operator track %q != chart appVersion %q", manifest.Channels.OperatorTrack, chart.AppVersion)
	}
	if manifest.Channels.DatabaseTrack != values.DocumentDBVersion {
		t.Fatalf("manifest database track %q != values.yaml documentDbVersion %q", manifest.Channels.DatabaseTrack, values.DocumentDBVersion)
	}

	if got := effectiveDeploymentImage(values.Image.Operator, chart.AppVersion); got != artifactReference(manifest.Images.Operator) {
		t.Fatalf("effective operator image %q != manifest %q", got, artifactReference(manifest.Images.Operator))
	}
	if got := effectiveDeploymentImage(values.Image.Sidecar, chart.AppVersion); got != artifactReference(manifest.Images.Sidecar) {
		t.Fatalf("effective sidecar image %q != manifest %q", got, artifactReference(manifest.Images.Sidecar))
	}
	if got := effectiveRuntimeDefaultImage(values.RuntimeDefaults.DocumentDB, values.DocumentDBVersion, util.DOCUMENTDB_EXTENSION_IMAGE_REPO); got != artifactReference(manifest.Images.DocumentDB) {
		t.Fatalf("effective documentdb default %q != manifest %q", got, artifactReference(manifest.Images.DocumentDB))
	}
	if got := effectiveRuntimeDefaultImage(values.RuntimeDefaults.Gateway, values.DocumentDBVersion, util.GATEWAY_IMAGE_REPO); got != artifactReference(manifest.Images.Gateway) {
		t.Fatalf("effective gateway default %q != manifest %q", got, artifactReference(manifest.Images.Gateway))
	}
	if got := effectiveRuntimeDefaultImage(values.RuntimeDefaults.Postgres, "", ""); got != artifactReference(manifest.Postgres) {
		t.Fatalf("effective postgres default %q != manifest %q", got, artifactReference(manifest.Postgres))
	}
}

func TestReleaseManifestSchemaIsValidJSON(t *testing.T) {
	root := findRepoRoot(t)

	schemaBytes, err := os.ReadFile(filepath.Join(root, "release", "artifacts.schema.json"))
	if err != nil {
		t.Fatalf("read schema: %v", err)
	}

	var schema map[string]any
	if err := json.Unmarshal(schemaBytes, &schema); err != nil {
		t.Fatalf("parse schema JSON: %v", err)
	}

	if schema["$id"] == "" {
		t.Fatal("schema is missing $id")
	}
}

func effectiveDeploymentImage(image imageOverrideValue, defaultTag string) string {
	if image.Tag != "" && image.Repository != "" {
		if image.Digest != "" {
			return image.Repository + ":" + image.Tag + "@" + image.Digest
		}
		return image.Repository + ":" + image.Tag
	}

	if image.Ref != "" {
		if image.Digest != "" {
			return image.Ref + "@" + image.Digest
		}
		return image.Ref
	}

	if image.Digest != "" {
		return image.Repository + ":" + defaultTag + "@" + image.Digest
	}
	return image.Repository + ":" + defaultTag
}

func effectiveRuntimeDefaultImage(image runtimeDefaultValue, legacyVersion, repository string) string {
	if image.Ref != "" {
		if image.Digest != "" {
			return image.Ref + "@" + image.Digest
		}
		return image.Ref
	}

	if legacyVersion != "" && repository != "" {
		return repository + ":" + legacyVersion
	}

	return ""
}

func artifactReference(artifact Artifact) string {
	if artifact.Digest != "" {
		return artifact.Ref + "@" + artifact.Digest
	}
	return artifact.Ref
}

func loadYAML(t *testing.T, path string, out any) {
	t.Helper()

	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if err := yaml.Unmarshal(content, out); err != nil {
		t.Fatalf("unmarshal %s: %v", path, err)
	}
}

func findRepoRoot(t *testing.T) string {
	t.Helper()

	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}

	for {
		if _, err := os.Stat(filepath.Join(dir, "AGENTS.md")); err == nil {
			return dir
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("failed to locate repository root")
		}
		dir = parent
	}
}
