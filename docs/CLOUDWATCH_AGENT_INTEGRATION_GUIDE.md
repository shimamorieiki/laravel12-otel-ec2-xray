# CloudWatch Agent統合ガイド

このガイドでは、AWS EC2環境でCloudWatch AgentとOpenTelemetry Collectorを統合する方法について説明します。

## 🎯 概要

CloudWatch Agentは、EC2インスタンスからシステムメトリクスとログを収集してCloudWatchに送信するサービスです。
OpenTelemetry Collectorと同時に使用する場合、ポート競合やプロトコルの問題が発生する可能性があります。

## 🔧 CloudWatch Agent設定

### 1. CloudWatch Agentの基本設定

#### 設定ファイルの場所
```bash
# CloudWatch Agent設定ファイル
/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# 設定の確認
sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

#### ⚠️ 重要：traceセクションの削除

**OpenTelemetry Collectorを使用する場合、CloudWatch Agentの`traces`セクションは不要です。**

```json
// ❌ 削除が必要な設定
"traces": {
  "traces_collected": {
    "otlp": {
      "grpc_endpoint": "127.0.0.1:4317",
      "http_endpoint": "127.0.0.1:4318"
    }
  }
}
```

**理由:**
1. **ポート競合**: CloudWatch Agentが4317/4318をリッスンし、OpenTelemetry Collectorと競合
2. **役割の重複**: トレース処理の二重化でパフォーマンス低下
3. **設定の複雑化**: 2つのサービスでトレース設定を管理する必要

#### 推奨設定（traceセクション削除版）
```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/nginx-access",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/aws/ec2/nginx-error",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/php-fpm/error.log",
            "log_group_name": "/aws/ec2/php-fpm-error",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/www/html/storage/logs/laravel.log",
            "log_group_name": "/aws/ec2/laravel-logs",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "diskio": {
        "measurement": [
          "io_time",
          "read_bytes",
          "write_bytes",
          "reads",
          "writes"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait"
        ],
        "metrics_collection_interval": 60
      },
      "processes": {
        "measurement": [
          "running",
          "sleeping",
          "dead"
        ]
      }
    }
  }
}
```

#### 🔄 設定変更の実行手順

**ステップ1: 現在の設定のバックアップ**
```bash
# 現在の設定をバックアップ
sudo cp /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
       /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json.backup.$(date +%Y%m%d_%H%M%S)

# バックアップの確認
ls -la /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json.backup.*
```

**ステップ2: traceセクションの削除**
```bash
# traceセクションが存在するか確認
sudo grep -A 10 '"traces"' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# traceセクションを削除（一時的なファイルを作成）
sudo jq 'del(.traces)' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /tmp/cloudwatch-agent-config.json

# 設定を適用
sudo cp /tmp/cloudwatch-agent-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo rm /tmp/cloudwatch-agent-config.json
```

**ステップ2b: 手動削除の方法（jqコマンドが使えない場合）**
```bash
# 設定ファイルを編集
sudo nano /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# 以下のセクションを削除：
# "traces": {
#   "traces_collected": {
#     "otlp": {
#       "grpc_endpoint": "127.0.0.1:4317",
#       "http_endpoint": "127.0.0.1:4318"
#     }
#   }
# },
# 
# 注意：最後の要素でない場合は、カンマも削除してください
```

**ステップ3: 設定の検証**
```bash
# JSONファイルの構文チェック
sudo python3 -m json.tool /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null
echo "設定ファイルの構文: OK"

# traceセクションが削除されたことを確認
sudo grep -q '"traces"' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
if [ $? -eq 0 ]; then
    echo "❌ traceセクションがまだ存在します"
else
    echo "✅ traceセクションが正常に削除されました"
fi
```

**ステップ4: CloudWatch Agentの再起動**
```bash
# CloudWatch Agentを停止
sudo systemctl stop amazon-cloudwatch-agent

# ポート4317/4318が開放されたことを確認
sudo lsof -i :4317 -i :4318

# CloudWatch Agentを起動
sudo systemctl start amazon-cloudwatch-agent

# 起動状態の確認
sudo systemctl status amazon-cloudwatch-agent
```

**ステップ5: OpenTelemetry Collectorの起動**
```bash
# OpenTelemetry Collectorを起動
sudo systemctl start otel-collector

# 起動状態の確認
sudo systemctl status otel-collector

# ポート4317/4318がOpenTelemetry Collectorで使用されていることを確認
sudo lsof -i :4317 -i :4318
```

**ステップ6: 動作確認**
```bash
# CloudWatch Agentのログ確認
sudo journalctl -u amazon-cloudwatch-agent -f --lines=20

