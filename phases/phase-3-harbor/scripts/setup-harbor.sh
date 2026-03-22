#!/bin/bash
# ============================================================
# Harbor Setup Script
# Configures: OIDC, projects, robot accounts
# Run this after Harbor is deployed
# ============================================================

set -e

HARBOR_URL="https://registry.ztcr.local:8443"
HARBOR_ADMIN_PASS="Harbor12345"
KEYCLOAK_CLIENT_SECRET="LB0XVHEgTlX1AvVrNxEcZ5cJTnRTqc9E"

echo "==> Configuring OIDC..."
curl -k -X PUT "$HARBOR_URL/api/v2.0/configurations" \
  -u admin:$HARBOR_ADMIN_PASS \
  -H "Content-Type: application/json" \
  -d '{
    "auth_mode": "oidc_auth",
    "oidc_name": "Keycloak",
    "oidc_endpoint": "https://auth.ztcr.local/realms/ztcr",
    "oidc_client_id": "harbor",
    "oidc_client_secret": "'"$KEYCLOAK_CLIENT_SECRET"'",
    "oidc_groups_claim": "groups",
    "oidc_admin_group": "harbor-admins",
    "oidc_scope": "openid,profile,email,harbor-groups",
    "oidc_verify_cert": true,
    "oidc_auto_onboard": true,
    "oidc_user_claim": "preferred_username"
  }'

echo "==> Creating team-alpha project..."
curl -k -X POST "$HARBOR_URL/api/v2.0/projects" \
  -u admin:$HARBOR_ADMIN_PASS \
  -H "Content-Type: application/json" \
  -d '{"project_name":"team-alpha","public":false,"metadata":{"auto_scan":"true","severity":"high","prevent_vul":"true"}}'

echo "==> Creating team-beta project..."
curl -k -X POST "$HARBOR_URL/api/v2.0/projects" \
  -u admin:$HARBOR_ADMIN_PASS \
  -H "Content-Type: application/json" \
  -d '{"project_name":"team-beta","public":false,"metadata":{"auto_scan":"true","severity":"high","prevent_vul":"true"}}'

echo "==> Creating robot accounts..."
curl -k -X POST "$HARBOR_URL/api/v2.0/robots" \
  -u admin:$HARBOR_ADMIN_PASS \
  -H "Content-Type: application/json" \
  -d '{"name":"team-alpha-ci","description":"CI/CD robot for team-alpha","duration":-1,"level":"project","permissions":[{"kind":"project","namespace":"team-alpha","access":[{"resource":"repository","action":"push"},{"resource":"repository","action":"pull"},{"resource":"artifact","action":"read"},{"resource":"tag","action":"create"}]}]}' | jq '{name, secret}'

curl -k -X POST "$HARBOR_URL/api/v2.0/robots" \
  -u admin:$HARBOR_ADMIN_PASS \
  -H "Content-Type: application/json" \
  -d '{"name":"team-alpha-argocd","description":"ArgoCD pull-only robot for team-alpha","duration":-1,"level":"project","permissions":[{"kind":"project","namespace":"team-alpha","access":[{"resource":"repository","action":"pull"},{"resource":"artifact","action":"read"}]}]}' | jq '{name, secret}'

curl -k -X POST "$HARBOR_URL/api/v2.0/robots" \
  -u admin:$HARBOR_ADMIN_PASS \
  -H "Content-Type: application/json" \
  -d '{"name":"team-beta-ci","description":"CI/CD robot for team-beta","duration":-1,"level":"project","permissions":[{"kind":"project","namespace":"team-beta","access":[{"resource":"repository","action":"push"},{"resource":"repository","action":"pull"},{"resource":"artifact","action":"read"},{"resource":"tag","action":"create"}]}]}' | jq '{name, secret}'

echo ""
echo "✅ Harbor setup complete!"
echo "   Projects: team-alpha, team-beta"
echo "   Robots:   team-alpha-ci, team-alpha-argocd, team-beta-ci"
echo "   OIDC:     Keycloak → https://auth.ztcr.local/realms/ztcr"
