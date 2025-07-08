# X-Ray トラブルシューティングガイド

このガイドでは、AWS X-Ray統合に関する問題の診断と解決方法を説明します。

## 🔍 問題の診断

### 1. X-Rayにトレースが表示されない

#### 症状
- AWS X-Rayコンソールにトレースが表示されない
- OTel Collectorが起動しているが、X-Ray関連のログが見つからない
- `.env`ファイルにAWS認証情報を設定したが動作しない

#### 診断手順

**1. 環境変数の確認**
```bash
# Docker Composeの設定確認
docker-compose config | Select-String -Pattern 'AWS_'

# 期待される出力:
# AWS_ACCESS_KEY_ID: [AWS_ACCESS_KEY_ID]
# AWS_DEFAULT_REGION: ap-northeast-1
# AWS_SECRET_ACCESS_KEY: [AWS_SECRET_ACCESS_KEY]
```

**2. OTel Collectorの初期化確認**
```bash
# X-Rayエクスポーターの初期化ログ確認
docker-compose logs otel-collector | Select-String -Pattern 'awsxray'

# 期待される出力:
# otelcol.component.id": "awsxray", "otelcol.component.kind": "exporter"
# "region": "ap-northeast-1"
```

**3. トレース送信の確認**
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

## 🚨 重要な問題と解決方法

### 問題1: 環境変数がOTel Collectorに渡されない

#### 症状
- `.env`ファイルにAWS認証情報を設定したが、X-Rayエクスポーターが初期化されない
- `docker-compose config`で環境変数が空または間違った値になっている

#### 原因
1. **システム環境変数の優先**: Docker Composeは以下の優先順位で環境変数を適用
   - システムの環境変数（最優先）
   - `docker-compose.yml`の`environment`セクション
   - `.env`ファイル（最低優先）

2. **env_fileの未指定**: `docker-compose.yml`で`.env`ファイルが明示的に指定されていない

#### 解決方法

**1. `docker-compose.yml`に`env_file`を追加**
```yaml
services:
  app:
    # ... 他の設定 ...
    env_file:
      - .env
    environment:
      - PHP_IDE_CONFIG=serverName=laravel-app

  otel-collector:
    # ... 他の設定 ...
    env_file:
      - .env
    environment:
      # 環境設定
      - OTEL_ENVIRONMENT=${OTEL_ENVIRONMENT:-docker}
      - OTEL_SERVICE_NAME=${OTEL_SERVICE_NAME:-laravel-app}
      
      # AWS設定 - システム環境変数を上書き
      - AWS_DEFAULT_REGION=ap-northeast-1
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      
      # X-Ray設定
      - OTEL_XRAY_LOCAL_MODE=${OTEL_XRAY_LOCAL_MODE:-false}
      - OTEL_XRAY_ENDPOINT=${OTEL_XRAY_ENDPOINT:-}
      
      # エクスポーター設定
      - OTEL_EXPORTERS=${OTEL_EXPORTERS:-debug,awsxray}
```

**2. システム環境変数の確認と対処**
```bash
# システムの環境変数確認
$env:AWS_DEFAULT_REGION

# システムに設定されている場合、docker-compose.ymlで強制指定
# AWS_DEFAULT_REGION=ap-northeast-1
```

### 問題2: X-Rayエクスポーターの設定エラー

#### 症状
- X-Rayエクスポーターが初期化されるが、トレースが送信されない
- 環境変数が空になっている

#### 原因
- 環境変数の参照が失敗している
- X-Rayエクスポーターの設定が不完全

#### 解決方法

**OTel Collectorの設定を最小限に変更**
```yaml
# docker/otel-collector/otel-collector-config.yaml
exporters:
  debug:
    verbosity: detailed

  # AWS X-Ray exporter（最小限の設定）
  awsxray:
    region: ap-northeast-1
    local_mode: false

service:
  telemetry:
    logs:
      level: debug  # デバッグログを有効化
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [debug, awsxray]
```

### 問題3: OTEL_EXPORTERS設定の形式エラー

