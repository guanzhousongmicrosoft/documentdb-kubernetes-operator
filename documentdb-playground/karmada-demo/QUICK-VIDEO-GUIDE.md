# Quick Guide: 3-Minute Karmada Demo Video (Beginner Friendly)

This guide helps you do two things:

1. **Set up everything from zero** (first time, ~45-60 minutes, off-camera)
2. **Record a clean ~3-minute demo** (on-camera, pre-staged environment)

> Important: In this repo, the current compatible strategy is `crossCloudNetworkingStrategy: AzureFleet`, and this guide uses that path.

---

## 0) What you are proving in the video

You are proving three core capabilities:

1. **“Karmada can orchestrate one DocumentDB manifest to multiple AKS clusters from a single control plane.”**
2. **“You can show a clean baseline with no DocumentDB resource present in all member clusters before propagation.”**
3. **“One control-plane apply can fan out and create the same DocumentDB resource across all member clusters.”**

You are **not** proving full production hardening in ~3 minutes.

---

## 1) Prerequisites (install once)

You need a Mac with terminal access and Azure account permissions to create AKS clusters.

### 1.1 Install required tools

```bash
# Docker Desktop (required by Kind)
brew install --cask docker

# Kubernetes + Azure tools
brew install azure-cli kubectl helm kind

# Karmada CLI
curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | sudo bash

# Mongo shell for final connectivity proof
brew install mongosh
```

### 1.2 Verify tools

```bash
az version | head -n 3
kubectl version --client
helm version
docker --version
kind --version
karmadactl version
mongosh --version
```

Expected: every command prints a version (no “command not found”).

### 1.3 Login to Azure

```bash
az login
az account show --output table
```

Expected: your subscription is shown.

---

## 2) Full setup before recording (copy/paste order)

> Do this once before recording. This is the long part.

### 2.1 Go to repo and set helper variable

```bash
export REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT/documentdb-playground/karmada-demo"
```

### 2.2 Create local Kind cluster for Karmada control plane

```bash
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

kind create cluster --name karmada-host --config /tmp/kind-karmada.yaml
docker ps --filter "name=karmada-host" --format "table {{.Names}}\t{{.Ports}}"
```

Expected: cluster created and port `32443` mapped.

### 2.3 Install Karmada into the Kind cluster

```bash
sudo karmadactl init \
  --kubeconfig="$HOME/.kube/config" \
  --context=kind-karmada-host \
  --karmada-apiserver-advertise-address=127.0.0.1
  
```

Expected: Karmada init ends successfully.

Verify:

```bash
kubectl --context kind-karmada-host get pods -n karmada-system
```

Expected: Karmada system pods show `Running`.

### 2.4 Install CRDs on Karmada control plane

```bash
# Install CNPG CRDs (includes CNPG operator resources)
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply --server-side \
  -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml

# Remove CNPG operator resources from control plane (keep CRDs only)
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete deployment \
  -n cnpg-system cnpg-controller-manager 2>/dev/null || true
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  validatingwebhookconfiguration cnpg-validating-webhook-configuration 2>/dev/null || true
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete \
  mutatingwebhookconfiguration cnpg-mutating-webhook-configuration 2>/dev/null || true
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete namespace cnpg-system 2>/dev/null || true

# Install DocumentDB CRDs
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply \
  -f "$REPO_ROOT/operator/documentdb-helm-chart/crds/"
```

Verify:

```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get crd | grep -E "documentdb|cnpg"
```

Expected: DocumentDB and CNPG CRDs listed.

### 2.5 Create 3 AKS clusters (takes time)

```bash
"$REPO_ROOT/documentdb-playground/karmada-demo/deploy-clusters.sh"
```

Verify:

```bash
az aks list -g karmada-demo-rg \
  --query "[].{Name:name,Location:location,Status:provisioningState}" \
  -o table
```

Expected: `member-eastus2`, `member-westus3`, `member-uksouth` all `Succeeded`.

### 2.6 Pull kubeconfig contexts for all AKS clusters

```bash
az aks get-credentials --resource-group karmada-demo-rg --name member-eastus2 --overwrite-existing
az aks get-credentials --resource-group karmada-demo-rg --name member-westus3 --overwrite-existing
az aks get-credentials --resource-group karmada-demo-rg --name member-uksouth --overwrite-existing
kubectl config get-contexts | grep member-
```

Expected: 3 member contexts are listed.

### 2.7 Join all AKS clusters to Karmada

```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  sudo karmadactl --kubeconfig /etc/karmada/karmada-apiserver.config \
    join "$c" \
    --cluster-kubeconfig="$HOME/.kube/config" \
    --cluster-context="$c"
done
```

