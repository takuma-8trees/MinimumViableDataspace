#!/bin/bash

set -e

echo "=========================================="
echo "Vaultにシークレットを追加"
echo "=========================================="

VAULT_ADDR="http://localhost:8200"
VAULT_TOKEN="root"

# Consumer用の秘密鍵を読み込み
CONSUMER_PRIVATE_KEY=$(cat deployment/assets/consumer_private.pem | sed 's/$/\\n/g' | tr -d '\n')

# Provider用の秘密鍵を読み込み
PROVIDER_PRIVATE_KEY=$(cat deployment/assets/provider_private.pem | sed 's/$/\\n/g' | tr -d '\n')

echo ""
echo "1. Consumer secrets を追加中..."

# Consumer秘密鍵
curl -s -X POST ${VAULT_ADDR}/v1/secret/data/did:web:consumer-identityhub:7083-alias \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"data\": {
      \"content\": \"${CONSUMER_PRIVATE_KEY}\"
    }
  }" > /dev/null

echo "  ✓ Consumer private key added"

# Consumer STS client secret
curl -s -X POST ${VAULT_ADDR}/v1/secret/data/did:web:consumer-identityhub:7083-sts-client-secret \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "content": "consumer-secret-123"
    }
  }' > /dev/null

echo "  ✓ Consumer STS client secret added"

echo ""
echo "2. Provider secrets を追加中..."

# Provider秘密鍵
curl -s -X POST ${VAULT_ADDR}/v1/secret/data/did:web:provider-identityhub:7093-alias \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"data\": {
      \"content\": \"${PROVIDER_PRIVATE_KEY}\"
    }
  }" > /dev/null

echo "  ✓ Provider private key added"

# Provider STS client secret
curl -s -X POST ${VAULT_ADDR}/v1/secret/data/did:web:provider-identityhub:7093-sts-client-secret \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "content": "provider-secret-456"
    }
  }' > /dev/null

echo "  ✓ Provider STS client secret added"

# Issuer signing key
curl -s -X POST ${VAULT_ADDR}/v1/secret/data/signing-key-alias \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "content": "issuer-signing-key"
    }
  }' > /dev/null

echo "  ✓ Issuer signing key added"

echo ""
echo "=========================================="
echo "Vault secrets 追加完了！"
echo "=========================================="
echo ""
echo "確認コマンド:"
echo "  curl -H \"X-Vault-Token: root\" http://localhost:8200/v1/secret/data/did:web:consumer-identityhub:7083-alias"
