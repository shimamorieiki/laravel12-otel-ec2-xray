# CloudWatch Agent統合ガイド

このガイドでは、AWS EC2環境でCloudWatch AgentとOpenTelemetry Collectorを統合し、包括的なモニタリングシステムを構築する方法について説明します。

## 🎯 システムアーキテクチャ

### 監視データの流れ
```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EC2 Instance                                   │
│                                                                         │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    │
│  │ Laravel App     │    │ System (OS)     │    │ Infrastructure  │    │
│  │ - HTTP Requests │    │ - CPU Usage     │    │ - Nginx         │    │
│  │ - DB Queries    │    │ - Memory Usage  │    │ - PHP-FPM       │    │
│  │ - Custom Events │    │ - Disk I/O      │    │ - PostgreSQL    │    │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘    │
│           │                       │                       │            │
│           ▼                       ▼                       ▼            │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    │
│  │ OpenTelemetry   │    │ CloudWatch      │    │ CloudWatch      │    │
│  │ Collector       │    │ Agent           │    │ Agent           │    │
│  │ - Traces        │    │ - System        │    │ - Application   │    │
│  │ - App Metrics   │    │   Metrics       │    │   Logs          │    │
│  │ - Custom Logs   │    │ - Process       │    │ - Error Logs    │    │
│  └─────────────────┘    │   Metrics       │    │ - Access Logs   │    │
│           │              └─────────────────┘    └─────────────────┘    │
│           │                       │                       │            │
└───────────┼───────────────────────┼───────────────────────┼────────────┘
            │                       │                       │
            ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ AWS X-Ray       │    │ CloudWatch      │    │ CloudWatch      │
│ - Distributed   │    │ Metrics         │    │ Logs            │
│   Traces        │    │ - CPU/Memory    │    │ - Application   │
│ - Service Map   │    │ - Disk/Network  │    │   Logs          │
│ - Performance   │    │ - Custom        │    │ - System Logs   │
│   Analysis      │    │   Metrics       │    │ - Error Logs    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 役割分担
| コンポーネント | 役割 | 収集データ |
|----------------|------|------------|
| **CloudWatch Agent** | システムメトリクス + ログ収集 | CPU、メモリ、ディスク、ネットワーク、アプリケーションログ |
| **OpenTelemetry Collector** | アプリケーション監視 | トレース、アプリケーションメトリクス、カスタムログ |
| **X-Ray** | 分散トレーシング | リクエストフロー、レスポンス時間、エラー分析 |

## 🔧 CloudWatch Agent設定

### 1. インストール

#### Amazon Linux 2023の場合（推奨）
```bash
# 直接yum/dnfでインストール
sudo yum install amazon-cloudwatch-agent -y

# または dnf を使用
sudo dnf install amazon-cloudwatch-agent -y
```

#### その他のLinuxディストリビューション
```bash
# CloudWatch Agentのダウンロード
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm

