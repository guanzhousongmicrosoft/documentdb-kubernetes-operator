#!/usr/bin/env bash
set -euo pipefail

# Deploy DocumentDB operator using Karmada PropagationPolicy

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../../operator/documentdb-helm-chart"

# Configuration
KARMADA_CONTEXT="karmada-apiserver"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-documentdb-demo}"
VERSION="${VERSION:-200}"

echo "======================================="
echo "Deploy DocumentDB with Karmada"
echo "======================================="
echo "Target Cluster: $AKS_CLUSTER_NAME"
echo "Operator Version: 0.0.$VERSION"
echo ""

# Check prerequisites
for cmd in kubectl helm karmadactl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is not installed"
    exit 1
  fi
done

# Verify Karmada context exists
if ! kubectl config get-contexts "$KARMADA_CONTEXT" &>/dev/null; then
  echo "Error: Karmada context '$KARMADA_CONTEXT' not found"
  echo "Please run ./setup-karmada-demo.sh first"
  exit 1
fi

# Verify member cluster is registered
if ! kubectl --context "$KARMADA_CONTEXT" get cluster "$AKS_CLUSTER_NAME" &>/dev/null; then
  echo "Error: Cluster '$AKS_CLUSTER_NAME' not found in Karmada"
  echo "Please run ./setup-karmada-demo.sh first"
  exit 1
fi

echo "✓ Prerequisites verified"
echo ""

# ============================================================================
# Step 1: Package and Deploy Operator
# ============================================================================

echo "======================================="
echo "Step 1: Deploying DocumentDB Operator"
echo "======================================="

# Build/package chart
CHART_PKG="$SCRIPT_DIR/documentdb-operator-0.0.${VERSION}.tgz"
if [ -f "$CHART_PKG" ]; then
  echo "Removing existing chart package..."
  rm -f "$CHART_PKG"
fi

echo "Packaging DocumentDB operator chart..."
helm dependency update "$CHART_DIR"
helm package "$CHART_DIR" --version "0.0.${VERSION}" --destination "$SCRIPT_DIR"

echo "✓ Chart packaged: $CHART_PKG"

# Install operator on Karmada host (it will propagate to members)
echo "Installing operator on Karmada host..."
helm upgrade --install documentdb-operator "$CHART_PKG" \
  --namespace documentdb-operator \
  --kube-context "$KARMADA_CONTEXT" \
  --create-namespace \
  --wait

echo "✓ Operator deployed to Karmada"
echo ""

# ============================================================================
# Step 2: Create PropagationPolicy for Base Resources
# ============================================================================

echo "======================================="
echo "Step 2: Creating PropagationPolicy"
echo "======================================="

cat <<EOF | kubectl --context "$KARMADA_CONTEXT" apply -f -
---
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-base-propagation
  namespace: documentdb-operator
spec:
  resourceSelectors:
    - apiVersion: v1
      kind: Namespace
      name: documentdb-operator
    - apiVersion: v1
      kind: Namespace
      name: cnpg-system
    - apiVersion: v1
      kind: ServiceAccount
      namespace: documentdb-operator
    - apiVersion: v1
      kind: ServiceAccount
      namespace: cnpg-system
    - apiVersion: v1
      kind: Service
      namespace: documentdb-operator
    - apiVersion: v1
      kind: ConfigMap
      namespace: documentdb-operator
    - apiVersion: apps/v1
      kind: Deployment
      namespace: documentdb-operator
  placement:
    clusterAffinity:
      clusterNames:
        - $AKS_CLUSTER_NAME
---
apiVersion: policy.karmada.io/v1alpha1
kind: ClusterPropagationPolicy
metadata:
  name: documentdb-crds-propagation
spec:
  resourceSelectors:
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: documentdbs.db.microsoft.com
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: clusters.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: backups.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: scheduledbackups.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: poolers.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: databases.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: publications.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: subscriptions.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: imagecatalogs.postgresql.cnpg.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: clusterimagecatalogs.postgresql.cnpg.io
    - apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
    - apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
  placement:
    clusterAffinity:
      clusterNames:
        - $AKS_CLUSTER_NAME
EOF

echo "✓ PropagationPolicies created"
echo ""

# ============================================================================
# Step 3: Deploy Sample DocumentDB Instance
# ============================================================================

echo "======================================="
echo "Step 3: Deploying Sample DocumentDB"
echo "======================================="

# Generate password
DB_PASSWORD="Demo$(openssl rand -base64 12 | tr -d '/+=' | head -c 10)!"
echo "Generated password: $DB_PASSWORD"

# Create DocumentDB namespace and resources
cat <<EOF | kubectl --context "$KARMADA_CONTEXT" apply -f -
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

# Create PropagationPolicy for DocumentDB instance
cat <<EOF | kubectl --context "$KARMADA_CONTEXT" apply -f -
---
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-instance-propagation
  namespace: documentdb-demo-ns
spec:
  resourceSelectors:
    - apiVersion: v1
      kind: Namespace
      name: documentdb-demo-ns
    - apiVersion: v1
      kind: Secret
      namespace: documentdb-demo-ns
      name: documentdb-credentials
    - apiVersion: db.microsoft.com/preview
      kind: DocumentDB
      namespace: documentdb-demo-ns
      name: documentdb-demo
  placement:
    clusterAffinity:
      clusterNames:
        - $AKS_CLUSTER_NAME
EOF

echo "✓ DocumentDB PropagationPolicy created"
echo ""

# ============================================================================
# Step 4: Verify Deployment
# ============================================================================

echo "======================================="
echo "Step 4: Verifying Deployment"
echo "======================================="

echo ""
echo "Waiting for resources to propagate (30 seconds)..."
sleep 30

echo ""
echo "Karmada Resources:"
echo "------------------"
kubectl --context "$KARMADA_CONTEXT" get propagationpolicy -A
kubectl --context "$KARMADA_CONTEXT" get clusterpropagationpolicy

echo ""
echo "Member Cluster - Operator Status:"
echo "-----------------------------------"
kubectl --context "$AKS_CLUSTER_NAME" get deploy -n documentdb-operator

echo ""
echo "Member Cluster - DocumentDB Resources:"
echo "---------------------------------------"
kubectl --context "$AKS_CLUSTER_NAME" get documentdb,pods,svc -n documentdb-demo-ns

echo ""
echo "======================================="
echo "✓ Deployment Complete!"
echo "======================================="
echo ""
echo "Connection Information:"
echo "  Namespace: documentdb-demo-ns"
echo "  DocumentDB: documentdb-demo"
echo "  Username: demo_user"
echo "  Password: $DB_PASSWORD"
echo ""
echo "Monitor deployment:"
echo "  kubectl --context $AKS_CLUSTER_NAME get pods -n documentdb-demo-ns -w"
echo ""
echo "Check Karmada resource binding:"
echo "  kubectl --context $KARMADA_CONTEXT get resourcebinding -n documentdb-demo-ns"
echo ""
echo "Get service endpoint (once LoadBalancer is ready):"
echo "  kubectl --context $AKS_CLUSTER_NAME get svc -n documentdb-demo-ns"
echo ""
