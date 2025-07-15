# OpenTelemetry監視ガイド

このガイドでは、OpenTelemetryシステムの監視方法とトラブルシューティングのための診断方法を説明します。

## 🎯 監視対象

### 1. OpenTelemetry Collector
- **コンテナの状態**: 起動状態、再起動回数
- **エクスポーターの初期化**: 各エクスポーターの初期化状況
- **データ処理**: トレース、メトリクス、ログの処理状況
- **AWS X-Ray送信**: X-Rayエクスポーターのトレース送信状況

### 2. Laravel Application
- **OpenTelemetry設定**: 設定の読み込み状況
- **トレース生成**: HTTPリクエスト、データベースクエリのトレース
- **メトリクス**: アプリケーションのパフォーマンス指標

## 🔧 監視コマンド

### 基本的な状態確認

#### コンテナの状態確認
```bash
# 全コンテナの状態確認
docker-compose ps

# 期待される出力:
# otel-collector   Up      0.0.0.0:4317->4317/tcp, :::4317->4317/tcp
# laravel-app      Up      0.0.0.0:80->80/tcp, :::80->80/tcp
```

#### 環境変数の確認（重要）
```bash
# Docker Composeの設定確認
docker-compose config | Select-String -Pattern 'AWS_|OTEL_'

# 期待される出力:
# AWS_ACCESS_KEY_ID: [AWS_ACCESS_KEY_ID]
# AWS_DEFAULT_REGION: ap-northeast-1
# AWS_SECRET_ACCESS_KEY: [AWS_SECRET_ACCESS_KEY]
# OTEL_EXPORTERS: debug,awsxray
```

### OTel Collectorの詳細監視

#### 基本ログの確認
```bash
# 最新のログ確認
docker-compose logs otel-collector --tail=20

# フォローモードでリアルタイム監視
docker-compose logs -f otel-collector
```

#### X-Rayエクスポーターの監視（重要）
```bash
# X-Rayエクスポーターの初期化確認
docker-compose logs otel-collector | Select-String -Pattern 'awsxray'

# 期待される出力:
# "otelcol.component.id": "awsxray", "otelcol.component.kind": "exporter"
# "region": "ap-northeast-1"

# X-Rayエクスポーターのトレース送信確認
docker-compose logs otel-collector | Select-String -Pattern 'TracesExporter'

# 期待される出力:
# TracesExporter ... "#spans": 10
# request: &{TraceSegmentDocuments:[...]}
# response: &{UnprocessedTraceSegments:[] ...}
```

#### エラーログの確認
```bash
# エラーログの確認
docker-compose logs otel-collector | Select-String -Pattern 'error|Error|failed|Failed'

# 警告ログの確認
docker-compose logs otel-collector | Select-String -Pattern 'warn|Warning'
```

#### デバッグログの確認（デバッグレベル有効時）
```bash
# デバッグレベルのログ確認
docker-compose logs otel-collector | Select-String -Pattern 'debug'

# X-Ray関連のデバッグログ
docker-compose logs otel-collector | Select-String -Pattern 'debug.*awsxray'
```

### Laravel Applicationの監視

#### OpenTelemetryの設定確認
```bash
# OpenTelemetry設定の確認
docker-compose exec app php artisan config:show opentelemetry

# 期待される出力:
# opentelemetry.service_name => "laravel-app"
# opentelemetry.traces.enabled => true
# opentelemetry.exporter => "otlp"
```

#### トレースの生成テスト
```bash
# OpenTelemetryテストコマンド
docker-compose exec app php artisan otel:test

# 期待される出力:
# OpenTelemetry Test Command
# Generating sample traces...
# Test completed successfully!
```

## 📊 ヘルスチェック

### OTel Collectorのヘルスチェック
```bash
# ヘルスチェックエンドポイント
curl http://localhost:13133/

# 期待される出力:
# {"status":"Server available","upSince":"2024-01-01T12:00:00Z"}
```

### メトリクスの確認
```bash
# Collectorのメトリクス
curl http://localhost:8888/metrics

# 主要なメトリクス:
# otelcol_receiver_accepted_spans_total
# otelcol_exporter_sent_spans_total
# otelcol_processor_batch_batch_send_size_sum
```

### zPagesでのデバッグ情報
```bash
# ブラウザでアクセス
# http://localhost:55679/debug/tracez
# http://localhost:55679/debug/pipelinez
```

## 🚨 アラート設定

### 重要な監視項目

#### 1. X-Rayエクスポーターの初期化失敗
```bash
# 確認方法
docker-compose logs otel-collector | Select-String -Pattern 'awsxray.*failed|awsxray.*error'

# 問題がある場合の対処
# 1. 環境変数の確認
# 2. AWS認証情報の確認
# 3. X-Ray権限の確認
```

#### 2. トレース送信の失敗
```bash
# 確認方法
docker-compose logs otel-collector | Select-String -Pattern 'TracesExporter.*error|TracesExporter.*failed'

# 問題がある場合の対処
# 1. AWS認証情報の確認
# 2. ネットワーク接続の確認
# 3. X-Ray API制限の確認
```

