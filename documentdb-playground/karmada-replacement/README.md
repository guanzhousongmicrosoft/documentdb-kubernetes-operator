# Karmada Multi-Region Deployment (Fleet Replacement Demo)

Purpose: show, end-to-end, that Karmada can replace Azure Fleet Manager for multi-cluster DocumentDB. Every step lists what Fleet used to do and the exact Karmada command to achieve the same outcome. Designed for beginners—copy/paste friendly.

Files in this folder
- deploy script: deploy-multi-region-karmada.sh
- manifest: multi-region-karmada.yaml

Set your working directory
```bash
cd /home/song/dko_111/documentdb-playground/karmada-replacement
REPO_ROOT=/home/song/dko_111
```

What you will get (same as Fleet result)
- Namespace, secret, and DocumentDB CR propagated to all clusters from one control plane.
- One primary DocumentDB instance, replicas on the rest.
- Karmada-driven placement (instead of Fleet CRP) and clusterset-local addressing for cross-cluster networking.

## Prerequisites (install once)
- CLI tools: kubectl, karmadactl, jq, openssl.
- Azure CLI (for creating/joining AKS and fetching kubeconfigs).
- Karmada control plane reachable (e.g., on kind) with kubeconfig at /etc/karmada/karmada-apiserver.config.
- Three AKS clusters created (can be any number ≥2). Join them to Karmada with Ready=True.

Install helpers (example on Linux/macOS):
```bash
brew install kubectl karmada-io/tap/karmadactl jq openssl   # macOS
# or
sudo snap install kubectl --classic && sudo snap install jq && sudo apt-get install -y openssl
```

## Step 1: Create or verify AKS clusters (Fleet: deploy-fleet-bicep.sh)
If you already have AKS clusters, skip to Step 2. Otherwise reuse the provided helper script to create member clusters. This mirrors Fleet’s bicep deploy but via CLI.

From repo root:
```bash
cd /home/song/dko_111/documentdb-playground/karmada-demo
RESOURCE_GROUP=karmada-demo-rg
REGIONS=(eastus2 westus3 uksouth)
az group create -n $RESOURCE_GROUP -l ${REGIONS[0]}

# Create 3 member clusters (1-node, cost-optimized)
for r in "${REGIONS[@]}"; do
  CLUSTER_NAME=member-$r
  LOCATION=$r
  ./create-cluster.sh --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
    --node-count 1 --node-size Standard_D2ps_v6 --skip-operator --skip-instance --skip-storage-class
done
```
Verify (expect Succeeded):
```bash
az aks list -g $RESOURCE_GROUP -o table
```

## Step 2: Fetch kubeconfigs for members (Fleet: hub/member contexts auto-added)
```bash
for r in eastus2 westus3 uksouth; do
  az aks get-credentials --resource-group karmada-demo-rg --name member-$r --overwrite-existing
done
kubectl config get-contexts | grep member-
```
You should see contexts like member-eastus2, member-westus3, member-uksouth.

## Step 3: Install Karmada locally (Fleet hub → local Kind)
Goal: run Karmada control plane on your laptop (kind), then use it to manage the three AKS clusters.

```bash
# Create local kind cluster for Karmada API server (exposes 32443)
cat > /tmp/kind-karmada.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 32443
    hostPort: 32443
    protocol: TCP
EOF

kind create cluster --name karmada-host --config /tmp/kind-karmada.yaml

# Install Karmada into the kind cluster
karmadactl init \
  --kubeconfig $HOME/.kube/config \
  --context kind-karmada-host \
  --karmada-apiserver-advertise-address=127.0.0.1

# Verify control plane is healthy (expect 7 pods Running)
kubectl --context kind-karmada-host get pods -n karmada-system
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config cluster-info
```

## Step 4: Join the 3 AKS clusters to local Karmada (Fleet member join equivalent)
```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  karmadactl join $c \
    --cluster-kubeconfig $HOME/.kube/config \
    --cluster-context $c \
    --karmada-kubeconfig /etc/karmada/karmada-apiserver.config \
    --cluster-labels region=$(echo $c | awk -F- '{print $2}')
done

# Verify all three show Ready=True
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters
```

## Step 5: Install CRDs and cert-manager (Fleet: installed via hub)
Install cert-manager onto each member cluster (needed for the operator):
```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true \
    --kube-context $c
  kubectl --context $c -n cert-manager rollout status deploy/cert-manager --timeout=180s
  kubectl --context $c -n cert-manager get pods
done
```

Apply CRDs through Karmada so every cluster knows the types:
```bash
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml
# Optional: remove CNPG operator, keep CRDs only (mirrors Fleet behavior)
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete deployment cnpg-controller-manager -n cnpg-system --ignore-not-found
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete validatingwebhookconfiguration cnpg-validating-webhook-configuration --ignore-not-found
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete mutatingwebhookconfiguration cnpg-mutating-webhook-configuration --ignore-not-found

# DocumentDB CRDs
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply -f $REPO_ROOT/operator/documentdb-helm-chart/crds/

# Verify CRDs are present
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get crd | grep -E "documentdb|postgresql"
```

