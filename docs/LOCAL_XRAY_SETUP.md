# ローカル環境でのX-Ray設定

このガイドでは、ローカル開発環境でOpenTelemetryからAWS X-Rayにトレースを送信する設定について説明します。

## 🎯 概要

ローカル環境では、OpenTelemetry CollectorがAWS X-Ray APIに直接トレースを送信します。

```
Laravel App → OpenTelemetry → OTel Collector → AWS X-Ray API
```

## ⚠️ 重要な注意事項

### 1. 環境変数の設定が必須
**最重要**: AWS認証情報を正しく設定しないと、X-Rayエクスポーターが初期化されません。

### 2. Docker Composeの環境変数優先順位
Docker Composeでは以下の優先順位で環境変数が適用されます：
1. **システムの環境変数**（最優先）
2. **docker-compose.ymlのenvironmentセクション**
3. **`.env`ファイル**（最低優先）

### 3. X-Rayエクスポーターの制限
- **トレースのみサポート**: メトリクスとログは送信できません
- **環境変数形式**: `OTEL_EXPORTERS=debug,awsxray`（配列形式は無効）

## 🔧 設定手順

### ステップ1: AWS認証情報の設定

#### 1.1 AWS CLIの設定確認
```bash
# AWS CLIが設定されているか確認
aws sts get-caller-identity

# 必要な権限の確認
aws xray get-sampling-rules
```

#### 1.2 認証情報の取得
```bash
# AWS CLIから認証情報を取得
aws configure get aws_access_key_id
aws configure get aws_secret_access_key
aws configure get region
```

#### 1.3 .envファイルの設定
```env
# AWS設定（必須）
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_DEFAULT_REGION=ap-northeast-1

# X-Ray設定
OTEL_XRAY_ENABLED=true
OTEL_XRAY_LOCAL_MODE=false
OTEL_XRAY_ENDPOINT=

# エクスポーター設定（重要：配列形式は無効）
OTEL_EXPORTERS=debug,awsxray
```

### ステップ2: Docker Compose設定

#### 2.1 docker-compose.ymlの設定
```yaml
services:
  app:
    # ... 他の設定 ...
    env_file:
      - .env
    environment:
      - PHP_IDE_CONFIG=serverName=laravel-app

  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: otel-collector
    restart: unless-stopped
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./docker/otel-collector/otel-collector-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4317:4317"
      - "4318:4318"
      - "8888:8888"
      - "13133:13133"
    networks:
      - laravel
    env_file:
      - .env
    environment:
      # 環境設定
      - OTEL_ENVIRONMENT=${OTEL_ENVIRONMENT:-docker}
      - OTEL_SERVICE_NAME=${OTEL_SERVICE_NAME:-laravel-app}
      
      # AWS設定（システム環境変数を上書き）
      - AWS_DEFAULT_REGION=ap-northeast-1
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      
      # X-Ray設定
      - OTEL_XRAY_LOCAL_MODE=${OTEL_XRAY_LOCAL_MODE:-false}
      - OTEL_XRAY_ENDPOINT=${OTEL_XRAY_ENDPOINT:-}
      
      # エクスポーター設定
      - OTEL_EXPORTERS=${OTEL_EXPORTERS:-debug,awsxray}
```

#### 2.2 重要なポイント
- **env_file**: `.env`ファイルを明示的に指定
- **AWS_DEFAULT_REGION**: システムの環境変数を上書きするため強制指定
- **env_file + environment**: 両方を使用して確実に設定を適用

### ステップ3: OTel Collector設定

#### 3.1 otel-collector-config.yamlの設定
```yaml
# docker/otel-collector/otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 512
    send_batch_max_size: 1024

  resource:
    attributes:
      - key: service.name
        value: ${env:OTEL_SERVICE_NAME}
        action: upsert
      - key: deployment.environment
        value: ${env:OTEL_ENVIRONMENT}
        action: upsert

exporters:
  debug:
    verbosity: detailed

  # AWS X-Ray exporter（最小限の設定）
  awsxray:
    region: ap-northeast-1
    local_mode: false

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777
  zpages:
    endpoint: 0.0.0.0:55679

service:
  extensions: [health_check, pprof, zpages]
  telemetry:
    logs:
      level: debug  # デバッグログを有効化
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug, awsxray]  # X-Rayはトレースのみ
    metrics:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug]           # X-Rayは使用不可
    logs:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug]           # X-Rayは使用不可
```

#### 3.2 重要なポイント
- **traceパイプラインのみ**: X-Rayエクスポーターはトレースのみをサポート
- **debugログレベル**: 問題診断のためデバッグログを有効化
- **最小限の設定**: X-Rayエクスポーターは`region`と`local_mode`のみ指定

