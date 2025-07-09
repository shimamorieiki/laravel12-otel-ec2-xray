# OpenTelemetry トラブルシューティングガイド

## 目次
1. [概要](#概要)
2. [一般的な問題と解決方法](#一般的な問題と解決方法)
3. [段階的なトラブルシューティング手順](#段階的なトラブルシューティング手順)
4. [設定ファイルの問題](#設定ファイルの問題)
5. [ポート競合の解決](#ポート競合の解決)
6. [プロトコルミスマッチの解決](#プロトコルミスマッチの解決)
7. [診断コマンド集](#診断コマンド集)
8. [予防策](#予防策)

## 概要

このドキュメントでは、Laravel + OpenTelemetry Collector + AWS X-Ray環境でよく発生する問題とその解決方法を説明します。

### システム構成
```
Laravel Application → OpenTelemetry Collector → AWS X-Ray
                   ↓                        ↓
              トレースデータ送信        AWS X-Rayへ転送
              (Port 4318: HTTP)      (Port 2000: X-Ray Daemon)
```

## 一般的な問題と解決方法

### 問題1: OpenTelemetry Collectorが起動しない

#### 症状
```
● otel-collector.service - OpenTelemetry Collector
     Active: activating (auto-restart) (Result: exit-code)
```

#### よくある原因
1. **設定ファイルの構文エラー**
2. **存在しないエクスポーター名**
3. **必須設定項目の不足**
4. **ポート競合**

#### 解決手順
```bash
# 1. 詳細なログを確認
sudo journalctl -u otel-collector -n 50

# 2. 設定ファイルの構文チェック
sudo /usr/local/bin/otelcol-contrib --config=/etc/otel-collector/config.yaml --dry-run

# 3. 手動起動でエラー確認
sudo /usr/local/bin/otelcol-contrib --config=/etc/otel-collector/config.yaml
```

### 問題2: Laravelからの接続エラー

#### 症状
```
OpenTelemetry: [error] Export failure [exception] cURL error 1: 
Received HTTP/0.9 when not allowed for http://127.0.0.1:4317/v1/traces
```

#### 原因
- **プロトコルミスマッチ**: HTTPリクエストをgRPCポートに送信
- **OpenTelemetry Collectorが起動していない**
- **ポート設定の不一致**

#### 解決方法
1. **正しいポートとプロトコルの使用**
2. **OpenTelemetry Collectorの起動確認**
3. **Laravel設定の更新**

### 問題3: ポート競合

#### 症状
```
Error: cannot start pipelines: listen tcp 0.0.0.0:4317: bind: address already in use
```

#### よくある競合サービス
- **CloudWatch Agent**: Port 4317
- **他のOpenTelemetryプロセス**
- **開発用サーバー**

## 段階的なトラブルシューティング手順

### ステップ1: 現在の状況確認

```bash
# サービス状態の確認
sudo systemctl status otel-collector
sudo systemctl status amazon-cloudwatch-agent

# ポート使用状況の確認
sudo netstat -tlnp | grep -E '4317|4318|2000'

# プロセス確認
ps aux | grep -E 'otelcol|cloudwatch|xray'
```

### ステップ2: ログ分析

```bash
# OpenTelemetry Collectorのログ
sudo journalctl -u otel-collector -n 50

# Laravel アプリケーションのログ
sudo tail -f /var/www/html/laravel12-otel-ec2-xray/storage/logs/laravel.log
```

### ステップ3: 設定確認

```bash
# OpenTelemetry Collector設定
sudo cat /etc/otel-collector/config.yaml

# Laravel OpenTelemetry設定
cd /var/www/html/laravel12-otel-ec2-xray
sudo -u nginx grep OTEL .env
```

### ステップ4: 接続テスト

```bash
# OpenTelemetry Collectorへの直接テスト
curl -v http://localhost:4318/v1/traces

# ヘルスチェック
curl -f http://localhost:13133/health
```

## 設定ファイルの問題

### 問題1: 存在しないエクスポーター名

#### エラー例
```
unknown type: "awscloudwatchmetrics" for id: "awscloudwatchmetrics"
```

#### 解決
```yaml
# ❌ 間違い
exporters:
  awscloudwatchmetrics:
    region: ap-northeast-1

# ✅ 正しい
exporters:
  awsemf:
    region: ap-northeast-1
```

### 問題2: memory_limiterの設定不足

#### エラー例
```
checkInterval must be greater than zero
```

#### 解決
```yaml
processors:
  memory_limiter:
    limit_mib: 256
    check_interval: 1s  # この行が必要
```

### 問題3: 非推奨設定の警告

#### 警告例
```
'loglevel' option is deprecated in favor of 'verbosity'
```

#### 解決
```yaml
exporters:
  logging:
    verbosity: normal  # loglevel から変更
```

### 正しい設定ファイル例

```yaml
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
        value: laravel-app
        action: upsert
      - key: service.version
        value: "1.0.0"
        action: upsert
      - key: deployment.environment
        value: production
        action: upsert

  memory_limiter:
    limit_mib: 256
    check_interval: 1s

exporters:
  logging:
    verbosity: normal

  awsxray:
    endpoint: http://127.0.0.1:2000
    local_mode: true
    region: ap-northeast-1
    no_verify_ssl: false
    index_all_attributes: true

  awsemf:
    region: ap-northeast-1
    namespace: Laravel/OpenTelemetry
    dimension_rollup_option: NoDimensionRollup
    metric_declarations:
      - dimensions: [[service.name], [service.name, deployment.environment]]
        metric_name_selectors:
          - ".*"

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
    path: /health

  pprof:
    endpoint: 0.0.0.0:1777

  zpages:
    endpoint: 0.0.0.0:55679

service:
  extensions: [health_check, pprof, zpages]
  telemetry:
    logs:
      level: info
    metrics:
      level: basic
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [logging, awsxray]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [logging, awsemf]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [logging]
```

## ポート競合の解決

### 状況1: CloudWatch Agentとの競合

#### 問題確認
```bash
# ポート4317の使用状況確認
sudo lsof -i :4317

# 期待されない結果例:
# COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
# amazon-cloudwa 5903 root  11u  IPv4  12345      0t0  TCP 127.0.0.1:4317 (LISTEN)
```

#### 解決方法1: CloudWatch Agentを停止（推奨）
```bash
# CloudWatch Agentを停止
sudo systemctl stop amazon-cloudwatch-agent
sudo systemctl disable amazon-cloudwatch-agent

# ポートが開放されたことを確認
sudo lsof -i :4317

# OpenTelemetry Collectorを起動
sudo systemctl start otel-collector
```

#### 解決方法2: ポート変更（非推奨）
```yaml
# OpenTelemetry Collectorの設定変更
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4319  # 4317 → 4319
      http:
        endpoint: 0.0.0.0:4320  # 4318 → 4320
```

```bash
# Laravel側の設定も変更
sudo -u nginx sed -i 's|OTEL_EXPORTER_OTLP_ENDPOINT=.*|OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4320|g' .env
```

### 状況2: 複数のOpenTelemetryプロセス

#### 問題確認
```bash
# OpenTelemetryプロセスの確認
ps aux | grep otelcol
```

#### 解決方法
```bash
# 重複プロセスの停止
sudo pkill otelcol-contrib

# サービス経由での起動
sudo systemctl start otel-collector
```

## プロトコルミスマッチの解決

### 問題: HTTPリクエストをgRPCポートに送信

#### 症状
```
cURL error 1: Received HTTP/0.9 when not allowed for http://127.0.0.1:4317/v1/traces
```

#### 原因分析
```
Laravel (HTTP) → Port 4317 (gRPC) ← OpenTelemetry Collector
                      ❌ プロトコルミスマッチ
```

#### 解決: 正しいポートとプロトコルの使用

```bash
# Laravel側の設定確認
cd /var/www/html/laravel12-otel-ec2-xray
sudo -u nginx grep OTEL_EXPORTER_OTLP_ENDPOINT .env

# HTTPエンドポイントを4318に変更
sudo -u nginx sed -i 's|OTEL_EXPORTER_OTLP_ENDPOINT=.*|OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318|g' .env

# プロトコル設定確認
sudo -u nginx sed -i 's|OTEL_EXPORTER_OTLP_PROTOCOL=.*|OTEL_EXPORTER_OTLP_PROTOCOL=http/json|g' .env

# 設定確認
sudo -u nginx grep -E "OTEL_EXPORTER_OTLP_ENDPOINT|OTEL_EXPORTER_OTLP_PROTOCOL" .env
```

#### 正しい設定例
```env
# Laravel .env ファイル
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
OTEL_LOGS_ENABLED=true
```

### ポートとプロトコルの対応表

| ポート | プロトコル | 用途 | Laravel設定例 |
|--------|------------|------|----------------|
| 4317 | gRPC | バイナリデータ | `grpc://127.0.0.1:4317` |
| 4318 | HTTP | JSON/Protobuf | `http://127.0.0.1:4318` |

## 診断コマンド集

### システム状態確認

```bash
# 全体的な状態確認
echo "=== サービス状態 ==="
sudo systemctl status otel-collector amazon-cloudwatch-agent xray

echo "=== ポート使用状況 ==="
sudo netstat -tlnp | grep -E '4317|4318|2000'

echo "=== プロセス確認 ==="
ps aux | grep -E 'otelcol|cloudwatch|xray'
```

### 設定確認

```bash
# OpenTelemetry Collector設定
echo "=== OpenTelemetry Collector設定 ==="
sudo cat /etc/otel-collector/config.yaml | grep -A10 -B5 endpoint

# Laravel OpenTelemetry設定
echo "=== Laravel OpenTelemetry設定 ==="
cd /var/www/html/laravel12-otel-ec2-xray
sudo -u nginx grep OTEL .env
```

### ログ確認

```bash
# リアルタイムログ監視
echo "=== OpenTelemetry Collectorログ ==="
sudo journalctl -u otel-collector -f

# エラーログ確認
echo "=== Laravel エラーログ ==="
sudo tail -f /var/www/html/laravel12-otel-ec2-xray/storage/logs/laravel.log
```

### 接続テスト

```bash
# ヘルスチェック
echo "=== ヘルスチェック ==="
curl -f http://localhost:13133/health

# エンドポイント接続テスト
echo "=== エンドポイント接続テスト ==="
curl -v http://localhost:4318/v1/traces

# Laravel マイグレーションテスト
echo "=== Laravel マイグレーションテスト ==="
cd /var/www/html/laravel12-otel-ec2-xray
sudo -u nginx php artisan migrate --dry-run
```

## 予防策

### 1. 設定管理

```bash
# 設定ファイルのバックアップ
sudo cp /etc/otel-collector/config.yaml /etc/otel-collector/config.yaml.backup

# Laravel .env ファイルのバックアップ
cd /var/www/html/laravel12-otel-ec2-xray
sudo -u nginx cp .env .env.backup
```

### 2. 監視とアラート

```bash
# ヘルスチェックスクリプト
cat > ~/health-check.sh << 'EOF'
#!/bin/bash
echo "Health Check: $(date)"

# OpenTelemetry Collectorの状態確認
if curl -f http://localhost:13133/health > /dev/null 2>&1; then
    echo "✅ OpenTelemetry Collector: Healthy"
else
    echo "❌ OpenTelemetry Collector: Unhealthy"
fi

# ポート確認
if netstat -tlnp | grep -q ":4318.*otelcol"; then
    echo "✅ Port 4318: Available"
else
    echo "❌ Port 4318: Not available"
fi

# X-Ray Daemon確認
if netstat -tlnp | grep -q ":2000"; then
    echo "✅ X-Ray Daemon: Running"
else
    echo "❌ X-Ray Daemon: Not running"
fi
EOF

chmod +x ~/health-check.sh
```

### 3. 定期実行設定

```bash
# crontabに追加（5分ごとにヘルスチェック）
echo "*/5 * * * * /home/ec2-user/health-check.sh >> /var/log/otel-health.log 2>&1" | crontab -
```

### 4. ログローテーション

```bash
# ログローテーション設定
sudo tee /etc/logrotate.d/otel-health << 'EOF'
/var/log/otel-health.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 ec2-user ec2-user
}
EOF
```

## まとめ

### よくある問題と解決パターン

| 問題 | 症状 | 解決方法 |
|------|------|----------|
| 設定ファイルエラー | `unknown type` | エクスポーター名確認・修正 |
| ポート競合 | `address already in use` | 競合サービス停止・ポート変更 |
| プロトコルミスマッチ | `HTTP/0.9 when not allowed` | HTTP用ポート(4318)使用 |
| サービス起動失敗 | `activating (auto-restart)` | ログ確認・設定修正 |

### 成功の確認方法

```bash
# 1. サービス状態確認
sudo systemctl status otel-collector  # Active (running)

# 2. ポート確認
sudo lsof -i :4318  # otelcol-contrib がLISTEN

# 3. Laravel テスト
sudo -u nginx php artisan migrate  # エラーなし

# 4. トレース確認
sudo journalctl -u otel-collector -f  # トレースデータ表示
```

### トラブルシューティングの流れ

1. **症状の確認**: エラーメッセージ・ログの確認
2. **現状の把握**: サービス状態・ポート・プロセスの確認
3. **問題の特定**: 設定・競合・プロトコルの確認
4. **解決策の実行**: 設定修正・サービス再起動
5. **動作確認**: テスト実行・ログ確認

このガイドに従うことで、OpenTelemetry関連の問題を体系的に解決できます。 
