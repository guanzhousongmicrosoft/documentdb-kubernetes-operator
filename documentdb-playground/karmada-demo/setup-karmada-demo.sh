#!/usr/bin/env bash
set -euo pipefail

# Setup script for Karmada Demo
# Creates an AKS cluster and installs Karmada locally to manage it

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-karmada-demo-rg}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-documentdb-demo}"
LOCATION="${LOCATION:-eastus2}"
NODE_COUNT="${NODE_COUNT:-2}"
VM_SIZE="${VM_SIZE:-Standard_DS3_v2}"
KARMADA_VERSION="${KARMADA_VERSION:-v1.11.3}"

# Karmada Kind cluster names
KARMADA_HOST_CLUSTER="karmada-host"

echo "======================================="
echo "Karmada Demo Setup"
echo "======================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "AKS Cluster: $AKS_CLUSTER_NAME"
echo "Location: $LOCATION"
echo "Karmada Version: $KARMADA_VERSION"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
for cmd in az kubectl docker helm jq kind; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is not installed. Please install it first."
    exit 1
  fi
done
echo "✓ All prerequisites found"
echo ""

# Check Docker is running
if ! docker info &>/dev/null; then
  echo "Error: Docker is not running. Please start Docker first."
  exit 1
fi
echo "✓ Docker is running"
echo ""

# ============================================================================
# Step 1: Create AKS Cluster
# ============================================================================

echo "======================================="
echo "Step 1: Creating AKS Cluster"
echo "======================================="

# Check if resource group exists
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
  echo "Resource group $RESOURCE_GROUP already exists"
else
  echo "Creating resource group $RESOURCE_GROUP..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
fi

# Check if AKS cluster exists
if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  echo "AKS cluster $AKS_CLUSTER_NAME already exists"
else
  echo "Creating AKS cluster $AKS_CLUSTER_NAME..."
  az aks create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --location "$LOCATION" \
    --node-count "$NODE_COUNT" \
    --node-vm-size "$VM_SIZE" \
    --enable-managed-identity \
    --generate-ssh-keys \
    --network-plugin azure \
    --network-policy azure
  echo "✓ AKS cluster created"
fi

# Get AKS credentials
echo "Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing

echo "✓ AKS cluster ready"
echo ""

# ============================================================================
# Step 2: Install Karmada Control Plane (Local Kind Cluster)
# ============================================================================

echo "======================================="
echo "Step 2: Installing Karmada Control Plane"
echo "======================================="

# Check if Karmada host cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${KARMADA_HOST_CLUSTER}$"; then
  echo "Karmada host cluster already exists"
  read -p "Do you want to delete and recreate it? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting existing Karmada cluster..."
    kind delete cluster --name "$KARMADA_HOST_CLUSTER"
  else
    echo "Using existing cluster"
  fi
fi

# Install karmadactl if not present
if ! command -v karmadactl &>/dev/null; then
  echo "Installing karmadactl..."
  
  # Detect OS and architecture
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
  esac
  
  KARMADA_URL="https://github.com/karmada-io/karmada/releases/download/${KARMADA_VERSION}/kubectl-karmada-${OS}-${ARCH}.tgz"
  
  echo "Downloading karmadactl from $KARMADA_URL"
  curl -sL "$KARMADA_URL" -o /tmp/kubectl-karmada.tgz
  tar -xzf /tmp/kubectl-karmada.tgz -C /tmp
  sudo mv /tmp/kubectl-karmada /usr/local/bin/karmadactl
  sudo chmod +x /usr/local/bin/karmadactl
  rm /tmp/kubectl-karmada.tgz
  
  echo "✓ karmadactl installed"
else
  echo "✓ karmadactl already installed: $(karmadactl version)"
fi

# Initialize Karmada
if ! kind get clusters 2>/dev/null | grep -q "^${KARMADA_HOST_CLUSTER}$"; then
  echo "Initializing Karmada control plane in Kind cluster..."
  # Use --host-cluster-domain to create a Kind-based Karmada
  karmadactl init --kubeconfig="$HOME/.kube/karmada.config" --context="karmada-host"
  
  # Merge the karmada config into main kubeconfig
  if [ -f "$HOME/.kube/karmada.config" ]; then
    KUBECONFIG="$HOME/.kube/config:$HOME/.kube/karmada.config" kubectl config view --flatten > /tmp/merged-config
    mv /tmp/merged-config "$HOME/.kube/config"
    rm "$HOME/.kube/karmada.config"
  fi
  
  echo "✓ Karmada control plane created"
else
  echo "✓ Karmada control plane already running"
fi

# Verify Karmada installation
echo "Verifying Karmada installation..."
kubectl --context "karmada-apiserver" wait --for=condition=available deploy/karmada-controller-manager -n karmada-system --timeout=180s || true
kubectl --context "karmada-apiserver" wait --for=condition=available deploy/karmada-scheduler -n karmada-system --timeout=180s || true

echo "✓ Karmada control plane ready"
echo ""

# ============================================================================
# Step 3: Join AKS Cluster to Karmada
# ============================================================================

echo "======================================="
echo "Step 3: Joining AKS to Karmada"
echo "======================================="

# Get the current context name for AKS (should be set from az aks get-credentials)
AKS_CONTEXT=$(kubectl config current-context)
echo "AKS context: $AKS_CONTEXT"

# Check if cluster is already joined
if kubectl --context karmada-apiserver get cluster "$AKS_CLUSTER_NAME" &>/dev/null; then
  echo "Cluster $AKS_CLUSTER_NAME already joined to Karmada"
else
  echo "Joining AKS cluster to Karmada..."
  
  # Use karmadactl to join the cluster
  karmadactl join "$AKS_CLUSTER_NAME" \
    --cluster-kubeconfig="$HOME/.kube/config" \
    --cluster-context="$AKS_CONTEXT" \
    --karmada-context="karmada-apiserver"
  
  echo "✓ AKS cluster joined to Karmada"
fi

# Wait for cluster to be ready
echo "Waiting for cluster to be ready in Karmada..."
kubectl --context karmada-apiserver wait --for=condition=Ready cluster/"$AKS_CLUSTER_NAME" --timeout=180s

echo "✓ AKS cluster is ready in Karmada"
echo ""

# ============================================================================
# Step 4: Verify Setup
# ============================================================================

echo "======================================="
echo "Step 4: Verification"
echo "======================================="

echo ""
echo "Karmada Member Clusters:"
kubectl --context karmada-apiserver get clusters

echo ""
echo "Karmada System Pods:"
kubectl --context karmada-apiserver get pods -n karmada-system

echo ""
echo "AKS Cluster Nodes:"
kubectl --context "$AKS_CONTEXT" get nodes

echo ""
echo "======================================="
echo "✓ Setup Complete!"
echo "======================================="
echo ""
echo "Next steps:"
echo "  1. Deploy DocumentDB operator: ./deploy-documentdb-with-karmada.sh"
echo "  2. Check member clusters: kubectl --context karmada-apiserver get clusters"
echo "  3. View this guide: cat README.md"
echo ""
echo "Contexts available:"
echo "  - karmada-apiserver: Karmada control plane"
echo "  - karmada-host: Kind cluster running Karmada"
echo "  - $AKS_CONTEXT: AKS member cluster"
echo ""
