# MinimumViableDataspace (MVD) アーキテクチャと認証フロー解説

## 目次
1. [システム構成図](#1-システム構成図)
2. [DCP認証とDAPSの違い](#2-dcp認証とdapsの違い)
3. [IdentityHubの役割](#3-identityhubの役割)
4. [参加者登録プロセス](#4-参加者登録プロセス)
5. [カタログ取得フロー (詳細)](#5-カタログ取得フロー-詳細)
6. [契約交渉・データ転送フロー](#6-契約交渉データ転送フロー)
7. [実践例: リクエスト/レスポンス](#7-実践例-リクエストレスポンス)

---

## 1. システム構成図

### 1.1 全体アーキテクチャ

```mermaid
graph TB
    subgraph "Dataspace Infrastructure"
        Issuer[Issuer Service<br/>VC発行局]
        NGINX[NGINX<br/>DID Document配信]
    end

    subgraph "Consumer Corp (消費者企業)"
        ConsumerIH[Consumer IdentityHub<br/>Port: 7081-7086]
        ConsumerConn[Consumer Connector<br/>Port: 9080-9085]
        ConsumerVault[Vault]
        ConsumerDB[(PostgreSQL)]
    end

    subgraph "Provider Corp (提供者企業)"
        ProviderIH[Provider IdentityHub<br/>Port: 7091-7096]
        ProviderQnA[Provider Connector QnA<br/>Port: 8190-8195]
        ProviderMfg[Provider Connector Mfg<br/>Port: 8290-8295]
        ProviderCatalog[Provider Catalog Server<br/>Port: 8180-8185]
        ProviderVault[Vault]
        ProviderDB[(PostgreSQL)]
    end

    Issuer -->|VCを発行| ConsumerIH
    Issuer -->|VCを発行| ProviderIH
    
    ConsumerConn -->|STS Token要求| ConsumerIH
    ConsumerConn -->|秘密鍵取得| ConsumerVault
    ConsumerIH -->|データ保存| ConsumerDB
    
    ProviderQnA -->|STS Token要求| ProviderIH
    ProviderMfg -->|STS Token要求| ProviderIH
    ProviderCatalog -->|STS Token要求| ProviderIH
    ProviderQnA -->|秘密鍵取得| ProviderVault
    ProviderMfg -->|秘密鍵取得| ProviderVault
    ProviderCatalog -->|秘密鍵取得| ProviderVault
    ProviderIH -->|データ保存| ProviderDB
    
    ConsumerConn -.->|DSPプロトコル| ProviderCatalog
    ConsumerConn -.->|DSPプロトコル| ProviderQnA
    ConsumerConn -.->|DSPプロトコル| ProviderMfg
    
    NGINX -->|DID Document| ConsumerConn
    NGINX -->|DID Document| ProviderConn

    style ConsumerIH fill:#e1f5ff
    style ProviderIH fill:#e1f5ff
    style Issuer fill:#ffe1e1
```

### 1.2 重要な設計原則

**1つの企業 = 1つのIdentityHub + 複数のConnector**

```mermaid
graph LR
    subgraph "Provider Corp"
        PID[ParticipantID:<br/>did:web:provider-identityhub:7093]
        
        subgraph "共有アイデンティティ"
            PIH[IdentityHub<br/>1つ]
            PVC[Verifiable Credentials<br/>- MembershipCredential<br/>- DataProcessorCredential]
            PKEY[鍵ペア<br/>- Public Key<br/>- Private Key]
        end
        
        subgraph "複数のランタイム"
            PC1[Connector QnA]
            PC2[Connector Manufacturing]
            PC3[Catalog Server]
        end
        
        PIH --> PC1
        PIH --> PC2
        PIH --> PC3
        PVC --> PIH
        PKEY --> PIH
    end
    
    style PIH fill:#b3e5fc
    style PVC fill:#fff9c4
    style PKEY fill:#ffccbc
```

---

## 2. DCP認証とDAPSの違い

### 2.1 認証方式の比較

```mermaid
graph TB
    subgraph "DAPS認証 (従来の中央集権型)"
        C1[Consumer Connector]
        DAPS[DAPS Server<br/>中央認証局]
        P1[Provider Connector]
        
        C1 -->|1. X.509証明書で認証| DAPS
        DAPS -->|2. DAT発行| C1
        C1 -->|3. DATをBearerトークンとして送信| P1
        P1 -->|4. DAPS公開鍵で検証| P1
    end
    
    subgraph "DCP認証 (MVDの分散型)"
        C2[Consumer Connector]
        CIH[Consumer IdentityHub<br/>STS]
        P2[Provider Connector]
        ISS[Issuer Service<br/>VC発行のみ]
        
        ISS -.->|事前にVC発行| CIH
        C2 -->|1. スコープ指定でトークン要求| CIH
        CIH -->|2. VP付きトークン発行| C2
        C2 -->|3. VP付きトークンを送信| P2
        P2 -->|4. VCの署名・ポリシー検証| P2
    end
    
    style DAPS fill:#ffcdd2
    style ISS fill:#c8e6c9
    style CIH fill:#b3e5fc
```

### 2.2 主な違い

| 項目 | DAPS認証 | DCP認証 (MVD) |
|------|----------|---------------|
| **アーキテクチャ** | 中央集権型 | 分散型 |
| **認証局** | DAPS (常時稼働必須) | Issuer Service (発行時のみ) |
| **クレデンシャル** | X.509証明書 | Verifiable Credentials (W3C標準) |
| **トークン** | DAT (シンプルJWT) | VP付きアクセストークン |
| **発行頻度** | 都度取得 (短命) | 長期間有効 (再発行不要) |
| **障害耐性** | DAPS停止で全体停止 | Issuer停止でも継続可能 |
| **プライバシー** | 全属性を常に開示 | 必要なVCのみ選択的開示 |
| **スケーラビリティ** | 低 (DAPS がボトルネック) | 高 (各IdentityHub独立) |

---

## 3. IdentityHubの役割

### 3.1 IdentityHub = 拡張VCウォレット + 認証基盤

```mermaid
graph TB
    subgraph "IdentityHub の機能"
        direction TB
        
        subgraph "1. VCウォレット機能"
            VCS[VC Storage<br/>Credential保管]
            VCM[VC Management<br/>有効期限・失効管理]
        end
        
        subgraph "2. STS機能"
            OAuth[OAuth2 Token発行]
            VPG[VP生成<br/>必要なVCを選択]
            JWTS[JWT署名]
        end
        
        subgraph "3. 参加者管理"
            PCM[ParticipantContext管理]
            SEP[ServiceEndpoint登録]
            KM[鍵管理]
        end
        
        subgraph "4. DID機能"
            DIDD[DID Document公開]
            PKPUB[公開鍵配布]
        end
        
        subgraph "5. 認証・認可"
            API[API Key認証]
            RBAC[Role-Based Access Control]
            CLIENTAUTH[Client認証]
        end
    end
    
    Connector[Connector] -->|トークン要求| OAuth
    OAuth --> VPG
    VPG --> VCS
    VPG --> JWTS
    
    External[外部参加者] -->|DID解決| DIDD
    DIDD --> PKPUB
    
    Admin[管理者] -->|参加者登録| PCM
    PCM --> SEP
    PCM --> KM
    
    style VCS fill:#fff9c4
    style OAuth fill:#b3e5fc
    style DIDD fill:#c8e6c9
```

### 3.2 IdentityHub API構成

```mermaid
graph LR
    subgraph "IdentityHub APIs"
        direction TB
        
        API1[Credentials API<br/>Port 7081/7091<br/>/api/credentials/v1]
        API2[Identity API<br/>Port 7082/7092<br/>/api/identity/v1alpha]
        API3[DID API<br/>Port 7083/7093<br/>/.well-known/did.json]
        API4[STS API<br/>Port 7086/7096<br/>/api/sts/token]
    end
    
    Connector[Connector] -->|VC取得・VP要求| API1
    Connector -->|トークン取得| API4
    Admin[管理者] -->|参加者登録| API2
    External[外部参加者] -->|公開鍵取得| API3
    
    style API1 fill:#ffe082
    style API2 fill:#80deea
    style API3 fill:#a5d6a7
    style API4 fill:#ce93d8
```

---

## 4. 参加者登録プロセス

### 4.1 参加者登録の目的

**IdentityHubとConnectorを結びつけ、企業のアイデンティティを確立する**

```mermaid
sequenceDiagram
    autonumber
    participant Admin as 管理者
    participant Vault as Vault<br/>(秘密鍵保管)
    participant IH as IdentityHub<br/>(Identity API)
    participant Conn as Connector<br/>(Management API)
    
    Note over Admin,Conn: フェーズ1: Vaultに秘密鍵を保存
    Admin->>Vault: POST /v1/secret/data/did:web:consumer-identityhub:7083-alias
    Note right of Vault: Consumer秘密鍵保存
    Admin->>Vault: POST /v1/secret/data/did:web:consumer-identityhub:7083-sts-client-secret
    Note right of Vault: STS Client Secret保存
    
    Note over Admin,Conn: フェーズ2: IdentityHubに参加者登録
    Admin->>IH: POST /api/identity/v1alpha/participants/
    Note right of IH: ParticipantContext作成<br/>- DID<br/>- 公開鍵<br/>- ServiceEndpoints<br/>- 権限ロール
    IH-->>Admin: { clientId, clientSecret }
    Note right of Admin: OAuth2クレデンシャル発行
    
    Note over Admin,Conn: フェーズ3: ConnectorにClient Secretを設定
    Admin->>Conn: POST /api/management/v3/secrets
    Note right of Conn: Connector VaultにClient Secret保存<br/>これでSTSにアクセス可能に
    
    Note over Admin,Conn: 完了: ConnectorがIdentityHubを使用可能
```

### 4.2 参加者登録リクエスト詳細

```json
POST http://localhost:7081/api/identity/v1alpha/participants/
Content-Type: application/json
X-Api-Key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=

{
  "participantId": "did:web:consumer-identityhub:7083",
  "active": true,
  "did": {
    "@context": ["https://www.w3.org/ns/did/v1"],
    "id": "did:web:consumer-identityhub:7083",
    "verificationMethod": [
      {
        "id": "did:web:consumer-identityhub:7083#key-1",
        "type": "JsonWebKey2020",
        "controller": "did:web:consumer-identityhub:7083",
        "publicKeyJwk": {
          "kty": "EC",
          "crv": "P-256",
          "x": "uT5vDxN5YdOt-dUG1fKoLmLfCiS-F8qSoY7lXdUDLOo",
          "y": "xYD0AFNK6lfqr6zKHHZXDlvQ3YYZdaKZKZOEGBRxgc8"
        }
      }
    ],
    "service": [
      {
        "id": "did:web:consumer-identityhub:7083#credential-service",
        "type": "CredentialService",
        "serviceEndpoint": "http://consumer-identityhub:7081"
      },
      {
        "id": "did:web:consumer-identityhub:7083#dsp",
        "type": "ProtocolEndpoint",
        "serviceEndpoint": "http://consumer-connector:9082/api/dsp"
      }
    ]
  },
  "serviceEndpoints": [
    {
      "id": "credential-service",
      "type": "CredentialService",
      "serviceEndpoint": "http://consumer-identityhub:7081"
    }
  ],
  "key": {
    "resourceId": "did:web:consumer-identityhub:7083-alias",
    "keyId": "did:web:consumer-identityhub:7083#key-1",
    "privateKeyAlias": "did:web:consumer-identityhub:7083-alias",
    "publicKeyPem": "-----BEGIN PUBLIC KEY-----\n..."
  }
}
```

---

## 5. カタログ取得フロー (詳細)

### 5.1 フルシーケンス図

```mermaid
sequenceDiagram
    autonumber
    participant User as ユーザー/システム
    participant CConn as Consumer<br/>Connector
    participant CIH as Consumer<br/>IdentityHub (STS)
    participant PConn as Provider<br/>Connector
    participant PIH as Provider<br/>IdentityHub
    
    Note over User,PIH: Phase 1: カタログ取得リクエスト
    User->>CConn: GET /api/catalog/request?<br/>counterPartyAddress=http://provider:8192
    
    Note over CConn: カタログ取得ポリシー確認<br/>必要なVC: MembershipCredential
    
    Note over User,PIH: Phase 2: Scope抽出
    Note over CConn: ポリシーエンジンで解析<br/>"Membership.active" constraint<br/>↓<br/>scope: org.eclipse.edc.vc.type:MembershipCredential:read
    
    Note over User,PIH: Phase 3: STS Token取得
    CConn->>CIH: POST /api/sts/token<br/>grant_type=client_credentials<br/>client_id=did:web:consumer-identityhub:7083<br/>client_secret=***<br/>scope=org.eclipse.edc.vc.type:MembershipCredential:read<br/>audience=did:web:provider-identityhub:7093
    
    Note over CIH: 1. Client認証 (client_id/secret検証)<br/>2. ParticipantContext取得<br/>3. Scopeに対応するVC検索<br/>   → MembershipCredential取得<br/>4. Verifiable Presentation作成<br/>5. JWT生成・署名
    
    CIH-->>CConn: { "access_token": "eyJhbGci...",<br/>  "token_type": "Bearer",<br/>  "expires_in": 300 }
    
    Note over User,PIH: Phase 4: DSPカタログリクエスト
    CConn->>PConn: POST /api/dsp/v1/catalog/request<br/>Authorization: Bearer eyJhbGci...<br/>Content-Type: application/json<br/>{"@context": "...", "@type": "CatalogRequestMessage"}
    
    Note over User,PIH: Phase 5: VP検証とポリシー評価
    Note over PConn: 1. JWT署名検証<br/>   (Consumer IdentityHubの公開鍵で)<br/>2. "vp" claimからVP抽出<br/>3. VP内のVC検証:<br/>   - Issuer署名検証<br/>   - 有効期限確認<br/>   - 失効確認 (StatusList)<br/>4. ポリシー評価:<br/>   - MembershipCredential存在確認<br/>   - membership.active == true
    
    alt 検証成功
        PConn-->>CConn: 200 OK<br/>{ "@type": "Catalog",<br/>  "dataset": [ asset-1, asset-2, ... ] }
        CConn-->>User: Catalog JSON
    else 検証失敗
        PConn-->>CConn: 403 Forbidden<br/>{ "error": "Insufficient credentials" }
        CConn-->>User: Error
    end
```

### 5.2 アクセストークンの中身

```mermaid
graph TB
    subgraph "Consumer IdentityHub が発行するアクセストークン (JWT)"
        direction TB
        
        Header[Header<br/>alg: ES256<br/>typ: JWT]
        
        Payload[Payload]
        subgraph Payload
            ISS[iss: did:web:consumer-identityhub:7083]
            SUB[sub: did:web:consumer-identityhub:7083]
            AUD[aud: did:web:provider-identityhub:7093]
            EXP[exp: 1700000000]
            SCOPE[scope: org.eclipse.edc.vc.type:MembershipCredential:read]
            
            subgraph "VP (Verifiable Presentation)"
                VPContext[context: https://www.w3.org/2018/credentials/v1]
                VPType[type: VerifiablePresentation]
                
                subgraph "VC (MembershipCredential)"
                    VCType[type: VerifiableCredential, MembershipCredential]
                    VCIssuer[issuer: did:web:dataspace-issuer]
                    VCSubject[credentialSubject:<br/>- id: did:web:consumer-identityhub:7083<br/>- holderIdentifier: BPNL000000000001<br/>- membership.active: true]
                    VCProof[proof: JWT署名 by Issuer]
                end
            end
        end
        
        Signature[Signature<br/>Consumer IdentityHubの秘密鍵で署名]
    end
    
    style Header fill:#e1bee7
    style VPContext fill:#c5e1a5
    style VCSubject fill:#fff9c4
    style Signature fill:#ffccbc
```

### 5.3 ポリシー評価の仕組み

```mermaid
graph TB
    subgraph "Provider側のポリシー評価プロセス"
        Policy[Asset Policy<br/>constraint: Membership.active == true]
        
        JWT[受信したJWT<br/>Bearer Token]
        
        Extract[VP抽出]
        JWT --> Extract
        
        VCList[VC一覧取得]
        Extract --> VCList
        
        Filter[MembershipCredential<br/>フィルタリング]
        VCList --> Filter
        
        Verify[VC検証<br/>1. Issuer署名検証<br/>2. 有効期限確認<br/>3. StatusList確認]
        Filter --> Verify
        
        Evaluate[ポリシー評価関数<br/>MembershipCredentialEvaluationFunction]
        Verify --> Evaluate
        Policy --> Evaluate
        
        Check[credentialSubject.membership.active<br/>== true ?]
        Evaluate --> Check
        
        Result{評価結果}
        Check -->|Yes| Allow[許可: カタログ返却]
        Check -->|No| Deny[拒否: 403 Forbidden]
        
        Result --> Allow
        Result --> Deny
    end
    
    style Policy fill:#e1f5fe
    style Verify fill:#fff9c4
    style Allow fill:#c8e6c9
    style Deny fill:#ffcdd2
```

---

## 6. 契約交渉・データ転送フロー

### 6.1 契約交渉フロー

```mermaid
sequenceDiagram
    autonumber
    participant CConn as Consumer<br/>Connector
    participant CIH as Consumer<br/>IdentityHub
    participant PConn as Provider<br/>Connector
    
    Note over CConn,PConn: Phase 1: 契約交渉開始
    CConn->>CIH: POST /api/sts/token<br/>scope=org.eclipse.edc.vc.type:MembershipCredential:read<br/>+DataProcessorCredential:read
    CIH-->>CConn: access_token (VP with 2 VCs)
    
    CConn->>PConn: POST /api/dsp/v1/negotiations<br/>Authorization: Bearer ...<br/>{ offer, asset, policy }
    
    Note over PConn: ポリシー評価:<br/>- MembershipCredential確認<br/>- DataProcessorCredential確認<br/>- DataAccess.level == "processing"
    
    PConn-->>CConn: Negotiation Created<br/>{ negotiationId, state: REQUESTED }
    
    Note over CConn,PConn: Phase 2: 契約合意
    PConn->>CConn: Contract Offer Event<br/>{ state: OFFERED }
    CConn->>PConn: Contract Agreement<br/>{ state: AGREED }
    
    PConn-->>CConn: Contract Agreement Confirmed<br/>{ agreementId, state: FINALIZED }
```

### 6.2 データ転送フロー

```mermaid
sequenceDiagram
    autonumber
    participant CConn as Consumer<br/>Connector
    participant CIH as Consumer<br/>IdentityHub
    participant PConn as Provider<br/>Control Plane
    participant PDP as Provider<br/>Data Plane
    participant Backend as Provider<br/>Backend System
    
    Note over CConn,Backend: Phase 1: 転送リクエスト
    CConn->>CIH: POST /api/sts/token<br/>scope=...
    CIH-->>CConn: access_token
    
    CConn->>PConn: POST /api/dsp/v1/transfers<br/>Authorization: Bearer ...<br/>{ agreementId, assetId, dataDestination }
    
    Note over PConn: 1. Agreement検証<br/>2. ポリシー再評価<br/>3. DataPlane選択
    
    PConn->>PDP: Data Plane選択・準備
    PDP-->>PConn: Ready
    
    PConn-->>CConn: Transfer Started<br/>{ transferProcessId, state: STARTED }
    
    Note over CConn,Backend: Phase 2: EDR (EndpointDataReference) 取得
    CConn->>PConn: GET /api/management/v3/edrs?<br/>transferProcessId=...
    PConn-->>CConn: { endpoint, authKey, authCode }
    
    Note over CConn,Backend: Phase 3: データアクセス
    CConn->>PDP: GET {endpoint}<br/>Authorization: Bearer {authCode}
    
    Note over PDP: プロキシトークン検証<br/>- Consumer署名確認<br/>- Agreement確認<br/>- 有効期限確認
    
    PDP->>Backend: GET /actual-data
    Backend-->>PDP: Data
    PDP-->>CConn: Data
```

---

## 7. 実践例: リクエスト/レスポンス

### 7.1 参加者登録

**リクエスト:**
```bash
curl -X POST http://localhost:7081/api/identity/v1alpha/participants/ \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=" \
  -d '{
    "participantId": "did:web:consumer-identityhub:7083",
    "active": true,
    "did": "did:web:consumer-identityhub:7083",
    "serviceEndpoints": [
      {
        "type": "CredentialService",
        "serviceEndpoint": "http://consumer-identityhub:7081",
        "id": "credential-service"
      },
      {
        "type": "ProtocolEndpoint",
        "serviceEndpoint": "http://consumer-connector:9082/api/dsp",
        "id": "dsp"
      }
    ],
    "key": {
      "keyId": "did:web:consumer-identityhub:7083#key-1",
      "privateKeyAlias": "did:web:consumer-identityhub:7083-alias",
      "publicKeyPem": "-----BEGIN PUBLIC KEY-----\nMFkw...AQAB\n-----END PUBLIC KEY-----"
    }
  }'
```

**レスポンス:**
```json
{
  "clientId": "did:web:consumer-identityhub:7083",
  "clientSecret": "6c7f9a8b-3e2d-4f1a-b9c8-5d7e6f8a9b0c",
  "apiKey": "ZGlkOndlYjpjb25zdW1lci1pZGVudGl0eWh1YiUzQTcwODM=.NWQ3ZTZmOGE5YjBj"
}
```

### 7.2 STS Token取得

**リクエスト:**
```bash
curl -X POST http://localhost:7086/api/sts/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=did:web:consumer-identityhub:7083" \
  -d "client_secret=6c7f9a8b-3e2d-4f1a-b9c8-5d7e6f8a9b0c" \
  -d "scope=org.eclipse.edc.vc.type:MembershipCredential:read" \
  -d "audience=did:web:provider-identityhub:7093"
```

**レスポンス:**
```json
{
  "access_token": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJkaWQ6d2ViOmNvbnN1bWVyLWlkZW50aXR5aHViOjcwODMiLCJzdWIiOiJkaWQ6d2ViOmNvbnN1bWVyLWlkZW50aXR5aHViOjcwODMiLCJhdWQiOiJkaWQ6d2ViOnByb3ZpZGVyLWlkZW50aXR5aHViOjcwOTMiLCJleHAiOjE3MDAwMDAwMDAsImlhdCI6MTY5OTk5OTcwMCwic2NvcGUiOiJvcmcuZWNsaXBzZS5lZGMudmMudHlwZTpNZW1iZXJzaGlwQ3JlZGVudGlhbDpyZWFkIiwidnAiOnsiQGNvbnRleHQiOlsiaHR0cHM6Ly93d3cudzMub3JnLzIwMTgvY3JlZGVudGlhbHMvdjEiXSwidHlwZSI6WyJWZXJpZmlhYmxlUHJlc2VudGF0aW9uIl0sInZlcmlmaWFibGVDcmVkZW50aWFsIjpbeyJAY29udGV4dCI6WyJodHRwczovL3d3dy53My5vcmcvMjAxOC9jcmVkZW50aWFscy92MSIsImh0dHBzOi8vdzNpZC5vcmcvbXZkL2NyZWRlbnRpYWxzLyJdLCJ0eXBlIjpbIlZlcmlmaWFibGVDcmVkZW50aWFsIiwiTWVtYmVyc2hpcENyZWRlbnRpYWwiXSwiaXNzdWVyIjoiZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyIiwiaXNzdWFuY2VEYXRlIjoiMjAyNC0wMS0wMVQwMDowMDowMFoiLCJleHBpcmF0aW9uRGF0ZSI6IjIwMjUtMTItMzFUMjM6NTk6NTlaIiwiY3JlZGVudGlhbFN1YmplY3QiOnsiaWQiOiJkaWQ6d2ViOmNvbnN1bWVyLWlkZW50aXR5aHViOjcwODMiLCJob2xkZXJJZGVudGlmaWVyIjoiQlBOTDAwMDAwMDAwMDAwMSIsIm1lbWJlcnNoaXAiOnsiYWN0aXZlIjp0cnVlLCJtZW1iZXJPZiI6IkRhdGFzcGFjZS1YIiwic2luY2UiOiIyMDI0LTAxLTAxVDAwOjAwOjAwWiJ9fSwicHJvb2YiOnsidHlwZSI6Ikp3dFByb29mMjAyMCIsImp3dCI6ImV5SmhiR2NpT2lKRlV6STFOaUo5Li4uIn19XX19.signature",
  "token_type": "Bearer",
  "expires_in": 300,
  "scope": "org.eclipse.edc.vc.type:MembershipCredential:read"
}
```

### 7.3 カタログ取得

**リクエスト:**
```bash
curl -X POST http://localhost:8192/api/dsp/v1/catalog/request \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -d '{
    "@context": "https://w3id.org/dspace/v1/context.json",
    "@type": "CatalogRequestMessage",
    "protocol": "dataspace-protocol-http",
    "counterPartyAddress": "http://provider-connector-qna:8192"
  }'
```

**レスポンス:**
```json
{
  "@id": "urn:uuid:catalog-123",
  "@type": "dcat:Catalog",
  "@context": {
    "dcat": "http://www.w3.org/ns/dcat#",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "dcat:dataset": [
    {
      "@id": "asset-1",
      "@type": "dcat:Dataset",
      "odrl:hasPolicy": {
        "@type": "odrl:Set",
        "odrl:permission": [
          {
            "odrl:action": "use",
            "odrl:constraint": [
              {
                "odrl:leftOperand": "Membership.active",
                "odrl:operator": "eq",
                "odrl:rightOperand": "true"
              }
            ]
          }
        ]
      },
      "dcat:distribution": [
        {
          "@type": "dcat:Distribution",
          "dcat:format": "application/json",
          "dcat:accessService": "http://provider-connector-qna:8192/api/dsp"
        }
      ],
      "name": "Q&A Asset",
      "description": "Sample asset for questions and answers"
    },
    {
      "@id": "asset-2",
      "@type": "dcat:Dataset",
      "odrl:hasPolicy": {
        "@type": "odrl:Set",
        "odrl:permission": [
          {
            "odrl:action": "use",
            "odrl:constraint": [
              {
                "odrl:leftOperand": "DataAccess.level",
                "odrl:operator": "eq",
                "odrl:rightOperand": "sensitive"
              }
            ]
          }
        ]
      },
      "name": "Sensitive Asset",
      "description": "Requires DataProcessorCredential with level=sensitive"
    }
  ],
  "dcat:service": {
    "@id": "http://provider-connector-qna:8192/api/dsp",
    "@type": "dcat:DataService",
    "dcat:endpointURL": "http://provider-connector-qna:8192/api/dsp"
  }
}
```

### 7.4 DID Document取得

**リクエスト:**
```bash
curl http://localhost:7093/.well-known/did.json
```

**レスポンス:**
```json
{
  "@context": ["https://www.w3.org/ns/did/v1"],
  "id": "did:web:provider-identityhub:7093",
  "verificationMethod": [
    {
      "id": "did:web:provider-identityhub:7093#key-1",
      "type": "JsonWebKey2020",
      "controller": "did:web:provider-identityhub:7093",
      "publicKeyJwk": {
        "kty": "EC",
        "crv": "P-256",
        "x": "uT5vDxN5YdOt-dUG1fKoLmLfCiS-F8qSoY7lXdUDLOo",
        "y": "xYD0AFNK6lfqr6zKHHZXDlvQ3YYZdaKZKZOEGBRxgc8"
      }
    }
  ],
  "authentication": [
    "did:web:provider-identityhub:7093#key-1"
  ],
  "assertionMethod": [
    "did:web:provider-identityhub:7093#key-1"
  ],
  "service": [
    {
      "id": "did:web:provider-identityhub:7093#credential-service",
      "type": "CredentialService",
      "serviceEndpoint": "http://provider-identityhub:7091/api/credentials/v1"
    },
    {
      "id": "did:web:provider-identityhub:7093#dsp-qna",
      "type": "ProtocolEndpoint",
      "serviceEndpoint": "http://provider-connector-qna:8192/api/dsp"
    },
    {
      "id": "did:web:provider-identityhub:7093#dsp-manufacturing",
      "type": "ProtocolEndpoint",
      "serviceEndpoint": "http://provider-connector-manufacturing:8292/api/dsp"
    },
    {
      "id": "did:web:provider-identityhub:7093#catalog",
      "type": "ProtocolEndpoint",
      "serviceEndpoint": "http://provider-catalog-server:8182/api/dsp"
    }
  ]
}
```

---

---

## 8. OID4VCとDCPの関係

### 8.1 MVDはOID4VCに準拠しているか？

**回答: いいえ、準拠していません。**

MVDは**DCP (Decentralized Claims Protocol)** という、データスペース・B2B通信に特化したプロトコルを使用しています。

```mermaid
graph TB
    subgraph "OID4VC (OpenID for Verifiable Credentials)"
        direction TB
        OID_HOLDER[Wallet<br/>👤 個人ユーザー]
        OID_ISSUER[Credential Issuer<br/>OpenID Connect]
        OID_VERIFIER[Verifier<br/>OpenID Connect]
        
        OID_HOLDER -->|1. Authorization Request| OID_ISSUER
        OID_ISSUER -->|2. Access Token| OID_HOLDER
        OID_HOLDER -->|3. Credential Request| OID_ISSUER
        OID_ISSUER -->|4. VC発行| OID_HOLDER
        OID_HOLDER -->|5. VP Token提示| OID_VERIFIER
        
        Note1[標準: OpenID Foundation<br/>用途: モバイルウォレット・個人認証<br/>特徴: ユーザー同意フロー]
    end
    
    subgraph "DCP (Decentralized Claims Protocol)"
        direction TB
        DCP_HOLDER[IdentityHub<br/>🏢 組織システム]
        DCP_ISSUER[Issuer Service<br/>カスタムAPI]
        DCP_CONNECTOR[Connector<br/>OAuth2 Client]
        
        DCP_HOLDER -->|1. Credential Request| DCP_ISSUER
        DCP_ISSUER -->|2. VC発行・保存| DCP_HOLDER
        DCP_CONNECTOR -->|3. STS Token要求| DCP_HOLDER
        DCP_HOLDER -->|4. VP付きトークン| DCP_CONNECTOR
        
        Note2[標準: Tractus-X / Eclipse EDC<br/>用途: データスペース・機械間通信<br/>特徴: 完全自動化]
    end
    
    style Note1 fill:#fff9c4
    style Note2 fill:#c5e1a5
```

### 8.2 プロトコル比較

| 項目 | OID4VC | DCP (MVD) |
|------|---------|-----------|
| **標準化団体** | OpenID Foundation | Tractus-X / Eclipse Foundation |
| **仕様** | [OpenID4VC Spec](https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html) | [DCP Spec](https://github.com/eclipse-tractusx/identity-trust) |
| **ベースプロトコル** | OpenID Connect | OAuth2 + カスタム拡張 |
| **主な用途** | モバイルウォレット、個人認証 (B2C) | データスペース、組織間通信 (B2B) |
| **想定環境** | ブラウザ、モバイルアプリ | サーバーサイド、API |
| **ユーザー操作** | 必須 (同意・選択・承認) | 不要 (完全自動化) |
| **認証フロー** | Authorization Code Flow | Client Credentials Flow |
| **VC選択** | ユーザーが手動選択 | Scope-driven自動選択 |
| **VP提示** | `vp_token` パラメーター (OpenID4VP) | JWT `vp` クレーム (カスタム) |
| **セッション** | 短命・対話的 | 長命・常時接続 |

### 8.3 VC発行フローの違い

**OID4VC Issuance Flow:**
```
1. Wallet → Issuer: Authorization Request (OAuth2)
2. Issuer → Wallet: Authorization Code
3. Wallet → Issuer: Token Request
4. Issuer → Wallet: Access Token
5. Wallet → Issuer: Credential Request
6. Issuer → Wallet: Credential Response (VC)
7. Wallet: VCを保存

特徴: OpenID Connect標準フロー、ユーザー認証必須
```

**DCP Issuance Flow:**
```
1. IdentityHub → Issuer: Credential Request (カスタムAPI)
   POST /api/identity/v1alpha/participants/{id}/credentials/request
   {
     "issuerDid": "did:web:issuer",
     "holderPid": "request-id",
     "credentials": [{"format": "VC1_0_JWT", "type": "MembershipCredential"}]
   }

2. Issuer → IdentityHub: VC発行・直接保存

特徴: カスタムAPI、システム間通信、人の介在なし
```

### 8.4 VP提示フローの違い

**OID4VP (OpenID for Verifiable Presentations):**
```
1. Verifier → Wallet: Authorization Request
   ?response_type=vp_token
   &presentation_definition={...}
   
2. Wallet: ユーザーにVC選択を促す

3. User → Wallet: VC選択・承認

4. Wallet → Verifier: Authorization Response
   vp_token=<VP in JWT or JSON-LD>
   &presentation_submission={...}

特徴: ユーザー同意必須、Presentation Definition使用
```

**DCP Presentation Flow:**
```
1. Connector → IdentityHub STS: Token Request (OAuth2 Client Credentials)
   POST /api/sts/token
   grant_type=client_credentials
   client_id=did:web:consumer-identityhub:7083
   client_secret=***
   scope=org.eclipse.edc.vc.type:MembershipCredential:read
   audience=did:web:provider-identityhub:7093

2. IdentityHub: Scopeから必要なVCを自動選択・VP作成

3. IdentityHub → Connector: Access Token with VP
   {
     "access_token": "eyJhbGci...",  // JWT内に"vp"クレーム
     "token_type": "Bearer",
     "expires_in": 300
   }

4. Connector → Provider: DSP Request
   Authorization: Bearer eyJhbGci...

特徴: 完全自動化、Scope-driven、人の介在なし
```

### 8.5 なぜ機械間通信にW3C VCが適しているか

```mermaid
graph TB
    subgraph "W3C VCの利点"
        direction TB
        
        ADV1[構造化データ<br/>JSON-LD]
        ADV2[セマンティクス明確<br/>@context]
        ADV3[プロトコル非依存<br/>どんな通信でも使える]
        ADV4[機械可読性<br/>自動処理容易]
        ADV5[相互運用性<br/>異なるシステム間]
    end
    
    subgraph "機械間通信の要件"
        REQ1[24時間365日稼働]
        REQ2[自動ポリシー評価]
        REQ3[高スループット]
        REQ4[人の介在なし]
        REQ5[複数システム統合]
    end
    
    ADV1 --> REQ2
    ADV2 --> REQ2
    ADV3 --> REQ5
    ADV4 --> REQ3
    ADV4 --> REQ4
    ADV5 --> REQ5
    
    style ADV1 fill:#c8e6c9
    style ADV4 fill:#c8e6c9
    style REQ2 fill:#b3e5fc
    style REQ4 fill:#b3e5fc
```

**W3C VCの機械間通信における優位性:**

1. **JSON-LDによる構造化データ**
   ```json
   {
     "@context": ["https://www.w3.org/2018/credentials/v1"],
     "type": ["VerifiableCredential", "MembershipCredential"],
     "credentialSubject": {
       "membership": {
         "@type": "Membership",
         "active": true
       }
     }
   }
   ```
   → 機械が意味を理解して自動処理可能

2. **自動ポリシー評価**
   ```java
   // MVDでの実装例
   public boolean evaluate(Policy policy, VerifiableCredential vc) {
       var subject = vc.getCredentialSubject();
       if (policy.getLeftOperand().equals("Membership.active")) {
           return subject.getClaim("membership", "active").equals(true);
       }
       return false;
   }
   ```
   → 人間の判断不要、完全自動化

3. **プロトコル非依存**
   - HTTP REST API
   - gRPC
   - MQTT (IoT)
   - DIDComm (P2P)
   - DSP (Dataspace Protocol)
   
   → 様々な通信方式で同じVCを使用可能

### 8.6 なぜMVDがDCPを採用したか

```mermaid
graph TB
    subgraph "データスペース要件"
        R1[複数Connector ← 1 IdentityHub]
        R2[Scope-driven VC選択<br/>ポリシーから自動抽出]
        R3[DSPプロトコル統合]
        R4[長時間稼働<br/>人の介在なし]
        R5[組織間信頼管理]
        R6[高頻度トランザクション<br/>数千〜数万/日]
    end
    
    subgraph "OID4VCの制約"
        LIMIT1[1ウォレット ← 1ユーザー想定]
        LIMIT2[ユーザー同意・選択必須]
        LIMIT3[Webベース・対話的]
        LIMIT4[短命セッション]
        LIMIT5[個人証明中心]
        LIMIT6[対話型フロー]
    end
    
    subgraph "DCPの利点"
        ADV1[✅ 1 Hub ← 複数Connector]
        ADV2[✅ 完全自動選択]
        ADV3[✅ APIベース統合]
        ADV4[✅ 長命トークン]
        ADV5[✅ 組織証明対応]
        ADV6[✅ バッチ処理可能]
    end
    
    R1 --> ADV1
    R2 --> ADV2
    R3 --> ADV3
    R4 --> ADV4
    R5 --> ADV5
    R6 --> ADV6
    
    R1 -.X 不適合.- LIMIT1
    R2 -.X 不適合.- LIMIT2
    R3 -.X 不適合.- LIMIT3
    R4 -.X 不適合.- LIMIT4
    R5 -.X 不適合.- LIMIT5
    R6 -.X 不適合.- LIMIT6
    
    style ADV1 fill:#c8e6c9
    style ADV2 fill:#c8e6c9
    style LIMIT1 fill:#ffcdd2
    style LIMIT2 fill:#ffcdd2
```

### 8.7 業界での使い分け

**個人向け (B2C): OID4VC採用**

```
eIDAS 2.0 (欧州デジタルID)
├── 運転免許証
├── パスポート
├── 銀行アカウント
├── 学位証明書
└── OpenID4VC準拠

mDL (Mobile Driver's License)
├── ISO 18013-5
├── モバイルウォレット
└── OpenID4VC統合

COVID-19証明書
├── EU Digital COVID Certificate
├── SMART Health Cards
└── OpenID4VC対応
```

**企業・機械間 (B2B): W3C VC + 独自プロトコル**

```
Tractus-X / Catena-X (自動車産業)
├── DCP (Decentralized Claims Protocol)
├── 工場システム間連携
├── サプライチェーンデータ交換
└── Eclipse EDC使用

Gaia-X (欧州データインフラ)
├── Gaia-X Trust Framework
├── Self-Description
├── Federated Catalogue
└── W3C VC + 独自プロトコル

IOTA Identity (IoT)
├── DIDComm + W3C VC
├── デバイス間自動通信
├── 分散台帳統合
└── Tanggle DLT使用
```

### 8.8 共通点と互換性

**共通要素:**

✅ **W3C Verifiable Credentials Data Model**
- 両方ともW3C VC標準に準拠
- JWT形式のVCをサポート
- 同じ署名・検証アルゴリズム

✅ **DID (Decentralized Identifiers)**
- `did:web`、`did:key`等の共通サポート
- DID Document解決方法は同じ

✅ **OAuth2ベース**
- DCPはOAuth2 Client Credentialsを使用
- OID4VCもOAuth2の拡張

**VCデータ構造の互換性:**

```json
// どちらでも使える同じVC形式
{
  "@context": [
    "https://www.w3.org/2018/credentials/v1",
    "https://w3id.org/mvd/credentials/"
  ],
  "type": ["VerifiableCredential", "MembershipCredential"],
  "issuer": "did:web:dataspace-issuer",
  "issuanceDate": "2024-01-01T00:00:00Z",
  "credentialSubject": {
    "id": "did:web:holder",
    "membership": {"active": true}
  },
  "proof": {
    "type": "JwtProof2020",
    "jwt": "eyJhbGci..."
  }
}
```

**非互換要素:**

❌ **プロトコルレイヤー**
- エンドポイント名が異なる
- リクエスト/レスポンス形式が異なる
- 認証フローが異なる

❌ **トークン形式**
- OID4VC: `vp_token`パラメーター
- DCP: JWT `vp`クレーム

❌ **VC選択メカニズム**
- OID4VC: Presentation Definition
- DCP: Scope-driven

### 8.9 まとめ: W3C VCは万能、プロトコルは用途次第

```mermaid
graph TB
    W3C[W3C Verifiable Credentials<br/>普遍的なデータ形式・検証方法]
    
    subgraph "B2C 個人向け"
        direction LR
        Mobile[📱 モバイルアプリ]
        Browser[🌐 Webブラウザ]
        Protocol1[OpenID4VC<br/>標準化プロトコル]
        Use1[運転免許証<br/>パスポート<br/>学位証明書]
        
        Mobile --> Protocol1
        Browser --> Protocol1
        Protocol1 --> Use1
    end
    
    subgraph "B2B 機械間"
        direction LR
        Server[🖥️ サーバー]
        IoT[📡 IoTデバイス]
        Protocol2[カスタムプロトコル<br/>DCP, DIDComm, etc.]
        Use2[サプライチェーン<br/>工場連携<br/>自動取引]
        
        Server --> Protocol2
        IoT --> Protocol2
        Protocol2 --> Use2
    end
    
    W3C --> B2C
    W3C --> B2B
    
    Note1[✅ 共通: W3C VC<br/>データ構造・署名・検証]
    Note2[❌ 異なる: プロトコル<br/>通信方法・認証フロー]
    
    style W3C fill:#4caf50,color:#fff
    style Note1 fill:#c8e6c9
    style Note2 fill:#fff9c4
```

**結論:**

1. **W3C VCは機械間通信に最適**
   - 構造化データで自動処理容易
   - セマンティクス明確で相互運用性高い
   - プロトコル非依存で柔軟な統合

2. **OID4VCは個人向けに特化**
   - ユーザー体験重視
   - モバイル・ブラウザ最適化
   - 既存OpenIDインフラ活用

3. **DCPはデータスペース向けに特化**
   - 組織間の大規模自動取引
   - 24/7稼働・高スループット
   - ポリシーベース自動判定

**すべてW3C VC標準の上に構築されているため、VCデータそのものは相互運用可能です。** プロトコル層（通信方法・認証フロー）が異なるだけです。

---

## 9. まとめ

### MVDの核心的な設計原則

1. **1企業 = 1 IdentityHub + 複数Connector**
   - IdentityHubが企業のアイデンティティを一元管理
   - 複数のConnectorが同じparticipantIdを共有
   - VCの発行・管理・提示はIdentityHubに集約

2. **分散型認証 (DCP)**
   - DAPS のような中央認証局は不要
   - Issuer Serviceは初回VC発行のみ
   - 各IdentityHubが独立してSTS機能を提供

3. **Scope-Driven VC選択**
   - ポリシーから必要なVCタイプを自動抽出
   - 必要最小限のVCのみを提示 (Selective Disclosure)
   - プライバシー保護とセキュリティの両立

4. **W3C標準準拠**
   - Verifiable Credentials Data Model
   - Decentralized Identifiers (DID)
   - OAuth2 Client Credentials Flow

5. **機械間通信最適化**
   - 完全自動化（ユーザー操作不要）
   - 高スループット対応
   - ポリシーベース自動判定

この設計により、スケーラブルで柔軟、かつセキュアなデータスペースが実現されています。
