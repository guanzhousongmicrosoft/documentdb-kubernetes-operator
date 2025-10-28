# kubectl-documentdb Plugin

The `kubectl documentdb` plugin provides operational tooling for Azure Cosmos DB for MongoDB (DocumentDB) deployments managed by this operator. It targets day-two operations such as status inspection, event triage, and primary promotion workflows.

## Installation

### Using Pre-built Binaries

Download the latest release from the [GitHub releases page](https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases) for your platform:

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
Expand-Archive kubectl-documentdb.zip
Move-Item kubectl-documentdb\kubectl-documentdb.exe C:\Windows\System32\
```

### Building from Source

```bash
cd plugins/documentdb-kubectl-plugin
make build              # builds kubectl-documentdb for the host platform
make build-all          # creates binaries for all supported platforms
make install            # builds and installs to /usr/local/bin
```

Verify installation with `kubectl documentdb --help`.

## Supported Commands

| Command | Purpose |
| --- | --- |
| `kubectl documentdb status` | Collects cluster-wide health information for a DocumentDB CR across all member clusters. |
| `kubectl documentdb events` | Streams Kubernetes events scoped to a DocumentDB CR, optionally following new events. |
| `kubectl documentdb promote` | Switches the primary cluster in a fleet by patching `spec.clusterReplication.primary` and waiting for convergence. |

Run `kubectl documentdb <command> --help` to review all flags. Key options include:

- `--documentdb`: (required) name of the `DocumentDB` custom resource.
- `--namespace/-n`: namespace containing the resource. Defaults to `documentdb-preview-ns` for all commands.
- `--context`: kubeconfig context to use for hub-level operations (defaults to the current context).
- `--show-connections`: include connection strings in `status` output.
- `--follow/-f`: follow mode for `events` (enabled by default).
- `--since`: limit historical events to a relative duration (for example `--since=1h`).
- `--target-cluster`: target cluster name for `promote` (required).
- `--hub-context` and `--cluster-context`: override hub and target kubeconfig contexts when promoting.

## Kubeconfig Expectations

`status` gathers information from every cluster listed in `spec.clusterReplication.clusterList`. For each entry the plugin attempts to load a kubeconfig context with the same name. Create or rename contexts accordingly so that `kubectl documentdb status` can authenticate to each member cluster.

The plugin never modifies kubeconfig files; it only reads them through `client-go`.

## Output Highlights

- **Status** prints a table containing cluster role, phase, pod readiness, service endpoints, and any retrieval errors per member cluster. Pass `--show-connections` to include the hub-reported primary connection string.
- **Events** prints the latest matching events immediately and switches to watch mode while `--follow` remains true.
- **Promote** patches the DocumentDB resource in the fleet hub, then (unless `--skip-wait` is used) polls both the hub and the target cluster until the reconciliation reports the desired primary cluster.

## Troubleshooting

- Ensure the operator has already synchronized status for the target resource; otherwise `status` may report unknown phases.
- If you see context lookup errors, verify the context name exists via `kubectl config get-contexts` and matches the cluster list entry.
- Promotion waits until `status.status` reports a healthy phase on both hub and target contexts. Use `--poll-interval` and `--wait-timeout` to tune.

## Supported Platforms

The plugin is released for the following platforms and architectures:

- **Linux**: amd64, arm64, arm
- **macOS**: amd64 (Intel), arm64 (Apple Silicon)
- **Windows**: amd64, arm64

All releases include SHA256 checksums for verification.

## Verifying Downloads

Each release includes SHA256 checksums. Verify your download:

```bash
# Download checksum file
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-linux-amd64.tar.gz.sha256

# Verify integrity
sha256sum -c kubectl-documentdb-linux-amd64.tar.gz.sha256
```

## Contributing

The plugin is a standalone Go module located in `plugins/documentdb-kubectl-plugin`. Use the Makefile targets to rebuild after code changes. Unit tests for the plugin should live alongside the command implementations under `plugins/documentdb-kubectl-plugin/cmd`.

For detailed release instructions, see:
- [Plugin README](../plugins/documentdb-kubectl-plugin/README.md)
- [Release Guide](../plugins/documentdb-kubectl-plugin/RELEASE.md)
- [Quick Start](../plugins/documentdb-kubectl-plugin/QUICKSTART.md)
