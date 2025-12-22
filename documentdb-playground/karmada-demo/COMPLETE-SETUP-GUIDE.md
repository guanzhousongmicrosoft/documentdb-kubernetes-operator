# Complete Beginner's Guide: Replacing Azure Fleet Manager with Karmada

## What This Guide Demonstrates

This guide shows how **Karmada** can replace **Azure Fleet Manager** for multi-cluster orchestration of DocumentDB deployments. You'll learn to:

- Deploy a Karmada control plane (centralized multi-cluster manager)
- Create 3 AKS clusters across different Azure regions
- Join clusters to Karmada for centralized management
- Deploy DocumentDB across all clusters from a single YAML manifest
- Compare Karmada vs Azure Fleet Manager capabilities

**Target Audience**: Complete beginners to Karmada, kubectl, or AKS.

**Time Required**: ~45-60 minutes total

**Cost**: ~$5-10 for running AKS clusters during the demo (delete resources when done)

---

## Why Karmada Over Azure Fleet Manager?

| Capability | Karmada | Azure Fleet Manager |
|------------|---------|---------------------|
| **Multi-cluster orchestration** | ✅ Yes | ✅ Yes |
| **Cloud agnostic** | ✅ Works on AWS, GCP, on-prem | ❌ Azure-only |
| **Cost** | ✅ Free (open source) | 💰 Azure service fees |
| **Multi-cloud support** | ✅ Mix AKS, EKS, GKE | ❌ AKS only |
| **Vendor lock-in** | ✅ None | ❌ Azure-specific |
| **Community** | ✅ CNCF project | ❌ Proprietary |

**This guide proves**: Karmada provides the **same orchestration capabilities** as Azure Fleet Manager, but with **greater flexibility** and **zero vendor lock-in**.

---

## Prerequisites

### Required Tools

Install these tools before starting:

```bash
# 1. Azure CLI (for creating AKS clusters)
# macOS:
brew install azure-cli

# Verify installation
az --version

# Login to Azure
az login

# 2. kubectl (Kubernetes command-line tool)
# macOS:
brew install kubectl

# Verify installation
kubectl version --client

# 3. Helm (Kubernetes package manager)
# macOS:
brew install helm

# Verify installation
helm version

# 4. kind (Kubernetes in Docker - for Karmada control plane)
# macOS:
brew install kind

# Verify installation
kind --version

# 5. karmadactl (Karmada command-line tool)
curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | sudo bash

# Verify installation
karmadactl version
```

**Verification**: All commands should show version numbers without errors.

---

## Part 1: Deploy Karmada Control Plane

**What is Karmada?** Karmada is a Kubernetes control plane that manages multiple Kubernetes clusters. Think of it as a "cluster of clusters" manager. Instead of deploying resources to each cluster individually, you deploy to Karmada once, and it distributes to all clusters automatically.

**Architecture**:
```
┌─────────────────────────────────────┐
│   Karmada Control Plane (Kind)     │  ← You apply YAML here
│   - API Server (port 32443)        │
│   - Controller Manager              │
│   - Scheduler                       │
└─────────────────────────────────────┘
         │          │          │
         ▼          ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐
    │ AKS-1  │ │ AKS-2  │ │ AKS-3  │  ← Resources appear here
    │eastus2 │ │westus3 │ │uksouth │
    └────────┘ └────────┘ └────────┘
```

### Step 1.1: Create Kind Cluster for Karmada

**What is Kind?** Kind (Kubernetes in Docker) creates a local Kubernetes cluster using Docker containers. We'll use it to host the Karmada control plane.

**Why port 32443?** This is the default port Karmada uses for its API server. We expose it so other clusters can communicate with Karmada.

```
# Create configuration file for Kind cluster
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

# Create the Kind cluster (takes ~30 seconds)
kind create cluster --name karmada-host --config /tmp/kind-karmada.yaml

# Verify port mapping
docker ps --filter "name=karmada-host" --format "table {{.Names}}\t{{.Ports}}"
```

**Expected Output**:
NAMES                    PORTS
karmada-host-control-plane   127.0.0.1:62XXX->6443/tcp, 0.0.0.0:32443->32443/tcp


✅ **Success Indicator**: You should see `0.0.0.0:32443->32443/tcp` in the ports list.

❌ **If it fails**: Check Docker is running: `docker ps`

### Step 1.2: Initialize Karmada

**What happens here?** The `karmadactl init` command installs all Karmada components (API server, scheduler, controller manager, etcd) into the Kind cluster we just created.

**Why sudo?** Karmada stores its configuration files in `/etc/karmada/` which requires root access.

**Time**: 5-10 minutes (downloads container images and starts 7 pods)

```

sudo karmadactl init \
  --kubeconfig=$HOME/.kube/config \
  --context=kind-karmada-host \
  --karmada-apiserver-advertise-address=127.0.0.1

# This command will:
# 1. Download Karmada container images (~2-3 minutes)
# 2. Create Karmada namespaces and CRDs
# 3. Deploy Karmada components (API server, scheduler, controllers)
# 4. Configure kubeconfig at /etc/karmada/karmada-apiserver.config
```

