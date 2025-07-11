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
sudo nano /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
# amazon-cloudwatch-agent.jsonの中身をコピー
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
不要な説がある(amazon-cloudwatch-agentがこの機能を持っているのならこのdaemonが不要なはず)

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