#### 症状
- Laravel起動時にエラー: "The environment file is invalid!"
- "Failed to parse dotenv file. Encountered unexpected whitespace at [[debug, awsxray]]"

#### 原因
- `OTEL_EXPORTERS=[debug, awsxray]` の配列形式が無効

#### 解決方法
```env
# 間違った形式
OTEL_EXPORTERS=[debug, awsxray]

# 正しい形式
OTEL_EXPORTERS=debug,awsxray
```

### 問題4: X-Rayエクスポーターの制限事項

#### 症状
- OTel Collectorの起動時にエラー:
  ```
  Error: failed to build pipelines: failed to create "awsxray" exporter for data type "logs": telemetry type is not supported
  Error: failed to build pipelines: failed to create "awsxray" exporter for data type "metrics": telemetry type is not supported
  ```

#### 原因
- AWS X-Rayエクスポーターはトレースのみをサポート

#### 解決方法
```yaml
# OTel Collector設定
service:
  pipelines:
    traces:
      exporters: [debug, awsxray]  # X-Rayはトレースのみ
    metrics:
      exporters: [debug]           # X-Rayは使用不可
    logs:
      exporters: [debug]           # X-Rayは使用不可
```

## 📋 チェックリスト

### 環境変数設定チェック
- [ ] `.env`ファイルにAWS認証情報が設定されている
- [ ] `docker-compose.yml`で`env_file: - .env`が指定されている
- [ ] `AWS_DEFAULT_REGION=ap-northeast-1`が強制指定されている
- [ ] `OTEL_EXPORTERS=debug,awsxray`（配列形式ではない）

### X-Rayエクスポーター設定チェック
- [ ] X-Rayエクスポーターがトレースパイプラインのみに設定されている
- [ ] メトリクスとログパイプラインからX-Rayエクスポーターが除外されている
- [ ] OTel Collectorでデバッグログが有効化されている

### 動作確認チェック
- [ ] `docker-compose config`でAWS環境変数が正しく表示される
- [ ] OTel Collectorログで`awsxray`エクスポーターの初期化が確認できる
- [ ] `TracesExporter`ログでトレース送信が確認できる
- [ ] `UnprocessedTraceSegments:[]`でX-Ray APIの成功レスポンスが確認できる

## 🔧 詳細診断コマンド

### 環境変数の詳細確認
```bash
# Docker Composeの完全な設定確認
docker-compose config

# 特定サービスの環境変数確認
docker-compose config | Select-String -Pattern 'otel-collector' -A 20

# .envファイルの内容確認
Get-Content '.env' | Select-String -Pattern 'AWS_|OTEL_'
```

### OTel Collectorの詳細診断
```bash
# 完全なログ確認
docker-compose logs otel-collector

# X-Ray関連ログのみ
docker-compose logs otel-collector | Select-String -Pattern 'awsxray|xray|TracesExporter'

# エラーログの確認
docker-compose logs otel-collector | Select-String -Pattern 'error|Error|failed|Failed'

# デバッグログの確認（デバッグレベル有効時）
docker-compose logs otel-collector | Select-String -Pattern 'debug.*awsxray'
```

### AWS認証の確認
```bash
# AWS認証情報確認
aws sts get-caller-identity

# X-Ray権限確認
aws xray get-sampling-rules
```

## 📈 パフォーマンスチューニング

### バッチプロセッサーの最適化
```yaml
processors:
  batch:
    timeout: 5s
    send_batch_size: 512
    send_batch_max_size: 1024
```

### サンプリング設定
```yaml
processors:
  probabilistic_sampler:
    sampling_percentage: 10  # 10%のサンプリング
```

## 🔗 関連リンク

- [AWS X-Rayコンソール](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)
- [OpenTelemetry Collector設定](../docker/otel-collector/otel-collector-config.yaml)
- [ローカルX-Ray設定ガイド](LOCAL_XRAY_SETUP.md)
- [OpenTelemetry監視ガイド](OPENTELEMETRY_MONITORING_GUIDE.md) 
