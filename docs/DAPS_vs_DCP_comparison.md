# DAPS認証 vs DCP認証の比較

## 概要

このドキュメントでは、従来のDAPS (Dynamic Attribute Provisioning Service)認証と、MinimumViableDataspace (MVD)で使用されているDCP (Decentralized Claims Protocol)認証の違いを説明します。

---

## 1. アーキテクチャの違い

### DAPS認証 (中央集権型)

```
┌─────────────┐
│   Consumer  │
└──────┬──────┘
       │ 1. 証明書で認証
       ↓
┌─────────────┐
│    DAPS     │←── 中央認証局
│   Server    │
└──────┬──────┘
       │ 2. DATトークン発行
       ↓
┌─────────────┐
│   Provider  │
└──────┬──────┘
       │ 3. DATを検証
       ↓
   データ提供
```

**特徴:**
- 単一のDAPS サーバーが全参加者を認証
- X.509証明書ベース
- DAT (Dynamic Attribute Token) = JWT形式のアクセストークン
- DAP Sサーバーに障害が発生すると全体が停止

---

### DCP認証 (分散型)

```
┌──────────────────┐
│ Issuer Service   │←── Verifiable Credentials発行
│ (Dataspace Trust │    (MembershipCredential, etc.)
│     Anchor)      │
└────────┬─────────┘
         │ 発行
    ┌────┴────┐
    ↓         ↓
┌─────────┐ ┌─────────┐
│Consumer │ │Provider │
│Identity │ │Identity │
│  Hub    │ │  Hub    │
└────┬────┘ └────┬────┘
     │           │
     │ 3. VP提示│
     ↓           ↓
┌─────────┐ ┌─────────┐
│Consumer │ │Provider │
│Connector│→│Connector│
└─────────┘ └─────────┘
    1. カタログ要求
    2. Scope抽出
    4. VC検証
    5. データ提供
```

**特徴:**
- 各参加者が独自のIdentityHubを持つ
- W3C標準のVerifiable Credentials
- DID (Decentralized Identifier) ベース
- Issuer Serviceが信頼の基点だが常時接続不要

---

## 2. 認証フローの違い

### DAPS認証フロー

```bash
# 1. Consumer: クライアント証明書でDAPS に認証
curl -X POST https://daps.example.com/token \
  --cert consumer.crt \
  --key consumer.key \
  -d "grant_type=client_credentials&scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"

# 2. DAPS: DATトークンを発行
{
  "access_token": "eyJhbGci...",  # DAT (JWT)
  "token_type": "Bearer",
  "expires_in": 3600
}

# 3. Consumer: DATをBearerトークンとしてProviderに送信
curl -X POST https://provider.example.com/api/catalog \
  -H "Authorization: Bearer eyJhbGci..."

# 4. Provider: DATの署名を検証 (DAP S公開鍵で)
#    - 発行者がDAPS か
#    - 有効期限内か
#    - 適切な属性を持っているか
```

**課題:**
- DAPS サーバーが単一障害点 (SPOF)
- 証明書管理が煩雑
- 属性の更新にDAPS 再発行が必要

---

### DCP認証フロー (MVD)

```bash
# === 事前準備: Issuer ServiceがVCを発行 ===
# Consumer IdentityHubにMembershipCredentialが保存されている

# 1. Consumer Connector: Providerのカタログ要求
curl -X POST http://provider-connector:8184/api/dsp/v1/catalog/request \
  -H "Content-Type: application/json" \
  -d '{
    "@context": "https://w3id.org/dspace/v1/context.json",
    "@type": "CatalogRequestMessage"
  }'

# 2. Consumer Connector内部処理:
#    a. ポリシーから必要なスコープを抽出
#       Policy: { "constraint": { "leftOperand": "Membership.active" } }
#       ↓
#       Scope: "org.eclipse.edc.vc.type:MembershipCredential:read"
#
#    b. STSにアクセストークンを要求
curl -X POST http://consumer-identityhub:7086/api/sts/token \
  -d "grant_type=client_credentials" \
  -d "client_id=did:web:consumer-identityhub:7083" \
  -d "client_secret=consumer-secret-123" \
  -d "scope=org.eclipse.edc.vc.type:MembershipCredential:read"

# 3. Consumer IdentityHub (STS):
#    a. クライアント認証 (client_id + client_secret)
#    b. 要求されたスコープに対応するVCを取得
#    c. Verifiable Presentation (VP) を作成
#    d. VPを含むアクセストークン (JWT) を発行
{
  "access_token": "eyJhbGci...",  # JWT内に"vp"クレームを含む
  "token_type": "Bearer",
  "expires_in": 300
}

# 4. Consumer Connector: アクセストークンをDSPメッセージに添付
#    DSPプロトコルのAuthorizationヘッダーに設定

# 5. Provider Connector: トークン検証
#    a. JWTの署名を検証 (Consumer IdentityHubの公開鍵で)
#    b. "vp"クレームからVerifiable Presentationを抽出
#    c. VP内のVerifiable Credentialsを検証:
#       - 発行者がIssuer Service (信頼されたIssuer) か
#       - 有効期限内か
#       - 取り消されていないか
#    d. ポリシー評価:
#       - MembershipCredentialが存在するか
#       - membership.activeがtrueか
#    e. すべて成功 → カタログを返す
```