Verify:

```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters
```

Expected: all 3 clusters show `READY=True`.

### 2.8 Install cert-manager on each AKS cluster

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

for cluster in member-eastus2 member-westus3 member-uksouth; do
  helm --kube-context "$cluster" install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.2 \
    --set installCRDs=true \
    --wait
done
```

### 2.9 Install DocumentDB operator on each AKS cluster

```bash
for cluster in member-eastus2 member-westus3 member-uksouth; do
  helm --kube-context "$cluster" install documentdb-operator \
    "$REPO_ROOT/operator/documentdb-helm-chart" \
    --namespace documentdb-operator \
    --create-namespace \
    --wait
done
```

Verify operator:

```bash
"$REPO_ROOT/documentdb-playground/karmada-demo/verify-operator.sh"
```

Expected: each cluster reports operator ready.

### 2.10 Create cluster-name ConfigMap required by AzureFleet strategy

```bash
for cluster in member-eastus2 member-westus3 member-uksouth; do
  kubectl --context "$cluster" create configmap cluster-name -n kube-system \
    --from-literal=name="$cluster" \
    --dry-run=client -o yaml | kubectl --context "$cluster" apply -f -
done
```

### 2.11 Apply the one Karmada manifest

```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply \
  -f "$REPO_ROOT/documentdb-playground/karmada-demo/documentdb-karmada.yaml"
```

Expected: namespace + policies + secret + DocumentDB resource created.

### 2.12 Verify propagation and workload readiness

```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -n documentdb-preview-ns

for cluster in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $cluster ==="
  kubectl --context "$cluster" get namespace documentdb-preview-ns
  kubectl --context "$cluster" get secret documentdb-credentials -n documentdb-preview-ns
  kubectl --context "$cluster" get documentdb documentdb-preview -n documentdb-preview-ns
  kubectl --context "$cluster" get pods -n documentdb-preview-ns
done
```

Expected:
- ResourceBinding shows `SCHEDULED=True` and `FULLYAPPLIED=True`
- All 3 clusters contain namespace + secret + DocumentDB resource
- Pods eventually show `2/2 Running`

### 2.13 Final connectivity proof (for eastus2)

```bash
# Terminal A
kubectl --context member-eastus2 port-forward -n documentdb-preview-ns pod/member-eastus2-1 10260:10260
```

```bash
# Terminal B
PASS=$(kubectl --context member-eastus2 get secret documentdb-credentials -n documentdb-preview-ns -o jsonpath='{.data.password}' | base64 -d)

mongosh --host 127.0.0.1 --port 10260 \
  -u demouser -p "$PASS" \
  --tls --tlsAllowInvalidCertificates \
  --eval "db.runCommand({ping:1})"
```

Expected: output contains `{ ok: 1 }`.

---

## 3) Pre-recording checklist (must be green)

Run these right before recording:

```bash
# 1) Karmada sees all member clusters
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters

# 2) Last applied manifest is fully propagated
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -n documentdb-preview-ns

# 3) Workload healthy in all clusters
for c in member-eastus2 member-westus3 member-uksouth; do
  kubectl --context "$c" get pods -n documentdb-preview-ns
done

# 4) Policies exist on Karmada control plane (single source of placement)
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusterpropagationpolicy documentdb-namespace-policy
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n documentdb-preview-ns get propagationpolicy documentdb-credentials-policy documentdb-resource-policy
```

Ready to record only when:
- All clusters are `READY=True`
- ResourceBinding is fully applied
- Pods are `2/2 Running`
- Placement policies are present on the control plane

### 3.1 Required before recording: remove DocumentDB so you can recreate it live

For this demo script, always run this **right before recording** so the on-camera apply clearly recreates DocumentDB:

```bash
# Remove only the DocumentDB custom resource from Karmada control plane.
# Karmada propagates deletion to member clusters.
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n documentdb-preview-ns delete documentdb documentdb-preview --ignore-not-found

for c in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $c ==="
  kubectl --context "$c" -n documentdb-preview-ns get documentdb documentdb-preview --ignore-not-found
done

