# ローカル環境でのAWS X-Ray設定ガイド

このドキュメントでは、ローカル開発環境からAWS X-Rayにトレースデータを送信するための設定手順を説明します。

## 📋 **前提条件**

### 1. AWS認証情報の準備

以下のいずれかの方法でAWS認証情報を準備してください：

#### 方法1: AWS CLI設定
```bash
# AWS CLIのインストール（未インストールの場合）
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# AWS認証情報の設定
aws configure
```

#### 方法2: 環境変数での設定
```bash
# PowerShellの場合
$env:AWS_ACCESS_KEY_ID="your-access-key-id"
$env:AWS_SECRET_ACCESS_KEY="your-secret-access-key"
$env:AWS_DEFAULT_REGION="ap-northeast-1"

# Bashの場合
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="ap-northeast-1"
```

### 2. 必要なAWS権限

使用するAWSアカウントに以下の権限が必要です：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
        "xray:GetSamplingStatisticSummaries"
      ],
      "Resource": "*"
    }
  ]
}
```

## 🔧 **設定手順**

### 1. 環境変数ファイルの作成

プロジェクトルートに`.env`ファイルを作成：

```env
# 基本設定
APP_NAME=Laravel
APP_ENV=local
APP_KEY=base64:your-app-key-here
APP_DEBUG=true
APP_URL=http://localhost

# データベース設定
DB_CONNECTION=pgsql
DB_HOST=db
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=user
DB_PASSWORD=pass

# AWS設定（実際の値に置き換えてください）
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_DEFAULT_REGION=ap-northeast-1

# OpenTelemetry設定
OTEL_SERVICE_NAME=laravel-app
OTEL_SERVICE_VERSION=1.0.0
OTEL_ENVIRONMENT=local
OTEL_RESOURCE_ATTRIBUTES=service.name=laravel-app,service.version=1.0.0,deployment.environment=local

# OpenTelemetry Collector設定
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
OTEL_TRACES_ENABLED=true
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_ENABLED=true
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_ENABLED=true
OTEL_LOGS_EXPORTER=otlp

# X-Ray設定（ローカル環境用）
OTEL_XRAY_ENABLED=true
OTEL_XRAY_LOCAL_MODE=false
OTEL_XRAY_ENDPOINT=
# 注意：OTEL_EXPORTERS設定は文字列形式で指定（配列形式[debug, awsxray]は無効）
OTEL_EXPORTERS=debug,awsxray

# セッション設定
SESSION_DRIVER=database
SESSION_LIFETIME=120

# その他設定
LOG_CHANNEL=stack
LOG_LEVEL=debug
BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
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

### 2. Docker環境の起動

```bash
# コンテナをビルド
docker-compose build

# コンテナを起動
docker-compose up -d

# Laravel環境のセットアップ
docker-compose exec app composer install
docker-compose exec app php artisan key:generate
docker-compose exec app php artisan migrate
```

### 3. 動作確認

```bash
# アプリケーションの動作確認
curl http://localhost/

# APIエンドポイントの確認
curl http://localhost/api/items

# OpenTelemetryテストコマンド
docker-compose exec app php artisan otel:test
```

## 🔍 **X-Rayでのトレース確認**

### 1. AWS X-Rayコンソールにアクセス

1. AWS Management Consoleにログイン
2. X-Rayサービスを選択
3. 「Traces」または「Service map」を確認

### 2. 期待されるトレースデータ

以下のような情報が表示されるはずです：

```json
{
  "id": "1-64f8b123-abcdef1234567890",
  "duration": 0.245,
  "segments": [
    {
      "id": "abc123def456",
      "name": "laravel-app",
      "start_time": "2024-01-01T12:00:00.000Z",
      "end_time": "2024-01-01T12:00:00.245Z",
      "http": {
        "request": {
          "method": "GET",
          "url": "http://localhost/api/items"
        },
        "response": {
          "status": 200
        }
      },
      "subsegments": [
        {
          "id": "def456ghi789",
          "name": "db.query",
          "start_time": "2024-01-01T12:00:00.100Z",
          "end_time": "2024-01-01T12:00:00.150Z",
          "sql": {
            "query": "SELECT * FROM items"
          }
        }
      ]
    }
  ]
}
```

### 3. サービスマップ

- **laravel-app**: メインアプリケーション
- **PostgreSQL**: データベース
- **HTTP**: 外部API呼び出し（存在する場合）

## 🐛 **トラブルシューティング**

### 1. トレースが表示されない場合

#### OpenTelemetry Collectorのログを確認

```bash
# Collectorのログを確認
docker-compose logs otel-collector

# 成功時のログ例
2024-01-01T12:00:00.000Z info exporters/awsxray/exporter.go:123 Successfully sent trace to X-Ray
```

#### Laravel側の設定確認

```bash
# 設定値の確認
docker-compose exec app php artisan config:show opentelemetry
```

### 2. AWS認証エラーの場合

#### 認証情報の確認

