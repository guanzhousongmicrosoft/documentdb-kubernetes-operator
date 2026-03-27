// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package release

import "fmt"

// OverrideOptions applies release-time changes to the canonical manifest.
type OverrideOptions struct {
	ChartVersion     string
	ChartAppVersion  string
	OperatorTrack    string
	DatabaseTrack    string
	OperatorRef      string
	OperatorDigest   string
	SidecarRef       string
	SidecarDigest    string
	DocumentDBRef    string
	DocumentDBDigest string
	GatewayRef       string
	GatewayDigest    string
	PostgresRef      string
	PostgresDigest   string
}

// Bundle is a machine-readable release or candidate summary derived from the manifest.
type Bundle struct {
	SchemaVersion  string           `json:"schemaVersion"`
	Scope          string           `json:"scope"`
	SourceManifest string           `json:"sourceManifest,omitempty"`
	SourceRef      string           `json:"sourceRef,omitempty"`
	Release        Manifest         `json:"release"`
	Candidate      *BundleCandidate `json:"candidate,omitempty"`
}

// BundleCandidate records candidate image refs produced by build workflows.
type BundleCandidate struct {
	Images ImageBundle `json:"images"`
}

// WithOverrides returns a validated manifest copy with release-time overrides applied.
func (m Manifest) WithOverrides(opts OverrideOptions) (*Manifest, error) {
	clone := m

	if opts.OperatorTrack != "" {
		clone.Channels.OperatorTrack = opts.OperatorTrack
		if opts.ChartVersion == "" {
			clone.Chart.Version = opts.OperatorTrack
		}
		if opts.ChartAppVersion == "" {
			clone.Chart.AppVersion = opts.OperatorTrack
		}

		if opts.OperatorRef == "" {
			ref, err := retagRef(clone.Images.Operator.Ref, opts.OperatorTrack)
			if err != nil {
				return nil, fmt.Errorf("retag operator image: %w", err)
			}
			clone.Images.Operator.Ref = ref
		}
		if opts.SidecarRef == "" {
			ref, err := retagRef(clone.Images.Sidecar.Ref, opts.OperatorTrack)
			if err != nil {
				return nil, fmt.Errorf("retag sidecar image: %w", err)
			}
			clone.Images.Sidecar.Ref = ref
		}
	}

	if opts.DatabaseTrack != "" {
		clone.Channels.DatabaseTrack = opts.DatabaseTrack

		if opts.DocumentDBRef == "" {
			ref, err := retagRef(clone.Images.DocumentDB.Ref, opts.DatabaseTrack)
			if err != nil {
				return nil, fmt.Errorf("retag documentdb image: %w", err)
			}
			clone.Images.DocumentDB.Ref = ref
		}
		if opts.GatewayRef == "" {
			ref, err := retagRef(clone.Images.Gateway.Ref, opts.DatabaseTrack)
			if err != nil {
				return nil, fmt.Errorf("retag gateway image: %w", err)
			}
			clone.Images.Gateway.Ref = ref
		}
	}

	if opts.ChartVersion != "" {
		clone.Chart.Version = opts.ChartVersion
	}
	if opts.ChartAppVersion != "" {
		clone.Chart.AppVersion = opts.ChartAppVersion
	}
	if opts.OperatorRef != "" {
		clone.Images.Operator.Ref = opts.OperatorRef
	}
	if opts.OperatorDigest != "" {
		clone.Images.Operator.Digest = opts.OperatorDigest
	}
	if opts.SidecarRef != "" {
		clone.Images.Sidecar.Ref = opts.SidecarRef
	}
	if opts.SidecarDigest != "" {
		clone.Images.Sidecar.Digest = opts.SidecarDigest
	}
	if opts.DocumentDBRef != "" {
		clone.Images.DocumentDB.Ref = opts.DocumentDBRef
	}
	if opts.DocumentDBDigest != "" {
		clone.Images.DocumentDB.Digest = opts.DocumentDBDigest
	}
	if opts.GatewayRef != "" {
		clone.Images.Gateway.Ref = opts.GatewayRef
	}
	if opts.GatewayDigest != "" {
		clone.Images.Gateway.Digest = opts.GatewayDigest
	}
	if opts.PostgresRef != "" {
		clone.Postgres.Ref = opts.PostgresRef
	}
	if opts.PostgresDigest != "" {
		clone.Postgres.Digest = opts.PostgresDigest
	}

	if err := clone.Validate(); err != nil {
		return nil, err
	}

	return &clone, nil
}

// BuildBundle converts the canonical manifest into a machine-readable bundle summary.
func BuildBundle(release *Manifest, scope, sourceManifest, sourceRef string, candidate *BundleCandidate) (*Bundle, error) {
	if release == nil {
		return nil, fmt.Errorf("release manifest is required")
	}
	if err := release.Validate(); err != nil {
		return nil, err
	}
	if err := validateScope(scope); err != nil {
		return nil, err
	}
	if err := validateCandidate(candidate); err != nil {
		return nil, err
	}

	return &Bundle{
		SchemaVersion:  SchemaVersion,
		Scope:          scope,
		SourceManifest: sourceManifest,
		SourceRef:      sourceRef,
		Release:        *release,
		Candidate:      candidate,
	}, nil
}

func validateScope(scope string) error {
	switch scope {
	case "operator", "database", "full":
		return nil
	default:
		return fmt.Errorf("scope must be one of operator, database, or full")
	}
}

func validateCandidate(candidate *BundleCandidate) error {
	if candidate == nil {
		return nil
	}

	candidateArtifacts := map[string]Artifact{
		"candidate.operator":   candidate.Images.Operator,
		"candidate.sidecar":    candidate.Images.Sidecar,
		"candidate.documentdb": candidate.Images.DocumentDB,
		"candidate.gateway":    candidate.Images.Gateway,
	}

	for name, artifact := range candidateArtifacts {
		if artifact.Ref == "" && artifact.Digest == "" {
			continue
		}
		if err := validateArtifact(name, artifact); err != nil {
			return err
		}
	}

	return nil
}

func retagRef(ref, tag string) (string, error) {
	repository, _, err := SplitRef(ref)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s:%s", repository, tag), nil
}