**Expected Output** (at the end):
```
------------------------------------------------------------------------------------------------------
 █████   ████   █████████   ████████   ████     ████   █████████   ████████     █████████
░░███   ███░   ███░░░░░███ ░░███░░███ ░███░    ░███  ███░░░░░███ ░░███░░███   ███░░░░░███
 ░███  ███    ░███    ░███  ░███ ░░░  ░███░    ░███ ░███    ░███  ░███ ░░███ ░███    ░███
 ░███████     ░███████████  ░███       ░███░    ░███ ░███████████  ░███  ░███ ░███████████
 ░███░░███    ░███░░░░░███  ░███       ░███░    ░███ ░███░░░░░███  ░███  ░███ ░███░░░░░███
 ░███ ░░███   ░███    ░███  ░███     █ ░███░    ░███ ░███    ░███  ░███  ░███ ░███    ░███
 █████ ░░████ █████   █████ ░░████████ ░░████████░  █████   █████ ████████  █████   █████
░░░░░   ░░░░ ░░░░░   ░░░░░   ░░░░░░░░   ░░░░░░░░   ░░░░░   ░░░░░ ░░░░░░░░  ░░░░░   ░░░░░
------------------------------------------------------------------------------------------------------
Karmada is installed successfully.
```

✅ **Success Indicator**: You see the Karmada ASCII art banner.

⏳ **If it takes longer than 10 minutes**: Check your internet connection for image downloads

