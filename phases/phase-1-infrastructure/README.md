# Phase 1 — Infrastructure Setup

**Goal:** A running K3d cluster with TLS, namespace isolation, and Helm ready — the foundation every other phase builds on.

**Time:** ~20 minutes  
**Prerequisites:** macOS, Docker Desktop running (4 CPU / 8 GB RAM allocated)

---

## What You'll Build

```
Your MacBook
└── Docker Desktop
    └── K3d cluster: ztcr-cluster
        ├── 1 server node + 2 agent nodes
        ├── ingress-nginx      → HTTPS routing (ports 80/443 → localhost)
        ├── cert-manager       → TLS certificate automation
        └── Namespaces
            ├── registry       → Harbor (Phase 3)
            ├── identity       → Keycloak (Phase 2)
            ├── kyverno        → Policy engine (Phase 5)
            ├── monitoring     → Prometheus + Grafana (Phase 7)
            ├── team-alpha     → workload namespace
            └── team-beta      → workload namespace
```

---

## Step 1 — Install Tools

```bash
brew install k3d kubectl helm cosign
```

Verify:
```bash
k3d version
kubectl version --client --short
helm version --short
cosign version
```

---

## Step 2 — Configure Docker Desktop

Open Docker Desktop → **Settings → Resources**:
- CPUs: `4`
- Memory: `8 GB`
- Disk: `40 GB`

Click **Apply & Restart**.

---

## Step 3 — Create K3d Cluster

```bash
k3d cluster create ztcr-cluster \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0" \
  --wait
```

| Flag | Purpose |
|---|---|
| `--servers 1 --agents 2` | 1 control plane + 2 workers |
| `--port "80:80@loadbalancer"` | Mac localhost:80 → cluster ingress |
| `--port "443:443@loadbalancer"` | Mac localhost:443 → cluster ingress |
| `--disable=traefik` | Remove default ingress; we use NGINX |

Verify:
```bash
kubectl get nodes
# NAME                         STATUS   ROLES                  AGE
# k3d-ztcr-cluster-server-0   Ready    control-plane,master   30s
# k3d-ztcr-cluster-agent-0    Ready    <none>                 25s
# k3d-ztcr-cluster-agent-1    Ready    <none>                 25s
```

---

## Step 4 — Run Bootstrap Script

```bash
# from repo root
cd phases/phase-1-infrastructure
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

Watch for `✅ Phase 1 Complete` at the end.

---

## Step 5 — Configure DNS (on your Mac)

```bash
sudo tee -a /etc/hosts <<EOF

# Zero Trust Container Registry — local dev
127.0.0.1  registry.ztcr.local
127.0.0.1  auth.ztcr.local
127.0.0.1  grafana.ztcr.local
EOF

# Verify
ping -c 1 registry.ztcr.local
# Expect: PING registry.ztcr.local (127.0.0.1)
```

---

## Step 6 — Trust the CA on macOS

```bash
# Extract CA cert from cluster
kubectl get secret ztcr-ca-secret \
  -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ztcr-ca.crt

# Trust in macOS Keychain (browser picks this up automatically)
sudo security add-trusted-cert \
  -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  /tmp/ztcr-ca.crt

# Trust for Docker CLI pulls/pushes
sudo mkdir -p /etc/docker/certs.d/registry.ztcr.local
sudo cp /tmp/ztcr-ca.crt /etc/docker/certs.d/registry.ztcr.local/ca.crt
```

**Restart Docker Desktop** after this step.

---

## Verification

```bash
echo "=== Nodes ===" && kubectl get nodes
echo "=== Ingress ===" && kubectl get pods -n ingress-nginx
echo "=== cert-manager ===" && kubectl get pods -n cert-manager
echo "=== ClusterIssuers ===" && kubectl get clusterissuer
echo "=== Namespaces ===" && kubectl get ns | grep -E "registry|identity|kyverno|monitoring|team-"
echo "=== DNS ===" && ping -c 1 registry.ztcr.local
```

All checks green → proceed to **[Phase 2 — Keycloak](../phase-2-keycloak/README.md)**

---

## Cluster Management

```bash
k3d cluster stop ztcr-cluster    # pause — preserves all data
k3d cluster start ztcr-cluster   # resume
k3d cluster delete ztcr-cluster  # full wipe / clean slate
k3d cluster list                 # show all clusters
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `port 80/443 already in use` | `sudo lsof -i :80` → kill conflicting process |
| cert-manager webhook errors | Wait 60s after install — webhook needs to init |
| Nodes stuck `NotReady` | `docker ps` — check K3d containers are running |
| Docker out of memory | Increase RAM in Docker Desktop → Resources |
| `bootstrap.sh: permission denied` | `chmod +x scripts/bootstrap.sh` |