**メリット:**
- 中央サーバー不要 (Issuerは発行時のみ)
- VCは長期間有効 (再発行不要)
- 詳細なアクセス制御が可能

---

## 3. データ構造の違い

### DAPS: DAT (Dynamic Attribute Token)

```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT"
  },
  "payload": {
    "iss": "https://daps.example.com",
    "sub": "consumer-connector",
    "aud": "idsc:IDS_CONNECTORS_ALL",
    "exp": 1700000000,
    "iat": 1699996400,
    "securityProfile": "idsc:BASE_SECURITY_PROFILE",
    "referringConnector": "https://consumer.example.com"
  }
}
```

---

### DCP: Access Token with Verifiable Presentation

```json
{
  "header": {
    "alg": "ES256",
    "typ": "JWT"
  },
  "payload": {
    "iss": "did:web:consumer-identityhub:7083",
    "sub": "did:web:consumer-identityhub:7083",
    "aud": "did:web:provider-identityhub:7093",
    "exp": 1700000000,
    "iat": 1699999700,
    "scope": "org.eclipse.edc.vc.type:MembershipCredential:read",
    "vp": {
      "@context": ["https://www.w3.org/2018/credentials/v1"],
      "type": ["VerifiablePresentation"],
      "verifiableCredential": [
        {
          "@context": [
            "https://www.w3.org/2018/credentials/v1",
            "https://w3id.org/mvd/credentials/"
          ],
          "type": ["VerifiableCredential", "MembershipCredential"],
          "issuer": "did:web:dataspace-issuer",
          "issuanceDate": "2024-01-01T00:00:00Z",
          "expirationDate": "2025-12-31T23:59:59Z",
          "credentialSubject": {
            "id": "did:web:consumer-identityhub:7083",
            "holderIdentifier": "BPNL000000000001",
            "membership": {
              "memberOf": "Dataspace-X",
              "active": true,
              "since": "2024-01-01T00:00:00Z"
            }
          },
          "proof": {
            "type": "JwtProof2020",
            "jwt": "eyJhbGci..."  # Issuer Serviceの署名
          }
        }
      ]
    }
  }
}
```

---

## 4. セキュリティモデルの違い

| 項目 | DAPS認証 | DCP認証 (MVD) |
|------|----------|---------------|
| **信頼モデル** | 中央集権 (DAPS が全参加者を信頼) | 分散型 (Issuerが信頼の基点) |
| **認証方式** | X.509証明書 + OAuth2 | DID + Verifiable Credentials |
| **トークン** | DAT (シンプルなJWT) | VP付きアクセストークン |
| **公開鍵管理** | DAPS 公開鍵1つ | DID Document経由で各参加者の公開鍵 |
| **失効管理** | 証明書失効リスト (CRL) | StatusList2021 |
| **スケーラビリティ** | 低 (DAPS がボトルネック) | 高 (各IdentityHubが独立) |
| **プライバシー** | DAT に全属性を含む | 必要なVCのみ提示 (Selective Disclosure) |
| **標準準拠** | IDS-RAM (カスタム仕様) | W3C VC Data Model |

---

## 5. 実装上の違い

