# kubectl-documentdb

A kubectl plugin for managing Azure Cosmos DB for MongoDB (DocumentDB) clusters in Kubernetes.

> **📖 Official Documentation**: For complete command reference and usage details, see the [kubectl-plugin documentation](../../docs/kubectl-plugin.md).

## Features

- **Status Monitoring**: Check the health and status of DocumentDB clusters
- **Event Tracking**: View events and issues for DocumentDB resources
- **Cluster Promotion**: Promote DocumentDB clusters for failover scenarios

## Installation

### Using Pre-built Binaries

Download the latest release for your platform from the [releases page](https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases).

#### Linux (AMD64)
```bash
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-linux-amd64.tar.gz
tar xzf kubectl-documentdb-linux-amd64.tar.gz
chmod +x kubectl-documentdb
sudo mv kubectl-documentdb /usr/local/bin/
```

#### Linux (ARM64)
```bash
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-linux-arm64.tar.gz
tar xzf kubectl-documentdb-linux-arm64.tar.gz
chmod +x kubectl-documentdb
sudo mv kubectl-documentdb /usr/local/bin/
```

#### macOS (Intel)
```bash
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-darwin-amd64.tar.gz
tar xzf kubectl-documentdb-darwin-amd64.tar.gz
chmod +x kubectl-documentdb
sudo mv kubectl-documentdb /usr/local/bin/
```

#### macOS (Apple Silicon)
```bash
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-darwin-arm64.tar.gz
tar xzf kubectl-documentdb-darwin-arm64.tar.gz
chmod +x kubectl-documentdb
sudo mv kubectl-documentdb /usr/local/bin/
```

#### Windows (PowerShell)
```powershell
Invoke-WebRequest -Uri "https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-windows-amd64.zip" -OutFile "kubectl-documentdb.zip"
Expand-Archive -Path kubectl-documentdb.zip -DestinationPath .
Move-Item kubectl-documentdb.exe $env:USERPROFILE\bin\
```

### Building from Source

#### Prerequisites
- Go 1.23.5 or later
- kubectl installed and configured

#### Build and Install
```bash
cd plugins/documentdb-kubectl-plugin
make install
```

Or build for a specific platform:
```bash
make linux/amd64
make darwin/arm64
make windows/amd64
```

Build all platforms:
```bash
make build-all
```

## Usage

The plugin integrates with kubectl and can be used with the `kubectl documentdb` command.

### Check Cluster Status

Get the status of a DocumentDB cluster:
```bash
kubectl documentdb status -n <namespace> <cluster-name>
```

Get status for all clusters in a namespace:
```bash
kubectl documentdb status -n <namespace>
```

Get status for all clusters in all namespaces:
```bash
kubectl documentdb status --all-namespaces
```

### View Events

View events for a specific DocumentDB cluster:
```bash
kubectl documentdb events -n <namespace> <cluster-name>
```

View events with filtering:
```bash
kubectl documentdb events -n <namespace> <cluster-name> --type Warning
```

### Promote a Cluster

Promote a DocumentDB cluster (useful for failover scenarios):
```bash
kubectl documentdb promote -n <namespace> <cluster-name>
```

Promote with force flag:
```bash
kubectl documentdb promote -n <namespace> <cluster-name> --force
```

## Command Reference

### Global Flags

- `-n, --namespace`: Kubernetes namespace (required unless using --all-namespaces)
- `-A, --all-namespaces`: Target all namespaces
- `-v, --verbose`: Enable verbose output
- `--kubeconfig`: Path to kubeconfig file (default: ~/.kube/config)

### Commands

#### `kubectl documentdb status`

Check the status of DocumentDB clusters.

**Flags:**
- `-o, --output`: Output format (json, yaml, wide, table)
- `-w, --watch`: Watch for changes

**Examples:**
```bash
# Get status in JSON format
kubectl documentdb status -n production my-cluster -o json

# Watch status updates
kubectl documentdb status -n production my-cluster --watch

# Get status for all clusters
kubectl documentdb status --all-namespaces
```

#### `kubectl documentdb events`

View events related to DocumentDB resources.

**Flags:**
- `--type`: Filter by event type (Normal, Warning)
- `--since`: Show events from a specific time (e.g., 1h, 30m)
- `--max`: Maximum number of events to show

**Examples:**
```bash
# Show warning events from the last hour
kubectl documentdb events -n production my-cluster --type Warning --since 1h

# Show last 10 events
kubectl documentdb events -n production my-cluster --max 10
```

#### `kubectl documentdb promote`

Promote a DocumentDB cluster.

**Flags:**
- `--force`: Force promotion without confirmation
- `--dry-run`: Preview promotion without executing

**Examples:**
```bash
# Promote with confirmation
kubectl documentdb promote -n production my-cluster

# Force promotion
kubectl documentdb promote -n production my-cluster --force

# Dry run
kubectl documentdb promote -n production my-cluster --dry-run
```

## Development

### Running Tests

```bash
make test
```

### Linting

```bash
make lint
```

### Building for Development

```bash
make dev
```

### Creating a Release

1. Tag the release:
   ```bash
   git tag plugin-v1.0.0
   git push origin plugin-v1.0.0
   ```

2. The GitHub Actions workflow will automatically:
   - Build binaries for all platforms
   - Create release archives
   - Generate checksums
   - Create a GitHub release with all artifacts

### Manual Release Build

```bash
VERSION=1.0.0 make release
```

This creates release artifacts in the `dist/` directory.

## Supported Platforms

- **Linux**: amd64, arm64, arm
- **macOS**: amd64 (Intel), arm64 (Apple Silicon)
- **Windows**: amd64, arm64

## Verifying Downloads

All releases include SHA256 checksums. Verify your download:

```bash
sha256sum -c kubectl-documentdb-linux-amd64.tar.gz.sha256
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for details.

## License

See [LICENSE](../../LICENSE) for details.

## Support

For issues and questions:
- GitHub Issues: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/issues
- Documentation: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/docs
- Official kubectl-plugin docs: [docs/kubectl-plugin.md](../../docs/kubectl-plugin.md)

## Related Projects

- [DocumentDB Kubernetes Operator](../../README.md)
- [DocumentDB Sidecar Injector](../sidecar-injector/README.md)
- [kubectl-plugin Official Documentation](../../docs/kubectl-plugin.md)
