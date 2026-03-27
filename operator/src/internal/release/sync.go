// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package release

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type yamlUpdate struct {
	file  string
	path  []string
	value string
}

var yamlKeyPattern = regexp.MustCompile(`^([ ]*)([A-Za-z0-9_.-]+):(?:[ ]*(.*))?$`)

// SyncRepositoryFromManifest updates release-controlled files from the canonical manifest.
func SyncRepositoryFromManifest(root, manifestPath string, manifest *Manifest) error {
	if manifest == nil {
		return fmt.Errorf("manifest is required")
	}
	if err := manifest.Validate(); err != nil {
		return err
	}

	operatorRepo, _, err := SplitRef(manifest.Images.Operator.Ref)
	if err != nil {
		return fmt.Errorf("split operator ref: %w", err)
	}
	sidecarRepo, _, err := SplitRef(manifest.Images.Sidecar.Ref)
	if err != nil {
		return fmt.Errorf("split sidecar ref: %w", err)
	}

	operatorDefaultExpression := fmt.Sprintf("${{ inputs.version || '%s' }}", manifest.Channels.OperatorTrack)
	operatorImageTagExpression := fmt.Sprintf("${{ inputs.version || '%s' }}-test", manifest.Channels.OperatorTrack)

	updates := []yamlUpdate{
		{file: manifestPath, path: []string{"chart", "version"}, value: manifest.Chart.Version},
		{file: manifestPath, path: []string{"chart", "appVersion"}, value: manifest.Chart.AppVersion},
		{file: manifestPath, path: []string{"channels", "operatorTrack"}, value: manifest.Channels.OperatorTrack},
		{file: manifestPath, path: []string{"channels", "databaseTrack"}, value: manifest.Channels.DatabaseTrack},
		{file: manifestPath, path: []string{"images", "operator", "ref"}, value: manifest.Images.Operator.Ref},
		{file: manifestPath, path: []string{"images", "operator", "digest"}, value: manifest.Images.Operator.Digest},
		{file: manifestPath, path: []string{"images", "sidecar", "ref"}, value: manifest.Images.Sidecar.Ref},
		{file: manifestPath, path: []string{"images", "sidecar", "digest"}, value: manifest.Images.Sidecar.Digest},
		{file: manifestPath, path: []string{"images", "documentdb", "ref"}, value: manifest.Images.DocumentDB.Ref},
		{file: manifestPath, path: []string{"images", "documentdb", "digest"}, value: manifest.Images.DocumentDB.Digest},
		{file: manifestPath, path: []string{"images", "gateway", "ref"}, value: manifest.Images.Gateway.Ref},
		{file: manifestPath, path: []string{"images", "gateway", "digest"}, value: manifest.Images.Gateway.Digest},
		{file: manifestPath, path: []string{"postgres", "ref"}, value: manifest.Postgres.Ref},
		{file: manifestPath, path: []string{"postgres", "digest"}, value: manifest.Postgres.Digest},

		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "Chart.yaml"), path: []string{"version"}, value: manifest.Chart.Version},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "Chart.yaml"), path: []string{"appVersion"}, value: manifest.Chart.AppVersion},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"documentDbVersion"}, value: manifest.Channels.DatabaseTrack},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"image", "documentdbk8soperator", "ref"}, value: manifest.Images.Operator.Ref},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"image", "documentdbk8soperator", "digest"}, value: manifest.Images.Operator.Digest},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"image", "documentdbk8soperator", "repository"}, value: operatorRepo},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"image", "sidecarinjector", "ref"}, value: manifest.Images.Sidecar.Ref},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"image", "sidecarinjector", "digest"}, value: manifest.Images.Sidecar.Digest},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"image", "sidecarinjector", "repository"}, value: sidecarRepo},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"runtimeDefaults", "documentdb", "ref"}, value: manifest.Images.DocumentDB.Ref},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"runtimeDefaults", "documentdb", "digest"}, value: manifest.Images.DocumentDB.Digest},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"runtimeDefaults", "gateway", "ref"}, value: manifest.Images.Gateway.Ref},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"runtimeDefaults", "gateway", "digest"}, value: manifest.Images.Gateway.Digest},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"runtimeDefaults", "postgres", "ref"}, value: manifest.Postgres.Ref},
		{file: filepath.Join(root, "operator", "documentdb-helm-chart", "values.yaml"), path: []string{"runtimeDefaults", "postgres", "digest"}, value: manifest.Postgres.Digest},

		{file: filepath.Join(root, ".github", "workflows", "build_operator_images.yml"), path: []string{"on", "workflow_dispatch", "inputs", "version", "default"}, value: manifest.Channels.OperatorTrack},
		{file: filepath.Join(root, ".github", "workflows", "build_operator_images.yml"), path: []string{"on", "workflow_call", "inputs", "version", "default"}, value: manifest.Channels.OperatorTrack},
		{file: filepath.Join(root, ".github", "workflows", "build_operator_images.yml"), path: []string{"env", "VERSION"}, value: operatorDefaultExpression},
		{file: filepath.Join(root, ".github", "workflows", "build_operator_images.yml"), path: []string{"env", "IMAGE_TAG"}, value: operatorImageTagExpression},

		{file: filepath.Join(root, ".github", "workflows", "release_operator.yml"), path: []string{"on", "workflow_dispatch", "inputs", "candidate_version", "default"}, value: manifest.Channels.OperatorTrack + "-test"},
		{file: filepath.Join(root, ".github", "workflows", "release_operator.yml"), path: []string{"on", "workflow_dispatch", "inputs", "version", "default"}, value: manifest.Channels.OperatorTrack},
		{file: filepath.Join(root, ".github", "workflows", "release_operator.yml"), path: []string{"on", "workflow_call", "inputs", "candidate_version", "default"}, value: manifest.Channels.OperatorTrack + "-test"},
		{file: filepath.Join(root, ".github", "workflows", "release_operator.yml"), path: []string{"on", "workflow_call", "inputs", "version", "default"}, value: manifest.Channels.OperatorTrack},

		{file: filepath.Join(root, ".github", "workflows", "build_documentdb_images.yml"), path: []string{"on", "workflow_dispatch", "inputs", "version", "default"}, value: manifest.Channels.DatabaseTrack},
		{file: filepath.Join(root, ".github", "workflows", "build_documentdb_images.yml"), path: []string{"on", "workflow_call", "inputs", "version", "default"}, value: manifest.Channels.DatabaseTrack},
		{file: filepath.Join(root, ".github", "workflows", "build_documentdb_images.yml"), path: []string{"env", "DEFAULT_DOCUMENTDB_VERSION"}, value: manifest.Channels.DatabaseTrack},

		{file: filepath.Join(root, ".github", "workflows", "release_documentdb_images.yml"), path: []string{"on", "workflow_dispatch", "inputs", "version", "default"}, value: manifest.Channels.DatabaseTrack},
		{file: filepath.Join(root, ".github", "workflows", "release_documentdb_images.yml"), path: []string{"on", "workflow_call", "inputs", "version", "default"}, value: manifest.Channels.DatabaseTrack},

		{file: filepath.Join(root, ".github", "workflows", "release.yml"), path: []string{"on", "workflow_dispatch", "inputs", "operator_candidate_version", "default"}, value: manifest.Channels.OperatorTrack + "-test"},
		{file: filepath.Join(root, ".github", "workflows", "release.yml"), path: []string{"on", "workflow_dispatch", "inputs", "operator_version", "default"}, value: manifest.Channels.OperatorTrack},
		{file: filepath.Join(root, ".github", "workflows", "release.yml"), path: []string{"on", "workflow_dispatch", "inputs", "database_version", "default"}, value: manifest.Channels.DatabaseTrack},

		{file: filepath.Join(root, ".github", "workflows", "test-upgrade-and-rollback.yml"), path: []string{"env", "RELEASED_DATABASE_VERSION"}, value: manifest.Channels.DatabaseTrack},
	}

	for _, update := range updates {
		if err := updateYAMLScalar(update.file, update.path, update.value); err != nil {
			return err
		}
	}

	gatewaySourceImage := fmt.Sprintf("ARG SOURCE_IMAGE=ghcr.io/documentdb/documentdb/documentdb-local:pg17-%s", manifest.Channels.DatabaseTrack)
	if err := replaceLineWithPrefix(
		filepath.Join(root, ".github", "dockerfiles", "Dockerfile_gateway_public_image"),
		"ARG SOURCE_IMAGE=",
		gatewaySourceImage,
	); err != nil {
		return err
	}

	return nil
}