## 🧪 動作確認

### ステップ1: コンテナの起動
```bash
# 設定を確認
docker-compose config | Select-String -Pattern 'AWS_'

# 期待される出力:
# AWS_ACCESS_KEY_ID: AKIAIOSFODNN7EXAMPLE
# AWS_DEFAULT_REGION: ap-northeast-1
# AWS_SECRET_ACCESS_KEY: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# コンテナの起動
docker-compose up -d
```

### ステップ2: X-Rayエクスポーターの初期化確認
```bash
# X-Rayエクスポーターの初期化ログ確認
docker-compose logs otel-collector | Select-String -Pattern 'awsxray'

# 期待される出力:
# "otelcol.component.id": "awsxray", "otelcol.component.kind": "exporter"
# "region": "ap-northeast-1"
```

### ステップ3: トレースの送信確認
```bash
# OpenTelemetryテスト実行
docker-compose exec app php artisan otel:test

# X-Rayエクスポーターのトレース送信ログ確認
docker-compose logs otel-collector | Select-String -Pattern 'TracesExporter'

# 期待される出力:
# TracesExporter ... "#spans": 10
# request: &{TraceSegmentDocuments:[...]}
# response: &{UnprocessedTraceSegments:[] ...}
```

### ステップ4: APIテスト
```bash
# Windows PowerShell
.\test_api.ps1

# Linux/macOS
./test_api.sh
```

### ステップ5: X-Rayコンソールでの確認
[AWS X-Rayコンソール](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)でトレースを確認してください。

## 🔧 トラブルシューティング

### 問題1: X-Rayエクスポーターが初期化されない

#### 症状
```bash
# X-Rayエクスポーターのログが見つからない
docker-compose logs otel-collector | Select-String -Pattern 'awsxray'
# 出力なし
```

#### 解決方法
1. **環境変数の確認**
   ```bash
   docker-compose config | Select-String -Pattern 'AWS_'
   ```

2. **システム環境変数の確認**
   ```bash
   $env:AWS_DEFAULT_REGION
   # us-east-1が出力される場合、docker-compose.ymlで強制指定が必要
   ```

3. **コンテナの再起動**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### 問題2: トレースが送信されない

#### 症状
```bash
# TracesExporterのログが見つからない
docker-compose logs otel-collector | Select-String -Pattern 'TracesExporter'
# 出力なし
```

#### 解決方法
1. **AWS認証情報の確認**
   ```bash
   aws sts get-caller-identity
   ```

2. **X-Ray権限の確認**
   ```bash
   aws xray get-sampling-rules
   ```

3. **詳細ログの確認**
   ```bash
   docker-compose logs otel-collector | Select-String -Pattern 'error|Error|failed|Failed'
   ```

### 問題3: 環境変数形式エラー

#### 症状
```
The environment file is invalid!
Failed to parse dotenv file. Encountered unexpected whitespace at [[debug, awsxray]].
```

#### 解決方法
```env
# 間違った形式
OTEL_EXPORTERS=[debug, awsxray]

# 正しい形式
OTEL_EXPORTERS=debug,awsxray
```

## 📋 チェックリスト

設定完了前に以下を確認してください：

### 環境変数設定
- [ ] `.env`ファイルにAWS認証情報が設定されている
- [ ] `docker-compose.yml`で`env_file: - .env`が指定されている
- [ ] `AWS_DEFAULT_REGION=ap-northeast-1`が強制指定されている
- [ ] `OTEL_EXPORTERS=debug,awsxray`（配列形式ではない）

### X-Rayエクスポーター設定
- [ ] X-Rayエクスポーターがトレースパイプラインのみに設定されている
- [ ] メトリクスとログパイプラインからX-Rayエクスポーターが除外されている
- [ ] OTel Collectorでデバッグログが有効化されている

### 動作確認
- [ ] `docker-compose config`でAWS環境変数が正しく表示される
- [ ] OTel Collectorログで`awsxray`エクスポーターの初期化が確認できる
- [ ] `TracesExporter`ログでトレース送信が確認できる
- [ ] AWS X-Rayコンソールでトレースが確認できる

## 🔗 関連リンク

- [X-Rayトラブルシューティングガイド](XRAY_TROUBLESHOOTING_GUIDE.md)
- [OpenTelemetry監視ガイド](OPENTELEMETRY_MONITORING_GUIDE.md)
- [AWS CLI設定ガイド](AWS_CLI_SETUP_GUIDE.md)
- [AWS X-Rayコンソール](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces) 
