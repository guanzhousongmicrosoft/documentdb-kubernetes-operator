# kubectl-documentdb Release Guide

This guide explains how to release the kubectl-documentdb plugin for multiple platforms and architectures.

## Release Process

### 1. Automated Release (Recommended)

The easiest way to create a release is using the automated GitHub Actions workflow.

#### Option A: Release via Git Tag

1. **Update Version** (if needed):
   ```bash
   # No code changes needed - version is set from the tag
   ```

2. **Create and Push Tag**:
   ```bash
   git tag plugin-v1.0.0
   git push origin plugin-v1.0.0
   ```

3. **Monitor the Release**:
   - Go to: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/actions
   - Watch the "Release kubectl-documentdb Plugin" workflow
   - Once complete, check the releases page

#### Option B: Manual Workflow Dispatch

1. Go to: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/actions
2. Select "Release kubectl-documentdb Plugin" workflow
3. Click "Run workflow"
4. Enter the version (e.g., `v1.0.0`)
5. Click "Run workflow" button

### 2. What Gets Built

The release workflow automatically builds binaries for:

- **Linux**:
  - `kubectl-documentdb-linux-amd64.tar.gz` (Intel/AMD 64-bit)
  - `kubectl-documentdb-linux-arm64.tar.gz` (ARM 64-bit)
  - `kubectl-documentdb-linux-arm.tar.gz` (ARM 32-bit)

- **macOS**:
  - `kubectl-documentdb-darwin-amd64.tar.gz` (Intel Macs)
  - `kubectl-documentdb-darwin-arm64.tar.gz` (Apple Silicon)

- **Windows**:
  - `kubectl-documentdb-windows-amd64.zip` (64-bit)
  - `kubectl-documentdb-windows-arm64.zip` (ARM64)

Each archive includes:
- Binary executable
- SHA256 checksum file
- Installation instructions

### 3. Manual/Local Release

For testing or custom builds:

#### Build All Platforms

```bash
cd plugins/documentdb-kubectl-plugin
VERSION=1.0.0 make release
```

This creates artifacts in `dist/`:
```
dist/
├── kubectl-documentdb-linux-amd64.tar.gz
├── kubectl-documentdb-linux-amd64.tar.gz.sha256
├── kubectl-documentdb-darwin-arm64.tar.gz
├── kubectl-documentdb-darwin-arm64.tar.gz.sha256
└── ...
```

#### Build for Specific Platform

```bash
# macOS Apple Silicon
make darwin/arm64

# Linux AMD64
make linux/amd64

# Windows
make windows/amd64
```

### 4. Testing a Release

Before creating a public release, test the binaries:

#### Test Local Build

```bash
# Build for your platform
make dev

# Run the binary
./kubectl-documentdb version
./kubectl-documentdb --help
```

#### Test Cross-Platform Build

```bash
# Build for specific platform
make linux/amd64

# Extract and test (on Linux)
cd dist
tar xzf kubectl-documentdb-linux-amd64.tar.gz
./kubectl-documentdb-linux-amd64 version
```

#### Test with kubectl

```bash
# Install locally
make install

# Test as kubectl plugin
kubectl documentdb version
kubectl documentdb --help
```

### 5. Release Checklist

Before releasing:

- [ ] All tests pass (`make test`)
- [ ] Code is linted (`make lint`)
- [ ] Version number follows semantic versioning (vX.Y.Z)
- [ ] CHANGELOG.md is updated (if exists)
- [ ] README.md is up to date
- [ ] Build succeeds for all platforms (`make build-all`)
- [ ] Local testing completed
- [ ] Git tag follows format: `plugin-vX.Y.Z`

### 6. Post-Release Tasks

After the release is published:

1. **Verify GitHub Release**:
   - Check all artifacts are attached
   - Verify checksums are included
   - Test download links

2. **Update Documentation**:
   - Update main README.md with new version
   - Update installation instructions if needed

3. **Announce Release**:
   - Create release notes highlighting new features
   - Update any external documentation

### 7. Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **Major (v2.0.0)**: Breaking changes
- **Minor (v1.1.0)**: New features, backward compatible
- **Patch (v1.0.1)**: Bug fixes, backward compatible

### 8. Troubleshooting

#### Build Fails for Specific Platform

Check platform-specific issues:
```bash
# Test build locally with verbose output
GOOS=linux GOARCH=arm64 go build -v -o kubectl-documentdb .
```

#### Workflow Fails

1. Check GitHub Actions logs
2. Verify go.mod dependencies are up to date
3. Ensure all required secrets are configured

#### Binary Doesn't Run

1. Check binary is executable: `chmod +x kubectl-documentdb`
2. Verify architecture matches: `file kubectl-documentdb`
3. Check dependencies: `ldd kubectl-documentdb` (Linux)

### 9. Emergency Rollback

If a release has critical issues:

1. **Delete the GitHub Release**:
   - Go to Releases page
   - Click "Delete" on the problematic release

2. **Delete the Git Tag**:
   ```bash
   git tag -d plugin-v1.0.0
   git push origin :refs/tags/plugin-v1.0.0
   ```

3. **Fix the Issue and Re-release**:
   - Create a patch version (e.g., v1.0.1)
   - Follow the release process again

### 10. CI/CD Workflow Details

The `.github/workflows/release-kubectl-plugin.yml` workflow:

1. **Triggers**:
   - Git tag push matching `plugin-v*.*.*`
   - Manual workflow dispatch

2. **Build Job** (runs for each platform):
   - Sets up Go environment
   - Builds binary with version info
   - Creates platform-specific archive
   - Generates SHA256 checksum
   - Uploads as artifact

3. **Release Job**:
   - Downloads all artifacts
   - Creates GitHub Release
   - Attaches all binaries and checksums
   - Generates installation instructions
   - Creates release notes

### 11. Local Development

For active development:

```bash
# Quick build without version info
make dev

# Build and install locally
make install

# Run tests continuously
watch -n 2 make test
```

### 12. Custom Build Flags

Override build parameters:

```bash
# Custom version
VERSION=1.2.3-beta make build-all

# With debug symbols (larger binary)
LDFLAGS="" make build

# Specific output directory
BUILD_DIR=releases make build-all
```

## Quick Reference

```bash
# Create release
git tag plugin-v1.0.0 && git push origin plugin-v1.0.0

# Build all platforms locally
VERSION=1.0.0 make release

# Test local build
make dev && ./kubectl-documentdb version

# Install for development
make install
```

## Support

For questions or issues with the release process:
- Open an issue: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/issues
- Check workflow runs: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/actions