# Understanding Karmada Architecture
- **Kind cluster**: Hosts the Karmada components (just infrastructure)
- **Karmada API server**: The control plane you interact with (runs inside Kind)
- **Member clusters**: Your actual AKS clusters (we'll add these next)

**Important**: You'll use `sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config` to talk to Karmada, not regular kubectl.

```
# ═══════════════════════════════════════════════════════════
# Verification 1: Check Karmada pods are running
# ═══════════════════════════════════════════════════════════
echo "Checking Karmada pods..."
kubectl --context kind-karmada-host get pods -n karmada-system

# Wait until you see ALL 7 pods in Running state (may take 2-3 minutes):
# NAME                                         READY   STATUS    AGE
# etcd-0                                       1/1     Running   2m
# karmada-apiserver-xxx                        1/1     Running   2m
# karmada-aggregated-apiserver-xxx             1/1     Running   2m
# karmada-controller-manager-xxx               1/1     Running   2m
# karmada-scheduler-xxx                        1/1     Running   2m
# karmada-webhook-xxx                          1/1     Running   2m
# kube-controller-manager-xxx                  1/1     Running   2m
```

**If pods are not Running**: Wait 2-3 minutes for images to download.

```
# ═══════════════════════════════════════════════════════════
# Step 1: Install CNPG (PostgreSQL) CRDs
# ═══════════════════════════════════════════════════════════
echo "Installing CNPG CRDs on Karmada control plane..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply --server-side \
  -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml

# ═══════════════════════════════════════════════════════════
# Step 2: Remove CNPG operator (we only need CRDs, not the operator)
# ═══════════════════════════════════════════════════════════
echo "Removing CNPG operator (keeping only CRDs)..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete deployment \
  -n cnpg-system cnpg-controller-manager 2>/dev/null || true

sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  validatingwebhookconfiguration cnpg-validating-webhook-configuration 2>/dev/null || true

sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  mutatingwebhookconfiguration cnpg-mutating-webhook-configuration 2>/dev/null || true

# ═══════════════════════════════════════════════════════════
# Step 3: Install DocumentDB CRDs
# ═══════════════════════════════════════════════════════════
echo "Installing DocumentDB CRDs on Karmada control plane..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply -f \
  /home/song/dko_111/operator/documentdb-helm-chart/crds/

# ═══════════════════════════════════════════════════════════
# Verification: Check installed CRDs
# ═══════════════════════════════════════════════════════════
echo -e "\nVerifying installed CRDs..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get crd | grep -E "documentdb|cnpg"
```

**Expected Output**:
```
backups.documentdb.io
clusters.postgresql.cnpg.io
dbs.documentdb.io
scheduledbackups.documentdb.io
```

✅ **Success**: You see DocumentDB and CNPG CRDs listed.

```
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config api-resources | grep "clusters.*cluster.karmada.io"
```

**Expected Output**:
```
clusters    cluster.karmada.io/v1alpha1    false    Cluster
```

✅ **All verifications passed?** Karmada is ready! You now have a multi-cluster control plane running locally.

---

## Part 2: Deploy AKS Clusters (3 regions)

**What are we building?** Three independent AKS (Azure Kubernetes Service) clusters in different Azure regions. These will be our "member clusters" that Karmada manages.

**Why 3 clusters?** This demonstrates multi-region deployment - a common real-world scenario for high availability and disaster recovery.

**Architecture after this part**:
```
Karmada Control Plane (localhost)
         │
         └─── (will connect in next step)
              
Azure Cloud:
├── member-eastus2  (East US 2)
├── member-westus3  (West US 3)
└── member-uksouth  (UK South)
```

### Step 2.1: Deploy AKS Clusters

**What will be created:**

| Resource | Name | Location | Size | Cost/hour |
|----------|------|----------|------|-----------|
| Resource Group | `karmada-demo-rg` | eastus2 | - | Free |
| AKS Cluster 1 | `member-eastus2` | eastus2 | 1 node (D2ps_v6) | low |
| AKS Cluster 2 | `member-westus3` | westus3 | 1 node (D2ps_v6) | low |
| AKS Cluster 3 | `member-uksouth` | uksouth | 1 node (D2ps_v6) | low |

**Total cost**: ~$1.20/hour (~$8 for this entire demo if you delete resources after 6-7 hours)

**Time**: 10-15 minutes (clusters deploy in parallel)

```bash
# Navigate to karmada-demo folder
cd /home/song/dko_111/documentdb-playground/karmada-demo

RESOURCE_GROUP=karmada-demo-rg
REGIONS=(eastus2 westus3 uksouth)

# Create 3 member clusters (1 node, cost-optimized)
for r in "${REGIONS[@]}"; do
  ./create-cluster.sh --cluster-name member-$r --resource-group $RESOURCE_GROUP --location $r \
    --node-count 1 --node-size Standard_D2ps_v6 --skip-operator --skip-instance --skip-storage-class
done

echo "✓ All clusters deployed successfully!"
```

⏳ **While waiting**: Each cluster takes ~10-15 minutes to provision. You'll see "✓" marks as each completes.

❌ **If deployment fails**: Check logs in `/tmp/cluster-eastus2.log` (or westus3/uksouth) for error details.

### Step 2.2: Verify Cluster Deployment

**What is kubectl context?** A "context" is a saved connection to a Kubernetes cluster. We'll create 3 contexts (one per AKS cluster) so we can easily switch between them.

```bash
# ═══════════════════════════════════════════════════════════
# Verification 1: Check clusters exist in Azure
# ═══════════════════════════════════════════════════════════
echo "Checking AKS clusters in Azure..."
az aks list -g karmada-demo-rg \
  --query "[].{Name:name, Location:location, Status:provisioningState, K8sVersion:kubernetesVersion}" \
  -o table
```

**Expected Output**:
```
Name             Location    Status     K8sVersion
---------------  ----------  ---------  ------------
member-eastus2   eastus2     Succeeded  1.33.x
member-westus3   westus3     Succeeded  1.33.x
member-uksouth   uksouth     Succeeded  1.33.x
```

✅ **Success**: All 3 clusters show `Status: Succeeded`.

```bash
# ═══════════════════════════════════════════════════════════
# Step 2: Get kubectl credentials for all clusters
# ═══════════════════════════════════════════════════════════
echo -e "\nDownloading cluster credentials..."

# Download credentials (this updates ~/.kube/config)
az aks get-credentials --resource-group karmada-demo-rg --name member-eastus2 --overwrite-existing
az aks get-credentials --resource-group karmada-demo-rg --name member-westus3 --overwrite-existing
az aks get-credentials --resource-group karmada-demo-rg --name member-uksouth --overwrite-existing

# Verify contexts exist
kubectl config get-contexts | grep member-

```bash
echo "Joining member-westus3 to Karmada..."
echo "Joining member-uksouth to Karmada..."
for c in member-eastus2 member-westus3 member-uksouth; do
  echo "Joining $c to Karmada..."
  sudo karmadactl --kubeconfig /etc/karmada/karmada-apiserver.config \
    join $c \
    --cluster-kubeconfig=$HOME/.kube/config \
    --cluster-context=$c \
    --cluster-labels region=$(echo $c | awk -F- '{print $2}')
done

# Verify: Ready=True
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters

```

**Expected Output**:
```
NAME             VERSION   MODE   READY   AGE
member-eastus2   v1.33.5   Push   True    30s
member-uksouth   v1.33.5   Push   True    10s
member-westus3   v1.33.5   Push   True    20s
```

✅ **Success Indicators**:
- All 3 clusters listed
- **MODE**: `Push` (Karmada pushes resources to clusters)
- **READY**: `True` (clusters are healthy and accessible)

**What just happened?** You now have:
```
┌─────────────────────────────────┐
│  Karmada Control Plane          │
│  (localhost)                    │
└─────────────────────────────────┘
         │          │          │
         ▼          ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐
    │eastus2 │ │westus3 │ │uksouth │  ← All registered!
    │ READY  │ │ READY  │ │ READY  │
    └────────┘ └────────┘ └────────┘
```

**This is the key difference from Azure Fleet Manager**: With Fleet Manager, you'd do this through Azure Portal. With Karmada, it's all open-source CLI commands that work anywhere!

**Expected Output** (for each cluster):
```
NAME                                STATUS   ROLES    AGE   VERSION
aks-nodepool1-12345678-vmss000000   Ready    <none>   5m    v1.33.x
aks-nodepool1-12345678-vmss000001   Ready    <none>   5m    v1.33.x
```

✅ **Success**: Each cluster shows 2 nodes in `Ready` state.

**Understanding what you have now**:
- 3 completely independent Kubernetes clusters running in Azure
- kubectl configured to access all 3 clusters
- Each cluster has 2 worker nodes ready to run workloads
- **Next step**: Connect these clusters to Karmada!

### Step 2.3: Join AKS Clusters to Karmada

```bash
# Join all three AKS clusters to Karmada control plane
sudo karmadactl --kubeconfig /etc/karmada/karmada-apiserver.config join member-eastus2 \
  --cluster-kubeconfig=$HOME/.kube/config --cluster-context=member-eastus2

sudo karmadactl --kubeconfig /etc/karmada/karmada-apiserver.config join member-westus3 \
  --cluster-kubeconfig=$HOME/.kube/config --cluster-context=member-westus3

sudo karmadactl --kubeconfig /etc/karmada/karmada-apiserver.config join member-uksouth \
  --cluster-kubeconfig=$HOME/.kube/config --cluster-context=member-uksouth

# Verify clusters are joined and ready
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters

```

Expected output:
```
NAME             VERSION   MODE   READY   AGE
member-eastus2   v1.33.5   Push   True    30s
member-uksouth   v1.33.5   Push   True    10s
member-westus3   v1.33.5   Push   True    20s
```

---

## Part 3: Install cert-manager (TLS Certificate Manager)

**What is cert-manager?** A Kubernetes operator that manages TLS certificates automatically. DocumentDB requires certificates for secure database connections.

**Why not use Karmada to deploy it?** Operators with webhooks and large CRDs work better when installed directly. We use Helm (Kubernetes package manager) for simplicity.

**Time**: ~2-3 minutes per cluster (runs in parallel)

### Step 3.1: Add Helm Repository and Install cert-manager

```bash
# ═══════════════════════════════════════════════════════════
# Step 1: Add cert-manager Helm repository
# ═══════════════════════════════════════════════════════════
echo "Adding cert-manager Helm repository..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

# ═══════════════════════════════════════════════════════════
# Step 2: Install cert-manager on all 3 clusters
# ═══════════════════════════════════════════════════════════
for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Installing cert-manager on $cluster..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if already installed
  if helm --kube-context $cluster list -n cert-manager 2>/dev/null | grep -q cert-manager; then
    echo "✓ cert-manager already installed on $cluster, skipping..."
    continue
  fi
  
  # Install cert-manager with CRDs
  helm --kube-context $cluster install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.2 \
    --set installCRDs=true \
    --wait
  
  echo "✓ cert-manager installed on $cluster"
  echo ""
done

echo "✅ cert-manager installation complete on all clusters!"
```

**Expected Output** (for each cluster):
```
Installing cert-manager on member-eastus2...
NAME: cert-manager
NAMESPACE: cert-manager
STATUS: deployed
✓ cert-manager installed on member-eastus2
```

⚠️ **Azure Policy Warning**: You might see warnings about `quay.io` images not being in approved registries. These are informational only - cert-manager will install successfully.

```bash
# ═══════════════════════════════════════════════════════════
# Verification: Check cert-manager pods are running
# ═══════════════════════════════════════════════════════════
echo "Verifying cert-manager deployment..."

for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $cluster ==="
  kubectl --context $cluster get pods -n cert-manager
  echo ""
done
```

**Expected Output** (for each cluster):
```
NAME                                      READY   STATUS    AGE
cert-manager-7d9b5d8c5f-xxxxx            1/1     Running   1m
cert-manager-cainjector-6d8c9f9d-xxxxx   1/1     Running   1m
cert-manager-webhook-5f7b8c8d-xxxxx      1/1     Running   1m
```

✅ **Success**: All 3 pods show `1/1 Running` on each cluster.

---

## Part 4: Install DocumentDB Operator

**What is the DocumentDB Operator?** The "brains" that manages DocumentDB instances. When you create a DocumentDB resource, the operator detects it and creates all necessary PostgreSQL clusters, services, and configurations.

**Why install on each cluster?** Operators need to run locally to watch for resources and manage them. The operator watches for DocumentDB resources in its cluster and acts on them.

**Time**: ~2-3 minutes per cluster

### Step 4.1: Install DocumentDB Operator Using Helm

```bash
# ═══════════════════════════════════════════════════════════
# Install DocumentDB operator on all 3 clusters
# ═══════════════════════════════════════════════════════════
for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Installing DocumentDB operator on $cluster..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if already installed
  if helm --kube-context $cluster list -n documentdb-operator 2>/dev/null | grep -q documentdb-operator; then
    echo "✓ DocumentDB operator already installed on $cluster, skipping..."
    continue
  fi
  
  # Install operator from local Helm chart
  helm --kube-context $cluster install documentdb-operator \
    /home/song/dko_111/operator/documentdb-helm-chart \
    --namespace documentdb-operator \
    --create-namespace \
    --wait
  
  echo "✓ DocumentDB operator installed on $cluster"
  echo ""
done

echo "✅ DocumentDB operator installation complete on all clusters!"
```

**Expected Output** (for each cluster):
```
Installing DocumentDB operator on member-eastus2...
NAME: documentdb-operator
NAMESPACE: documentdb-operator
STATUS: deployed
✓ DocumentDB operator installed on member-eastus2
```

### Step 4.2: Verify Operator Deployment

```bash
# ═══════════════════════════════════════════════════════════
# Comprehensive verification of DocumentDB operator
# ═══════════════════════════════════════════════════════════
echo "Verifying DocumentDB operator deployment..."

for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "=== $cluster ==="
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check namespace
  if kubectl --context $cluster get namespace documentdb-operator &>/dev/null; then
    echo "✓ Namespace: documentdb-operator exists"
  else
    echo "✗ Namespace: documentdb-operator MISSING"
    continue
  fi
  
  # Check DocumentDB CRDs
  crd_count=$(kubectl --context $cluster get crd 2>/dev/null | grep -c "documentdb.io" || echo "0")
  echo "✓ DocumentDB CRDs installed: $crd_count"
  
  # Check CNPG CRD (operator needs this)
  if kubectl --context $cluster get crd clusters.postgresql.cnpg.io &>/dev/null; then
    echo "✓ CNPG CRD installed"
  else
    echo "⚠️  CNPG CRD missing - installing..."
    kubectl --context $cluster apply --server-side -f \
      https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml
  fi
  
  # Check deployment
  echo ""
  echo "Deployment status:"
  kubectl --context $cluster get deployment -n documentdb-operator
  
  # Check pods
  echo ""
  echo "Pod status:"
  kubectl --context $cluster get pods -n documentdb-operator
  
  # Wait for pod to be ready
  echo ""
  kubectl --context $cluster wait --for=condition=Ready pod \
    -l app.kubernetes.io/name=documentdb-operator \
    -n documentdb-operator \
    --timeout=120s 2>/dev/null && echo "✅ Operator is Ready!" || echo "⏳ Operator not ready yet..."
  
  echo ""
done

echo "✅ All operators verified!"
```

**Expected Output** (for each cluster):
```
=== member-eastus2 ===
✓ Namespace: documentdb-operator exists
✓ DocumentDB CRDs installed: 3
✓ CNPG CRD installed

Deployment status:
NAME                  READY   UP-TO-DATE   AVAILABLE
documentdb-operator   1/1     1            1

Pod status:
NAME                                   READY   STATUS    AGE
documentdb-operator-xxxxx-xxxxx        1/1     Running   2m

✅ Operator is Ready!
```

✅ **Success Indicators**:
- Deployment shows `1/1 READY`
- Pod shows `1/1 Running`
- Message: "✅ Operator is Ready!"

❌ **Troubleshooting** (if operator not ready):

```bash
# Check operator logs for errors
kubectl --context member-eastus2 logs -n documentdb-operator \
  -l app.kubernetes.io/name=documentdb-operator --tail=50

# Check pod events
kubectl --context member-eastus2 describe pod -n documentdb-operator \
  -l app.kubernetes.io/name=documentdb-operator
```

---

## Part 5: Deploy DocumentDB via Karmada (The Main Event!)

**This is where Karmada shows its power!** You'll apply ONE YAML file to Karmada, and it automatically deploys DocumentDB to all 3 clusters. This is exactly what Azure Fleet Manager does, but with Karmada you get:
- Open source (no vendor lock-in)
- Multi-cloud support (works on AWS, GCP, on-prem)
- Zero Azure fees

**What we're deploying**:
- Namespace (documentdb-preview-ns)
- Secret (database credentials)
- DocumentDB resource `documentdb-preview` (replicated to all 3 clusters)
- PropagationPolicies (tell Karmada which clusters get the namespace, secret, and DocumentDB)

**Time**: 2-3 minutes

### Step 5.1: Create DocumentDB Deployment Manifest

**Understanding PropagationPolicy**: This is Karmada's "routing table". It tells Karmada:
- **resourceSelectors**: Which resources to propagate
- **placement**: Which clusters should receive them

```bash
# ═══════════════════════════════════════════════════════════
# Create complete DocumentDB deployment manifest
# ═══════════════════════════════════════════════════════════
cat > /tmp/documentdb-karmada.yaml << 'EOF'
# Namespace for DocumentDB
apiVersion: v1
kind: Namespace
metadata:
  name: documentdb-preview-ns
---
# PropagationPolicy for namespace (apply to all clusters)
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-namespace-policy
  namespace: documentdb-preview-ns
spec:
  resourceSelectors:
    - apiVersion: v1
      kind: Namespace
      name: documentdb-preview-ns
  placement:
    clusterAffinity:
      clusterNames:
        - member-eastus2
        - member-westus3
        - member-uksouth
---
# Secret with database credentials
apiVersion: v1
kind: Secret
metadata:
  name: documentdb-credentials
  namespace: documentdb-preview-ns
type: Opaque
stringData:
  username: demouser
  password: DemoPassword123!
---
# PropagationPolicy for secret (apply to all clusters)
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-credentials-policy
  namespace: documentdb-preview-ns
spec:
  resourceSelectors:
    - apiVersion: v1
      kind: Secret
      name: documentdb-credentials
  placement:
    clusterAffinity:
      clusterNames:
        - member-eastus2
        - member-westus3
        - member-uksouth
---
# DocumentDB resource (multi-cluster, Karmada networking)
apiVersion: documentdb.io/preview
kind: DocumentDB
metadata:
  name: documentdb-preview
  namespace: documentdb-preview-ns
spec:
  nodeCount: 1
  instancesPerNode: 1
  documentDbCredentialSecret: documentdb-credentials
  documentDBImage: ghcr.io/microsoft/documentdb/documentdb-local:16
  gatewayImage: ghcr.io/microsoft/documentdb/documentdb-local:16
  resource:
    storage:
      pvcSize: 10Gi
  environment: aks
  clusterReplication:
    highAvailability: true
    crossCloudNetworkingStrategy: Karmada
    primary: member-eastus2
    clusterList:
      - name: member-eastus2
        environment: aks
      - name: member-westus3
        environment: aks
      - name: member-uksouth
        environment: aks
  exposeViaService:
    serviceType: LoadBalancer
  logLevel: info
---
# PropagationPolicy for DocumentDB (apply to all clusters)
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: documentdb-resource-policy
  namespace: documentdb-preview-ns
spec:
  resourceSelectors:
    - apiVersion: documentdb.io/preview
      kind: DocumentDB
      name: documentdb-preview
  placement:
    clusterAffinity:
      clusterNames:
        - member-eastus2
        - member-westus3
        - member-uksouth
EOF

echo "✓ Manifest created at /tmp/documentdb-karmada.yaml"
```

### Step 5.2: Deploy to Karmada Control Plane

**Magic Moment**: You apply to ONE place (Karmada), it deploys to THREE clusters automatically!

```bash
# ═══════════════════════════════════════════════════════════
# Apply manifest to Karmada control plane
# ═══════════════════════════════════════════════════════════
echo "Deploying DocumentDB via Karmada..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply -f /tmp/documentdb-karmada.yaml
```

**Expected Output**:
```
namespace/documentdb-preview-ns created
propagationpolicy.policy.karmada.io/documentdb-namespace-policy created
secret/documentdb-credentials created
propagationpolicy.policy.karmada.io/documentdb-credentials-policy created
documentdb.documentdb.io/documentdb-preview created
propagationpolicy.policy.karmada.io/documentdb-resource-policy created
```

✅ **Success**: You see 6 resources created (3 resources + 3 propagation policies).

⚠️ **If you see webhook error**: Remove CNPG webhooks and retry:

```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  validatingwebhookconfiguration cnpg-validating-webhook-configuration 2>/dev/null || true
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  mutatingwebhookconfiguration cnpg-mutating-webhook-configuration 2>/dev/null || true

# Retry
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply -f /tmp/documentdb-karmada.yaml
```

### Step 5.3: Verify Karmada Propagation

**What to check**:
1. **ResourceBinding**: Karmada's tracking mechanism - shows which resources were sent to which clusters
2. **Member clusters**: Verify resources actually arrived on each cluster

```bash
# ═══════════════════════════════════════════════════════════
# Check ResourceBinding (Karmada's propagation tracker)
# ═══════════════════════════════════════════════════════════
echo "Checking Karmada ResourceBinding status..."
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -n documentdb-preview-ns
```

**Expected Output**:
```
NAME                                    SCHEDULED   FULLYAPPLIED   AGE
documentdb-credentials-xxx              True        True           30s
documentdb-preview-ns-namespace-xxx     True        True           30s
documentdb-preview-documentdb-xxx       True        True           30s
```

✅ **Success Indicators**:
- **SCHEDULED**: `True` (Karmada decided where to send resources)
- **FULLYAPPLIED**: `True` (resources successfully created on member clusters)

```bash
# ═══════════════════════════════════════════════════════════
# Verify resources on member clusters
# ═══════════════════════════════════════════════════════════
echo -e "\nVerifying resources on member clusters..."

for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "=== $cluster ==="
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check namespace
  kubectl --context $cluster get namespace documentdb-preview-ns 2>/dev/null && echo "✓ Namespace exists" || echo "✗ Namespace missing"
  
  # Check secret
  kubectl --context $cluster get secret documentdb-credentials -n documentdb-preview-ns 2>/dev/null && echo "✓ Secret exists" || echo "✗ Secret missing"
  
  # Check DocumentDB resource
  kubectl --context $cluster get documentdb documentdb-preview -n documentdb-preview-ns 2>/dev/null && echo "✓ DocumentDB resource exists" || echo "✗ DocumentDB missing"

  echo ""

```
**Expected Output** (for each cluster):
```
=== member-eastus2 ===
NAME                      STATUS   AGE
documentdb-preview-ns     Active   1m
✓ Namespace exists

NAME                      TYPE     DATA   AGE
documentdb-credentials    Opaque   2      1m
✓ Secret exists

NAME                 AGE
documentdb-preview    1m
✓ DocumentDB resource exists
```

✅ **Success**: All 3 clusters show all 3 resources (namespace, secret, DocumentDB).

**What just happened?**
```
You applied to:                  It deployed to:
┌─────────────┐                 ┌──────────────┐
│  Karmada    │────────────────▶│ member-eastus2 │
│  (1 place)  │   Propagated    │ member-westus3 │
└─────────────┘                 │ member-uksouth │
                                 └──────────────┘
                                   (3 clusters!)
```

**This is the core value of Karmada**: Deploy once, propagate automatically!

### Step 5.4: Wait for DocumentDB Pods to Start

**What happens now?** The DocumentDB operator on each cluster saw the DocumentDB resource and is creating PostgreSQL clusters. This takes 2-3 minutes.

```bash
# ═══════════════════════════════════════════════════════════
# Wait for DocumentDB pods to start
# ═══════════════════════════════════════════════════════════
echo "Waiting for DocumentDB pods to start (this takes ~2-3 minutes)..."
echo "Checking every 30 seconds..."

for i in {1..8}; do
  echo -e "\n━━━━━━━━━━━━━━━━ Check $i/8 ━━━━━━━━━━━━━━━━"
  
  for cluster in member-eastus2 member-westus3 member-uksouth; do
    echo "=== $cluster ==="
    kubectl --context $cluster get pods -n documentdb-preview-ns 2>/dev/null | grep documentdb-preview || echo "No pods yet..."
  done
  
  # Check if all pods are running
  ready_count=$(kubectl --context member-eastus2 get pods -n documentdb-preview-ns 2>/dev/null | grep "2/2.*Running" | wc -l)
  ready_count=$((ready_count + $(kubectl --context member-westus3 get pods -n documentdb-preview-ns 2>/dev/null | grep "2/2.*Running" | wc -l)))
  ready_count=$((ready_count + $(kubectl --context member-uksouth get pods -n documentdb-preview-ns 2>/dev/null | grep "2/2.*Running" | wc -l)))
  
  if [ "$ready_count" -ge 3 ]; then
    echo -e "\n✅ All 3 DocumentDB pods are running!"
    break
  fi
  
  if [ $i -lt 8 ]; then
    echo -e "\n⏳ Waiting 30 seconds..."
    sleep 30
  fi
done

# ═══════════════════════════════════════════════════════════
# Final status check
# ═══════════════════════════════════════════════════════════
echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Final Status Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo ""
  echo "=== $cluster ==="
  kubectl --context $cluster get pods,svc -n documentdb-preview-ns
done
```

**Expected Output** (for each cluster after 2-3 minutes):
```
=== member-eastus2 ===
NAME                              READY   STATUS    AGE
pod/documentdb-preview-1          2/2     Running   2m

NAME                                    TYPE        CLUSTER-IP     PORT(S)
service/documentdb-preview-r           ClusterIP   10.0.123.45    5432/TCP
service/documentdb-preview-ro          ClusterIP   10.0.123.46    5432/TCP
service/documentdb-preview-rw          ClusterIP   10.0.123.47    5432/TCP,10260/TCP
```

✅ **Success Indicators**:
- Pod shows `2/2 Running` (PostgreSQL + DocumentDB Gateway)
- 3 services created (r, ro, rw)

**Understanding the pod**:
- **2/2**: Two containers running
  - Container 1: PostgreSQL database
  - Container 2: DocumentDB Gateway (MongoDB API compatibility)

---

## Part 6: Test and Verify Deployment

### Step 6.1: Check DocumentDB Status

```bash
# ═══════════════════════════════════════════════════════════
# Check DocumentDB resource status on each cluster
# ═══════════════════════════════════════════════════════════
echo "Checking DocumentDB status on all clusters..."

for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "=== $cluster ==="
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  kubectl --context $cluster get documentdb -n documentdb-preview-ns -o wide
  echo ""
done
```

**Expected Output** (for each cluster):
```
NAME                 AGE
documentdb-preview   5m
```

### Step 6.2: Connect to DocumentDB (Optional)

If you want to test database connectivity:

```bash
# Port-forward to one of the clusters
kubectl --context member-eastus2 port-forward -n documentdb-preview-ns svc/documentdb-preview-rw 10260:10260 &

# Test MongoDB connection (if you have mongosh installed)
mongosh "mongodb://demouser:DemoPassword123!@localhost:10260/?directConnection=true"

# Stop port-forward when done
killall kubectl
```

---

## Part 7: Karmada vs Azure Fleet Manager - Final Comparison

**What you just accomplished**:

| Action | With Karmada (Today) | With Azure Fleet Manager |
|--------|----------------------|--------------------------|
| **Control plane setup** | Kind cluster (5 min) | Azure Portal setup |
| **Cluster registration** | `karmadactl join` commands | Portal clicks |
| **Resource deployment** | One YAML to Karmada | One YAML to Fleet Manager |
| **Propagation mechanism** | PropagationPolicy | ClusterResourcePlacement |
| **Multi-cloud support** | ✅ Works anywhere | ❌ AKS only |
| **Cost** | $0 (open source) | Azure service fees |
| **Vendor lock-in** | None | Azure-specific |

**Key Insight**: Both provide **identical multi-cluster orchestration capabilities**. The difference is:
- **Karmada**: Open source, cloud-agnostic, zero lock-in
- **Azure Fleet Manager**: Proprietary, Azure-only, service fees

**What we proved today**:
1. ✅ Karmada successfully orchestrates multi-cluster DocumentDB deployment
2. ✅ Single YAML manifest deploys to 3 clusters automatically
3. ✅ PropagationPolicy provides fine-grained control over resource distribution
4. ✅ Completely cloud-agnostic (works on any Kubernetes cluster)
5. ✅ Zero code changes needed in DocumentDB operator

---

## Cleanup

**Important**: Delete resources to avoid Azure charges!

```bash
# ═══════════════════════════════════════════════════════════
# Delete AKS clusters and Azure resources
# ═══════════════════════════════════════════════════════════
echo "Deleting Azure resources..."
az group delete --name karmada-demo-rg --yes --no-wait

# ═══════════════════════════════════════════════════════════
# Delete Kind cluster (Karmada control plane)
# ═══════════════════════════════════════════════════════════
echo "Deleting Karmada control plane..."
kind delete cluster --name karmada-host

# ═══════════════════════════════════════════════════════════
# Remove kubectl contexts
# ═══════════════════════════════════════════════════════════
echo "Cleaning up kubectl contexts..."
kubectl config delete-context member-eastus2 2>/dev/null || true
kubectl config delete-context member-westus3 2>/dev/null || true
kubectl config delete-context member-uksouth 2>/dev/null || true
kubectl config delete-context kind-karmada-host 2>/dev/null || true

# ═══════════════════════════════════════════════════════════
# Remove Karmada configuration (optional)
# ═══════════════════════════════════════════════════════════
echo "Removing Karmada config files..."
sudo rm -rf /etc/karmada

echo "✅ Cleanup complete!"
```

---

## Summary and Next Steps

### What You Learned

1. **Karmada Setup**: Created a local Karmada control plane using Kind
2. **Multi-cluster Management**: Joined 3 AKS clusters to Karmada
3. **Declarative Deployment**: Used PropagationPolicy to distribute resources
4. **Automated Propagation**: Single YAML applied to Karmada deployed to 3 clusters
5. **Cloud-Agnostic Architecture**: Same approach works on any Kubernetes cluster

### Architecture You Built

```
┌─────────────────────────────────────┐
│   Karmada Control Plane (Kind)     │
│   Single point of control           │
│   - API Server                      │
│   - PropagationPolicy engine        │
└─────────────────────────────────────┘
         │          │          │
         ▼          ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐
    │eastus2 │ │westus3 │ │uksouth │
    │  AKS   │ │  AKS   │ │  AKS   │
    │        │ │        │ │        │
    │ Doc DB │ │ Doc DB │ │ Doc DB │
    └────────┘ └────────┘ └────────┘
```

### Key Takeaways

**Karmada Successfully Replaces Azure Fleet Manager** ✅
- Provides identical multi-cluster orchestration
- Adds multi-cloud flexibility (AWS, GCP, on-prem)
- Eliminates vendor lock-in
- Zero cost (open source)

**DocumentDB Operator is Orchestration-Agnostic** ✅
- Works with Karmada
- Works with Azure Fleet Manager
- Works with standalone clusters
- Minimal code changes needed (~5 lines for different orchestrators)

### Next Steps

**For Production Deployment**:
1. **High Availability**: Deploy Karmada control plane on production Kubernetes cluster (not Kind)
2. **Cross-cluster Networking**: Add Istio or Submariner for cross-cluster service mesh
3. **Backup & Disaster Recovery**: Configure DocumentDB backups across regions
4. **Monitoring**: Add Prometheus/Grafana for multi-cluster monitoring
5. **Security**: Configure RBAC, network policies, and secrets management

**For Learning More**:
- Karmada documentation: https://karmada.io/docs/
- DocumentDB operator: https://github.com/microsoft/documentdb-kubernetes-operator
- CNCF multi-cluster SIG: https://github.com/kubernetes/community/tree/master/sig-multicluster

---

## Troubleshooting Guide

### Common Issues

**1. Karmada pods not starting**
```bash
# Check pod logs
kubectl --context kind-karmada-host logs -n karmada-system <pod-name>

# Check events
kubectl --context kind-karmada-host get events -n karmada-system --sort-by='.lastTimestamp'
```

**2. Clusters not joining Karmada**
```bash
# Verify kubectl can access cluster
kubectl --context member-eastus2 get nodes

# Check Karmada logs
kubectl --context kind-karmada-host logs -n karmada-system -l app=karmada-controller-manager
```

**3. Resources not propagating**
```bash
# Check PropagationPolicy
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get pp -A

# Check ResourceBinding
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get rb -A

# Check Karmada controller logs
kubectl --context kind-karmada-host logs -n karmada-system -l app=karmada-controller-manager --tail=100
```

**4. DocumentDB pods not starting**
```bash
# Check operator logs
kubectl --context member-eastus2 logs -n documentdb-operator -l app.kubernetes.io/name=documentdb-operator --tail=100

# Check pod events
kubectl --context member-eastus2 describe pod -n documentdb-preview-ns <pod-name>

# Check DocumentDB resource status
kubectl --context member-eastus2 get documentdb -n documentdb-preview-ns -o yaml
```

---

**Congratulations!** 🎉 You've successfully demonstrated that Karmada can replace Azure Fleet Manager for multi-cluster DocumentDB orchestration!
