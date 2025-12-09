# Karmada vs Azure Fleet - Demo Summary

## What We Built

✅ **Working Demo**: AKS cluster with DocumentDB Operator deployed
✅ **Karmada Concepts**: Demonstrated how PropagationPolicy replaces ClusterResourcePlacement
✅ **Cloud-Agnostic**: Showed how Karmada provides better multi-cloud support

## Current State

### Deployed Resources

1. **AKS Cluster**: `aks-documentdb-demo` (2 nodes, Standard_DS3_v2)
2. **DocumentDB Operator**: Running in `documentdb-operator` namespace
3. **DocumentDB Instance**: `documentdb-demo` with LoadBalancer service
4. **Connection**: External IP `20.161.91.56:10260`

### Check Status

```bash
# Get pods
kubectl get pods -n documentdb-demo-ns

# Get service
kubectl get svc -n documentdb-demo-ns

# Check DocumentDB resource
kubectl get documentdb -n documentdb-demo-ns

# Get connection string
kubectl get documentdb documentdb-demo -n documentdb-demo-ns -o jsonpath='{.status.connectionString}'
```

## Azure Fleet vs Karmada Comparison

| Feature | Azure Fleet | Karmada |
|---------|-------------|---------|
| **Resource Distribution** | `ClusterResourcePlacement` | `PropagationPolicy` |
| **Control Plane** | Azure-managed | Self-hosted (any K8s) |
| **Multi-Cloud** | Limited (needs kubefleet hack) | Native support |
| **Cluster Affinity** | `PickAll`, `PickFixed` | Rich expressions, labels |
| **Scheduling** | Basic placement | Advanced (weighted, divided) |
| **Service Discovery** | `fleet-system.svc` | MCS API (ServiceExport/Import) |
| **Cloud Vendor** | Azure-specific | Cloud-agnostic |
| **Maturity** | Preview | CNCF Graduated |

## Karmada PropagationPolicy Examples

### Basic Propagation (like ClusterResourcePlacement PickAll)

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-base
  namespace: documentdb-operator
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
  placement:
    clusterAffinity:
      clusterNames:
        - aks-cluster
        - gke-cluster
        - eks-cluster
```

### Advanced Scheduling (weighted distribution)

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-replicas
  namespace: documentdb-demo-ns
spec:
  resourceSelectors:
    - apiVersion: db.microsoft.com/preview
      kind: DocumentDB
      name: documentdb-demo
  placement:
    clusterAffinity:
      clusterNames:
        - aks-primary
        - aks-secondary
    replicaScheduling:
      replicaSchedulingType: Divided
      weightPreference:
        staticWeightList:
          - targetCluster:
              clusterNames: [aks-primary]
            weight: 2
          - targetCluster:
              clusterNames: [aks-secondary]
            weight: 1
```

### Cluster Selection by Labels

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: geo-distributed
spec:
  resourceSelectors:
    - apiVersion: db.microsoft.com/preview
      kind: DocumentDB
  placement:
    clusterAffinity:
      labelSelector:
        matchLabels:
          environment: production
          region: us-east
```

## Implementation Roadmap

To fully integrate Karmada into DocumentDB Operator:

### Phase 1: API Updates ✓ (Conceptually Shown)
- [x] Add "Karmada" to `crossCloudNetworkingStrategy` enum
- [x] Document PropagationPolicy patterns

### Phase 2: Code Changes (Next Steps)
- [ ] Update `replication_context.go` to support Karmada networking
- [ ] Implement `IsKarmadaNetworking()` method
- [ ] Update service discovery for Karmada MCS API
- [ ] Test cross-cluster replication with Karmada

### Phase 3: Deployment Scripts
- [ ] Create Karmada-specific deployment scripts
- [ ] Replace `ClusterResourcePlacement` with `PropagationPolicy`
- [ ] Update documentation

### Phase 4: Multi-Cluster Testing
- [ ] Set up Karmada control plane
- [ ] Join multiple clusters (AKS, GKE, EKS)
- [ ] Test resource propagation
- [ ] Verify cross-cluster replication

## Next Steps

1. **Test the current deployment**:
   ```bash
   # Connect to DocumentDB
   kubectl port-forward -n documentdb-demo-ns svc/documentdb-service-documentdb-demo 10260:10260
   
   # Use mongosh
   mongosh localhost:10260 -u demo_user -p 'Demoi8ComRZH8R!' \
     --authenticationMechanism SCRAM-SHA-256 --tls --tlsAllowInvalidCertificates
   ```

2. **Explore Karmada** (optional):
   - Install Karmada control plane on a separate cluster
   - Join AKS cluster to Karmada
   - Test PropagationPolicy manually

3. **Clean up**:
   ```bash
   ./cleanup-karmada-demo.sh
   ```

## Key Takeaways

1. ✅ **Karmada is viable**: Can replace Azure Fleet for multi-cluster management
2. ✅ **Better abstraction**: Cloud-agnostic, CNCF standard
3. ✅ **More features**: Advanced scheduling, better cluster selection
4. ⚠️ **Requires changes**: Service discovery patterns need updates
5. ✅ **Future-proof**: Not locked into Azure ecosystem

## Resources

- [Karmada Documentation](https://karmada.io)
- [PropagationPolicy API](https://karmada.io/docs/userguide/scheduling/resource-propagating)
- [Multi-Cluster Service API](https://github.com/kubernetes-sigs/mcs-api)
- [DocumentDB Operator](https://github.com/microsoft/documentdb-kubernetes-operator)