# OpenTelemetry Collectorのログ確認
sudo journalctl -u otel-collector -f --lines=20

# ポート使用状況の最終確認
sudo netstat -tlnp | grep -E "4317|4318|2000"
```

#### 🎯 設定変更による改善点

**1. ポート競合の解決**
```bash
# 変更前（問題のある状態）
# Port 4317: amazon-cloudwatch-agent (CloudWatch Agent)
# Port 4318: amazon-cloudwatch-agent (CloudWatch Agent)
# Port 2000: xray (X-Ray Daemon)

# 変更後（正しい状態）
# Port 4317: otelcol-contrib (OpenTelemetry Collector)
# Port 4318: otelcol-contrib (OpenTelemetry Collector)
# Port 2000: xray (X-Ray Daemon)
```

**2. 明確な役割分担**
- **CloudWatch Agent**: システムメトリクス + アプリケーションログ収集
- **OpenTelemetry Collector**: トレース + 分散メトリクス + 構造化ログ処理
- **X-Ray Daemon**: トレースの最終送信先

**3. パフォーマンス向上**
- トレース処理の重複を排除
- メモリ使用量の最適化
- ネットワーク帯域の効率化

**4. 運用の簡素化**
- トレース設定の一元管理（OpenTelemetry Collectorのみ）
- 監視ポイントの明確化
- トラブルシューティングの簡素化

#### 🔍 最終確認方法

**期待される状態の確認**
```bash
# 1. サービス状態の確認
sudo systemctl status amazon-cloudwatch-agent otel-collector xray

# 期待される出力:
# amazon-cloudwatch-agent.service - Amazon CloudWatch Agent
#    Active: active (running)
# 
# otel-collector.service - OpenTelemetry Collector
#    Active: active (running)
# 
# xray.service - AWS X-Ray Daemon
#    Active: active (running)

# 2. ポート使用状況の確認
sudo lsof -i :4317 -i :4318 -i :2000

# 期待される出力:
# COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
# otelcol-co  1234 root  10u  IPv4  12345      0t0  TCP *:4317 (LISTEN)
# otelcol-co  1234 root  11u  IPv4  12346      0t0  TCP *:4318 (LISTEN)
# xray        5678 root  12u  IPv4  12347      0t0  TCP 127.0.0.1:2000 (LISTEN)

# 3. トレース送信の確認
sudo journalctl -u otel-collector -f --lines=10 | grep -E "awsxray|TracesExporter"

# 期待される出力:
# "otelcol.component.id": "awsxray"
# TracesExporter ... "#spans": 5
```

**トラブルシューティング用の確認コマンド**
```bash
# CloudWatch Agentにtraceセクションがないことを確認
sudo grep -q '"traces"' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
if [ $? -eq 0 ]; then
    echo "❌ traceセクションがまだ存在します - 再度削除してください"
else
    echo "✅ traceセクションが正常に削除されています"
fi

# OpenTelemetry Collectorが正常に動作していることを確認
curl -f http://localhost:13133/
if [ $? -eq 0 ]; then
    echo "✅ OpenTelemetry Collectorが正常に動作しています"
else
    echo "❌ OpenTelemetry Collectorに問題があります"
fi

# X-Ray Daemonが正常に動作していることを確認
curl -f http://localhost:2000/
if [ $? -eq 0 ]; then
    echo "✅ X-Ray Daemonが正常に動作しています"
else
    echo "❌ X-Ray Daemonに問題があります"
fi
```

### 2. CloudWatch Agentの管理

#### サービスの状態確認
```bash
# CloudWatch Agentの状態確認
sudo systemctl status amazon-cloudwatch-agent

# 期待される出力:
# ● amazon-cloudwatch-agent.service - Amazon CloudWatch Agent
#    Loaded: loaded (/etc/systemd/system/amazon-cloudwatch-agent.service; enabled; vendor preset: disabled)
#    Active: active (running) since Mon 2024-01-01 12:00:00 UTC; 1h 30min ago
```

#### サービスの制御
```bash
# CloudWatch Agentの開始
sudo systemctl start amazon-cloudwatch-agent

# CloudWatch Agentの停止
sudo systemctl stop amazon-cloudwatch-agent

# CloudWatch Agentの再起動
sudo systemctl restart amazon-cloudwatch-agent

# CloudWatch Agentの自動起動設定
sudo systemctl enable amazon-cloudwatch-agent
```

#### ログの確認
```bash
# CloudWatch Agentのログ確認
sudo journalctl -u amazon-cloudwatch-agent -f

# 設定ファイルの検証
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -a query-config
```

## ⚠️ ポート競合問題

### 1. ポート競合の発見

#### 使用中のポート確認
```bash
# OpenTelemetryのポート（4317, 4318）の使用状況確認
sudo lsof -i :4317
sudo lsof -i :4318

