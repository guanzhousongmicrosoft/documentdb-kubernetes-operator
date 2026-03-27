// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package release

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"go.yaml.in/yaml/v3"
)

const SchemaVersion = "v1alpha1"

var (
	semverPattern = regexp.MustCompile(`^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$`)
	digestPattern = regexp.MustCompile(`^sha256:[a-f0-9]{64}$`)
)

// Manifest captures the canonical release metadata for the chart and runtime images.
type Manifest struct {
	SchemaVersion string      `yaml:"schemaVersion" json:"schemaVersion"`
	Chart         Chart       `yaml:"chart" json:"chart"`
	Channels      Channels    `yaml:"channels" json:"channels"`
	Images        ImageBundle `yaml:"images" json:"images"`
	Postgres      Artifact    `yaml:"postgres" json:"postgres"`
}

type Chart struct {
	Name       string `yaml:"name" json:"name"`
	Version    string `yaml:"version" json:"version"`
	AppVersion string `yaml:"appVersion" json:"appVersion"`
}

type Channels struct {
	OperatorTrack string `yaml:"operatorTrack" json:"operatorTrack"`
	DatabaseTrack string `yaml:"databaseTrack" json:"databaseTrack"`
}

type ImageBundle struct {
	Operator   Artifact `yaml:"operator" json:"operator"`
	Sidecar    Artifact `yaml:"sidecar" json:"sidecar"`
	DocumentDB Artifact `yaml:"documentdb" json:"documentdb"`
	Gateway    Artifact `yaml:"gateway" json:"gateway"`
}

type Artifact struct {
	Ref    string `yaml:"ref" json:"ref"`
	Digest string `yaml:"digest,omitempty" json:"digest,omitempty"`
}

// LoadManifest decodes a release manifest from disk and validates its shape.
func LoadManifest(path string) (*Manifest, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open manifest: %w", err)
	}
	defer file.Close()

	decoder := yaml.NewDecoder(file)
	decoder.KnownFields(true)

	var manifest Manifest
	if err := decoder.Decode(&manifest); err != nil {
		return nil, fmt.Errorf("decode manifest: %w", err)
	}

	if err := manifest.Validate(); err != nil {
		return nil, err
	}

	return &manifest, nil
}

// Validate checks the manifest for the fields and conventions Phase 1 requires.
func (m *Manifest) Validate() error {
	var issues []string

	if m.SchemaVersion != SchemaVersion {
		issues = append(issues, fmt.Sprintf("schemaVersion must be %q", SchemaVersion))
	}

	if strings.TrimSpace(m.Chart.Name) == "" {
		issues = append(issues, "chart.name must be set")
	}
	if !semverPattern.MatchString(m.Chart.Version) {
		issues = append(issues, "chart.version must be a semantic version")
	}
	if !semverPattern.MatchString(m.Chart.AppVersion) {
		issues = append(issues, "chart.appVersion must be a semantic version")
	}
	if !semverPattern.MatchString(m.Channels.OperatorTrack) {
		issues = append(issues, "channels.operatorTrack must be a semantic version")
	}
	if !semverPattern.MatchString(m.Channels.DatabaseTrack) {
		issues = append(issues, "channels.databaseTrack must be a semantic version")
	}

	if err := validateTaggedArtifact("images.operator", m.Images.Operator, m.Channels.OperatorTrack); err != nil {
		issues = append(issues, err.Error())
	}
	if err := validateTaggedArtifact("images.sidecar", m.Images.Sidecar, m.Channels.OperatorTrack); err != nil {
		issues = append(issues, err.Error())
	}
	if err := validateTaggedArtifact("images.documentdb", m.Images.DocumentDB, m.Channels.DatabaseTrack); err != nil {
		issues = append(issues, err.Error())
	}
	if err := validateTaggedArtifact("images.gateway", m.Images.Gateway, m.Channels.DatabaseTrack); err != nil {
		issues = append(issues, err.Error())
	}
	if err := validateArtifact("postgres", m.Postgres); err != nil {
		issues = append(issues, err.Error())
	}

	if len(issues) > 0 {
		return fmt.Errorf("invalid release manifest: %s", strings.Join(issues, "; "))
	}

	return nil
}

func validateTaggedArtifact(name string, artifact Artifact, expectedTag string) error {
	repository, tag, err := SplitRef(artifact.Ref)
	if err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	if repository == "" {
		return fmt.Errorf("%s: repository must not be empty", name)
	}
	if tag != expectedTag {
		return fmt.Errorf("%s: tag %q must match track version %q", name, tag, expectedTag)
	}
	if artifact.Digest != "" && !digestPattern.MatchString(artifact.Digest) {
		return fmt.Errorf("%s: digest must be sha256:<64 hex chars>", name)
	}
	return nil
}

func validateArtifact(name string, artifact Artifact) error {
	if _, _, err := SplitRef(artifact.Ref); err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	if artifact.Digest != "" && !digestPattern.MatchString(artifact.Digest) {
		return fmt.Errorf("%s: digest must be sha256:<64 hex chars>", name)
	}
	return nil
}

// SplitRef separates an image reference into repository and tag.
func SplitRef(ref string) (string, string, error) {
	ref = strings.TrimSpace(ref)
	if ref == "" {
		return "", "", fmt.Errorf("ref must not be empty")
	}
	if strings.Contains(ref, "@") {
		return "", "", fmt.Errorf("ref must use a tag; store digests in the digest field")
	}

	tagIndex := strings.LastIndex(ref, ":")
	slashIndex := strings.LastIndex(ref, "/")
	if tagIndex == -1 || tagIndex <= slashIndex || tagIndex == len(ref)-1 {
		return "", "", fmt.Errorf("ref %q must look like repository:tag", ref)
	}

	return ref[:tagIndex], ref[tagIndex+1:], nil
}
