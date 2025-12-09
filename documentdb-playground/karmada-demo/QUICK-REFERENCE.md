# Quick Reference: Azure Fleet vs Karmada

## API Equivalence Cheat Sheet

### Basic Resource Propagation

| Azure Fleet | Karmada |
|-------------|---------|
| `ClusterResourcePlacement` | `PropagationPolicy` (namespaced)<br>`ClusterPropagationPolicy` (cluster-scoped) |
| `placementType: PickAll` | `clusterAffinity.clusterNames: [...]` |
| `placementType: PickFixed` | Same as above with specific names |
| `resourceSelectors` | `resourceSelectors` (same concept) |

### Example Side-by-Side

#### Azure Fleet
```yaml
apiVersion: placement.kubernetes-fleet.io/v1beta1
kind: ClusterResourcePlacement
metadata:
  name: my-app
spec:
  resourceSelectors:
    - group: apps
      version: v1
      kind: Deployment
      name: my-app
  policy:
    placementType: PickAll
  strategy:
    type: RollingUpdate
```

#### Karmada Equivalent
```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: my-app
  namespace: default
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      name: my-app
  placement:
    clusterAffinity:
      clusterNames:
        - cluster1
        - cluster2
        - cluster3
```

## Service Discovery Patterns

### Azure Fleet
```
# Pattern
<namespace>-<service-name>.fleet-system.svc

# Example
documentdb-ns-documentdb-demo-rw.fleet-system.svc
```

### Karmada (MCS API)
```
# Pattern
<service-name>.<namespace>.svc.clusterset.local

# Example (after ServiceExport)
documentdb-demo-rw.documentdb-ns.svc.clusterset.local
```

## Advanced Features

### Weighted Distribution (Karmada Only)

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: weighted-distribution
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
  placement:
    clusterAffinity:
      clusterNames:
        - cluster-east
        - cluster-west
    replicaScheduling:
      replicaSchedulingType: Divided
      weightPreference:
        staticWeightList:
          - targetCluster:
              clusterNames: [cluster-east]
            weight: 3
          - targetCluster:
              clusterNames: [cluster-west]
            weight: 1
```

### Label-Based Selection (Karmada Only)

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: label-based
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
  placement:
    clusterAffinity:
      labelSelector:
        matchLabels:
          environment: production
          region: us-east
```

## CLI Commands

### Azure Fleet
```bash
# Get credentials
az fleet get-credentials --resource-group <rg> --name <fleet>

# List members
az fleet member list --fleet-name <fleet> --resource-group <rg>

# Check placement
kubectl get clusterresourceplacement
```

### Karmada
```bash
# Join cluster
karmadactl join <cluster-name> \
  --cluster-context <context> \
  --karmada-context karmada-apiserver

# List clusters
kubectl --context karmada-apiserver get clusters

# Check propagation
kubectl --context karmada-apiserver get propagationpolicy -A
kubectl --context karmada-apiserver get resourcebinding -A
```

## DocumentDB Operator Integration

### Current (Azure Fleet Mode)
```yaml
apiVersion: db.microsoft.com/preview
kind: DocumentDB
metadata:
  name: my-db
spec:
  clusterReplication:
    crossCloudNetworkingStrategy: AzureFleet
    primary: cluster-1
    clusterList:
      - name: cluster-1
      - name: cluster-2
```

### Future (Karmada Mode)
```yaml
apiVersion: db.microsoft.com/preview
kind: DocumentDB
metadata:
  name: my-db
spec:
  clusterReplication:
    crossCloudNetworkingStrategy: Karmada
    primary: cluster-1
    clusterList:
      - name: cluster-1
      - name: cluster-2
```

## Installation Quick Start

### Azure Fleet
```bash
# Create fleet
az fleet create --name my-fleet --resource-group my-rg

# Add AKS member
az fleet member create \
  --name member1 \
  --fleet-name my-fleet \
  --resource-group my-rg \
  --member-cluster-id <aks-id>
```

### Karmada
```bash
# Install karmadactl
curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | bash

# Create local cluster (for testing)
kind create cluster --name karmada-host

# Install Karmada
helm repo add karmada-charts https://raw.githubusercontent.com/karmada-io/karmada/master/charts
helm install karmada karmada-charts/karmada \
  --create-namespace \
  --namespace karmada-system

# Join member cluster
karmadactl join my-cluster \
  --cluster-kubeconfig=$HOME/.kube/config \
  --cluster-context=my-cluster \
  --karmada-context=karmada-apiserver
```

## Decision Matrix

Choose **Azure Fleet** if:
- ✅ Azure-only deployment
- ✅ Want managed control plane
- ✅ Need quick setup
- ✅ Prefer Azure native tools

Choose **Karmada** if:
- ✅ Multi-cloud (AKS + GKE + EKS)
- ✅ Need advanced scheduling
- ✅ Want cloud portability
- ✅ Prefer open standards (CNCF)
- ✅ Need fine-grained control

## Common Operations

| Operation | Azure Fleet | Karmada |
|-----------|-------------|---------|
| View placements | `kubectl get crp` | `kubectl get pp -A` |
| Check status | `kubectl describe crp <name>` | `kubectl get rb -A` |
| Debug | Check Fleet logs in Azure | Check karmada-controller-manager logs |
| Update placement | Patch CRP resource | Patch PropagationPolicy |
| Remove cluster | `az fleet member delete` | `kubectl delete cluster <name>` |

---

**Quick Tip:** Karmada's `PropagationPolicy` is more expressive than Fleet's `ClusterResourcePlacement`, offering better control over resource distribution and scheduling.
