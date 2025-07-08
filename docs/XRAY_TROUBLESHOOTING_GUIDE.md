# AWS X-Ray トラブルシューティングガイド

このガイドでは、Laravel + OpenTelemetry + AWS X-Ray統合で発生する可能性のある問題と解決方法について説明します。

## 🚨 緊急度の高い問題

### 1. OTel Collectorが再起動を繰り返す

#### 現象
```bash
# docker-compose psの実行結果
otel-collector   Restarting (1) 11 seconds ago

# docker-compose logsの出力
The "AWS_ACCESS_KEY_ID" variable is not set. Defaulting to a blank string.
The "AWS_SECRET_ACCESS_KEY" variable is not set. Defaulting to a blank string.
```

#### 原因
- `.env`ファイルにAWS認証情報が設定されていない
- Docker環境ではホストのAWS CLI設定を参照できない
- `docker-compose.yml`の環境変数が空になっている

#### 解決方法
1. **AWS認証情報を取得**
   ```bash
   aws configure get aws_access_key_id
   aws configure get aws_secret_access_key
   aws configure get region
   ```

2. **`.env`ファイルに追加**
   ```env
   # AWS設定（重要：Docker環境では.envファイルに記載が必要）
   AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
   AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   AWS_DEFAULT_REGION=ap-northeast-1
   ```

3. **コンテナの再起動**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### 2. X-Rayエクスポーターのエラー

#### 現象
```
Error: failed to build pipelines: failed to create "awsxray" exporter for data type "logs": telemetry type is not supported
Error: failed to build pipelines: failed to create "awsxray" exporter for data type "metrics": telemetry type is not supported
```

#### 原因
- AWS X-Rayエクスポーターは**トレースのみ**をサポート
- メトリクスとログではX-Rayエクスポーターを使用できない
- `otel-collector-config.yaml`でX-Rayを全パイプラインで使用している

#### 解決方法
1. **`docker/otel-collector/otel-collector-config.yaml`を修正**
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

2. **コンテナの再起動**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### 3. Laravel環境変数のパースエラー

#### 現象
```
The environment file is invalid!
Failed to parse dotenv file. Encountered unexpected whitespace at [[debug, awsxray]].
```

#### 原因
- `OTEL_EXPORTERS`設定で配列形式`[debug, awsxray]`を使用している
- `.env`ファイルでは配列形式は無効
- 環境変数は文字列形式でのみ指定可能

#### 解決方法
1. **`.env`ファイルの修正**
   ```env
   # 間違った形式
   OTEL_EXPORTERS=[debug, awsxray]
   
   # 正しい形式
   OTEL_EXPORTERS=debug,awsxray
   ```

2. **設定の確認**
   ```bash
   # 設定値の確認
   cat .env | grep OTEL_EXPORTERS
   
   # 期待される出力
   OTEL_EXPORTERS=debug,awsxray
   ```

## 🔍 診断手順

### ステップ1: 基本設定の確認

```bash
# 1. AWS認証情報の確認
aws sts get-caller-identity

# 2. .envファイルの確認
cat .env | grep -E "(AWS|OTEL)"

# 3. Docker Composeの状態確認
docker-compose ps

# 4. Collectorログの確認
docker-compose logs otel-collector --tail=20
```

### ステップ2: Laravel設定の確認

```bash
# 1. Laravelアプリケーションの動作確認
docker-compose exec app php artisan --version

# 2. OpenTelemetry設定の確認
docker-compose exec app php artisan about

# 3. 設定ファイルの確認
docker-compose exec app php artisan config:show opentelemetry
```

### ステップ3: X-Ray権限の確認

```bash
# 1. X-Ray権限のテスト
aws xray get-sampling-rules

# 2. 期待される出力（成功時）
{
    "SamplingRuleRecords": []
}

# 3. エラー時の対処
# - IAMユーザーにAWSXRayDaemonWriteAccessポリシーを追加
# - 以下の権限が必要：
#   - xray:PutTraceSegments
#   - xray:PutTelemetryRecords
#   - xray:GetSamplingRules
#   - xray:GetSamplingTargets
#   - xray:GetSamplingStatisticSummaries
```

