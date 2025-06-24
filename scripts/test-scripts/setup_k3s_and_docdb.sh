#!/bin/bash

# ==============================================================================
# All-in-One K3s and DocumentDB Deployment Script
#
# This script assumes a clean system and will:
# 1. Install K3s.
# 2. Configure kubectl access for the non-root user.
# 3. Install and verify cert-manager.
# 4. Install and verify the DocumentDB Operator.
# 5. Deploy a sample DocumentDB cluster.
#
# Run this script with sudo: sudo ./setup_k3s_and_docdb.sh
# ==============================================================================

# --- Configuration & Safety Checks ---
# Stop script on any error
set -e
# Fail on pipeline errors
set -o pipefail

# Check if running as root/sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo."
  exit 1
fi

# Get the original user who ran sudo, for setting file permissions later
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
ORIGINAL_USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)

# Namespaces and release names
CERT_MANAGER_NS="cert-manager"
OPERATOR_NS="documentdb-operator"
DB_NS="documentdb-preview-ns"
DB_NAME="documentdb-preview"

# --- Helper Functions ---
# For colored output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if pods are ready in a namespace based on a label selector.
# Arguments: $1: namespace, $2: label_selector, $3: expected_pod_count
wait_for_pods_ready() {
    local namespace="$1"
    local label_selector="$2"
    local expected_pod_count="$3"
    local timeout=300 # 5 minutes
    local end_time=$((SECONDS + timeout))

    echo -e "${YELLOW}--> Waiting for $expected_pod_count pod(s) with label '$label_selector' in namespace '$namespace' to be ready...${NC}"

    while [ $SECONDS -lt $end_time ]; do
        local ready_pods=$(k3s kubectl get pods -n "$namespace" -l "$label_selector" -o json | \
                           jq '.items[] | select(.status.phase == "Running" and ([.status.containerStatuses[] | .ready] | all))' | \
                           jq -s 'length')

        if [[ "$ready_pods" -eq "$expected_pod_count" ]]; then
            echo -e "${GREEN}--> Success: All $expected_pod_count pod(s) are ready.${NC}"
            return 0
        fi
        sleep 5
        echo -n "."
    done

    echo -e "\n${RED}--> Error: Timed out waiting for pods in namespace '$namespace' to become ready.${NC}"
    k3s kubectl get pods -n "$namespace" -l "$label_selector" # Print final status for debugging
    return 1
}


# --- Main Execution ---

echo -e "${GREEN}=== Starting Full K3s and DocumentDB Deployment ===${NC}"

# Step 1: Check for Prerequisites
echo -e "\n${YELLOW}Step 1: Checking for prerequisites (helm, jq)...${NC}"
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed. Please install helm first.${NC}"
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq first (e.g., sudo apt-get install jq).${NC}"
    exit 1
fi
echo -e "${GREEN}--> Prerequisites found.${NC}"

# Step 2: Install K3s
echo -e "\n${YELLOW}Step 2: Installing K3s...${NC}"
if [ -f /usr/local/bin/k3s ]; then
    echo "--> K3s is already installed, skipping installation."
else
    curl -sfL https://get.k3s.io | sh -
    echo -e "${GREEN}--> K3s installed successfully.${NC}"
    echo "--> Waiting for node to become ready..."
    sleep 15 # Give k3s a moment to start up
fi
k3s kubectl wait --for=condition=Ready node --all --timeout=2m


# Step 3: Configure kubectl for the original user
echo -e "\n${YELLOW}Step 3: Configuring kubectl for user '$ORIGINAL_USER'...${NC}"
mkdir -p "$ORIGINAL_USER_HOME/.kube"
cp /etc/rancher/k3s/k3s.yaml "$ORIGINAL_USER_HOME/.kube/config"
chown "$ORIGINAL_USER:$SUDO_GID" "$ORIGINAL_USER_HOME/.kube/config"
chmod 600 "$ORIGINAL_USER_HOME/.kube/config"
echo -e "${GREEN}--> kubectl configured at $ORIGINAL_USER_HOME/.kube/config${NC}"