func updateYAMLScalar(path string, targetPath []string, value string) error {
	contentBytes, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}

	updatedContent, err := updateYAMLScalarContent(string(contentBytes), targetPath, value)
	if err != nil {
		return fmt.Errorf("update %s %s: %w", path, strings.Join(targetPath, "."), err)
	}

	if updatedContent == string(contentBytes) {
		return nil
	}

	if err := os.WriteFile(path, []byte(updatedContent), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}

	return nil
}

func updateYAMLScalarContent(content string, targetPath []string, value string) (string, error) {
	lines := strings.Split(content, "\n")
	var (
		stack       []yamlFrame
		found       bool
		blockIndent = -1
	)

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		indent := len(line) - len(strings.TrimLeft(line, " "))

		if blockIndent >= 0 {
			if trimmed == "" || indent > blockIndent {
				continue
			}
			blockIndent = -1
		}

		if trimmed == "" || strings.HasPrefix(trimmed, "#") || strings.HasPrefix(trimmed, "- ") {
			continue
		}

		matches := yamlKeyPattern.FindStringSubmatch(line)
		if matches == nil {
			continue
		}

		keyIndent := len(matches[1])
		key := matches[2]
		rawValue := matches[3]

		for len(stack) > 0 && keyIndent <= stack[len(stack)-1].indent {
			stack = stack[:len(stack)-1]
		}
		stack = append(stack, yamlFrame{indent: keyIndent, key: key})

		if isBlockScalar(rawValue) {
			blockIndent = keyIndent
		}

		if strings.TrimSpace(rawValue) == "" {
			continue
		}

		if !pathEquals(stack, targetPath) {
			continue
		}

		comment := ""
		valuePortion := strings.TrimSpace(rawValue)
		if idx := strings.Index(valuePortion, " #"); idx >= 0 {
			comment = valuePortion[idx:]
			valuePortion = strings.TrimSpace(valuePortion[:idx])
		}

		formatted := formatYAMLScalar(valuePortion, value)
		updatedLine := fmt.Sprintf("%s%s: %s", matches[1], key, formatted)
		if comment != "" {
			updatedLine += comment
		}
		lines[i] = updatedLine
		found = true
	}

	if !found {
		return "", fmt.Errorf("path %s not found", strings.Join(targetPath, "."))
	}

	return strings.Join(lines, "\n"), nil
}

