# Karmada Demo Transcript
## Replacing Azure Fleet Manager with Karmada for Multi-Cluster DocumentDB

**Total Demo Time**: ~45-60 minutes  
**Prerequisites**: Azure CLI, kubectl, Helm, Kind, karmadactl installed and `az login` completed

---

## Opening (2 minutes)

> **SAY**: "Today I'm going to demonstrate how Karmada can replace Azure Fleet Manager for multi-cluster orchestration. We'll deploy DocumentDB across 3 AKS clusters in different Azure regions—all from a single YAML file."

> **SAY**: "Why Karmada over Azure Fleet Manager? Three key reasons:
> 1. **Cloud agnostic** - works on AWS, GCP, on-prem, not just Azure
> 2. **Zero cost** - it's open source, no Azure service fees
> 3. **No vendor lock-in** - it's a CNCF project with strong community support"

---
## Part 1: Deploy Karmada Control Plane (10 minutes)
### prerequisites
> **SAY**: "First, we need to set up the Karmada control plane. We'll run Karmada in a local Kind cluster."
```bash
az --version
kubectl version --client
helm version
kind --version
karmadactl version

```
### Step 1.1: Create Kind Cluster

> **SAY**: "First, we need a Kubernetes cluster to host Karmada. We'll use Kind—Kubernetes in Docker—to create a local cluster. This will be our control plane."

```bash
# Create Kind cluster config
cat > /tmp/kind-karmada.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 32443
    hostPort: 32443
    protocol: TCP
EOF

# Create the cluster
kind create cluster --name karmada-host --config /tmp/kind-karmada.yaml

```

> **SAY**: "Port 32443 is exposed for the Karmada API server—this is how member clusters will communicate with Karmada."

**✓ VERIFY**: You should see the Kind cluster creation succeed.

```bash
# Verify port mapping
docker ps --filter "name=karmada-host" --format "table {{.Names}}\t{{.Ports}}"
```

> **SAY**: "You can see port 32443 is mapped correctly."

---

### Step 1.2: Initialize Karmada

> **SAY**: "Now let's install Karmada into this Kind cluster. This installs the API server, scheduler, controller manager, and etcd. It takes about 5 minutes."

```bash
sudo karmadactl init \
  --kubeconfig=$HOME/.kube/config \
  --context=kind-karmada-host \
  --karmada-apiserver-advertise-address=127.0.0.1
```

> **SAY** (while waiting): "Karmada is pulling container images and deploying 7 components. Think of Karmada as a 'cluster of clusters' manager—you deploy resources to Karmada once, and it distributes them to all your member clusters automatically."

**✓ VERIFY**: Wait for the Karmada ASCII banner to appear.

```bash
# Verify all 7 pods are running
kubectl --context kind-karmada-host get pods -n karmada-system

```

> **SAY**: "All 7 Karmada pods are now running."

---

### Step 1.3: Install CRDs on Karmada

> **SAY**: "For Karmada to understand DocumentDB resources, we need to install the CRDs on the control plane."

```bash
# Set repo root
export REPO_ROOT="$(git rev-parse --show-toplevel)"

# Install CNPG CRDs
echo "Installing CNPG CRDs..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply --server-side \
  -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml

# Remove CNPG operator (we only need CRDs, not the operator itself)
# WHY: The CNPG YAML installs both CRDs AND the operator deployment.
# We only need CRDs on Karmada so it understands the resource types.
# If we leave the cnpg-system namespace here, Karmada would propagate it
# to member clusters, causing Helm ownership conflicts when the
# DocumentDB operator Helm chart tries to install its own CNPG components.
echo "Removing CNPG operator components..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete deployment \
  -n cnpg-system cnpg-controller-manager 2>/dev/null || true

sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  validatingwebhookconfiguration cnpg-validating-webhook-configuration 2>/dev/null || true

sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  mutatingwebhookconfiguration cnpg-mutating-webhook-configuration 2>/dev/null || true
  
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete namespace cnpg-system 2>/dev/null || true

# Install DocumentDB CRDs
echo "Installing DocumentDB CRDs..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply -f operator/documentdb-helm-chart/crds/

```