# Step 4: Install cert-manager
# Note: From here, we run helm as the original user to avoid permission issues with helm's config
echo -e "\n${YELLOW}Step 4: Installing cert-manager...${NC}"
sudo -u "$ORIGINAL_USER" helm repo add jetstack https://charts.jetstack.io > /dev/null 2>&1 || echo "jetstack repo already exists."
sudo -u "$ORIGINAL_USER" helm repo update > /dev/null
sudo -u "$ORIGINAL_USER" helm install cert-manager jetstack/cert-manager \
  --namespace "$CERT_MANAGER_NS" \
  --create-namespace \
  --set installCRDs=true
wait_for_pods_ready "$CERT_MANAGER_NS" "app.kubernetes.io/instance=cert-manager" 3
echo -e "${GREEN}--> cert-manager installed successfully.${NC}"


# Step 5: Install the DocumentDB Operator
echo -e "\n${YELLOW}Step 5: Installing the DocumentDB Operator...${NC}"
# Handle Docker credential issues that can interfere with OCI registry access
if [ -f "$ORIGINAL_USER_HOME/.docker/config.json" ]; then
    echo -e "${YELLOW}--> Temporarily backing up Docker config to avoid credential issues...${NC}"
    sudo -u "$ORIGINAL_USER" mv "$ORIGINAL_USER_HOME/.docker/config.json" "$ORIGINAL_USER_HOME/.docker/config.json.bak" 2>/dev/null || true
fi

# Install the operator
sudo -u "$ORIGINAL_USER" helm install documentdb-operator oci://ghcr.io/microsoft/documentdb-kubernetes-operator/documentdb-operator \
  --version 0.0.1 \
  --namespace "$OPERATOR_NS" \
  --create-namespace

# Restore Docker config if it was backed up
if [ -f "$ORIGINAL_USER_HOME/.docker/config.json.bak" ]; then
    sudo -u "$ORIGINAL_USER" mv "$ORIGINAL_USER_HOME/.docker/config.json.bak" "$ORIGINAL_USER_HOME/.docker/config.json"
fi

echo -e "${YELLOW}--> Waiting for operator deployment to become available...${NC}"
k3s kubectl wait --for=condition=Available deployment/documentdb-operator -n "$OPERATOR_NS" --timeout=5m
echo -e "${GREEN}--> DocumentDB Operator installed successfully.${NC}"


# Step 6: Deploy a DocumentDB Cluster
echo -e "\n${YELLOW}Step 6: Deploying a sample DocumentDB cluster...${NC}"
cat <<EOF | k3s kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${DB_NS}
---
apiVersion: db.microsoft.com/preview
kind: DocumentDB
metadata:
  name: ${DB_NAME}
  namespace: ${DB_NS}
spec:
  nodeCount: 1
  instancesPerNode: 1
  documentDBImage: ghcr.io/microsoft/documentdb/documentdb-local:16
  resource:
    pvcSize: 10Gi
  publicLoadBalancer:
    enabled: true
EOF
wait_for_pods_ready "$DB_NS" "cnpg.io/cluster=${DB_NAME}" 1
echo -e "${GREEN}--> DocumentDB cluster pod is running successfully.${NC}"

# Stop printing commands
set +x

echo ""
echo "#######################################################"
echo "###      Deployment Script Finished Successfully    ###"
echo "#######################################################"
echo ""
echo "Your DocumentDB cluster '${DB_NAME}' is ready in the '${DB_NS}' namespace."
echo ""
echo "To connect, run kubectl as the '$ORIGINAL_USER' user in a new terminal:"
echo -e "${YELLOW}kubectl port-forward pod/${DB_NAME}-1 10260:10260 -n ${DB_NS}${NC}"
echo ""