# 例: CloudWatch Agentが4317を使用している場合
# COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
# amazon-cloudwa 5903 root  11u  IPv4  12345      0t0  TCP 127.0.0.1:4317 (LISTEN)
```

#### ポート競合の対処法

**方法1: OpenTelemetry Collectorのポート変更**
```yaml
# docker/otel-collector/otel-collector-config.ec2.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4319  # 4317から変更
      http:
        endpoint: 0.0.0.0:4320  # 4318から変更
```

**方法2: CloudWatch Agentのポート変更**
```bash
# CloudWatch Agent設定でポートを変更
# 通常、CloudWatch Agentは4317を内部で使用するため、
# 設定ファイルで代替ポートを指定する必要があります
```

### 2. プロトコル設定の重要性

#### HTTP vs gRPC
```bash
# CloudWatch Agentは通常gRPCプロトコルを使用（ポート4317）
# OpenTelemetryクライアントがHTTPを使用する場合はポート4318を使用

# Laravel設定確認
grep -r "4317\|4318" config/opentelemetry.php

# 期待される出力:
# 'endpoint' => env('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://localhost:4318'),
```

## 🔄 統合設定

### 1. OpenTelemetry Collector設定

#### EC2環境用設定
```yaml
# docker/otel-collector/otel-collector-config.ec2.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4319  # CloudWatch Agent競合回避
      http:
        endpoint: 0.0.0.0:4320  # CloudWatch Agent競合回避

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
  # Console exporter for debugging
  logging:
    verbosity: detailed  # loglevelは非推奨

  # AWS X-Ray exporter
  awsxray:
    endpoint: http://127.0.0.1:2000
    local_mode: true
    region: ap-northeast-1
    no_verify_ssl: false
    index_all_attributes: true

  # CloudWatch metrics exporter (修正版)
  awsemf:  # awscloudwatchmetricsは存在しない
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

service:
  extensions: [health_check]
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

### 2. Laravel設定の調整

#### 環境変数の設定
```bash
# .env
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4320
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
OTEL_LOGS_ENABLED=true
```

#### Docker Compose設定
```yaml
# docker-compose.yml
version: '3.8'

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./docker/otel-collector/otel-collector-config.ec2.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4319:4319"  # gRPC (CloudWatch Agent競合回避)
      - "4320:4320"  # HTTP (CloudWatch Agent競合回避)
      - "13133:13133"  # Health check
    environment:
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
    depends_on:
      - app

  app:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "80:80"
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4320
      - OTEL_EXPORTER_OTLP_PROTOCOL=http/json
    volumes:
      - .:/var/www/html
```

## 🔍 トラブルシューティング

### 1. ポート競合の診断

#### ポート使用状況の確認
```bash
# 全体的なポート使用状況
sudo netstat -tlnp | grep -E "4317|4318|4319|4320"

# プロセス別のポート使用状況
sudo lsof -i -P -n | grep -E "4317|4318|4319|4320"
```

#### CloudWatch Agentの詳細確認
```bash
# CloudWatch Agentの設定確認
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -a query-config

# CloudWatch Agentのログ確認
sudo journalctl -u amazon-cloudwatch-agent --since "1 hour ago"
```

### 2. 接続エラーの対処

#### OpenTelemetry接続エラー
```bash
# Laravelアプリケーションのログ確認
docker-compose logs app | grep -i "opentelemetry\|otel"

# 一般的なエラーと対処法:
# "cURL error 1: Received HTTP/0.9 when not allowed"
# → HTTPエンドポイント（4320）を使用しているか確認

# "Connection refused"
# → ポート番号が正しいか確認
# → OpenTelemetry Collectorが起動しているか確認
```

#### X-Ray接続エラー
```bash
# X-Ray daemonの状態確認
sudo systemctl status xray

# X-Ray daemonのログ確認
sudo journalctl -u xray -f

# X-Ray daemonの再起動
sudo systemctl restart xray
```

### 3. パフォーマンスの最適化

#### CloudWatch Agentのリソース使用量
```bash
# CloudWatch Agentのリソース使用量確認
top -p $(pgrep amazon-cloudwatch-agent)

# メモリ使用量の詳細確認
sudo cat /proc/$(pgrep amazon-cloudwatch-agent)/status | grep -i mem
```

#### OpenTelemetry Collectorのリソース使用量
```bash
# OpenTelemetry Collectorのリソース使用量確認
docker stats otel-collector

# 期待される出力:
# CONTAINER ID   NAME           CPU %     MEM USAGE / LIMIT     MEM %     NET I/O
# 1234567890ab   otel-collector 2.34%     45.67MiB / 256.0MiB   17.84%    1.2kB / 3.4kB
```

