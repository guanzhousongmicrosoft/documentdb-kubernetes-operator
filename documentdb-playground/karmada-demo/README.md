# Karmada Demo - DocumentDB Operator with Karmada

This demo shows how Karmada can replace Azure Fleet Manager for managing DocumentDB deployments across clusters. We'll use a single AKS cluster to demonstrate the concepts.

## Architecture

- **Member Cluster**: Single AKS cluster in Azure (ready to use)
- **DocumentDB Operator**: Deployed directly, demonstrating Karmada equivalents
- **Karmada Concepts**: Shown through PropagationPolicy examples

## What This Demo Shows

1. **Azure Fleet vs Karmada**: Side-by-side comparison of resource distribution
2. **PropagationPolicy**: How to replace ClusterResourcePlacement 
3. **Multi-Cluster Concepts**: Preparation for true multi-cluster setups

## Prerequisites

- Azure CLI installed and logged in (`az login`)
- kubectl installed
- Helm 3.x installed

## Quick Start

### 1. Create AKS Cluster

```bash
./setup-aks-only.sh
```

This script creates:
- An AKS cluster in Azure with 2 nodes
- Necessary credentials configured

### 2. Deploy DocumentDB Operator

```bash
# Install cert-manager first (required dependency)
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

# Deploy DocumentDB with Karmada concepts demo
./deploy-documentdb-demo.sh
```

This will:
1. Package and deploy the DocumentDB operator
2. Show PropagationPolicy examples (Karmada equivalent of ClusterResourcePlacement)
3. Deploy a sample DocumentDB instance
4. Display multi-cluster concepts

### 3. Test the Deployment

```bash
# Get connection information
./test-connection.sh

# Check operator status
kubectl get deploy -n documentdb-operator

# Check DocumentDB instance
kubectl get documentdb,pods,svc -n documentdb-demo-ns

# Monitor pods
kubectl get pods -n documentdb-demo-ns -w
```

## Configuration

Edit variables at the top of `setup-karmada-demo.sh`:

```bash
RESOURCE_GROUP="karmada-demo-rg"
AKS_CLUSTER_NAME="aks-documentdb-demo"
LOCATION="eastus2"
NODE_COUNT=2
VM_SIZE="Standard_DS3_v2"
```

## Clean Up

```bash
./cleanup-karmada-demo.sh
```

This will:
- Delete the AKS cluster and resource group
- Delete the local Karmada Kind cluster
- Clean up kubectl contexts

## Key Differences from Azure Fleet

| Feature | Azure Fleet | Karmada |
|---------|-------------|---------|
| API Resource | ClusterResourcePlacement | PropagationPolicy |
| Control Plane | Azure-managed | Self-hosted (Kind) |
| Multi-Cloud | Requires kubefleet hack | Native support |
| Service Discovery | fleet-system.svc | MCS API or custom |
| Cloud Agnostic | Limited | Full |

## Next Steps

- Add more member clusters (GKE, EKS, on-prem)
- Implement multi-cluster replication
- Configure Karmada-based service discovery
- Test failover scenarios
