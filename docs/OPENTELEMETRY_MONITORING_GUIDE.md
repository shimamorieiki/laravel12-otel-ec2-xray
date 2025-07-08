# OpenTelemetry監視ガイド

## 📋 **概要**

このドキュメントは、Laravel 12アプリケーションに実装されたOpenTelemetryの監視システムについて、どこに何があり、どのようにアクセスして何が分かるかを詳細に説明します。

## 🏗️ **システム構成**

### コンテナ構成
```
laravel-app      → Laravel 12アプリケーション（OpenTelemetryクライアント）
otel-collector   → OpenTelemetry Collector（データ収集・処理）
nginx           → Webサーバー
db              → PostgreSQL データベース
```

### OpenTelemetryデータフロー
```
Laravel App → OpenTelemetry Middleware → OTLP HTTP → Collector → Debug Exporter → ログ出力
```

## 🔧 **OpenTelemetry Collector設定**

### バージョン
- **OpenTelemetry Collector**: v0.129.0
- **イメージ**: `otel/opentelemetry-collector-contrib:latest`

### 設定ファイル
**場所**: `docker/otel-collector/otel-collector-config.yaml`

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317  # gRPC受信
      http:
        endpoint: 0.0.0.0:4318  # HTTP受信（Laravel使用）

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024
  resource:
    attributes:
    - key: environment
      value: docker
      action: upsert

exporters:
  debug:
    verbosity: detailed       # コンソール出力（詳細）

extensions:
  health_check:
    endpoint: 0.0.0.0:13133  # ヘルスチェック
  pprof:
    endpoint: 0.0.0.0:1777   # プロファイリング
  zpages:
    endpoint: 0.0.0.0:55679  # デバッグページ

service:
  extensions: [health_check, pprof, zpages]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug]
    logs:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug]
```

## 🌐 **アクセス可能なエンドポイント**

### 1. **Laravel アプリケーション**
| エンドポイント | URL | 説明 |
|----------------|-----|------|
| メインページ | `http://localhost/` | Laravel情報ページ |
| API - アイテム一覧 | `http://localhost/api/items` | アイテム一覧取得 |
| API - アイテム作成 | `POST http://localhost/api/items` | アイテム作成 |
| API - アイテム詳細 | `GET http://localhost/api/items/{id}` | 特定アイテム取得 |
| API - アイテム更新 | `PUT http://localhost/api/items/{id}` | アイテム更新 |
| API - アイテム削除 | `DELETE http://localhost/api/items/{id}` | アイテム削除 |

### 2. **OpenTelemetry Collector**
| エンドポイント | URL | 説明 | 現在の状態 |
|----------------|-----|------|-----------|
| OTLP gRPC受信 | `http://localhost:4317` | gRPCプロトコル受信 | 🟡 利用可能だが未使用 |
| OTLP HTTP受信 | `http://localhost:4318` | HTTP受信（Laravel使用） | 🟢 **使用中** |
| Prometheus メトリクス | `http://localhost:8888/metrics` | Collector自体のメトリクス | 🔴 現在アクセス不可 |
| Prometheus エクスポート | `http://localhost:8889` | エクスポート用メトリクス | 🔴 現在アクセス不可 |

### 3. **診断・監視エンドポイント**
| エンドポイント | URL | 説明 | 現在の状態 |
|----------------|-----|------|-----------|
| ヘルスチェック | `http://localhost:13133` | Collector稼働状況 | 🔴 設定済みだがアクセス不可 |
| プロファイリング | `http://localhost:1777` | パフォーマンス分析 | 🔴 設定済みだがアクセス不可 |
| zPages | `http://localhost:55679` | デバッグ情報 | 🔴 設定済みだがアクセス不可 |

**注意**: 診断エンドポイントはCollector設定ファイルで有効化されていますが、現在外部からアクセスできません。

## 📊 **データ確認方法**

### 1. **トレースデータの確認**
**方法**: Docker Composeログを確認
```bash
docker-compose logs -f otel-collector
```