## 📊 監視とアラート

### 1. CloudWatch Metricsの確認

#### コンソールでの確認
```bash
# AWS CLIでメトリクスを確認
aws cloudwatch get-metric-statistics \
    --namespace "Laravel/OpenTelemetry" \
    --metric-name "http_requests_total" \
    --dimensions Name=service.name,Value=laravel-app \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 300 \
    --statistics Sum
```

#### カスタムメトリクスの設定
```yaml
# OpenTelemetry Collectorでのメトリクス設定
exporters:
  awsemf:
    region: ap-northeast-1
    namespace: Laravel/OpenTelemetry
    dimension_rollup_option: NoDimensionRollup
    metric_declarations:
      - dimensions: [[service.name], [service.name, deployment.environment]]
        metric_name_selectors:
          - "http_requests_total"
          - "http_request_duration_seconds"
          - "database_query_duration_seconds"
```

### 2. アラートの設定

#### CloudWatch Alarmの作成
```bash
# アプリケーションエラー率のアラーム
aws cloudwatch put-metric-alarm \
    --alarm-name "Laravel-ErrorRate-High" \
    --alarm-description "Laravel application error rate is too high" \
    --metric-name "http_requests_total" \
    --namespace "Laravel/OpenTelemetry" \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2

# システムリソースのアラーム
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2-HighCPUUtilization" \
    --alarm-description "EC2 instance CPU utilization is too high" \
    --metric-name "CPUUtilization" \
    --namespace "AWS/EC2" \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2
```

## 🚀 ベストプラクティス

### 1. 設定の管理

#### 設定ファイルのバージョン管理
```bash
# 設定ファイルのバックアップ
sudo cp /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
       /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json.backup

# 設定の変更履歴を記録
echo "$(date): CloudWatch Agent configuration updated" >> /var/log/config-changes.log
```

#### 環境別の設定管理
```bash
# 環境別設定ファイル
# - cloudwatch-agent-dev.json
# - cloudwatch-agent-staging.json
# - cloudwatch-agent-prod.json

# 設定の切り替え
sudo cp /opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-agent-prod.json \
       /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

### 2. セキュリティ

#### IAM権限の最小化
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

#### ネットワークセキュリティ
```bash
# ファイアウォール設定（必要に応じて）
# OpenTelemetry Collectorのポートを内部ネットワークのみに制限
sudo ufw allow from 10.0.0.0/8 to any port 4319
sudo ufw allow from 10.0.0.0/8 to any port 4320
```

### 3. 運用

#### 定期的なヘルスチェック
```bash
#!/bin/bash
# healthcheck.sh

echo "=== CloudWatch Agent & OpenTelemetry Health Check ==="
echo "Date: $(date)"
echo ""

# CloudWatch Agent状態確認
echo "1. CloudWatch Agent Status:"
sudo systemctl is-active amazon-cloudwatch-agent
echo ""

# OpenTelemetry Collector状態確認
echo "2. OpenTelemetry Collector Status:"
curl -s http://localhost:13133/ | jq .status
echo ""

# ポート競合チェック
echo "3. Port Conflict Check:"
sudo lsof -i :4317 -i :4318 -i :4319 -i :4320
echo ""

# 最近のエラーログ確認
echo "4. Recent Error Logs:"
sudo journalctl -u amazon-cloudwatch-agent --since "1 hour ago" | grep -i error
docker-compose logs otel-collector --since=1h | grep -i error
```

#### ログローテーション
```bash
# CloudWatch Agentログのローテーション設定
sudo logrotate -f /etc/logrotate.d/amazon-cloudwatch-agent

# OpenTelemetryログのローテーション
docker-compose logs otel-collector > /var/log/otel-collector-$(date +%Y%m%d).log
```

## 📚 関連ドキュメント

- [OpenTelemetry監視ガイド](OPENTELEMETRY_MONITORING_GUIDE.md)
- [X-Rayトラブルシューティングガイド](XRAY_TROUBLESHOOTING_GUIDE.md)
- [EC2設定ガイド](EC2_SETUP.md)
- [AWS認証情報設定](AWS_CREDENTIALS_SETUP.md)

## 📞 サポート

問題が発生した場合は、以下の情報を含めて報告してください：

1. CloudWatch Agentの設定ファイル
2. OpenTelemetry Collectorの設定ファイル
3. エラーログ（CloudWatch Agent、OpenTelemetry Collector）
4. ポート使用状況（`sudo lsof -i :4317-4320`）
5. システムリソース使用状況（`top`、`free -h`） 