## Step 6: Install DocumentDB operator on every member (Fleet: install-documentdb-operator.sh)
```bash
pushd $REPO_ROOT/operator/documentdb-helm-chart
for c in member-eastus2 member-westus3 member-uksouth; do
  helm upgrade --install documentdb-operator . \
    -n documentdb-operator --create-namespace \
    --set forceArch=amd64 \
    --kube-context $c
  kubectl --context $c -n documentdb-operator rollout status deploy/documentdb-operator --timeout=180s
  kubectl --context $c -n documentdb-operator get pods
done
popd
```
Expected: one `documentdb-operator` pod Running per cluster.

## Step 7: Run the Karmada deployment script (Fleet: deploy-multi-region.sh)
From this folder:
```bash
chmod +x deploy-multi-region-karmada.sh
./deploy-multi-region-karmada.sh
# or provide a password
DOCUMENTDB_PASSWORD=MySecureP@ss ./deploy-multi-region-karmada.sh
```
What the script does (Fleet equivalents):
- Discovers Ready clusters from Karmada (Fleet: az aks list member-*).
- Picks primary (defaults to eastus2 regex) (Fleet: same preference).
- Creates per-member identity ConfigMap `kube-system/cluster-name` via member contexts (Fleet: same step).
- Renders manifest with `crossCloudNetworkingStrategy: Karmada` (Fleet: AzureFleet) and your cluster list/primary.
- Applies namespace, secret, DocumentDB, and ClusterPropagationPolicy via Karmada API server (Fleet: via hub + CRP).

Expected on success (script prints):
- Cluster list, chosen primary.
- `clusterpropagationpolicy/documentdb-preview` present.
- `work` objects listed for each cluster.

## Step 8: Verify propagation and health
Karmada control plane checks (expect resources listed):
```bash
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusterpropagationpolicy documentdb-preview
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get work -A | head
```

Per-cluster checks (expect namespace/secret/DocumentDB present, pods running):
```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $c ==="
  kubectl --context $c get ns documentdb-preview-ns || true
  kubectl --context $c get secret documentdb-credentials -n documentdb-preview-ns || true
  kubectl --context $c get documentdb documentdb-preview -n documentdb-preview-ns || true
  kubectl --context $c get pods -n documentdb-preview-ns || true
done
```
Interpretation:
- Namespace exists → propagated
- Secret exists → propagated
- DocumentDB shows STATUS (e.g., Ready/Running) → operator working
- Pods list shows DocumentDB pods scheduled

## Step 8: Connect to the primary (Fleet: same)
Identify primary printed by the script (or read from the CR):
```bash
PRIMARY=$(kubectl --context member-eastus2 get documentdb documentdb-preview -n documentdb-preview-ns -o jsonpath='{.spec.clusterReplication.primary}' 2>/dev/null || echo "member-eastus2")
echo "Primary is $PRIMARY"
kubectl --context $PRIMARY port-forward -n documentdb-preview-ns svc/documentdb-preview 10260:10260
```
In another terminal, get the connection string:
```bash
kubectl --context $PRIMARY get documentdb documentdb-preview -n documentdb-preview-ns -o jsonpath='{.status.connectionString}'
```

## Step 9: Failover demo (Fleet: patch via hub)
Choose a different cluster, e.g., member-westus3:
```bash
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config patch documentdb documentdb-preview -n documentdb-preview-ns \
  --type=merge -p '{"spec":{"clusterReplication":{"primary":"member-westus3"}}}'
```
Watch status per member (phase should stabilize; primary/replica roles will swap):
```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $c ==="; kubectl --context $c get documentdb documentdb-preview -n documentdb-preview-ns -o jsonpath='{.status.phase}' || echo "n/a"; echo
done
```

## Step 10: Cleanup (Fleet: delete via hub)
```bash
kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete -f multi-region-karmada.yaml
# Optionally delete AKS clusters
for r in eastus2 westus3 uksouth; do az aks delete -g karmada-demo-rg -n member-$r --yes --no-wait; done
```

## Troubleshooting quick list
- Clusters not Ready: `kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters -o wide`
- Propagation stuck: describe the ClusterPropagationPolicy and check `work` status.
- Per-cluster missing ConfigMap: ensure local kubecontext exists and rerun script; or manually create `kube-system/cluster-name` with name/region.
- Pods Pending: check node capacity on that member cluster.

## Mapping: Fleet → Karmada (at a glance)
- Fleet hub deployment → Karmada control plane install
- Fleet members → Karmada joined clusters
- CRP (ClusterResourcePlacement) → ClusterPropagationPolicy
- az aks list member-* → kubectl get clusters (Karmada)
- Apply via hub → Apply via Karmada API server
- AzureFleet networking → Karmada networking (`crossCloudNetworkingStrategy: Karmada`)
