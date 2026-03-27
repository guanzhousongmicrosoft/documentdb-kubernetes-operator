// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	releasepkg "github.com/documentdb/documentdb-operator/internal/release"
)

func main() {
	if len(os.Args) < 2 {
		exitf("usage: %s <bundle|sync> [flags]", filepath.Base(os.Args[0]))
	}

	switch os.Args[1] {
	case "bundle":
		runBundle(os.Args[2:])
	case "sync":
		runSync(os.Args[2:])
	default:
		exitf("unknown command %q", os.Args[1])
	}
}

func runBundle(args []string) {
	fs := flag.NewFlagSet("bundle", flag.ExitOnError)
	manifestPath := fs.String("manifest", "", "Path to release/artifacts.yaml")
	scope := fs.String("scope", "full", "Bundle scope: operator, database, or full")
	outputPath := fs.String("output", "", "Optional output path (defaults to stdout)")
	sourceRef := fs.String("source-ref", "", "Optional git ref associated with the bundle")
	operatorCandidate := fs.String("candidate-operator-ref", "", "Optional operator candidate image ref")
	operatorCandidateDigest := fs.String("candidate-operator-digest", "", "Optional operator candidate image digest")
	sidecarCandidate := fs.String("candidate-sidecar-ref", "", "Optional sidecar candidate image ref")
	sidecarCandidateDigest := fs.String("candidate-sidecar-digest", "", "Optional sidecar candidate image digest")
	documentdbCandidate := fs.String("candidate-documentdb-ref", "", "Optional documentdb candidate image ref")
	documentdbCandidateDigest := fs.String("candidate-documentdb-digest", "", "Optional documentdb candidate image digest")
	gatewayCandidate := fs.String("candidate-gateway-ref", "", "Optional gateway candidate image ref")
	gatewayCandidateDigest := fs.String("candidate-gateway-digest", "", "Optional gateway candidate image digest")
	fs.Parse(args)

	manifest := loadManifestOrExit(*manifestPath)
	bundle, err := releasepkg.BuildBundle(manifest, *scope, *manifestPath, *sourceRef, &releasepkg.BundleCandidate{
		Images: releasepkg.ImageBundle{
			Operator:   releasepkg.Artifact{Ref: *operatorCandidate, Digest: *operatorCandidateDigest},
			Sidecar:    releasepkg.Artifact{Ref: *sidecarCandidate, Digest: *sidecarCandidateDigest},
			DocumentDB: releasepkg.Artifact{Ref: *documentdbCandidate, Digest: *documentdbCandidateDigest},
			Gateway:    releasepkg.Artifact{Ref: *gatewayCandidate, Digest: *gatewayCandidateDigest},
		},
	})
	if err != nil {
		exitf("build bundle: %v", err)
	}

	writeJSONOrExit(*outputPath, bundle)
}

func runSync(args []string) {
	fs := flag.NewFlagSet("sync", flag.ExitOnError)
	manifestPath := fs.String("manifest", "", "Path to release/artifacts.yaml")
	repoRoot := fs.String("repo-root", "", "Repository root")
	chartVersion := fs.String("chart-version", "", "Override chart.version")
	chartAppVersion := fs.String("chart-app-version", "", "Override chart.appVersion")
	operatorTrack := fs.String("operator-track", "", "Override operator track version")
	databaseTrack := fs.String("database-track", "", "Override database track version")
	operatorRef := fs.String("operator-ref", "", "Override released operator image ref")
	operatorDigest := fs.String("operator-digest", "", "Override released operator image digest")
	sidecarRef := fs.String("sidecar-ref", "", "Override released sidecar image ref")
	sidecarDigest := fs.String("sidecar-digest", "", "Override released sidecar image digest")
	documentdbRef := fs.String("documentdb-ref", "", "Override released documentdb image ref")
	documentdbDigest := fs.String("documentdb-digest", "", "Override released documentdb image digest")
	gatewayRef := fs.String("gateway-ref", "", "Override released gateway image ref")
	gatewayDigest := fs.String("gateway-digest", "", "Override released gateway image digest")
	postgresRef := fs.String("postgres-ref", "", "Override released postgres image ref")
	postgresDigest := fs.String("postgres-digest", "", "Override released postgres image digest")
	fs.Parse(args)

	manifest := loadManifestOrExit(*manifestPath)
	updatedManifest, err := manifest.WithOverrides(releasepkg.OverrideOptions{
		ChartVersion:     *chartVersion,
		ChartAppVersion:  *chartAppVersion,
		OperatorTrack:    *operatorTrack,
		DatabaseTrack:    *databaseTrack,
		OperatorRef:      *operatorRef,
		OperatorDigest:   *operatorDigest,
		SidecarRef:       *sidecarRef,
		SidecarDigest:    *sidecarDigest,
		DocumentDBRef:    *documentdbRef,
		DocumentDBDigest: *documentdbDigest,
		GatewayRef:       *gatewayRef,
		GatewayDigest:    *gatewayDigest,
		PostgresRef:      *postgresRef,
		PostgresDigest:   *postgresDigest,
	})
	if err != nil {
		exitf("apply overrides: %v", err)
	}
	if err := releasepkg.SyncRepositoryFromManifest(*repoRoot, *manifestPath, updatedManifest); err != nil {
		exitf("sync repository: %v", err)
	}
}

func loadManifestOrExit(path string) *releasepkg.Manifest {
	if path == "" {
		exitf("manifest path is required")
	}
	manifest, err := releasepkg.LoadManifest(path)
	if err != nil {
		exitf("load manifest: %v", err)
	}
	return manifest
}

func writeJSONOrExit(path string, value any) {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		exitf("marshal json: %v", err)
	}
	data = append(data, '\n')

	if path == "" {
		if _, err := os.Stdout.Write(data); err != nil {
			exitf("write stdout: %v", err)
		}
		return
	}

	if err := os.WriteFile(path, data, 0o644); err != nil {
		exitf("write %s: %v", path, err)
	}
}

func exitf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