#### 3. コンテナの再起動
```bash
# 確認方法
docker-compose ps | Select-String -Pattern 'Restarting|Exit'

# 問題がある場合の対処
# 1. ログの確認
# 2. 設定ファイルの確認
# 3. リソース使用量の確認
```

### 自動監視スクリプト

#### 基本的な監視スクリプト
```bash
#!/bin/bash
# monitor_otel.sh

echo "=== OpenTelemetry Monitoring ==="
echo "Date: $(date)"
echo ""

echo "1. Container Status:"
docker-compose ps
echo ""

echo "2. X-Ray Exporter Status:"
docker-compose logs otel-collector --tail=10 | grep -i "awsxray\|TracesExporter"
echo ""

echo "3. Recent Errors:"
docker-compose logs otel-collector --tail=50 | grep -i "error\|failed\|warn"
echo ""

echo "4. Health Check:"
curl -s http://localhost:13133/ | head -1
echo ""
```

## 🔍 パフォーマンス監視

### メトリクスの収集
```bash
# システムリソース使用量
docker stats --no-stream

# 特定コンテナのリソース使用量
docker stats otel-collector --no-stream
```

### バッチ処理の監視
```bash
# バッチ処理の統計
curl -s http://localhost:8888/metrics | grep "otelcol_processor_batch"

# 重要なメトリクス:
# otelcol_processor_batch_batch_send_size_sum - 送信バッチサイズの合計
# otelcol_processor_batch_timeout_trigger_send_total - タイムアウトによる送信回数
```

## 📈 AWS X-Ray監視

### X-Rayコンソールでの確認
[AWS X-Rayコンソール](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)

#### 確認項目
1. **トレースの受信状況**
   - 最新のトレースが表示されているか
   - トレースの頻度が適切か

2. **サービスマップ**
   - `laravel-app`サービスが表示されているか
   - 依存関係が正しく表示されているか

3. **エラー率**
   - エラーの発生頻度
   - エラーの種類と原因

### AWS CLIを使用した監視
```bash
# X-Rayサービス統計の取得
aws xray get-service-graph --start-time 2024-01-01T00:00:00Z --end-time 2024-01-01T23:59:59Z

# トレースの検索
aws xray get-trace-summaries --time-range-type TimeRangeByStartTime --start-time 2024-01-01T00:00:00Z --end-time 2024-01-01T23:59:59Z
```

## 🔧 トラブルシューティング

### 症状別の診断手順

#### 1. X-Rayにトレースが表示されない
```bash
# 1. 環境変数の確認
docker-compose config | Select-String -Pattern 'AWS_'

# 2. X-Rayエクスポーターの初期化確認
docker-compose logs otel-collector | Select-String -Pattern 'awsxray'

# 3. トレース送信の確認
docker-compose logs otel-collector | Select-String -Pattern 'TracesExporter'

# 4. AWS認証の確認
aws sts get-caller-identity
```

#### 2. コンテナが頻繁に再起動する
```bash
# 1. 現在の状態確認
docker-compose ps

# 2. 詳細ログの確認
docker-compose logs otel-collector --tail=100

# 3. 設定ファイルの確認
docker-compose config

# 4. リソース使用量の確認
docker stats
```

#### 3. パフォーマンス問題
```bash
# 1. メトリクスの確認
curl http://localhost:8888/metrics

# 2. バッチサイズの確認
docker-compose logs otel-collector | grep "batch"

# 3. 設定の最適化
# otel-collector-config.yamlのprocessors設定を調整
```

## 📋 定期確認チェックリスト

### 日次チェック
- [ ] コンテナの状態確認
- [ ] X-Rayエクスポーターの初期化確認
- [ ] 最新のトレースがX-Rayコンソールに表示されているか
- [ ] エラーログの有無確認

### 週次チェック
- [ ] パフォーマンスメトリクスの確認
- [ ] バッチ処理の効率確認
- [ ] AWS X-Rayコンソールでのサービスマップ確認
- [ ] 設定ファイルの最適化検討

### 月次チェック
- [ ] ログの長期傾向分析
- [ ] コスト最適化の検討
- [ ] 設定の見直しと更新
- [ ] ドキュメントの更新

## 🔗 関連リンク

- [X-Rayトラブルシューティングガイド](XRAY_TROUBLESHOOTING_GUIDE.md)
- [ローカルX-Ray設定ガイド](LOCAL_XRAY_SETUP.md)
- [AWS X-Rayコンソール](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)
- [OpenTelemetry Collector メトリクス](https://opentelemetry.io/docs/collector/monitoring/)

---

## 💡 重要なポイント

### 1. 環境変数の監視
- **最重要**: AWS認証情報が正しく設定されているか定期的に確認
- システムの環境変数とDockerの環境変数の競合に注意

### 2. X-Rayエクスポーターの監視
- 初期化ログの確認は必須
- `TracesExporter`ログでトレース送信の成功を確認
- `UnprocessedTraceSegments:[]`で全てのトレースが処理されていることを確認

### 3. 継続的な監視
- ログの傾向を定期的に分析
- パフォーマンスメトリクスの追跡
- AWS X-Rayコンソールでの定期的な確認 