### DAPS認証実装

```java
// DAP S認証拡張 (EDC古いバージョン)
public class DapsTokenProvider {
    public String obtainToken() {
        // 1. クライアント証明書で認証
        var request = HttpRequest.newBuilder()
            .uri(dapsUrl)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .POST(BodyPublishers.ofString(
                "grant_type=client_credentials&scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"))
            .build();
        
        // 2. DAT取得
        var response = httpClient.send(request, BodyHandlers.ofString());
        return parseToken(response.body());
    }
}
```

---

### DCP認証実装 (MVD)

```java
// Identity & Trust拡張 (EDC最新)
public class IdentityAndTrustService {
    
    // 1. Scope抽出
    public Set<String> extractScopes(Policy policy) {
        // ポリシーから必要なVCタイプを判断
        // "Membership.active" → "org.eclipse.edc.vc.type:MembershipCredential:read"
        return scopeExtractor.extract(policy);
    }
    
    // 2. STSでVP付きトークン取得
    public String obtainToken(String participantId, Set<String> scopes) {
        var tokenRequest = TokenRequest.Builder.newInstance()
            .audience(providerId)
            .scopes(scopes)
            .build();
        return stsClient.obtainClientCredentials(tokenRequest);
    }
    
    // 3. VP検証
    public Result<Void> verifyPresentation(String token) {
        var jwt = parseJwt(token);
        var vp = jwt.getClaim("vp");
        
        // VPから各VCを取り出して検証
        for (var vc : vp.getVerifiableCredentials()) {
            // - 発行者が信頼されているか
            if (!trustedIssuerRegistry.isTrusted(vc.getIssuer())) {
                return Result.failure("Untrusted issuer");
            }
            
            // - 有効期限内か
            if (vc.isExpired()) {
                return Result.failure("Credential expired");
            }
            
            // - 署名が正しいか
            if (!verifySignature(vc)) {
                return Result.failure("Invalid signature");
            }
        }
        
        return Result.success();
    }
    
    // 4. ポリシー評価
    public boolean evaluatePolicy(Policy policy, ParticipantAgent agent) {
        // ParticipantAgentに検証済みVCが含まれている
        var credentials = agent.getClaims().get("vc");
        
        // ポリシー関数で評価
        return policyEngine.evaluate(policy, agent);
    }
}
```

---

## 6. MVDでの具体例

### MembershipCredentialを要求するポリシー

```json
{
  "@type": "Set",
  "permission": [
    {
      "action": "use",
      "constraint": {
        "leftOperand": "Membership.active",
        "operator": "eq",
        "rightOperand": "true"
      }
    }
  ]
}
```

**処理フロー:**

1. **Scope抽出** (`MembershipCredentialScopeExtractor`)
   ```
   "Membership.active" → "org.eclipse.edc.vc.type:MembershipCredential:read"
   ```

2. **STS要求**
   ```bash
   POST /api/sts/token
   scope=org.eclipse.edc.vc.type:MembershipCredential:read
   ```

3. **VC選択** (Consumer IdentityHub)
   - MembershipCredentialをストアから取得
   - VPにラップしてトークンに含める

4. **検証** (Provider Connector)
   - VP内のMembershipCredentialを検証
   - Issuer署名を確認
   - 有効期限を確認

5. **ポリシー評価** (`MembershipCredentialEvaluationFunction`)
   ```java
   var membership = credential.getCredentialSubject().get("membership");
   return membership.get("active").equals(true);
   ```

---

## 7. まとめ

| 観点 | DAPS | DCP (MVD) |
|------|------|-----------|
| **複雑さ** | シンプル | 高度 |
| **柔軟性** | 低 | 高 |
| **スケーラビリティ** | 低 | 高 |
| **プライバシー** | 低 | 高 |
| **標準準拠** | IDS固有 | W3C標準 |
| **学習曲線** | 緩やか | 急峻 |
| **本番適用** | Catena-X (旧) | Catena-X (新) |

**結論:**
- **DAPS**: OAuth2 + X.509証明書によるシンプルな中央集権型認証
- **DCP**: Verifiable Credentials + DIDによる分散型・高度な認証

MVDはDCPを採用することで、W3C標準準拠かつ将来性のある分散型データスペースを実現しています。
