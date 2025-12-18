#!/bin/bash

set -e

# Configuration
RESOURCE_GROUP="karmada-demo-rg"
LOCATION_1="eastus2"
LOCATION_2="westus3"
LOCATION_3="uksouth"
K8S_VERSION="1.33.0"
NODE_SIZE="Standard_D4s_v5"
NODE_COUNT=2

echo "========================================"
echo "Deploying 3 AKS Clusters for Karmada Demo"
echo "========================================"
echo ""

# Create resource group
echo "Creating resource group: $RESOURCE_GROUP"
az group create --name $RESOURCE_GROUP --location $LOCATION_1

# Deploy clusters in parallel
echo ""
echo "Deploying AKS clusters (this will take 5-10 minutes)..."
echo ""

az aks create \
  --resource-group $RESOURCE_GROUP \
  --name member-eastus2 \
  --location $LOCATION_1 \
  --kubernetes-version $K8S_VERSION \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_SIZE \
  --enable-managed-identity \
  --generate-ssh-keys \
  --no-wait &

az aks create \
  --resource-group $RESOURCE_GROUP \
  --name member-westus3 \
  --location $LOCATION_2 \
  --kubernetes-version $K8S_VERSION \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_SIZE \
  --enable-managed-identity \
  --generate-ssh-keys \
  --no-wait &

az aks create \
  --resource-group $RESOURCE_GROUP \
  --name member-uksouth \
  --location $LOCATION_3 \
  --kubernetes-version $K8S_VERSION \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_SIZE \
  --enable-managed-identity \
  --generate-ssh-keys \
  --no-wait &

# Wait for all clusters
echo "Waiting for cluster provisioning to complete..."
az aks wait --created --resource-group $RESOURCE_GROUP --name member-eastus2 &
az aks wait --created --resource-group $RESOURCE_GROUP --name member-westus3 &
az aks wait --created --resource-group $RESOURCE_GROUP --name member-uksouth &
wait

echo ""
echo "✅ All clusters created successfully!"
echo ""

# Get credentials
echo "Getting cluster credentials..."
az aks get-credentials --resource-group $RESOURCE_GROUP --name member-eastus2 --overwrite-existing
az aks get-credentials --resource-group $RESOURCE_GROUP --name member-westus3 --overwrite-existing
az aks get-credentials --resource-group $RESOURCE_GROUP --name member-uksouth --overwrite-existing

echo ""
echo "✅ Credentials configured"
echo ""

# Verify clusters
echo "Cluster Status:"
az aks list -g $RESOURCE_GROUP --query "[].{Name:name, Location:location, Status:provisioningState, K8sVersion:kubernetesVersion}" -o table

echo ""
echo "Kubernetes Contexts:"
kubectl config get-contexts | grep member

echo ""
echo "========================================"
echo "✅ AKS Clusters Ready for Karmada!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Join clusters to Karmada"
echo "2. Install cert-manager on all clusters"
echo "3. Install DocumentDB operator on all clusters"
echo "4. Deploy DocumentDB via Karmada"
