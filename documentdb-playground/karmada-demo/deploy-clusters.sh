#!/usr/bin/env bash
# Deploy 3 AKS clusters for Karmada demo
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AKS_SETUP_SCRIPT="$SCRIPT_DIR/create-cluster.sh"

RESOURCE_GROUP="karmada-demo-rg"
REGIONS=("eastus2" "westus3" "uksouth")
NODE_COUNT=2
NODE_SIZE="Standard_D4s_v5"

echo "=========================================="
echo "Deploying 3 AKS Clusters for Karmada Demo"
echo "=========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Regions: ${REGIONS[@]}"
echo ""

# Create resource group
echo "Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location eastus2 --output none

# Deploy clusters in parallel
echo "Deploying clusters in parallel..."
for region in "${REGIONS[@]}"; do
  CLUSTER_NAME="member-${region}"
  echo "Starting deployment: $CLUSTER_NAME in $region"
  
  (
    "$AKS_SETUP_SCRIPT" \
      --cluster-name "$CLUSTER_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$region" \
      --node-count "$NODE_COUNT" \
      --node-size "$NODE_SIZE" \
      > "/tmp/cluster-${region}.log" 2>&1
    echo "✓ $CLUSTER_NAME deployed successfully"
  ) &
done

# Wait for all deployments to complete
echo ""
echo "Waiting for all cluster deployments to complete..."
wait

echo ""
echo "=========================================="
echo "All clusters deployed successfully!"
echo "=========================================="

# Show deployed clusters
echo ""
echo "Deployed clusters:"
az aks list -g "$RESOURCE_GROUP" --query "[].{Name:name, Location:location, Status:provisioningState}" -o table

echo ""
echo "Next steps:"
echo "1. Set up Karmada control plane: ./setup-karmada.sh"
echo "2. Deploy DocumentDB instances: ./deploy-documentdb.sh"