# インストール
sudo rpm -U amazon-cloudwatch-agent.rpm
```

#### 共通設定
```bash
# 設定ディレクトリの作成
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
```

### 2. 包括的な設定ファイル
```bash
# 設定ファイルの作成
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "Laravel/Infrastructure",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system",
          "cpu_usage_steal",
          "cpu_usage_nice",
          "cpu_usage_softirq",
          "cpu_usage_irq"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": true,
        "resources": [
          "*"
        ]
      },
      "disk": {
        "measurement": [
          "used_percent",
          "inodes_free",
          "inodes_used",
          "inodes_total"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ],
        "ignore_file_system_types": [
          "sysfs",
          "devtmpfs",
          "tmpfs"
        ]
      },
      "diskio": {
        "measurement": [
          "io_time",
          "read_bytes",
          "write_bytes",
          "reads",
          "writes",
          "read_time",
          "write_time",
          "iops_in_progress"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent",
          "mem_available",
          "mem_used",
          "mem_total",
          "mem_cached",
          "mem_buffers"
        ],
        "metrics_collection_interval": 60
      },
      "net": {
        "measurement": [
          "bytes_sent",
          "bytes_recv",
          "packets_sent",
          "packets_recv",
          "err_in",
          "err_out",
          "drop_in",
          "drop_out"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait",
          "tcp_close",
          "tcp_close_wait",
          "tcp_closing",
          "tcp_fin_wait1",
          "tcp_fin_wait2",
          "tcp_last_ack",
          "tcp_listen",
          "tcp_syn_sent",
          "tcp_syn_recv",
          "udp_socket"
        ],
        "metrics_collection_interval": 60
      },
      "processes": {
        "measurement": [
          "running",
          "sleeping",
          "dead",
          "zombies",
          "stopped",
          "total"
        ]
      },
      "swap": {
        "measurement": [
          "swap_used_percent",
          "swap_free",
          "swap_used",
          "swap_total"
        ]
      },
      "procstat": [
        {
          "pattern": "nginx",
          "measurement": [
            "cpu_usage",
            "memory_rss",
            "memory_vms",
            "memory_swap",
            "read_bytes",
            "write_bytes",
            "read_count",
            "write_count",
            "num_threads"
          ],
          "metrics_collection_interval": 60,
          "totalcpu": true
        },
        {
          "pattern": "php-fpm",
          "measurement": [
            "cpu_usage",
            "memory_rss",
            "memory_vms",
            "memory_swap",
            "read_bytes",
            "write_bytes",
            "read_count",
            "write_count",
            "num_threads"
          ],
          "metrics_collection_interval": 60,
          "totalcpu": true
        },
        {
          "pattern": "otelcol-contrib",
          "measurement": [
            "cpu_usage",
            "memory_rss",
            "memory_vms",
            "num_threads"
          ],
          "metrics_collection_interval": 60,
          "totalcpu": true
        }
      ]
    },
    "append_dimensions": {
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}",
      "ImageId": "${aws:ImageId}",
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}",
      "Environment": "production",
      "Application": "Laravel-OpenTelemetry"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/nginx/access",
            "log_stream_name": "{instance_id}-{hostname}",
            "timezone": "UTC",
            "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/aws/ec2/nginx/error",
            "log_stream_name": "{instance_id}-{hostname}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/php-fpm/error.log",
            "log_group_name": "/aws/ec2/php-fpm/error",
            "log_stream_name": "{instance_id}-{hostname}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/php-fpm/www-error.log",
            "log_group_name": "/aws/ec2/php-fpm/www-error",
            "log_stream_name": "{instance_id}-{hostname}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/www/html/laravel12-otel-ec2-xray/storage/logs/laravel.log",
            "log_group_name": "/aws/ec2/laravel/application",
            "log_stream_name": "{instance_id}-{hostname}",
            "timezone": "UTC",
            "timestamp_format": "[%Y-%m-%d %H:%M:%S]"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/ec2/system/messages",
            "log_stream_name": "{instance_id}-{hostname}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF
```

### 3. CloudWatch Agentの起動と管理
```bash
# CloudWatch Agentの設定適用
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# サービスの有効化と起動
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent

# 状態確認
sudo systemctl status amazon-cloudwatch-agent
```

## 🔄 OpenTelemetry Collector統合設定

### 1. OpenTelemetry Collectorの役割
OpenTelemetry Collectorは以下を担当します：
- **アプリケーション トレース**: リクエストフロー、データベースクエリ
- **カスタム メトリクス**: ビジネスロジック固有のメトリクス
- **構造化ログ**: アプリケーションログの構造化処理

### 2. OpenTelemetry Collectorのインストール

#### Amazon Linux 2023の場合
```bash
# OpenTelemetry Collectorのダウンロード
OTEL_VERSION="0.129.0"
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz

# 展開とインストール
tar -xzf otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz
sudo mv otelcol-contrib /usr/local/bin/
sudo chmod +x /usr/local/bin/otelcol-contrib