```bash
# AWS認証情報の確認
aws sts get-caller-identity

# 期待される出力
{
    "UserId": "AIDABC123DEFGHIJKLMN",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

#### 権限の確認

```bash
# X-Ray権限の確認
aws xray get-sampling-rules

# 成功時は空の配列が返される
{
    "SamplingRuleRecords": []
}
```

### 3. OTel Collectorが再起動を繰り返す場合

#### 現象
```
The "AWS_ACCESS_KEY_ID" variable is not set. Defaulting to a blank string.
The "AWS_SECRET_ACCESS_KEY" variable is not set. Defaulting to a blank string.
```

#### 原因
- .envファイルにAWS認証情報が設定されていない
- Docker環境ではホストのAWS CLI設定を参照できない

#### 解決方法
```env
# .envファイルに以下を追加
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_DEFAULT_REGION=ap-northeast-1
```

### 4. X-Rayエクスポーターでエラーが発生する場合

#### 現象
```
Error: failed to build pipelines: failed to create "awsxray" exporter for data type "logs": telemetry type is not supported
Error: failed to build pipelines: failed to create "awsxray" exporter for data type "metrics": telemetry type is not supported
```

#### 原因
- AWS X-Rayエクスポーターはトレースのみをサポート
- メトリクスとログでX-Rayエクスポーターを使用している

#### 解決方法
`docker/otel-collector/otel-collector-config.yaml`を以下のように修正：
```yaml
service:
  pipelines:
    traces:
      exporters: [debug, awsxray]  # X-Rayはトレースのみ
    metrics:
      exporters: [debug]           # X-Rayは使用不可
    logs:
      exporters: [debug]           # X-Rayは使用不可
```

### 5. Laravel環境変数のパースエラーの場合

#### 現象
```
The environment file is invalid!
Failed to parse dotenv file. Encountered unexpected whitespace at [[debug, awsxray]].
```

#### 原因
- OTEL_EXPORTERS設定で配列形式を使用している
- .envファイルでは配列形式は無効

#### 解決方法
```env
# 間違った形式
OTEL_EXPORTERS=[debug, awsxray]

# 正しい形式
OTEL_EXPORTERS=debug,awsxray
```

### 6. 設定修正後の確認手順

```bash
# 1. コンテナの停止
docker-compose down

# 2. .envファイルの設定確認
cat .env | grep -E "(AWS|OTEL)"

# 3. コンテナの再起動
docker-compose up -d

# 4. Collectorログの確認
docker-compose logs otel-collector

# 5. Laravelアプリケーションの確認
docker-compose exec app php artisan --version

# 6. APIテストの実行
curl http://localhost/api/items

# 7. X-Rayコンソールでトレースの確認
# https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces
```

### 5. パフォーマンスの問題

#### バッチ処理の最適化

OpenTelemetry Collectorの設定で調整可能：

```yaml
processors:
  batch:
    timeout: 1s
    send_batch_size: 1024      # バッチサイズを調整
    send_batch_max_size: 1024  # 最大バッチサイズを調整
```

#### サンプリング設定の調整

```env
# サンプリング率の調整（0.1 = 10%）
OTEL_TRACES_SAMPLER_RATIO=0.1
```

### 4. よくあるエラーと解決方法

#### エラー1: "Could not load credentials"

```bash
# 解決方法: AWS認証情報を正しく設定
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
```

#### エラー2: "InvalidSignatureException"

```bash
# 解決方法: 時刻同期の確認
sudo ntpdate -s time.nist.gov
```

#### エラー3: "AccessDenied"

```bash
# 解決方法: X-Ray権限の確認・追加
aws iam attach-user-policy --user-name your-username --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
```

## 💡 **最適化のヒント**

### 1. 開発環境での設定

```env
# 開発時は詳細ログを有効化
OTEL_LOG_LEVEL=debug
OTEL_TRACES_SAMPLER=always_on
OTEL_TRACES_SAMPLER_RATIO=1.0
```

### 2. 本番環境での設定

```env
# 本番環境では適切なサンプリング設定
OTEL_LOG_LEVEL=info
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_RATIO=0.1
```

### 3. コスト最適化

- サンプリングレートを調整してトレース量を制御
- 不要な属性を除外してデータ量を削減
- バッチサイズを最適化してAPI呼び出し回数を削減

## 📊 **監視とアラート**

### 1. CloudWatchメトリクス

X-Rayは以下のメトリクスを提供：

- **TracesReceived**: 受信したトレース数
- **TracesProcessed**: 処理されたトレース数
- **LatencyHigh**: 高レイテンシのトレース数
- **ErrorRate**: エラー率

### 2. アラート設定

```bash
# CloudWatch Alarmの設定例
aws cloudwatch put-metric-alarm \
    --alarm-name "X-Ray-High-Error-Rate" \
    --alarm-description "X-Ray error rate is high" \
    --metric-name ErrorRate \
    --namespace AWS/X-Ray \
    --statistic Average \
    --period 300 \
    --threshold 5.0 \
    --comparison-operator GreaterThanThreshold
```

これでローカル環境からAWS X-Rayへのトレースデータ送信が設定完了です！ 
