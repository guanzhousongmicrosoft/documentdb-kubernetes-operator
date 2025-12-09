#!/usr/bin/env bash
set -euo pipefail

# Test DocumentDB deployment

echo "======================================="
echo "Testing DocumentDB Deployment"
echo "======================================="
echo ""

# Get connection details
EXTERNAL_IP=$(kubectl get svc -n documentdb-demo-ns documentdb-service-documentdb-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
USERNAME=$(kubectl get secret documentdb-credentials -n documentdb-demo-ns -o jsonpath='{.data.username}' | base64 -d)
PASSWORD=$(kubectl get secret documentdb-credentials -n documentdb-demo-ns -o jsonpath='{.data.password}' | base64 -d)

echo "Connection Details:"
echo "  Host: $EXTERNAL_IP:10260"
echo "  Username: $USERNAME"
echo "  Password: $PASSWORD"
echo ""

echo "Connection String:"
echo "mongodb://$USERNAME:$PASSWORD@$EXTERNAL_IP:10260/?directConnection=true&authMechanism=SCRAM-SHA-256&tls=true&tlsAllowInvalidCertificates=true&replicaSet=rs0"
echo ""

echo "To test with mongosh:"
echo "  mongosh $EXTERNAL_IP:10260 -u $USERNAME -p '$PASSWORD' \\"
echo "    --authenticationMechanism SCRAM-SHA-256 --tls --tlsAllowInvalidCertificates"
echo ""

echo "To test with port-forward (for local testing):"
echo "  kubectl port-forward -n documentdb-demo-ns svc/documentdb-service-documentdb-demo 10260:10260"
echo "  mongosh localhost:10260 -u $USERNAME -p '$PASSWORD' \\"
echo "    --authenticationMechanism SCRAM-SHA-256 --tls --tlsAllowInvalidCertificates"
echo ""

echo "Resource Status:"
echo "----------------"
kubectl get documentdb,pods,svc -n documentdb-demo-ns
echo ""

echo "Operator Logs (last 20 lines):"
echo "-------------------------------"
kubectl logs -n documentdb-operator deploy/documentdb-operator --tail=20 2>/dev/null || echo "Logs not available yet"
echo ""