> **SAY**: "We install the CRDs but remove the operator itself—the operator will run on each member cluster, not on Karmada."

**✓ VERIFY**:
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get crd | grep -E "documentdb|cnpg"
```

> **SAY**: "You can see the DocumentDB and CNPG CRDs are installed."

---

## Part 2: Deploy AKS Clusters (15 minutes)

### Step 2.1: Create 3 AKS Clusters

> **SAY**: "Now let's create our member clusters. We'll deploy 3 AKS clusters across different Azure regions: East US 2, West US 3, and UK South. This demonstrates multi-region high availability."

```bash
# Deploy all 3 clusters in parallel
$REPO_ROOT/documentdb-playground/karmada-demo/deploy-clusters.sh
```

> **SAY** (while waiting ~10-15 min): "The script creates 3 clusters in parallel:
> - `member-eastus2` in East US 2
> - `member-westus3` in West US 3  
> - `member-uksouth` in UK South
> 
> Each cluster has 2 nodes with Standard_D4s_v5 VMs. This will take about 10-15 minutes."

**✓ VERIFY** (when complete):
```bash
az aks list -g karmada-demo-rg \
  --query "[].{Name:name, Location:location, Status:provisioningState}" \
  -o table

```

> **SAY**: "All 3 clusters show Status: Succeeded."

---

### Step 2.2: Get Cluster Credentials

> **SAY**: "Let's download the credentials so kubectl can access each cluster."

```bash
az aks get-credentials --resource-group karmada-demo-rg --name member-eastus2 --overwrite-existing
az aks get-credentials --resource-group karmada-demo-rg --name member-westus3 --overwrite-existing
az aks get-credentials --resource-group karmada-demo-rg --name member-uksouth --overwrite-existing

# Verify contexts
kubectl config get-contexts | grep member-

```

> **SAY**: "We now have kubectl contexts for all 3 clusters."

---

### Step 2.3: Join Clusters to Karmada

> **SAY**: "This is the key step—we register each AKS cluster with Karmada. After this, Karmada can push resources to them automatically."

```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  echo "Joining $c to Karmada..."
  sudo karmadactl --kubeconfig /etc/karmada/karmada-apiserver.config \
    join $c \
    --cluster-kubeconfig=$HOME/.kube/config \
    --cluster-context=$c
done

```

**✓ VERIFY**:
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters

```

> **SAY**: "Look at the output—all 3 clusters show READY: True. Karmada is now managing them."

```
NAME             VERSION   MODE   READY   AGE
member-eastus2   v1.33.x   Push   True    30s
member-westus3   v1.33.x   Push   True    20s
member-uksouth   v1.33.x   Push   True    10s
```

> **SAY**: "The MODE is 'Push'—meaning Karmada pushes resources to clusters, rather than clusters pulling them."

---

## Part 3: Install Prerequisites on Clusters (5 minutes)

### Step 3.1: Install cert-manager

> **SAY**: "Before deploying DocumentDB, we need cert-manager for TLS certificates and the DocumentDB operator itself."

```bash
# Add cert-manager repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install on all clusters
for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "Installing cert-manager on $cluster..."
  helm --kube-context $cluster install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.2 \
    --set installCRDs=true \
    --wait
done

```

> **SAY**: "cert-manager is now installed on all 3 clusters."

---

### Step 3.2: Install DocumentDB Operator

> **SAY**: "Now let's install the DocumentDB operator on each cluster."

```bash
for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "Installing DocumentDB operator on $cluster..."
  helm --kube-context $cluster install documentdb-operator \
    "$REPO_ROOT/operator/documentdb-helm-chart" \
    --namespace documentdb-operator \
    --create-namespace \
    --wait
done

```

