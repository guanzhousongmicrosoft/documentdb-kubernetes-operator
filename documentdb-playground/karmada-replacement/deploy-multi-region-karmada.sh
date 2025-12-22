#!/usr/bin/env bash
set -euo pipefail

# Deploy multi-cluster DocumentDB via Karmada
# Usage: ./deploy-multi-region-karmada.sh [password]
#
# Env vars:
#   KARMADA_KUBECONFIG: kubeconfig for Karmada API server (default: /etc/karmada/karmada-apiserver.config)
#   DOCUMENTDB_PASSWORD: database password (generated if empty)
#   PREFERRED_PRIMARY_REGEX: regex to pick primary (default: eastus2)
#
# This mirrors the Azure Fleet workflow but targets Karmada:
# - Discover member clusters from Karmada
# - Pick a primary cluster
# - Create per-cluster identity ConfigMaps (name/region) using member contexts
# - Apply DocumentDB manifest + Karmada propagation policy through the Karmada API server
# - Verify propagation and per-cluster status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KARMADA_KUBECONFIG="${KARMADA_KUBECONFIG:-/etc/karmada/karmada-apiserver.config}"
PREFERRED_PRIMARY_REGEX="${PREFERRED_PRIMARY_REGEX:-eastus2}"

# Password handling
DOCUMENTDB_PASSWORD="${1:-${DOCUMENTDB_PASSWORD:-}}"
if [ -z "$DOCUMENTDB_PASSWORD" ]; then
  echo "No password provided. Generating a secure password..."
  DOCUMENTDB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
  echo "Generated password: $DOCUMENTDB_PASSWORD"
  echo "(Save this password for client connections)"
  echo ""
fi
export DOCUMENTDB_PASSWORD