### ステップ4: トレース送信テスト

```bash
# 1. APIリクエストの送信
curl http://localhost/api/items

# 2. OpenTelemetryテストコマンドの実行
docker-compose exec app php artisan otel:test

# 3. Collectorログの確認（トレースが送信されているか）
docker-compose logs otel-collector | grep "Trace ID"

# 4. X-Rayコンソールでの確認
# https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces
```

## 🛠️ よくある問題と解決方法

### 問題: "Cannot connect to OTel Collector"

#### 原因と解決方法
```bash
# 原因1: Collectorコンテナが起動していない
docker-compose ps otel-collector

# 解決方法: コンテナの再起動
docker-compose up -d otel-collector

# 原因2: ネットワークの問題
docker-compose exec app ping otel-collector

# 解決方法: ネットワークの再作成
docker-compose down
docker-compose up -d
```

### 問題: "X-Ray traces not visible in console"

#### 原因と解決方法
```bash
# 原因1: AWS認証情報の問題
aws sts get-caller-identity

# 原因2: リージョンの設定ミス
# .envファイルでAWS_DEFAULT_REGIONを確認

# 原因3: X-Ray権限の不足
aws xray get-sampling-rules
```

### 問題: パフォーマンスの劣化

#### 原因と解決方法
```yaml
# docker/otel-collector/otel-collector-config.yamlの調整
processors:
  batch:
    timeout: 1s          # デフォルト: 1s（小さくしすぎない）
    send_batch_size: 1024 # デフォルト: 1024（大きくしすぎない）
```

## 📊 監視とアラート

### 重要なメトリクス

1. **Collectorの健全性**
   - コンテナの再起動回数
   - メモリ使用量
   - CPU使用率

2. **トレース送信の成功率**
   - エラーログの頻度
   - X-Ray APIの応答時間
   - タイムアウトエラーの発生

3. **アプリケーションパフォーマンス**
   - HTTPリクエストの応答時間
   - データベースクエリの実行時間
   - エラー率

### 監視コマンド

```bash
# Dockerコンテナの統計
docker stats

# Collectorのヘルスチェック
curl http://localhost:13133/

# Collectorの統計情報
curl http://localhost:8888/metrics

# zpagesでのトレース確認
# http://localhost:55679/debug/tracez
```

## 🎯 最適化のヒント

### 1. バッチ処理の調整

```yaml
# より効率的な設定例
processors:
  batch:
    timeout: 2s
    send_batch_size: 512
    send_batch_max_size: 1024
```

### 2. リソース属性の最適化

```yaml
# 必要最小限の属性に絞る
processors:
  resource:
    attributes:
      - key: service.name
        value: ${env:OTEL_SERVICE_NAME}
        action: upsert
      - key: deployment.environment
        value: ${env:OTEL_ENVIRONMENT}
        action: upsert
```

### 3. サンプリングの設定

```yaml
# トレースのサンプリング率を調整
processors:
  probabilistic_sampler:
    sampling_percentage: 100  # 本番環境では10-50%程度に調整
```

## 📚 参考リンク

- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/)
- [OpenTelemetry Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
- [AWS X-Ray OpenTelemetry](https://aws-otel.github.io/docs/getting-started/x-ray)
- [Laravel OpenTelemetry Package](https://github.com/open-telemetry/opentelemetry-php)

---

## 💡 まとめ

X-Ray統合で最も重要なポイント：

1. **AWS認証情報**: Docker環境では`.env`ファイルに明示的に設定
2. **X-Rayエクスポーター**: トレースのみをサポート
3. **環境変数形式**: 文字列形式で指定（配列形式は無効）
4. **権限設定**: 適切なIAM権限が必要
5. **監視**: ログとメトリクスで継続的な監視が重要 
