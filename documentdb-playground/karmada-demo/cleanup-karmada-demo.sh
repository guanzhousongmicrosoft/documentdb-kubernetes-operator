#!/usr/bin/env bash
set -euo pipefail

# Cleanup script for Karmada Demo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_GROUP="${RESOURCE_GROUP:-karmada-demo-rg}"
KARMADA_HOST_CLUSTER="karmada-host"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-documentdb-demo}"

echo "======================================="
echo "Karmada Demo Cleanup"
echo "======================================="
echo ""
echo "This will delete:"
echo "  - Kind cluster: $KARMADA_HOST_CLUSTER"
echo "  - AKS cluster: $AKS_CLUSTER_NAME"
echo "  - Resource group: $RESOURCE_GROUP"
echo ""
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled"
  exit 0
fi

echo ""
echo "Starting cleanup..."

# Delete Karmada Kind cluster
if kind get clusters 2>/dev/null | grep -q "^${KARMADA_HOST_CLUSTER}$"; then
  echo "Deleting Karmada Kind cluster..."
  kind delete cluster --name "$KARMADA_HOST_CLUSTER"
  echo "✓ Karmada cluster deleted"
else
  echo "Karmada cluster not found, skipping"
fi

# Delete AKS and resource group
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
  echo "Deleting Azure resource group (this may take several minutes)..."
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  echo "✓ Resource group deletion initiated"
  echo "  (deletion continues in background)"
else
  echo "Resource group not found, skipping"
fi

# Clean up kubectl contexts
echo "Cleaning up kubectl contexts..."
kubectl config delete-context "karmada-apiserver" 2>/dev/null || true
kubectl config delete-context "karmada-host" 2>/dev/null || true
kubectl config delete-context "$AKS_CLUSTER_NAME" 2>/dev/null || true

# Clean up generated files
echo "Cleaning up generated files..."
rm -f "$SCRIPT_DIR"/*.tgz

echo ""
echo "======================================="
echo "✓ Cleanup Complete!"
echo "======================================="
echo ""
echo "Note: Azure resource deletion continues in the background."
echo "Check status with: az group show --name $RESOURCE_GROUP"
echo ""
