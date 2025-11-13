# Docker Compose デプロイメントガイド

このガイドでは、Docker Composeを使用してMinimum Viable Dataspace (MVD)をデプロイする方法を説明します。

## 前提条件

- Docker 20.10以上
- Docker Compose 2.0以上
- Java 17以上（ビルド時のみ必要）
- 16GB以上のRAM推奨

## アーキテクチャ概要

このDocker Compose環境には以下のコンポーネントが含まれます：

### インフラストラクチャ
- **PostgreSQL (3インスタンス)**: Consumer、Provider、Issuer用のデータベース
- **HashiCorp Vault**: シークレット管理
- **NGINX**: Issuer DID documentのホスティング

### アプリケーション
- **Issuer Service**: VerifiableCredentialsの発行サービス
- **Consumer側**:
  - Consumer IdentityHub (ポート: 7083, 7086)
  - Consumer Connector (ポート: 8080-8085, 11001)
- **Provider側**:
  - Provider IdentityHub (ポート: 7093, 7096)
  - Provider Connector - QnA (ポート: 8190-8195, 12001)
  - Provider Connector - Manufacturing (ポート: 8290-8295, 12002)
  - Provider Catalog Server (ポート: 8180-8185)

## クイックスタート

### 1. プロジェクトをビルド

```bash
chmod +x build-docker.sh
./build-docker.sh
```

このスクリプトは以下を実行します：
- Gradleでプロジェクトをビルド
- 全てのランチャーのJARファイルを生成

### 2. Dockerイメージをビルド

```bash
docker-compose build
```

### 3. 環境を起動

```bash
# 全サービスをバックグラウンドで起動
docker-compose up -d

# ログを確認
docker-compose logs -f
```

### 4. サービスのヘルスチェック

```bash
# 全サービスのステータス確認
docker-compose ps

# 特定のサービスのヘルスチェック
curl http://localhost:8081/api/check/health  # Consumer Connector
curl http://localhost:8191/api/check/health  # Provider QnA Connector
curl http://localhost:7083/api/check/health  # Consumer IdentityHub
```

### 5. データスペースをシード（初回のみ）

```bash
chmod +x seed-docker.sh
./seed-docker.sh
```

## 主要なエンドポイント

### Consumer Connector
- **Management API**: http://localhost:8081/api/management/
- **DSP Protocol**: http://localhost:8082/api/dsp
- **Catalog API**: http://localhost:8084/api/catalog
- **Data Plane Public**: http://localhost:11001/api/public

### Provider QnA Connector
- **Management API**: http://localhost:8191/api/management/
- **DSP Protocol**: http://localhost:8192/api/dsp
- **Catalog API**: http://localhost:8194/api/catalog
- **Data Plane Public**: http://localhost:12001/api/public

### Provider Manufacturing Connector
- **Management API**: http://localhost:8291/api/management/
- **DSP Protocol**: http://localhost:8292/api/dsp
- **Catalog API**: http://localhost:8294/api/catalog
- **Data Plane Public**: http://localhost:12002/api/public

### Provider Catalog Server
- **Management API**: http://localhost:8181/api/management/
- **DSP Protocol**: http://localhost:8182/api/dsp
- **Catalog API**: http://localhost:8184/api/catalog

### IdentityHubs
- **Consumer IdentityHub**: http://localhost:7083/api
- **Consumer STS**: http://localhost:7086/api/sts
- **Provider IdentityHub**: http://localhost:7093/api
- **Provider STS**: http://localhost:7096/api/sts

### その他
- **Issuer Service**: http://localhost:8091/api
- **Vault UI**: http://localhost:8200 (Token: `root`)
- **NGINX (Issuer DID)**: http://localhost:9876/.well-known/did.json

## 認証

Management APIとCatalog APIへのアクセスには認証が必要です：

```bash
# Management API例
curl -X GET http://localhost:8081/api/management/v3/assets \
  -H "X-Api-Key: password"

# Catalog API例
curl -X GET http://localhost:8084/api/catalog \
  -H "X-Api-Key: password"
```

## Postmanコレクション

RESTリクエストをテストするには、プロジェクトに含まれるPostmanコレクションを使用できます：

```
deployment/postman/MVD.postman_collection.json
deployment/postman/MVD Local Development.postman_environment.json
```

Postmanで上記のファイルをインポートして使用してください。

## トラブルシューティング

### サービスが起動しない場合

```bash
# ログを確認
docker-compose logs [service-name]

# 例：Consumer Connectorのログを確認
docker-compose logs consumer-connector
```

### データベース接続エラー

```bash
# PostgreSQLコンテナが稼働しているか確認
docker-compose ps postgres-consumer postgres-provider postgres-issuer

# データベースに直接接続して確認
docker exec -it mvd-postgres-consumer psql -U consumer -d consumer
```

### メモリ不足

Docker Desktopの設定でメモリを増やしてください（推奨: 8GB以上）。

### ポート競合

他のアプリケーションが使用しているポートと競合している場合は、`docker-compose.yml`のポートマッピングを変更してください。

## コンテナの管理

```bash
# 全サービスを停止
docker-compose stop

# 全サービスを停止して削除（データは保持）
docker-compose down

# 全サービスとボリュームを削除（データも削除）
docker-compose down -v

# 特定のサービスのみ再起動
docker-compose restart consumer-connector

# サービスを再ビルドして起動
docker-compose up -d --build

# リソース使用状況を確認
docker stats
```

## データの永続化

以下のDockerボリュームにデータが永続化されます：

- `postgres-consumer-data`: Consumer用データベース
- `postgres-provider-data`: Provider用データベース
- `postgres-issuer-data`: Issuer用データベース

ボリュームを確認：
```bash
docker volume ls | grep mvd
```

## 開発とデバッグ

### ログレベルの変更

`docker-compose.yml`の各サービスの環境変数に以下を追加：

```yaml
environment:
  JAVA_TOOL_OPTIONS: "-Djava.util.logging.level=DEBUG"
```

### コンテナ内でコマンド実行

```bash
# コンテナ内でシェルを起動
docker exec -it mvd-consumer-connector sh

# ログファイルを確認
docker exec mvd-consumer-connector cat /app/logs/edc.log
```

## 制限事項と注意事項

1. **本番環境では使用しないでください**: このDocker Compose設定は開発・デモ目的のみです。
2. **DID設定**: `did:web`を使用しており、コンテナ名ベースのDIDになっています。
3. **認証情報**: デフォルトの認証情報（`password`）を使用しています。本番環境では変更してください。
4. **Vault**: 開発モード（dev mode）で動作しており、データは永続化されません。
5. **UI**: 専用のWeb UIは含まれていません。REST API経由での操作になります。

## 次のステップ

1. [元のREADME](../README.md)で動作シナリオを理解する
2. Postmanコレクションを使ってAPIを試す
3. カタログの取得、契約交渉、データ転送を実行する

## 参考リンク

- [Eclipse Dataspace Components](https://github.com/eclipse-edc/Connector)
- [IdentityHub](https://github.com/eclipse-edc/IdentityHub)
- [Decentralized Claims Protocol](https://github.com/eclipse-tractusx/identity-trust)

## サポート

問題が発生した場合は、[GitHubリポジトリ](https://github.com/eclipse-edc/MinimumViableDataspace/issues)でIssueを作成してください。
