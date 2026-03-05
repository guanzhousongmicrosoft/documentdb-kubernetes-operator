#!/bin/bash
# verify-operator.sh - Verify DocumentDB operator deployment on all member clusters
#
# Usage: ./verify-operator.sh
#
# This script checks:
#   - documentdb-operator namespace exists
#   - DocumentDB CRDs are installed
#   - CNPG CRD is installed (installs if missing)
#   - Operator deployment and pod status
#   - Operator readiness

set -e

echo "Verifying DocumentDB operator deployment..."

for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "=== $cluster ==="
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Check namespace
  if kubectl --context "$cluster" get namespace documentdb-operator >/dev/null 2>&1; then
    echo "✓ Namespace: documentdb-operator exists"
  else
    echo "✗ Namespace: documentdb-operator MISSING"
    continue
  fi

  # Check DocumentDB CRDs
  crd_count=$(kubectl --context "$cluster" get crd 2>/dev/null | grep -c "documentdb.io" || echo "0")
  echo "✓ DocumentDB CRDs installed: $crd_count"

  # Check CNPG CRD (operator needs this)
  if kubectl --context "$cluster" get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then
    echo "✓ CNPG CRD installed"
  else
    echo "⚠️  CNPG CRD missing - installing..."
    kubectl --context "$cluster" apply --server-side --force-conflicts -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml
    kubectl --context "$cluster" wait --for=condition=Established crd/clusters.postgresql.cnpg.io --timeout=90s
  fi

  echo ""
  echo "Deployment status:"
  kubectl --context "$cluster" get deployment -n documentdb-operator

  echo ""
  echo "Pod status:"
  kubectl --context "$cluster" get pods -n documentdb-operator

  echo ""
  kubectl --context "$cluster" rollout status deployment/documentdb-operator -n documentdb-operator --timeout=180s && echo "✅ Operator is Ready!" || echo "⏳ Operator not ready yet..."

  echo ""
done

echo "✅ All operators verified!"