**✓ VERIFY**:
```bash
$REPO_ROOT/documentdb-playground/karmada-demo/verify-operator.sh
```

> **SAY**: "The operator is running on all 3 clusters, ready to process DocumentDB resources."

---

### Step 3.3: Create Cluster Name ConfigMaps

> **SAY**: "The operator needs to know each cluster's name for multi-cluster coordination."

```bash
for cluster in member-eastus2 member-westus3 member-uksouth; do
  kubectl --context $cluster create configmap cluster-name -n kube-system --from-literal=name=$cluster \
    --dry-run=client -o yaml | kubectl --context $cluster apply -f -
done

```

---

## Part 4: Deploy DocumentDB via Karmada (5 minutes)

> **SAY**: "Now for the main event! This is where Karmada shows its power. We'll apply ONE YAML file to Karmada, and it automatically deploys DocumentDB to all 3 clusters."

### Step 4.1: Review the Manifest

> **SAY**: "Let me show you the manifest structure."

```bash
cat $REPO_ROOT/documentdb-playground/karmada-demo/documentdb-karmada.yaml
```

> **SAY**: "The manifest has 6 parts:
> 1. **Namespace** - `documentdb-preview-ns`
> 2. **ClusterPropagationPolicy** - tells Karmada to send the namespace to all 3 clusters
> 3. **Secret** - database credentials
> 4. **PropagationPolicy** - routes the secret to all clusters
> 5. **DocumentDB resource** - the actual database definition
> 6. **PropagationPolicy** - routes DocumentDB to all clusters"

---

### Step 4.2: Apply to Karmada

> **SAY**: "Watch this—one command, and resources appear on all 3 clusters."

```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply \
  -f $REPO_ROOT/documentdb-playground/karmada-demo/documentdb-karmada.yaml
```

**Expected output**:
```
namespace/documentdb-preview-ns created
clusterpropagationpolicy.policy.karmada.io/documentdb-namespace-policy created
secret/documentdb-credentials created
propagationpolicy.policy.karmada.io/documentdb-credentials-policy created
documentdb.documentdb.io/documentdb-preview created
propagationpolicy.policy.karmada.io/documentdb-resource-policy created
```

> **SAY**: "6 resources created. Now let's verify they propagated."

---

### Step 4.3: Verify Propagation

```bash
# Check Karmada's propagation status
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -n documentdb-preview-ns
```

> **SAY**: "The ResourceBinding shows SCHEDULED: True and FULLYAPPLIED: True—Karmada successfully distributed the resources."

```bash
# Verify on each member cluster
for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $cluster ==="
  kubectl --context $cluster get namespace documentdb-preview-ns
  kubectl --context $cluster get secret documentdb-credentials -n documentdb-preview-ns
  kubectl --context $cluster get documentdb -n documentdb-preview-ns
done

```

> **SAY**: "Namespace, secret, and DocumentDB resource exist on all 3 clusters. This is the magic of Karmada—deploy once, propagate everywhere."

---

### Step 4.4: Wait for Pods

> **SAY**: "Now the DocumentDB operator on each cluster is creating the PostgreSQL instances. This takes about 2-3 minutes."

```bash
# Watch pods come up
for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $cluster ==="
  kubectl --context $cluster get pods -n documentdb-preview-ns
done
```

> **SAY** (while waiting): "Each pod runs 2 containers:
> - PostgreSQL database
> - DocumentDB Gateway that provides MongoDB API compatibility"

**✓ VERIFY** (when ready):
```bash
kubectl --context member-eastus2 get pods -n documentdb-preview-ns
```

> **SAY**: "The pod shows 2/2 Running—both containers are up."

---

## Part 5: Test the Deployment (5 minutes)

### Step 5.1: Connect to DocumentDB

> **SAY**: "Let's test the connection. DocumentDB requires TLS, so we'll use a port-forward and connect with mongosh."

