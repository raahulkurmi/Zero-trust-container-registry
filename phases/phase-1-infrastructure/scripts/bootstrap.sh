#!/usr/bin/env bash
# =============================================================================
# ZTCR — Phase 1 Bootstrap
# Installs: NGINX Ingress, cert-manager, TLS CA, namespaces, network policies
#
# Usage:
#   cd phases/phase-1-infrastructure
#   chmod +x scripts/bootstrap.sh
#   ./scripts/bootstrap.sh
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
section "Preflight Checks"

command -v kubectl >/dev/null 2>&1 || error "kubectl not found. Run: brew install kubectl"
command -v helm    >/dev/null 2>&1 || error "helm not found.    Run: brew install helm"
command -v k3d     >/dev/null 2>&1 || error "k3d not found.     Run: brew install k3d"

kubectl cluster-info >/dev/null 2>&1 \
  || error "Cannot reach cluster. Start it first: k3d cluster start ztcr-cluster"

info "Cluster reachable"
kubectl get nodes --no-headers | awk '{print "  Node: " $1 "  →  " $2}'

# ── Helm Repos ────────────────────────────────────────────────────────────────
section "Helm Repos"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack      https://charts.jetstack.io
helm repo add harbor        https://helm.goharbor.io
helm repo add bitnami       https://charts.bitnami.com/bitnami
helm repo add kyverno       https://kyverno.github.io/kyverno
helm repo add prometheus    https://prometheus-community.github.io/helm-charts
helm repo update

info "All repos added and updated"

# ── NGINX Ingress Controller ───────────────────────────────────────────────────
section "NGINX Ingress Controller"

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --wait --timeout 5m

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

info "NGINX Ingress Controller ready"

# ── cert-manager ──────────────────────────────────────────────────────────────
section "cert-manager"

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait --timeout 5m

kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s

info "cert-manager ready — waiting 30s for webhook to initialize..."
sleep 30

# ── TLS Certificate Authority ──────────────────────────────────────────────────
section "TLS Certificate Authority"

kubectl apply -f manifests/cert-manager-issuer.yaml

info "Waiting for CA certificate to be issued..."
kubectl wait --namespace cert-manager \
  --for=condition=ready certificate/ztcr-ca \
  --timeout=60s

sleep 5

ISSUER_READY=$(kubectl get clusterissuer ztcr-ca-issuer \
  -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "False")
[[ "$ISSUER_READY" == "True" ]] || error "ClusterIssuer ztcr-ca-issuer is not ready"

info "ClusterIssuer ztcr-ca-issuer is ready"

# ── Namespaces ────────────────────────────────────────────────────────────────
section "Namespaces"

kubectl apply -f manifests/namespaces.yaml

info "Namespaces created:"
kubectl get namespaces | grep -E "registry|identity|kyverno|monitoring|team-" \
  | awk '{print "  " $1 "  →  " $2}'

# ── Network Policies ──────────────────────────────────────────────────────────
section "Network Policies"

kubectl apply -f manifests/network-policies.yaml
info "Network policies applied"

# ── Summary ───────────────────────────────────────────────────────────────────
section "Summary"

echo ""
echo "  Nodes:"
kubectl get nodes --no-headers | awk '{print "    " $1 "  " $2}'

echo ""
echo "  Ingress:"
kubectl get pods -n ingress-nginx --no-headers \
  | awk '{print "    " $1 "  →  " $4}'

echo ""
echo "  cert-manager:"
kubectl get pods -n cert-manager --no-headers \
  | awk '{print "    " $1 "  →  " $4}'

echo ""
echo "  ClusterIssuers:"
kubectl get clusterissuer --no-headers \
  | awk '{print "    " $1 "  →  " $2}'

echo ""
echo "  Namespaces:"
kubectl get ns | grep -E "registry|identity|kyverno|monitoring|team-" \
  | awk '{print "    " $1}'

echo ""
echo -e "${GREEN}✅ Phase 1 Complete!${NC}"
echo ""
echo "  Remaining manual steps (run on your Mac terminal):"
echo ""
echo "  ① Add /etc/hosts entries:"
echo "      sudo tee -a /etc/hosts <<EOF"
echo "      127.0.0.1  registry.ztcr.local"
echo "      127.0.0.1  auth.ztcr.local"
echo "      127.0.0.1  grafana.ztcr.local"
echo "      EOF"
echo ""
echo "  ② Trust CA in macOS Keychain:"
echo "      kubectl get secret ztcr-ca-secret -n cert-manager \\"
echo "        -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ztcr-ca.crt"
echo "      sudo security add-trusted-cert -d -r trustRoot \\"
echo "        -k /Library/Keychains/System.keychain /tmp/ztcr-ca.crt"
echo ""
echo "  ③ Trust CA for Docker pulls:"
echo "      sudo mkdir -p /etc/docker/certs.d/registry.ztcr.local"
echo "      sudo cp /tmp/ztcr-ca.crt /etc/docker/certs.d/registry.ztcr.local/ca.crt"
echo "      (then restart Docker Desktop)"
echo ""
echo "  Next phase: phases/phase-2-keycloak/"
