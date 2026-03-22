#!/bin/bash
# ============================================================
# Keycloak Setup Script
# Creates: ztcr realm, harbor client, groups, dev-user
# Run this after Keycloak is deployed
# ============================================================

set -e

KEYCLOAK_URL="https://auth.ztcr.local:8443"
CA_CERT="/tmp/ztcr-ca.crt"
ADMIN_USER="admin"
ADMIN_PASS="ztcr-admin-secret"
HARBOR_CLIENT_SECRET="LB0XVHEgTlX1AvVrNxEcZ5cJTnRTqc9E"

echo "==> Getting admin token..."
ADMIN_TOKEN=$(curl -s -X POST \
  "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  --cacert $CA_CERT \
  -d "client_id=admin-cli" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASS" \
  -d "grant_type=password" | jq -r .access_token)

echo "==> Creating ztcr realm..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"realm":"ztcr","enabled":true}'

echo "==> Creating harbor client..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/ztcr/clients" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"clientId\":\"harbor\",\"enabled\":true,\"protocol\":\"openid-connect\",\"clientAuthenticatorType\":\"client-secret\",\"secret\":\"$HARBOR_CLIENT_SECRET\",\"redirectUris\":[\"https://registry.ztcr.local:8443/c/oidc/callback\"],\"webOrigins\":[\"https://registry.ztcr.local:8443\"],\"standardFlowEnabled\":true,\"directAccessGrantsEnabled\":true,\"publicClient\":false}"

echo "==> Creating groups..."
for group in harbor-admins harbor-developers harbor-viewers; do
  curl -s -X POST "$KEYCLOAK_URL/admin/realms/ztcr/groups" \
    --cacert $CA_CERT \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$group\"}"
  echo "Created: $group"
done

echo "==> Creating dev-user..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/ztcr/users" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"dev-user","email":"dev@ztcr.local","emailVerified":true,"enabled":true,"requiredActions":[],"credentials":[{"type":"password","value":"dev-password","temporary":false}]}'

echo "==> Adding dev-user to harbor-developers group..."
USER_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/ztcr/users?username=dev-user" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

GROUP_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/ztcr/groups" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[] | select(.name=="harbor-developers") | .id')

curl -s -X PUT "$KEYCLOAK_URL/admin/realms/ztcr/users/$USER_ID/groups/$GROUP_ID" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN"

echo "==> Adding groups claim mapper..."
CLIENT_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/ztcr/clients?clientId=harbor" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

curl -s -X POST "$KEYCLOAK_URL/admin/realms/ztcr/clients/$CLIENT_ID/protocol-mappers/models" \
  --cacert $CA_CERT \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"groups","protocol":"openid-connect","protocolMapper":"oidc-group-membership-mapper","config":{"claim.name":"groups","full.path":"false","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}'

echo ""
echo "✅ Keycloak setup complete!"
echo "   Realm:         ztcr"
echo "   Client:        harbor"
echo "   User:          dev-user / dev-password"
echo "   Groups:        harbor-admins, harbor-developers, harbor-viewers"