# 設定ディレクトリの作成
sudo mkdir -p /etc/otel-collector
```

#### systemdサービスファイルの作成
```bash
sudo tee /etc/systemd/system/otel-collector.service > /dev/null <<'EOF'
[Unit]
Description=OpenTelemetry Collector
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/otelcol-contrib --config=/etc/otel-collector/config.yaml
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
```

### 3. CloudWatch Agent統合設定

#### CloudWatch Agent設定でOpenTelemetry Collectorを統合
```bash
# CloudWatch Agent設定（OpenTelemetry Collector統合版）
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "traces": {
    "traces_collected": {
      "otlp": {
        "grpc_endpoint": "127.0.0.1:4317",
        "http_endpoint": "127.0.0.1:4318"
      }
    }
  },
  "metrics": {
    "namespace": "Laravel/Infrastructure",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": true
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
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
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          "mem_used_percent",
          "mem_available",
          "mem_used",
          "mem_total"
        ],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [
          "swap_used_percent",
          "swap_free",
          "swap_used"
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait"
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF
```

### 5. サービスの起動と管理

#### 両方のサービスの起動
```bash
# CloudWatch Agentの設定適用と起動
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# OpenTelemetry Collectorの起動
sudo systemctl daemon-reload
sudo systemctl enable otel-collector
sudo systemctl start otel-collector

# X-Ray Daemonの起動
sudo systemctl enable xray
sudo systemctl start xray

# 全サービスの状態確認
sudo systemctl status amazon-cloudwatch-agent otel-collector xray
```

#### サービス間の連携確認
```bash
# ポート使用状況の確認
echo "=== ポート使用状況 ==="
sudo netstat -tlnp | grep -E "4317|4318|8125|2000|13133"

# 期待される結果:
# 4317: otelcol-contrib (OpenTelemetry Collector gRPC)
# 4318: otelcol-contrib (OpenTelemetry Collector HTTP)
# 8125: amazon-cloudwatch-agent (StatsD)
# 2000: xray (X-Ray Daemon)
# 13133: otelcol-contrib (Health Check)

# CloudWatch Agentのログ確認
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# OpenTelemetry Collectorのログ確認
sudo journalctl -u otel-collector -f
```

### 6. 統合テストスクリプト

#### 統合動作テスト
```bash
#!/bin/bash
# integrated-test.sh - CloudWatch Agent + OpenTelemetry Collector統合テスト

echo "🔍 統合動作テスト"
echo "=================="

# 1. サービス状態確認
echo "1. サービス状態確認"
services=("amazon-cloudwatch-agent" "otel-collector" "xray")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: Active"
    else
        echo "❌ $service: Inactive"
    fi
done

# 2. ポート競合チェック
echo -e "\n2. ポート競合チェック"
echo "CloudWatch Agent StatsD (8125):"
if sudo lsof -i :8125 | grep -q amazon-cloudwatch-agent; then
    echo "✅ CloudWatch Agent listening on 8125"
else
    echo "❌ CloudWatch Agent not listening on 8125"
fi

echo "OpenTelemetry Collector (4317/4318):"
if sudo lsof -i :4317 | grep -q otelcol-contrib; then
    echo "✅ OpenTelemetry Collector listening on 4317"
else
    echo "❌ OpenTelemetry Collector not listening on 4317"
fi

# 3. OpenTelemetry Collector health check
echo -e "\n3. OpenTelemetry Collector Health Check"
if curl -s http://localhost:13133/ | grep -q "Server available"; then
    echo "✅ OpenTelemetry Collector is healthy"
else
    echo "❌ OpenTelemetry Collector health check failed"
fi

# 4. StatsD連携テスト
echo -e "\n4. StatsD連携テスト"
echo "test.metric:1|c" | nc -u -w1 127.0.0.1 8125
if [ $? -eq 0 ]; then
    echo "✅ StatsD送信成功"
else
    echo "❌ StatsD送信失敗"
fi

# 5. メトリクス送信確認
echo -e "\n5. メトリクス送信確認"
echo "CloudWatch Agent メトリクス:"
aws cloudwatch get-metric-statistics \
    --namespace "Laravel/Infrastructure" \
    --metric-name "cpu_usage_active" \
    --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics "Average" \
    --query 'Datapoints[0].Average' \
    --output text 2>/dev/null | head -1

echo "OpenTelemetry Application メトリクス:"
aws cloudwatch get-metric-statistics \
    --namespace "Laravel/Application" \
    --metric-name "http_request_duration" \
    --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics "Average" \
    --query 'Datapoints[0].Average' \
    --output text 2>/dev/null | head -1

echo -e "\n✅ 統合テスト完了"
```

### 7. 自動デプロイスクリプト

#### 一括セットアップスクリプト
```bash
#!/bin/bash
# setup-integrated-monitoring.sh - 統合監視システムのセットアップ

echo "🚀 統合監視システムセットアップ"
echo "================================"

# 1. CloudWatch Agentのインストール
echo "1. CloudWatch Agentのインストール"
if command -v yum &> /dev/null; then
    sudo yum install amazon-cloudwatch-agent -y
elif command -v dnf &> /dev/null; then
    sudo dnf install amazon-cloudwatch-agent -y
else
    echo "❌ yum/dnf not found"
    exit 1
fi

# 2. OpenTelemetry Collectorのインストール
echo "2. OpenTelemetry Collectorのインストール"
OTEL_VERSION="0.129.0"
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz
tar -xzf otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz
sudo mv otelcol-contrib /usr/local/bin/
sudo chmod +x /usr/local/bin/otelcol-contrib
sudo mkdir -p /etc/otel-collector

# 3. X-Ray Daemonのインストール
echo "3. X-Ray Daemonのインストール"
if ! command -v xray &> /dev/null; then
    wget https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-3.x.rpm
    sudo yum install -y aws-xray-daemon-3.x.rpm
fi

# 4. 設定ファイルの作成
echo "4. 設定ファイルの作成"
# CloudWatch Agent設定は上記のJSONを使用
# OpenTelemetry Collector設定は上記のYAMLを使用

# 5. systemdサービスの設定
echo "5. systemdサービスの設定"
# OpenTelemetry Collectorのサービスファイルを作成（上記参照）

# 6. サービスの起動
echo "6. サービスの起動"
sudo systemctl daemon-reload
sudo systemctl enable amazon-cloudwatch-agent otel-collector xray
sudo systemctl start amazon-cloudwatch-agent otel-collector xray

# 7. 動作確認
echo "7. 動作確認"
sleep 10
sudo systemctl status amazon-cloudwatch-agent otel-collector xray

echo "✅ 統合監視システムセットアップ完了"
EOF
```

## 📊 メトリクス統合とダッシュボード

### 1. CloudWatch ダッシュボード設定
```bash
# CloudWatch ダッシュボードの作成
aws cloudwatch put-dashboard --dashboard-name "Laravel-OpenTelemetry-Dashboard" --dashboard-body '{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["Laravel/Infrastructure", "cpu_usage_active", "InstanceId", "AUTO"],
          [".", "mem_used_percent", ".", "."],
          [".", "disk_used_percent", ".", ".", "device", "/dev/xvda1"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1",
        "title": "System Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["Laravel/Application", "http_request_duration", "service.name", "laravel-app"],
          [".", "db_query_duration", ".", "."],
          [".", "cache_hit_ratio", ".", "."]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1",
        "title": "Application Metrics"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/ec2/laravel/application' | fields @timestamp, level, message | filter level = 'ERROR' | sort @timestamp desc | limit 20",
        "region": "ap-northeast-1",
        "title": "Recent Errors"
      }
    }
  ]
}'
```

### 2. アラーム設定
```bash
# 高CPU使用率アラーム
aws cloudwatch put-metric-alarm \
    --alarm-name "Laravel-HighCPU" \
    --alarm-description "High CPU usage detected" \
    --metric-name "cpu_usage_active" \
    --namespace "Laravel/Infrastructure" \
    --statistic "Average" \
    --period 300 \
    --threshold 80 \
    --comparison-operator "GreaterThanThreshold" \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws:sns:ap-northeast-1:123456789012:alerts"

