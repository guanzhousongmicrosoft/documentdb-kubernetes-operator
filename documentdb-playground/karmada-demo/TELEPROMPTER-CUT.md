# 2-Minute Demo Teleprompter Cut (Read + Run)

Use this only after environment is fully pre-staged.

---

## Pre-roll (do before recording)

Run once in each terminal:

```bash
export REPO_ROOT="$(git rev-parse --show-toplevel)"
```

Keep this running in **Terminal 3**:

```bash
kubectl --context member-eastus2 port-forward -n documentdb-preview-ns pod/member-eastus2-1 10260:10260
```

---

## Recording script (2:00)

### 0:00 - 0:20

**Say:**  
“In two minutes, I’ll show Karmada orchestrating DocumentDB across three AKS clusters from one manifest, using the AzureFleet strategy.”

**Run (Terminal 1):**
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters
```

**You should see:**  
`member-eastus2`, `member-westus3`, `member-uksouth` and all `READY=True`.

---

### 0:20 - 0:45

**Say:**  
“Now I apply one YAML to Karmada, instead of deploying to each cluster separately.”

**Run (Terminal 1):**
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config apply \
  -f "$REPO_ROOT/documentdb-playground/karmada-demo/documentdb-karmada.yaml"
```

**You should see:**  
created/configured resources for namespace, policy, secret, and DocumentDB.

---

### 0:45 - 1:05

**Say:**  
“Karmada now reports the resources are scheduled and fully applied to member clusters.”

**Run (Terminal 1):**
```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -n documentdb-preview-ns
```

**You should see:**  
`SCHEDULED=True` and `FULLYAPPLIED=True`.

---

### 1:05 - 1:30

**Say:**  
“Now I verify the DocumentDB resource exists on all three AKS clusters.”

**Run (Terminal 2):**
```bash
for c in member-eastus2 member-westus3 member-uksouth; do
  echo "=== $c ==="
  kubectl --context "$c" get documentdb documentdb-preview -n documentdb-preview-ns
done
```

**You should see:**  
`documentdb-preview` returned in each cluster block.

---

### 1:30 - 1:55

**Say:**  
“Finally, I’ll prove the endpoint is working by running a Mongo ping.”

**Run (Terminal 2):**
```bash
PASS=$(kubectl --context member-eastus2 get secret documentdb-credentials -n documentdb-preview-ns -o jsonpath='{.data.password}' | base64 -d)

mongosh --host 127.0.0.1 --port 10260 \
  -u demouser -p "$PASS" \
  --tls --tlsAllowInvalidCertificates \
  --eval "db.runCommand({ping:1})"
```

**You should see:**  
`{ ok: 1 }`

---

### 1:55 - 2:00

**Say:**  
“This shows single-point, multi-cluster orchestration: one manifest through Karmada, propagated and operational across three AKS clusters.”

---

## If one status is missing (pause recording)

```bash
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters
sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get resourcebinding -n documentdb-preview-ns
for c in member-eastus2 member-westus3 member-uksouth; do kubectl --context "$c" get pods -n documentdb-preview-ns; done
```

Record only when all are green.