**Terminal 1**:
```bash
kubectl --context member-eastus2 port-forward -n documentdb-preview-ns pod/member-eastus2-1 10260:10260

```

**Terminal 2**:
```bash
# Get password
PASS=$(kubectl --context member-eastus2 get secret documentdb-credentials -n documentdb-preview-ns -o jsonpath='{.data.password}' | base64 -d)

# Test connection (TLS is required)
mongosh --host 127.0.0.1 --port 10260 \
  -u demouser -p "$PASS" \
  --tls --tlsAllowInvalidCertificates \
  --eval "db.runCommand({ping:1})"
```

> **SAY**: "We get `{ ok: 1 }` — DocumentDB is working!"

---

### Step 5.2: Insert and Query Data

```bash
mongosh --host 127.0.0.1 --port 10260 \
  -u demouser -p "$PASS" \
  --tls --tlsAllowInvalidCertificates \
  --eval "db.testCollection.insertOne({name: 'karmada-demo', timestamp: new Date()}); db.testCollection.find().toArray()"
```

> **SAY**: "We successfully inserted a document and read it back. DocumentDB is fully operational across all 3 regions."

---

## Part 6: Comparison Summary (2 minutes)

> **SAY**: "Let me summarize what we achieved versus Azure Fleet Manager:"

| **Capability** | **Karmada (Today)** | **Azure Fleet Manager** |
|----------------|---------------------|-------------------------|
| Multi-cluster deployment | ✅ One YAML | ✅ One YAML |
| Cloud agnostic | ✅ Any K8s | ❌ AKS only |
| Cost | ✅ Free (open source) | 💰 Azure fees |
| Vendor lock-in | ✅ None | ❌ Azure-specific |

> **SAY**: "Karmada provides **identical orchestration capabilities** but with **greater flexibility** and **zero vendor lock-in**. The DocumentDB operator works unchanged—it's completely orchestration-agnostic."

---

## Cleanup

> **SAY**: "Don't forget to clean up to avoid Azure charges."

```bash
# Delete Azure resources
az group delete --name karmada-demo-rg --yes --no-wait

# Delete Kind cluster
kind delete cluster --name karmada-host

# Clean up kubectl contexts
kubectl config delete-context member-eastus2 2>/dev/null || true
kubectl config delete-context member-westus3 2>/dev/null || true
kubectl config delete-context member-uksouth 2>/dev/null || true
kubectl config delete-context kind-karmada-host 2>/dev/null || true

# Remove Karmada config
sudo rm -rf /etc/karmada
```

---

## Closing

> **SAY**: "In summary, we've proven that Karmada can fully replace Azure Fleet Manager for multi-cluster orchestDB orchestration. The key benefits are:
> 1. **Cloud agnostic** - deploy the same way on AWS, GCP, or on-prem
> 2. **Open source** - no licensing fees, strong CNCF community
> 3. **Flexible** - fine-grained control with PropagationPolicies
> 
> Thank you! Any questions?"

---

## Quick Reference - Key Commands

```bash
# Talk to Karmada control plane
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config <command>

# List registered clusters
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters

# Check propagation status
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -A

# Talk to member cluster
kubectl --context member-eastus2 <command>
```

---

## Troubleshooting During Demo

**If pods don't start**:
```bash
kubectl --context member-eastus2 describe pod -n documentdb-preview-ns -l app=documentdb
kubectl --context member-eastus2 logs -n documentdb-operator -l app=documentdb-operator --tail=50
```

**If resources don't propagate**:
```bash
kubectl --context kind-karmada-host logs -n karmada-system -l app=karmada-controller-manager --tail=50
```

**If connection fails**:
```bash
# Verify gateway is listening (0x2814 = 10260)
kubectl --context member-eastus2 exec -n documentdb-preview-ns member-eastus2-1 -c documentdb-gateway -- sh -c "grep 2814 /proc/net/tcp6"
```