# 高メモリ使用率アラーム
aws cloudwatch put-metric-alarm \
    --alarm-name "Laravel-HighMemory" \
    --alarm-description "High memory usage detected" \
    --metric-name "mem_used_percent" \
    --namespace "Laravel/Infrastructure" \
    --statistic "Average" \
    --period 300 \
    --threshold 85 \
    --comparison-operator "GreaterThanThreshold" \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws:sns:ap-northeast-1:123456789012:alerts"

# アプリケーション応答時間アラーム
aws cloudwatch put-metric-alarm \
    --alarm-name "Laravel-SlowResponse" \
    --alarm-description "Slow application response detected" \
    --metric-name "http_request_duration" \
    --namespace "Laravel/Application" \
    --statistic "Average" \
    --period 300 \
    --threshold 2000 \
    --comparison-operator "GreaterThanThreshold" \
    --evaluation-periods 3 \
    --alarm-actions "arn:aws:sns:ap-northeast-1:123456789012:alerts"
```

## 🔧 Laravel設定

### 1. OpenTelemetry設定
```bash
# Laravel .env設定
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
OTEL_LOGS_ENABLED=true
OTEL_SERVICE_NAME=laravel-app
OTEL_SERVICE_VERSION=1.0.0
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

### 2. カスタムメトリクス例
```php
// app/Http/Middleware/MetricsMiddleware.php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use OpenTelemetry\API\Metrics\MeterProvider;

class MetricsMiddleware
{
    private $meter;
    private $httpRequestDuration;
    private $httpRequestCount;

    public function __construct()
    {
        $this->meter = MeterProvider::getMeter('laravel-app');
        
        $this->httpRequestDuration = $this->meter->createHistogram(
            'http_request_duration',
            'milliseconds',
            'Duration of HTTP requests'
        );
        
        $this->httpRequestCount = $this->meter->createCounter(
            'http_requests_total',
            'requests',
            'Total number of HTTP requests'
        );
    }

    public function handle(Request $request, Closure $next)
    {
        $startTime = microtime(true);
        
        $response = $next($request);
        
        $duration = (microtime(true) - $startTime) * 1000;
        
        $attributes = [
            'method' => $request->method(),
            'route' => $request->route()?->getName() ?? 'unknown',
            'status_code' => $response->getStatusCode(),
        ];
        
        $this->httpRequestDuration->record($duration, $attributes);
        $this->httpRequestCount->add(1, $attributes);
        
        return $response;
    }
}
```