**出力例**:
```
otel-collector  |     Trace ID       : 36e14d1689717bdfcd701936d27a6eaf
otel-collector  |     Parent ID      :
otel-collector  |     ID             : 9085d4bf6376345e
otel-collector  |     Name           : http.server.request
otel-collector  |     Kind           : Internal
otel-collector  |     Start time     : 2025-07-07 08:33:23.759106803 +0000 UTC
otel-collector  |     End time       : 2025-07-07 08:33:24.383178573 +0000 UTC
otel-collector  |     Status code    : Unset
otel-collector  |     Status message :
otel-collector  | Attributes:
otel-collector  |      -> http.method: Str(GET)
otel-collector  |      -> http.url: Str(http://localhost/api/items)
otel-collector  |      -> http.target: Str(api/items)
otel-collector  |      -> http.host: Str(localhost)
otel-collector  |      -> http.scheme: Str(http)
otel-collector  |      -> http.route: Str(unknown)
otel-collector  |      -> http.user_agent: Str(Mozilla/5.0...)
otel-collector  |      -> http.client_ip: Str(192.168.192.1)
otel-collector  |      -> http.status_code: Int(200)
```

### 2. **データベースクエリトレース**
**場所**: 同じログに出力されます
**含まれる情報**:
- SQL文
- 実行時間
- バインディング
- データベース種別

### 3. **システムメトリクス**
**場所**: 同じログに出力されます
**含まれる情報**:
- リクエスト数
- レスポンス時間
- エラー率
- サービス情報

## 🔄 **Laravel側の設定**

### 環境変数（.env）
```env
# OpenTelemetry設定
OTEL_SERVICE_NAME=laravel-app
OTEL_RESOURCE_ATTRIBUTES=service.name=laravel-app,service.version=1.0.0,deployment.environment=docker
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
OTEL_LOGS_ENABLED=true

# AWS設定（X-Ray使用時は必須）
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_DEFAULT_REGION=ap-northeast-1

# X-Ray設定
OTEL_XRAY_ENABLED=true
OTEL_XRAY_LOCAL_MODE=false
OTEL_XRAY_ENDPOINT=
# 注意：OTEL_EXPORTERS設定は文字列形式で指定（配列形式[debug, awsxray]は無効）
OTEL_EXPORTERS=debug,awsxray
```

### 🚨 **重要な注意点**

#### **AWS認証情報の設定**
- **Docker環境の場合**: .envファイルに`AWS_ACCESS_KEY_ID`と`AWS_SECRET_ACCESS_KEY`の明示的な設定が必要
- **理由**: Docker内のOTel CollectorはホストのAWS CLI設定を直接参照できないため
- **セキュリティ**: .envファイルは.gitignoreに含まれており、Gitにコミットされません

#### **OTEL_EXPORTERS設定の形式**
- **正しい形式**: `OTEL_EXPORTERS=debug,awsxray`
- **間違った形式**: `OTEL_EXPORTERS=[debug, awsxray]`（配列形式は無効）
- **理由**: .envファイルでは文字列形式でのみ指定可能

#### **X-Rayエクスポーターの制限**
- **対応データ**: トレースのみ
- **非対応データ**: メトリクス、ログ
- **設定**: OTel Collectorでは、X-Rayエクスポーターをトレースパイプラインでのみ使用
- **メトリクス・ログ**: debugエクスポーターのみ使用

### 🔧 **OTel Collector設定の確認**

`docker/otel-collector/otel-collector-config.yaml`が以下のように設定されていることを確認してください：

```yaml
service:
  extensions: [health_check, pprof, zpages]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug, awsxray]  # X-Rayはトレースのみ
    metrics:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug]           # メトリクスではX-Ray使用不可
    logs:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug]           # ログではX-Ray使用不可
```

### 実装されている機能
1. **HTTPリクエストトレース**: OpenTelemetryMiddleware
2. **データベースクエリトレース**: OpenTelemetryServiceProvider
3. **ログトレース**: OpenTelemetryServiceProvider
4. **カスタム属性**: リクエストヘッダー、クライアントIP等

## 🧪 **テスト方法**

### 1. **基本的なHTTPリクエストテスト**
```bash
# PowerShell
Invoke-WebRequest -Uri "http://localhost/" -Method Get

# 期待される結果: 200 OK + OpenTelemetryログ出力
```