type yamlFrame struct {
	indent int
	key    string
}

func pathEquals(stack []yamlFrame, target []string) bool {
	if len(stack) != len(target) {
		return false
	}
	for i := range stack {
		if stack[i].key != target[i] {
			return false
		}
	}
	return true
}

func isBlockScalar(value string) bool {
	value = strings.TrimSpace(value)
	return strings.HasPrefix(value, "|") || strings.HasPrefix(value, ">")
}

func formatYAMLScalar(existingValue, replacement string) string {
	switch {
	case strings.HasPrefix(existingValue, "'") && strings.HasSuffix(existingValue, "'"):
		return "'" + strings.ReplaceAll(replacement, "'", "''") + "'"
	case strings.HasPrefix(existingValue, "\"") && strings.HasSuffix(existingValue, "\""):
		return `"` + strings.ReplaceAll(replacement, `"`, `\"`) + `"`
	default:
		return replacement
	}
}

func replaceLineWithPrefix(path, prefix, replacement string) error {
	contentBytes, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}

	lines := strings.Split(string(contentBytes), "\n")
	found := false
	for i, line := range lines {
		if strings.HasPrefix(line, prefix) {
			lines[i] = replacement
			found = true
		}
	}
	if !found {
		return fmt.Errorf("update %s: prefix %q not found", path, prefix)
	}

	updated := strings.Join(lines, "\n")
	if updated == string(contentBytes) {
		return nil
	}
	if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}