## 🔍 監視とトラブルシューティング

### 1. 統合監視コマンド
```bash
#!/bin/bash
# monitoring-check.sh - 統合監視スクリプト

echo "🔍 Laravel OpenTelemetry 統合監視"
echo "================================="

# 1. サービス状態確認
echo "1. サービス状態"
services=("amazon-cloudwatch-agent" "otel-collector" "xray" "nginx" "php-fpm")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: Active"
    else
        echo "❌ $service: Inactive"
    fi
done

# 2. メトリクス送信状況
echo -e "\n2. メトリクス送信状況"
echo "CloudWatch Agent メトリクス (最新5分間):"
aws cloudwatch get-metric-statistics \
    --namespace "Laravel/Infrastructure" \
    --metric-name "cpu_usage_active" \
    --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics "Average" \
    --query 'Datapoints[0].Average' \
    --output text

# 3. ログ送信状況
echo -e "\n3. ログ送信状況"
log_groups=("/aws/ec2/nginx/access" "/aws/ec2/nginx/error" "/aws/ec2/laravel/application")
for log_group in "${log_groups[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text >/dev/null 2>&1; then
        echo "✅ $log_group: Active"
    else
        echo "❌ $log_group: Not Found"
    fi
done

echo -e "\n✅ CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=Laravel-OpenTelemetry-Dashboard"
echo "✅ X-Ray Service Map: https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map"
```

### 2. パフォーマンス最適化
```bash
# CloudWatch Agentのメモリ使用量最適化
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/common-config.toml > /dev/null <<'EOF'
[agent]
  buffer_time = 10000
  collection_jitter = "0s"
  debug = false
  flush_interval = "1s"
  flush_jitter = "0s"
  hostname = ""
  interval = "10s"
  logfile = ""
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  omit_hostname = false
  precision = ""
  quiet = false
  round_interval = true
EOF
```

### 3. トラブルシューティング用の自動修正スクリプト
```bash
#!/bin/bash
# fix-cloudwatch-integration.sh

echo "🔧 CloudWatch Agent統合問題修正スクリプト"
echo "=========================================="

# CloudWatch Agentのtraceセクション削除
if sudo grep -q '"traces"' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json 2>/dev/null; then
    echo "⚠️  traceセクションを削除中..."
    sudo jq 'del(.traces)' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /tmp/cw-config.json
    sudo cp /tmp/cw-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    sudo rm /tmp/cw-config.json
    echo "✅ traceセクション削除完了"
fi

# サービス再起動
echo "🔄 サービス再起動中..."
sudo systemctl restart amazon-cloudwatch-agent
sudo systemctl restart otel-collector

echo "✅ 修正完了"
```

## 🎯 統合監視システムのメリット