```

Then, during recording, apply `documentdb-karmada.yaml` (step below) to show DocumentDB recreation from one control plane command.

---

## 4) 3–5 minute recording transcript (~4:15 runbook)

> Use a pre-staged environment. Do not create clusters during recording.
> This transcript assumes Section 3.1 has already been run and `documentdb-preview` was deleted before you press record.

### Screen setup before pressing record

- In each terminal, run once:
  ```bash
  export REPO_ROOT="$(git rev-parse --show-toplevel)"
  export DEMO_RUN_ID="$(date +%H%M%S)"
  ```
- Terminal 1: Karmada control plane commands
- Terminal 2: Member cluster verification + mongosh
- Terminal 3: Keep port-forward running:
  ```bash
  kubectl --context member-eastus2 port-forward -n documentdb-preview-ns pod/member-eastus2-1 10260:10260
  ```
- Font zoomed enough for leadership/customer viewing

### 0:00 - 0:25 (Goal)

**Say**  
“In this demo, I’ll show how Karmada can propagate a resource across multiple clusters with a single command, as a proof point of Karmada for multi-cluster orchestration.”

### 0:25 - 0:45 (Control-plane readiness)

**Say (before command)**  
“First I’ll confirm that all member clusters are connected and ready in Karmada.”

**Do**
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters
```

**Say (after command)**  
“All three member clusters are ready, so one control plane can orchestrate all targets.”

### 0:45 - 1:15 (Clean baseline proof)

**Say (before command)**  
“First let's check all clusters are clean with no `documentdb-preview` resource exists yet.”

**Do**
```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $c (before apply) ==="
  kubectl --context "$c" get documentdb documentdb-preview -n documentdb-preview-ns --ignore-not-found
done
```

**Say (after command)**  
“No DocumentDB resource is returned from any cluster. That is our clean starting point.”

**Expected on screen**  
- No `documentdb-preview` output in all three clusters.

### 1:15 - 1:35 (Run one Karmada command)

**Say (before command)**  
“Now I run a single command in the Karmada control plane to deploy DocumentDB everywhere.”

**Do**
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply \
  -f "$REPO_ROOT/documentdb-playground/karmada-demo/documentdb-karmada.yaml"
```

**Say (after command)**  
“This is the only deployment command I run. Next I’ll verify fan-out to every member cluster.”

**Expected on screen**  
`documentdb-karmada.yaml` is applied from Karmada control plane.

### 1:35 - 2:15 (Fan-out proof across three clusters)

**Say (before command)**  
“Now I’ll verify the exact same DocumentDB resource appears in East US 2, West US 3, and UK South.”

**Do**
```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $c ==="
  kubectl --context "$c" get documentdb documentdb-preview -n documentdb-preview-ns
done
```

**Say (after command)**  
“All three clusters now show `documentdb-preview`. That is one-command propagation from a single control plane.”

**Expected on screen**  
`documentdb-preview` appears in all three clusters.

### 2:15 - 2:45 (Karmada propagation status)

**Say (before command)**  
“I’ll confirm Karmada status for scheduling and full apply.”

**Do**
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -n documentdb-preview-ns
```

**Say (after command)**  
“`SCHEDULED=True` and `FULLYAPPLIED=True` confirm Karmada completed placement and propagation.”

**Expected on screen**  
`SCHEDULED=True` and `FULLYAPPLIED=True`.

### 2:45 - 3:30 (Runtime proof with mongosh)

**Say (before command)**  
“Finally, I’ll prove this is not just declared state. I’ll connect and run a database ping.”

**Do**
```bash

kubectl --context member-eastus2 port-forward -n documentdb-preview-ns pod/member-eastus2-1 10260:10260


PASS=$(kubectl --context member-eastus2 get secret documentdb-credentials -n documentdb-preview-ns -o jsonpath='{.data.password}' | base64 -d)

mongosh --host 127.0.0.1 --port 10260 \
  -u demouser -p "$PASS" \
  --tls --tlsAllowInvalidCertificates \
  --eval "db.runCommand({ping:1})"

```

**Say (after command)**  
“The ping returns `{ ok: 1 }`, confirming the endpoint is operational.”

**Expected on screen**  
`{ ok: 1 }`

### 3:30 - 4:15 (Close)

**Say**  
“To summarize: we started from three empty clusters, ran one Karmada command, and then saw DocumentDB present across all three clusters with successful runtime connectivity.  
This demonstrates that Karmada can orchestrate multi-cluster application deployment with a single control plane and command.

---

## 5) If one status is not green before recording

- If pods are not `2/2 Running`, wait and recheck:
  ```bash
  for c in member-eastus2 member-westus3 member-uksouth; do
    kubectl --context "$c" get pods -n documentdb-preview-ns
  done
  ```
- If ping fails, ensure port-forward is running in another terminal:
  ```bash
  kubectl --context member-eastus2 port-forward -n documentdb-preview-ns pod/member-eastus2-1 10260:10260
  ```
- If DocumentDB is slow to become ready, keep the focus on control-plane fan-out proof (`resourcebinding`, per-cluster CR presence), then run the `mongosh` ping after recording.

Do not start recording until all checks are green.
