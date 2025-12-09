#!/usr/bin/env bash
set -euo pipefail

# Simple AKS setup for Karmada demo

RESOURCE_GROUP="${RESOURCE_GROUP:-karmada-demo-rg}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-documentdb-demo}"
LOCATION="${LOCATION:-eastus2}"
NODE_COUNT="${NODE_COUNT:-2}"
VM_SIZE="${VM_SIZE:-Standard_DS3_v2}"

echo "==============================================="
echo "Setting up AKS Cluster for Karmada Demo"
echo "==============================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "AKS Cluster: $AKS_CLUSTER_NAME"
echo "Location: $LOCATION"
echo ""

# Check prerequisites
for cmd in az kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is not installed"
    exit 1
  fi
done

# Create resource group
if az group show --name "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  echo "✓ Resource group $RESOURCE_GROUP exists"
else
  echo "Creating resource group..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
fi

# Create AKS cluster
if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  echo "✓ AKS cluster $AKS_CLUSTER_NAME exists"
else
  echo "Creating AKS cluster (this takes 5-10 minutes)..."
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
fi

# Get credentials
echo "Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing

# Verify
echo ""
echo "==============================================="
echo "✓ Setup Complete!"
echo "==============================================="
echo ""
echo "Cluster: $AKS_CLUSTER_NAME"
echo "Context: $AKS_CLUSTER_NAME"
echo ""
kubectl get nodes
echo ""
echo "Next: ./deploy-documentdb-demo.sh"
echo ""
