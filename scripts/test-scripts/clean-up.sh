#!/bin/bash

# ==============================================================================
# ULTIMATE CLEANUP SCRIPT
#
# This script will FORCE DELETE all resources related to the DocumentDB and
# cert-manager installations, and then COMPLETELY UNINSTALL K3s.
#
# WARNING: THIS IS DESTRUCTIVE AND WILL REMOVE YOUR ENTIRE CLUSTER.
#
# Run this script with sudo: sudo ./nuke_k3s_and_apps.sh
# ==============================================================================

# --- Configuration ---
# Exit on any error
set -e
# Print each command before executing it
set -x

# Namespaces to be deleted
ALL_NAMESPACES="documentdb-preview-ns documentdb-operator cert-manager cnpg-system"

# --- Main Execution ---
echo "### Starting Ultimate Cleanup and K3s Uninstall ###"

# Use the k3s-provided kubectl if available
KUBECTL_CMD="k3s kubectl"
if ! command -v $KUBECTL_CMD &> /dev/null; then
    KUBECTL_CMD="kubectl"
fi

# Set KUBECONFIG to the root-owned one for consistency
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# --- Phase 1: Application Teardown ---
echo "### Phase 1: Removing Kubernetes Application Resources ###"

# Turn off exit-on-error temporarily for deletions that might fail
set +e

# Uninstall Helm releases
helm uninstall documentdb-operator -n documentdb-operator
helm uninstall cert-manager -n cert-manager

# Delete namespaces forcefully
$KUBECTL_CMD delete namespace $ALL_NAMESPACES --force --grace-period=0 --ignore-not-found=true

# Find and patch any stuck Persistent Volumes (PVs) to remove finalizers
echo "--- Finding and fixing any stuck Persistent Volumes (PVs) ---"
STUCK_PVS=$($KUBECTL_CMD get pv -o json | jq -r '.items[] | select(.status.phase == "Released" and .metadata.finalizers != null) | .metadata.name')

if [ -n "$STUCK_PVS" ]; then
    for pv in $STUCK_PVS; do
        echo "Found stuck PV: $pv. Removing finalizers..."
        $KUBECTL_CMD patch pv "$pv" -p '{"metadata":{"finalizers":null}}'
    done
else
    echo "No stuck PVs found."
fi

# Delete all related CRDs
echo "--- Deleting all related Custom Resource Definitions (CRDs) ---"
$KUBECTL_CMD delete crd documentdbs.db.microsoft.com --ignore-not-found=true
$KUBECTL_CMD delete crd backups.postgresql.cnpg.io \
  clusterimagecatalogs.postgresql.cnpg.io \
  clusters.postgresql.cnpg.io \
  databases.postgresql.cnpg.io \
  imagecatalogs.postgresql.cnpg.io \
  poolers.postgresql.cnpg.io \
  publications.postgresql.cnpg.io \
  scheduledbackups.postgresql.cnpg.io \
  subscriptions.postgresql.cnpg.io --ignore-not-found=true
$KUBECTL_CMD delete crd certificates.cert-manager.io \
  certificaterequests.cert-manager.io \
  challenges.acme.cert-manager.io \
  clusterissuers.cert-manager.io \
  issuers.cert-manager.io \
  orders.acme.cert-manager.io --ignore-not-found=true

# Re-enable exit-on-error
set -e

echo "### Phase 1: Application cleanup complete. ###"


# --- Phase 2: K3s Uninstallation ---
echo "### Phase 2: Uninstalling K3s ###"

# Run the official K3s uninstall script
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    echo "--- Running k3s-uninstall.sh ---"
    /usr/local/bin/k3s-uninstall.sh
else
    echo "--- k3s-uninstall.sh not found, skipping. ---"
fi

# Optional: Also run the agent uninstall script in case it exists
if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
    echo "--- Running k3s-agent-uninstall.sh ---"
    /usr/local/bin/k3s-agent-uninstall.sh
fi

echo "--- Removing leftover K3s directories ---"
rm -rf /var/lib/rancher/k3s
rm -rf /etc/rancher/k3s

# Stop printing commands
set +x

echo ""
echo "###########################################"
echo "###      Cleanup Script Finished      ###"
echo "### K3s and all related components    ###"
echo "### have been removed from the system.###"
echo "###########################################"