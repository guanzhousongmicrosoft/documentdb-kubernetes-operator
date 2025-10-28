# kubectl-documentdb Quick Start

Get started with the kubectl-documentdb plugin in 5 minutes.

> **📖 Complete Documentation**: For full command reference and detailed usage, see the [official kubectl-plugin documentation](../../docs/kubectl-plugin.md).

## Installation

Choose your platform and run the appropriate commands:

### macOS (Apple Silicon)
```bash
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-darwin-arm64.tar.gz
tar xzf kubectl-documentdb-darwin-arm64.tar.gz
chmod +x kubectl-documentdb
sudo mv kubectl-documentdb /usr/local/bin/
```

### macOS (Intel)
```bash
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-darwin-amd64.tar.gz
tar xzf kubectl-documentdb-darwin-amd64.tar.gz
chmod +x kubectl-documentdb
sudo mv kubectl-documentdb /usr/local/bin/
```

### Linux
```bash
curl -LO https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-linux-amd64.tar.gz
tar xzf kubectl-documentdb-linux-amd64.tar.gz
chmod +x kubectl-documentdb
sudo mv kubectl-documentdb /usr/local/bin/
```

### Windows (PowerShell - Run as Administrator)
```powershell
Invoke-WebRequest -Uri "https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases/latest/download/kubectl-documentdb-windows-amd64.zip" -OutFile "kubectl-documentdb.zip"
Expand-Archive kubectl-documentdb.zip
Move-Item kubectl-documentdb\kubectl-documentdb.exe C:\Windows\System32\
```

## Verify Installation

```bash
kubectl documentdb version
```

You should see output like:
```
kubectl-documentdb version v1.0.0
```

## Basic Usage

### 1. Check Cluster Status

View the status of your DocumentDB clusters:

```bash
# Single cluster
kubectl documentdb status -n production my-documentdb-cluster

# All clusters in a namespace
kubectl documentdb status -n production

# All clusters across all namespaces
kubectl documentdb status --all-namespaces
```

### 2. Monitor Events

Watch events related to DocumentDB resources:

```bash
# View recent events
kubectl documentdb events -n production my-documentdb-cluster

# Watch events in real-time
kubectl documentdb events -n production my-documentdb-cluster --watch

# Filter warning events
kubectl documentdb events -n production my-documentdb-cluster --type Warning
```

### 3. Promote a Cluster

Promote a DocumentDB cluster for failover scenarios:

```bash
# Promote with interactive confirmation
kubectl documentdb promote -n production my-documentdb-cluster

# Force promotion without confirmation
kubectl documentdb promote -n production my-documentdb-cluster --force

# Dry run to preview changes
kubectl documentdb promote -n production my-documentdb-cluster --dry-run
```

## Common Workflows

### Health Check

Quickly check if all your DocumentDB clusters are healthy:

```bash
kubectl documentdb status --all-namespaces -o wide
```

### Troubleshooting

When a cluster is having issues:

```bash
# Check current status
kubectl documentdb status -n production problem-cluster -o json

# Review recent events
kubectl documentdb events -n production problem-cluster --since 1h

# Watch for new events
kubectl documentdb events -n production problem-cluster --watch
```

### Failover

To perform a manual failover:

```bash
# Preview the promotion
kubectl documentdb promote -n production secondary-cluster --dry-run

# Execute the promotion
kubectl documentdb promote -n production secondary-cluster
```

## Output Formats

The plugin supports multiple output formats:

```bash
# Table format (default)
kubectl documentdb status -n production my-cluster

# JSON for scripting
kubectl documentdb status -n production my-cluster -o json

# YAML
kubectl documentdb status -n production my-cluster -o yaml

# Wide format (more details)
kubectl documentdb status -n production my-cluster -o wide
```

## Tips & Tricks

### Use Aliases

Create an alias for faster access:

```bash
# Add to ~/.bashrc or ~/.zshrc
alias kdoc='kubectl documentdb'

# Usage
kdoc status -n production my-cluster
kdoc events -n production my-cluster
```

### Watch Mode

Monitor cluster status continuously:

```bash
kubectl documentdb status -n production my-cluster --watch
```

### Namespace Shortcuts

Set a default namespace:

```bash
kubectl config set-context --current --namespace=production

# Now you can omit -n flag
kubectl documentdb status my-cluster
```

### JSON Processing with jq

Combine with jq for advanced filtering:

```bash
# Get cluster health status
kubectl documentdb status -n production my-cluster -o json | jq '.status.health'

# List all cluster names
kubectl documentdb status --all-namespaces -o json | jq -r '.items[].metadata.name'
```

## Getting Help

### Built-in Help

```bash
# General help
kubectl documentdb --help

# Command-specific help
kubectl documentdb status --help
kubectl documentdb events --help
kubectl documentdb promote --help
```

### Command Completion

Enable shell completion for faster typing:

```bash
# Bash
kubectl documentdb completion bash > /etc/bash_completion.d/kubectl-documentdb

# Zsh
kubectl documentdb completion zsh > "${fpath[1]}/_kubectl-documentdb"

# Fish
kubectl documentdb completion fish > ~/.config/fish/completions/kubectl-documentdb.fish
```

## Next Steps

- Read the [official kubectl-plugin documentation](../../docs/kubectl-plugin.md)
- Read the [full README](README.md)
- Check out [example deployments](../../scripts/deployment-examples/)
- Learn about [DocumentDB Kubernetes Operator](../../README.md)

## Troubleshooting

### Plugin Not Found

If you get "kubectl: unknown command", ensure:
1. Binary is named exactly `kubectl-documentdb` (or `kubectl-documentdb.exe` on Windows)
2. Binary is in your PATH
3. Binary has execute permissions (Unix/Linux/macOS)

```bash
# Check if in PATH
which kubectl-documentdb

# Check permissions
ls -l $(which kubectl-documentdb)

# Fix permissions if needed
chmod +x /usr/local/bin/kubectl-documentdb
```

### Connection Issues

If the plugin can't connect to your cluster:

```bash
# Verify kubectl access
kubectl get nodes

# Check current context
kubectl config current-context

# Use specific kubeconfig
kubectl documentdb status -n production my-cluster --kubeconfig=/path/to/config
```

## Support

- **Issues**: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/issues
- **Documentation**: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/docs
- **Releases**: https://github.com/guanzhousongmicrosoft/documentdb-kubernetes-operator/releases
