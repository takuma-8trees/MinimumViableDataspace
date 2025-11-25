# Docker Compose セットアップ完了

## ✅ 起動成功したサービス

### インフラストラクチャ
- **PostgreSQL Consumer** (localhost:5432)
- **PostgreSQL Provider** (localhost:5433)
- **PostgreSQL Issuer** (localhost:5434)
- **HashiCorp Vault** (localhost:8200) - Token: `root`
- **NGINX Issuer** (localhost:9876) - DID document配信

### アプリケーション
- **Issuer Service** (localhost:8091)
- **Consumer IdentityHub** (localhost:7080-7086)
- **Provider IdentityHub** (localhost:7090-7096)
- **Consumer Connector** (localhost:9080-9085, 11001)
- **Provider QnA Connector** (localhost:8190-8195, 12001)
- **Provider Manufacturing Connector** (localhost:8290-8295, 12002)
- **Provider Catalog Server** (localhost:8180-8185)

## 🔧 主な変更点

### 1. ヘルスチェックの修正
- Vault: `vault status` コマンドを使用
- NGINX: `wget` で127.0.0.1を指定

### 2. ポート設定
- Consumer Connectorは9080-9085に変更 (8080はKeycloakと競合のため)
- IdentityHubsは複数のAPIポートを正しく設定

### 3. 必要な環境変数の追加
- STS関連: `EDC_IAM_STS_OAUTH_CLIENT_SECRET_ALIAS`
- キー管理: `EDC_IAM_STS_PRIVATEKEY_ALIAS`, `EDC_IAM_STS_PUBLICKEY_ID`
- カタログ: `EDC_MVD_PARTICIPANTS_LIST_FILE`
- データベース: `EDC_SQL_SCHEMA_AUTOCREATE=true`

### 4. ボリュームマウント
- Credentials: `/credentials` ディレクトリ
- Public keys: PEMファイル
- Participants list: `participants.local.json`

## 📝 次のステップ

### データのシード
現在、全サービスは起動していますがデータが空です。以下が必要です：

1. **Vaultにシークレットを追加**
   - 各参加者の秘密鍵
   - STS client secrets

2. **IdentityHubsに参加者を登録**
   - Consumer participant
   - Provider participant

3. **Connectorsにアセットを作成**
   - Provider QnAに asset-1, asset-2
   - Provider Manufacturingに asset-1, asset-2

4. **Catalog Serverにリンクアセットを作成**
   - QnAとManufacturingへのポインター

## 🚀 使用方法

### 起動
```bash
docker compose up -d
```

### 停止
```bash
docker compose down
```

### ログ確認
```bash
docker compose logs -f [service-name]
```

### ステータス確認
```bash
docker compose ps
```

## 🔗 主要エンドポイント

### Consumer
- Management API: http://localhost:9081/api/management/
- Catalog API: http://localhost:9084/api/catalog
- IdentityHub: http://localhost:7080/api

### Provider QnA
- Management API: http://localhost:8191/api/management/
- DSP: http://localhost:8192/api/dsp

### Provider Manufacturing
- Management API: http://localhost:8291/api/management/
- DSP: http://localhost:8292/api/dsp

### Provider Catalog Server
- Management API: http://localhost:8181/api/management/
- Catalog API: http://localhost:8184/api/catalog

### 認証
Management APIへのアクセスには以下のヘッダーが必要：
```
X-Api-Key: password
```

## ⚠️ 注意事項

1. **ポート8080の競合**: 他のKeycloakコンテナが使用中のため、Consumer Connectorは9080を使用
2. **データ永続化**: PostgreSQLデータはDockerボリュームに保存
3. **開発環境のみ**: 本番環境では使用しないでください