### 2. **API呼び出しテスト**
```bash
# PowerShell
Invoke-WebRequest -Uri "http://localhost/api/items" -Method Get

# 期待される結果: JSON応答 + データベースクエリトレース
```

### 3. **複数リクエストでの負荷テスト**
```bash
# PowerShell
1..10 | ForEach-Object { Invoke-WebRequest -Uri "http://localhost/api/items" -Method Get }

# 期待される結果: 10個のトレースが生成される
```

## 🔍 **監視ポイント**

### 1. **パフォーマンス監視**
- **レスポンス時間**: Start time - End time
- **データベース実行時間**: db.execution_time_ms
- **エラー率**: http.status_code >= 400

### 2. **エラー監視**
- **502エラー**: Nginx-PHP-FPM通信エラー
- **500エラー**: Laravel内部エラー
- **データベース接続エラー**: 接続プールの問題

### 3. **リソース監視**
- **メモリ使用量**: Collectorログで確認
- **CPU使用率**: Dockerコンテナ統計
- **ディスク使用量**: ログファイルサイズ

## 🛠️ **トラブルシューティング**

### 1. **データが送信されない場合**
```bash
# Laravel設定確認
docker-compose exec app php artisan about

# Collector状態確認
docker-compose logs otel-collector

# ネットワーク確認
docker-compose exec app ping otel-collector
```

### 2. **Collectorが再起動し続ける場合**
```bash
# 設定ファイル検証
docker-compose exec otel-collector /otelcol-contrib --config-validate=/etc/otel-collector-config.yaml

# ログ確認
docker-compose logs otel-collector
```

### 3. **パフォーマンスの問題**
```bash
# バッチ処理設定調整
# batch processor の timeout と send_batch_size を調整

# メモリ制限確認
docker stats otel-collector
```

## 📈 **データ送信確認**

### 現在の状況
✅ **データ送信**: Laravel → OpenTelemetry Collector（HTTP経由 port:4318）  
✅ **データ処理**: Collector内でバッチ処理  
✅ **データ出力**: Collectorログに詳細出力  
✅ **トレース生成**: すべてのHTTPリクエストで自動生成  
✅ **パフォーマンス**: レスポンス時間 20秒+ → 2秒に大幅改善

### ✅ **Collectorへの送信が確認されていること**
**送信と言っているのはCollectorに届いていることを指しています。** 以下で確認済み：

1. **HTTPリクエスト→トレース生成**: リクエスト毎に自動で生成
2. **Collectorでの受信**: OTLP HTTP (port:4318) で正常受信
3. **ログ出力**: Collectorログでトレースデータの詳細確認可能
4. **属性収集**: HTTP詳細、DB情報、リクエスト情報など

### 確認方法
1. **リクエスト送信**
   ```bash
   Invoke-WebRequest -Uri "http://localhost/api/items" -Method Get
   ```

2. **ログ確認** (Collectorに送信されたデータの確認)
   ```bash
   docker-compose logs -f otel-collector
   ```

3. **データ確認** (実際に送信されているデータ)
   - **Trace ID**: 一意のトレース識別子 (例: 36e14d1689717bdfcd701936d27a6eaf)
   - **Span ID**: 個別操作の識別子 (例: 9085d4bf6376345e)
   - **属性**: HTTP詳細情報（method, url, status_code, user_agent等）
   - **タイムスタンプ**: 開始・終了時間（実行時間測定可能）

## 🔮 **今後の拡張**

### 1. **外部エクスポーターの追加**
- Jaeger（分散トレーシング）
- Prometheus（メトリクス）
- AWS X-Ray（クラウド監視）

### 2. **カスタムメトリクスの実装**
- ビジネスメトリクス
- カスタムイベント
- アプリケーション固有の測定値

### 3. **アラート設定**
- エラー率しきい値
- レスポンス時間アラート
- リソース使用率アラート

---

## 💡 **まとめ**

OpenTelemetryシステムは正常に動作しており、すべてのHTTPリクエストがCollectorに送信され、詳細なトレースデータがログに出力されています。現在の設定では、デバッグ目的でコンソール出力を使用していますが、本番環境では適切な外部システムへの送信を検討してください。 
