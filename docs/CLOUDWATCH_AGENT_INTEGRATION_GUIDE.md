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

### 5. AWS X-Ray Daemon のインストールと設定

#### 5.1 X-Ray Daemon のインストール

```bash
# X-Ray Daemonのダウンロード
wget https://s3.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-linux-3.x.zip

# 解凍とインストール
unzip aws-xray-daemon-linux-3.x.zip -d /tmp/xray
sudo mkdir -p /opt/xray
sudo mv /tmp/xray/xray /opt/xray/
sudo chmod +x /opt/xray/xray

# 一時ファイルの削除
rm -rf /tmp/xray aws-xray-daemon-linux-3.x.zip
```

#### 5.2 X-Ray Daemon の設定

#### 5.3 systemd サービスの設定

##### サービスファイルの作成
```bash
# X-Ray Daemon systemdサービスファイルの作成
sudo tee /etc/systemd/system/xray.service > /dev/null <<EOF
[Unit]
Description=AWS X-Ray Daemon
After=network.target

[Service]
Type=simple
ExecStart=/opt/xray/xray -o -n ap-northeast-1
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
```

##### サービスの有効化
```bash
# systemdの再読み込み
sudo systemctl daemon-reload

# サービスの有効化
sudo systemctl enable xray

# サービスの起動
sudo systemctl start xray

# 状態確認
sudo systemctl status xray

# エラーログの確認
sudo journalctl -u xray -n 20 --no-pager
```

## 必要なパッケージのインストール

**SSH接続したEC2内で実行**：
```bash
# システムを更新
sudo yum update -y

# 必要なパッケージをインストール
sudo yum install -y git nginx php php-fpm php-mbstring php-xml php-pdo php-pgsql php-zip php-curl php-gd php-intl php-bcmath composer

# PostgreSQLクライアントをインストール
sudo yum install -y postgresql15

# サービスを有効化・開始
sudo systemctl enable nginx php-fpm
sudo systemctl start nginx php-fpm
```

## アプリケーションのインストール

```bash
# ディレクトリ作成
sudo mkdir -p /var/www/html
cd /var/www/html

# リポジトリクローン
sudo git clone https://github.com/shimamorieiki/laravel12-otel-ec2-xray.git

# 権限回りの修正
git config --global --add safe.directory /var/www/laravel12-otel-ec2-xray

# 所有権設定
sudo chown -R nginx:nginx /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 755 /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/bootstrap/cache

# 依存関係をインストール
composer install --no-dev --optimize-autoloader

# APP_KEYを生成
sudo php artisan key:generate

# キャッシュをクリア
sudo php artisan config:cache
sudo php artisan route:cache
sudo php artisan view:cache

# データベースマイグレーション
sudo php artisan migrate
```

## nginxの設定

```bash
# Laravelアプリケーション用のNginx設定
sudo tee /etc/nginx/conf.d/laravel.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/html/laravel12-otel-ec2-xray/public;

    index index.php;

    # ログファイルの設定
    access_log /var/log/nginx/laravel_access.log;
    error_log /var/log/nginx/laravel_error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_param HTTP_PROXY "";
        
        # タイムアウト設定
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 60s;
        fastcgi_read_timeout 60s;
    }

    location ~ /\.ht {
        deny all;
    }

    # セキュリティヘッダー
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # サーバー情報の非表示
    server_tokens off;
}
EOF
```

## nginxサービス起動
```bash
# systemdの設定を再読み込み
sudo systemctl daemon-reload

# サービスの有効化と起動
sudo systemctl enable --now nginx

sudo systemctl start nginx

sudo systemctl status nginx
```


## php-fpmサービス起動
```bash
# PHP-FPMをnginxユーザーで実行するよう設定
sudo sed -i 's/^user = apache/user = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^listen.owner = apache/listen.owner = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^listen.group = apache/listen.group = nginx/' /etc/php-fpm.d/www.conf

# systemdの設定を再読み込み
sudo systemctl daemon-reload

# サービスの有効化と起動
sudo systemctl restart php-fpm
```

cloud watch agentのログを見る
```bash
sudo tail -30 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

作成したファイルを読む権限
```bash
sudo chmod 644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo chown root:root /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```