# Discover member clusters from Karmada
echo "Discovering member clusters from Karmada..."
CLUSTER_JSON=$(kubectl --kubeconfig "$KARMADA_KUBECONFIG" get clusters -o json)
CLUSTER_ARRAY=($(echo "$CLUSTER_JSON" | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | .metadata.name' | sort))

if [ ${#CLUSTER_ARRAY[@]} -eq 0 ]; then
  echo "Error: no Ready clusters found in Karmada. Join clusters before deploying."
  exit 1
fi

echo "Found ${#CLUSTER_ARRAY[@]} clusters:" 
for c in "${CLUSTER_ARRAY[@]}"; do echo "  - $c"; done

# Select primary cluster (prefer regex match, else first)
PRIMARY_CLUSTER=""
for cluster in "${CLUSTER_ARRAY[@]}"; do
  if [[ "$cluster" =~ $PREFERRED_PRIMARY_REGEX ]]; then
    PRIMARY_CLUSTER="$cluster"
    break
  fi
done
if [ -z "$PRIMARY_CLUSTER" ]; then
  PRIMARY_CLUSTER="${CLUSTER_ARRAY[0]}"
fi

echo "Selected primary cluster: $PRIMARY_CLUSTER"

# Build cluster list YAML block
CLUSTER_LIST=""
for cluster in "${CLUSTER_ARRAY[@]}"; do
  if [ -z "$CLUSTER_LIST" ]; then
    CLUSTER_LIST="      - name: ${cluster}"
    CLUSTER_LIST="${CLUSTER_LIST}"$'\n'"        environment: aks"
  else
    CLUSTER_LIST="${CLUSTER_LIST}"$'\n'"      - name: ${cluster}"
    CLUSTER_LIST="${CLUSTER_LIST}"$'\n'"        environment: aks"
  fi

done

# Create per-cluster identity ConfigMaps using member contexts
# (required for cross-cluster replication to resolve self name)
echo ""
echo "======================================="
echo "Creating cluster identification ConfigMaps (per member)..."
echo "======================================="
for cluster in "${CLUSTER_ARRAY[@]}"; do
  echo ""
  echo "Processing ConfigMap for $cluster..."

  if ! kubectl config get-contexts "$cluster" &>/dev/null; then
    echo "✗ Context $cluster not found; skip. Provide kubeconfig for member clusters if you need per-cluster ConfigMaps."
    continue
  fi

  REGION=$(echo "$cluster" | awk -F- '{print $2}')
  kubectl --context "$cluster" create configmap cluster-name \
    -n kube-system \
    --from-literal=name="$cluster" \
    --from-literal=region="$REGION" \
    --dry-run=client -o yaml | kubectl --context "$cluster" apply -f -

  if kubectl --context "$cluster" get configmap cluster-name -n kube-system &>/dev/null; then
    echo "✓ ConfigMap created/updated for $cluster (region: $REGION)"
  else
    echo "✗ Failed to create ConfigMap for $cluster"
  fi

done

# Render manifest with substitutions
TEMP_YAML=$(mktemp)
sed -e "s/{{DOCUMENTDB_PASSWORD}}/$DOCUMENTDB_PASSWORD/g" \
    -e "s/{{PRIMARY_CLUSTER}}/$PRIMARY_CLUSTER/g" \
    "$SCRIPT_DIR/multi-region-karmada.yaml" | \
while IFS= read -r line; do
  if [[ "$line" == '{{CLUSTER_LIST}}' ]]; then
    echo "$CLUSTER_LIST"
  else
    echo "$line"
  fi
done > "$TEMP_YAML"

echo ""
echo "Generated configuration preview:"
echo "--------------------------------"
echo "Primary cluster: $PRIMARY_CLUSTER"
echo "Cluster list:"
echo "$CLUSTER_LIST"
echo "--------------------------------"

# Apply manifest + propagation policy via Karmada API server
echo ""
echo "Applying DocumentDB configuration through Karmada..."
kubectl --kubeconfig "$KARMADA_KUBECONFIG" apply -f "$TEMP_YAML"
rm -f "$TEMP_YAML"

echo ""
echo "Checking propagation objects..."
kubectl --kubeconfig "$KARMADA_KUBECONFIG" get clusterpropagationpolicy documentdb-preview
kubectl --kubeconfig "$KARMADA_KUBECONFIG" get work -A | head -20

echo ""
echo "======================================="
echo "Checking deployment status on member clusters..."
echo "======================================="
for cluster in "${CLUSTER_ARRAY[@]}"; do
  echo ""
  echo "=== $cluster ==="

  if ! kubectl config get-contexts "$cluster" &>/dev/null; then
    echo "Context $cluster not available locally; skip per-cluster inspection."
    continue
  fi

  if kubectl --context "$cluster" get namespace documentdb-preview-ns &>/dev/null; then
    echo "✓ Namespace exists"
  else
    echo "✗ Namespace missing (may still be propagating)"
    continue
  fi

  if kubectl --context "$cluster" get secret documentdb-credentials -n documentdb-preview-ns &>/dev/null; then
    echo "✓ Secret exists"
  else
    echo "✗ Secret not found"
  fi

  if kubectl --context "$cluster" get documentdb documentdb-preview -n documentdb-preview-ns &>/dev/null; then
    STATUS=$(kubectl --context "$cluster" get documentdb documentdb-preview -n documentdb-preview-ns -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "✓ DocumentDB resource exists (status: $STATUS)"
    if [ "$cluster" = "$PRIMARY_CLUSTER" ]; then
      echo "  Role: PRIMARY"
    else
      echo "  Role: REPLICA"
    fi
  else
    echo "✗ DocumentDB resource not found"
  fi

  PODS=$(kubectl --context "$cluster" get pods -n documentdb-preview-ns --no-headers 2>/dev/null | wc -l || echo "0")
  echo "  Pods: $PODS"
  if [ "$PODS" -gt 0 ]; then
    kubectl --context "$cluster" get pods -n documentdb-preview-ns 2>/dev/null | head -5
  fi

done

echo ""
echo "Done. If any members are missing resources, verify propagation policy, cluster readiness, and member kubeconfigs."