### 1. データフローの最適化
```
┌─────────────────────────────────────────────────────────────────────────┐
│                    統合監視データフロー                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  Laravel App → OpenTelemetry Collector → StatsD → CloudWatch Agent      │
│                                        → X-Ray                         │
│                                        → CloudWatch Logs               │
│                                                                         │
│  System Metrics → CloudWatch Agent → CloudWatch Metrics               │
│                                                                         │
│  Log Files → CloudWatch Agent → CloudWatch Logs                       │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2. 役割分担の明確化
| コンポーネント | 主な役割 | 送信先 |
|----------------|----------|--------|
| **CloudWatch Agent** | システムメトリクス収集 + ログ収集 + StatsD受信 | CloudWatch Metrics/Logs |
| **OpenTelemetry Collector** | アプリケーション監視 + メトリクス変換 + トレース処理 | X-Ray + CloudWatch (StatsD経由) |
| **X-Ray Daemon** | トレース受信 + 分散トレーシング | X-Ray Service |

### 3. 統合の利点

#### パフォーマンス面
- **メトリクス重複の排除**: 同じメトリクスの二重収集を避ける
- **ネットワーク負荷軽減**: StatsD経由で効率的なメトリクス送信
- **リソース使用量最適化**: 各コンポーネントの専門化

#### 運用面
- **一元管理**: CloudWatch Agentを中心とした統合管理
- **設定の簡素化**: 各コンポーネントの設定が明確に分離
- **トラブルシューティング**: 問題の所在が特定しやすい

#### コスト面
- **CloudWatch API呼び出し削減**: StatsD経由でバッチ送信
- **データ転送量最適化**: 効率的なメトリクス集約
- **運用コスト削減**: 自動化されたスクリプトによる管理

### 4. 監視カバレッジ

#### インフラストラクチャ層
- **CloudWatch Agent**: CPU、メモリ、ディスク、ネットワーク
- **プロセス監視**: Nginx、PHP-FPM、OpenTelemetry Collectorの詳細メトリクス
- **システムログ**: OS、アプリケーション、エラーログ

#### アプリケーション層
- **OpenTelemetry Collector**: HTTPリクエスト、データベースクエリ、カスタムメトリクス
- **分散トレーシング**: X-Ray経由でリクエストフローの可視化
- **構造化ログ**: アプリケーションの詳細ログ

#### 統合ダッシュボード
- **CloudWatch Dashboard**: システム全体の統一された可視化
- **X-Ray Service Map**: 分散システムの依存関係マップ
- **CloudWatch Insights**: ログとメトリクスの高度な分析

### 5. ベストプラクティス

#### 設定管理
```bash
# 設定ファイルのバージョン管理
sudo cp /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
       /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json.$(date +%Y%m%d_%H%M%S)

sudo cp /etc/otel-collector/config.yaml \
       /etc/otel-collector/config.yaml.$(date +%Y%m%d_%H%M%S)
```

#### 監視・アラート
```bash
# 統合ヘルスチェック
curl -s http://localhost:13133/ | jq .
aws cloudwatch get-metric-statistics --namespace "Laravel/Infrastructure" --metric-name "cpu_usage_active" --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" --period 300 --statistics "Average"
```

#### セキュリティ
```bash
# ポート制限（内部通信のみ）
sudo ufw allow from 127.0.0.1 to any port 8125  # StatsD
sudo ufw allow from 127.0.0.1 to any port 4317  # OpenTelemetry gRPC
sudo ufw allow from 127.0.0.1 to any port 4318  # OpenTelemetry HTTP
```

## 🎯 まとめ

この統合設定により、以下の包括的な監視が実現できます：

### CloudWatch Agentが収集するメトリクス
- **システムメトリクス**: CPU、メモリ、ディスク、ネットワーク
- **プロセスメトリクス**: Nginx、PHP-FPM、OpenTelemetry Collectorの詳細
- **ログ**: アプリケーション、システム、エラーログ
- **StatsD受信**: OpenTelemetry Collectorからのメトリクス統合

### OpenTelemetry Collectorが収集するデータ
- **分散トレーシング**: リクエストフロー、レスポンス時間
- **アプリケーションメトリクス**: HTTPリクエスト、データベースクエリ
- **カスタムメトリクス**: ビジネスロジック固有の指標
- **メトリクス変換**: CloudWatch Agent向けStatsD変換

### 監視の利点
- **統一ダッシュボード**: CloudWatchでシステム全体を可視化
- **プロアクティブアラート**: 問題発生前の早期警告
- **根本原因分析**: トレースとメトリクスの組み合わせによる詳細分析
- **運用効率化**: 自動化されたスクリプトによる問題解決
- **コスト最適化**: 効率的なメトリクス送信とAPI呼び出し削減 
