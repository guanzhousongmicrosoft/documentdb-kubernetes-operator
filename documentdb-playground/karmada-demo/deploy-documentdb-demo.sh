#!/usr/bin/env bash
set -euo pipefail

# Deploy DocumentDB on AKS and show Karmada equivalents

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../../operator/documentdb-helm-chart"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-documentdb-demo}"
VERSION="${VERSION:-200}"

echo "======================================="
echo "DocumentDB Demo on AKS"
echo "======================================="
echo "Cluster: $AKS_CLUSTER_NAME"
echo ""

# Check cluster access
if ! kubectl get nodes &>/dev/null; then
  echo "Error: Cannot access cluster. Run ./setup-aks-only.sh first"
  exit 1
fi

echo "✓ Cluster access verified"
echo ""

# ============================================================================
# Step 1: Deploy DocumentDB Operator
# ============================================================================

echo "======================================="
echo "Step 1: Deploying DocumentDB Operator"
echo "======================================="

# Package chart
CHART_PKG="$SCRIPT_DIR/documentdb-operator-0.0.${VERSION}.tgz"
if [ -f "$CHART_PKG" ]; then
  rm -f "$CHART_PKG"
fi

echo "Packaging DocumentDB operator chart..."
helm dependency update "$CHART_DIR"
helm package "$CHART_DIR" --version "0.0.${VERSION}" --destination "$SCRIPT_DIR"

echo "Installing operator..."
helm upgrade --install documentdb-operator "$CHART_PKG" \
  --namespace documentdb-operator \
  --create-namespace \
  --wait

echo "✓ Operator deployed"
echo ""

# ============================================================================
# Step 2: Show Karmada Equivalent (Conceptual)
# ============================================================================

echo "======================================="
echo "Karmada Concept: PropagationPolicy"
echo "======================================="
echo ""
echo "With Azure Fleet, you use ClusterResourcePlacement."
echo "With Karmada, you would use PropagationPolicy."
echo ""
echo "Example PropagationPolicy (not applied, just shown):"
echo "---"
cat <<'EOF'
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-operator-propagation
  namespace: documentdb-operator
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      namespace: documentdb-operator
    - apiVersion: v1
      kind: Service
      namespace: documentdb-operator
  placement:
    clusterAffinity:
      clusterNames:
        - aks-documentdb-demo
        - gke-cluster
        - eks-cluster
EOF
echo "---"
echo ""

# ============================================================================
# Step 3: Deploy DocumentDB Instance
# ============================================================================

echo "======================================="
echo "Step 2: Deploying DocumentDB Instance"
echo "======================================="

# Generate password
DB_PASSWORD="Demo$(openssl rand -base64 12 | tr -d '/+=' | head -c 10)!"
echo "Generated password: $DB_PASSWORD"

# Create resources
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: documentdb-demo-ns
---
apiVersion: v1
kind: Secret
metadata:
  name: documentdb-credentials
  namespace: documentdb-demo-ns
type: Opaque
stringData:
  username: demo_user
  password: $DB_PASSWORD
---
apiVersion: db.microsoft.com/preview
kind: DocumentDB
metadata:
  name: documentdb-demo
  namespace: documentdb-demo-ns
spec:
  nodeCount: 1
  instancesPerNode: 1
  documentDBImage: ghcr.io/microsoft/documentdb/documentdb-local:16
  gatewayImage: ghcr.io/microsoft/documentdb/documentdb-local:16
  resource:
    storage:
      pvcSize: 10Gi
  environment: aks
  exposeViaService:
    serviceType: LoadBalancer
  logLevel: info
EOF

echo "✓ DocumentDB resources created"
echo ""

# ============================================================================
# Step 4: Show Multi-Cluster Karmada Concepts
# ============================================================================

echo "======================================="
echo "Multi-Cluster Karmada Concepts"
echo "======================================="
echo ""
echo "For multi-cluster setup with Karmada, you would:"
echo ""
echo "1. Install Karmada control plane (hub cluster)"
echo "2. Join member clusters (AKS, GKE, EKS)"
echo "3. Use PropagationPolicy for base resources (CRDs, RBAC)"
echo "4. Use PropagationPolicy for DocumentDB instances"
echo ""
echo "Example multi-cluster PropagationPolicy:"
echo "---"
cat <<'EOF'
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-multi-cluster
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
        - gke-us-west
    replicaScheduling:
      replicaDivisionPreference: Weighted
      replicaSchedulingType: Divided
      weightPreference:
        staticWeightList:
          - targetCluster:
              clusterNames:
                - aks-primary
            weight: 2
          - targetCluster:
              clusterNames:
                - aks-secondary
            weight: 1
EOF
echo "---"
echo ""

# ============================================================================
# Step 5: Verify Deployment
# ============================================================================

echo "======================================="
echo "Verification"
echo "======================================="
echo ""
echo "Waiting for DocumentDB to be ready (this may take a few minutes)..."
sleep 10

echo ""
echo "Operator Status:"
kubectl get deploy -n documentdb-operator

echo ""
echo "DocumentDB Resources:"
kubectl get documentdb,pods,svc -n documentdb-demo-ns

echo ""
echo "======================================="
echo "✓ Demo Complete!"
echo "======================================="
echo ""
echo "Connection Information:"
echo "  Username: demo_user"
echo "  Password: $DB_PASSWORD"
echo ""
echo "Monitor deployment:"
echo "  kubectl get pods -n documentdb-demo-ns -w"
echo ""
echo "Get LoadBalancer IP (once ready):"
echo "  kubectl get svc -n documentdb-demo-ns"
echo ""
echo "Key Differences - Azure Fleet vs Karmada:"
echo "  Fleet: ClusterResourcePlacement → Karmada: PropagationPolicy"
echo "  Fleet: Azure-only → Karmada: Cloud-agnostic"
echo "  Fleet: fleet-system.svc → Karmada: Multi-Cluster Service API"
echo ""
echo "Cleanup:"
echo "  ./cleanup-karmada-demo.sh"
echo ""
