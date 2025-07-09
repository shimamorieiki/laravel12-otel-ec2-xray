# EC2でOpenTelemetryを利用するための完全ガイド

## 目次
1. [概要](#概要)
2. [前提条件](#前提条件)
3. [システム構成](#システム構成)
4. [インストール手順](#インストール手順)
5. [設定方法](#設定方法)
6. [起動・動作確認](#起動動作確認)
7. [トラブルシューティング](#トラブルシューティング)
8. [監視・メンテナンス](#監視メンテナンス)

## 概要

このドキュメントでは、Amazon EC2インスタンス上でLaravel + OpenTelemetry + AWS X-Rayの監視環境を構築する手順を説明します。

### 構成要素
- **Laravel Application**: メインアプリケーション
- **OpenTelemetry Collector**: テレメトリデータの収集・処理
- **AWS X-Ray Daemon**: AWS X-Rayへのデータ送信
- **PostgreSQL**: データベース（RDS）
- **Nginx**: Webサーバー
- **PHP-FPM**: PHPプロセス管理

## 前提条件

### EC2インスタンス
- **OS**: Amazon Linux 2023
- **インスタンスタイプ**: t3.micro以上推奨
- **セキュリティグループ**: HTTP(80), HTTPS(443)を許可

### AWS権限
- EC2インスタンスロールまたはIAMユーザーに以下の権限が必要：
  - `xray:PutTraceSegments`
  - `xray:PutTelemetryRecords`
  - `xray:GetSamplingRules`
  - `xray:GetSamplingTargets`
  - `cloudwatch:PutMetricData`

### 外部リソース
- **RDS PostgreSQL**: データベースインスタンス
- **GitHub Repository**: ソースコード管理

## システム構成

```
┌─────────────────────────────────────────────────────────────┐
│                        EC2 Instance                         │
│                                                             │
│  ┌─────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │   Nginx     │    │   Laravel App   │    │   PHP-FPM   │ │
│  │   (Port 80) │ -> │                 │ -> │   (Socket)  │ │
│  └─────────────┘    └─────────────────┘    └─────────────┘ │
│                              │                              │
│                              ▼                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │           OpenTelemetry Collector                       │ │
│  │           (Port 4317: gRPC, 4318: HTTP)               │ │
│  └─────────────────────────────────────────────────────────┘ │
│                              │                              │
│                              ▼                              │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │   X-Ray Daemon  │    │   CloudWatch    │                │
│  │   (Port 2000)   │    │   Metrics       │                │
│  └─────────────────┘    └─────────────────┘                │
│                              │                              │
└──────────────────────────────┼──────────────────────────────┘
                               ▼
        ┌─────────────────────────────────────────┐
        │               AWS Services               │
        │  ┌─────────────┐    ┌─────────────────┐ │
        │  │   X-Ray     │    │   CloudWatch    │ │
        │  │   Traces    │    │   Metrics       │ │
        │  └─────────────┘    └─────────────────┘ │
        │                                         │
        │  ┌─────────────────────────────────────┐ │
        │  │         RDS PostgreSQL              │ │
        │  └─────────────────────────────────────┘ │
        └─────────────────────────────────────────┘
```

## インストール手順

### 1. システムのアップデート

```bash
# システムパッケージの更新
sudo yum update -y

# 必要なパッケージのインストール
sudo yum install -y \
    git \
    nginx \
    php8.3 \
    php8.3-cli \
    php8.3-fpm \
    php8.3-pgsql \
    php8.3-mbstring \
    php8.3-xml \
    php8.3-curl \
    php8.3-bcmath \
    php8.3-zip \
    php8.3-gd \
    php8.3-opcache \
    unzip \
    curl \
    wget \
    htop \
    tree
```

### 2. Composerのインストール

```bash
# Composerのダウンロードとインストール
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer
```

### 3. OpenTelemetry Collectorのインストール

```bash
# OpenTelemetry Collectorのダウンロード
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.129.1/otelcol-contrib_0.129.1_linux_amd64.tar.gz

# 解凍とインストール
tar -xzf otelcol-contrib_0.129.1_linux_amd64.tar.gz
sudo mv otelcol-contrib /usr/local/bin/
sudo chmod +x /usr/local/bin/otelcol-contrib

# 設定ディレクトリの作成
sudo mkdir -p /etc/otel-collector
```

### 4. AWS X-Ray Daemonのインストール

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

### 5. アプリケーションのデプロイ

```bash
# アプリケーションディレクトリの作成
sudo mkdir -p /var/www/html
cd /var/www/html

# Gitリポジトリのクローン
sudo git clone https://github.com/yourusername/laravel12-otel-ec2-xray.git
cd laravel12-otel-ec2-xray

# 所有権の設定
sudo chown -R nginx:nginx /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 755 /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/bootstrap/cache

# Composer依存関係のインストール
sudo -u nginx composer install --no-dev --optimize-autoloader
```

## 設定方法

### 1. OpenTelemetry Collectorの設定

```bash
sudo mkdir /etc/otel-collector/ 
# EC2用の設定ファイルをコピー
sudo cp /var/www/html/laravel12-otel-ec2-xray/docker/otel-collector/otel-collector-config.ec2.yaml /etc/otel-collector/config.yaml

# 設定ファイルの確認
sudo cat /etc/otel-collector/config.yaml
```

### 2. systemdサービスの作成

#### OpenTelemetry Collectorサービス

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

# 環境変数（必要に応じて設定）
Environment=AWS_DEFAULT_REGION=ap-northeast-1
# Environment=AWS_ACCESS_KEY_ID=your-access-key-id
# Environment=AWS_SECRET_ACCESS_KEY=your-secret-access-key

[Install]
WantedBy=multi-user.target
EOF
```

#### X-Ray Daemonサービス

```bash
sudo tee /etc/systemd/system/xray.service > /dev/null <<'EOF'
[Unit]
Description=AWS X-Ray Daemon
After=network.target

[Service]
Type=simple
ExecStart=/opt/xray/xray -o -n ap-northeast-1
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
```

### 3. Nginxの設定

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

### 4. PHP-FPMの設定

```bash
# PHP-FPMをnginxユーザーで実行するよう設定
sudo sed -i 's/^user = apache/user = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^listen.owner = apache/listen.owner = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^listen.group = apache/listen.group = nginx/' /etc/php-fpm.d/www.conf
```

### 5. 環境変数の設定

```bash
# .envファイルの作成
cd /var/www/html/laravel12-otel-ec2-xray
sudo -u nginx cp .env.example .env

# .envファイルの編集
sudo -u nginx nano .env
```

#### .envファイルの重要な設定

```env
# アプリケーション設定
APP_NAME=Laravel
APP_ENV=production
APP_KEY=base64:generated-key-here
APP_DEBUG=false
APP_URL=http://your-ec2-public-ip

# データベース設定
DB_CONNECTION=pgsql
DB_HOST=your-rds-endpoint
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=your-db-username
DB_PASSWORD=your-db-password

# OpenTelemetry設定
OTEL_SERVICE_NAME=laravel-app
OTEL_SERVICE_VERSION=1.0.0
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
OTEL_LOGS_ENABLED=true

# X-Ray設定
OTEL_XRAY_ENABLED=true
OTEL_XRAY_DAEMON_ADDRESS=127.0.0.1:2000
OTEL_XRAY_LOCAL_MODE=true

# AWS設定
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_DEFAULT_REGION=ap-northeast-1

# エクスポーター設定
OTEL_EXPORTERS=debug,awsxray
OTEL_ENVIRONMENT=production
```

### 6. IAM権限の設定

#### EC2インスタンスロールの作成

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
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
```

## 起動・動作確認

### 1. サービスの起動

```bash
# systemdの設定を再読み込み
sudo systemctl daemon-reload

# サービスの有効化と起動
sudo systemctl enable --now nginx
sudo systemctl enable --now php-fpm
sudo systemctl enable --now xray
sudo systemctl enable --now otel-collector
```

### 2. サービス状態の確認

```bash
# 全サービスの状態確認
sudo systemctl status nginx php-fpm xray otel-collector

# 個別サービスの詳細確認
sudo systemctl status otel-collector
sudo systemctl status xray
```

### 3. ポート確認

```bash
# 必要なポートが開いているか確認
sudo netstat -tlnp | grep -E '80|4317|4318|2000'

# プロセス確認
ps aux | grep -E 'nginx|php-fpm|otelcol|xray'
```

### 4. アプリケーションの初期化

```bash
cd /var/www/html/laravel12-otel-ec2-xray

# アプリケーションキーの生成
sudo -u nginx php artisan key:generate

# データベースマイグレーション
sudo -u nginx php artisan migrate

# 設定キャッシュのクリア
sudo -u nginx php artisan config:cache
sudo -u nginx php artisan route:cache
sudo -u nginx php artisan view:cache
```

### 5. ヘルスチェック

```bash
# OpenTelemetry Collectorのヘルスチェック
curl -f http://localhost:13133/health

# アプリケーションのヘルスチェック
curl -f http://localhost/

# X-Ray Daemonのログ確認
sudo journalctl -u xray --since "1 hour ago"
```

### 6. テスト実行

```bash
# OpenTelemetryテストコマンド
sudo -u nginx php artisan otel:test

# API テスト
curl -X GET http://localhost/api/items
curl -X POST http://localhost/api/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "Test Description"}'
```

## トラブルシューティング

### 1. OpenTelemetryが接続できない場合

#### 症状
```
OpenTelemetry: [error] Export failure [exception] Export retry limit exceeded
cURL error 7: Failed to connect to 127.0.0.1 port 4317
```

#### 解決方法
```bash
# 一時的にOpenTelemetryを無効化
OTEL_SDK_DISABLED=true php artisan migrate

# OpenTelemetry Collectorの起動確認
sudo systemctl status otel-collector
sudo journalctl -u otel-collector -f

# ポート確認
sudo netstat -tlnp | grep 4318

# サービスの再起動
sudo systemctl restart otel-collector
```

### 2. X-Ray Daemonが動作しない場合

#### 症状
```
X-Ray daemon connection failed
```

#### 解決方法
```bash
# X-Ray Daemonの状態確認
sudo systemctl status xray
sudo journalctl -u xray -f

# ポート確認
sudo netstat -tlnp | grep 2000

# 権限確認
aws sts get-caller-identity
aws xray get-sampling-rules

# サービスの再起動
sudo systemctl restart xray
```

### 3. Nginxの設定問題

#### 症状
```
502 Bad Gateway
```

#### 解決方法
```bash
# Nginxの設定テスト
sudo nginx -t

# PHP-FPMの確認
sudo systemctl status php-fpm

# ソケットファイルの確認
ls -la /var/run/php-fpm/www.sock

# ログの確認
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/php-fpm/www-error.log
```

### 4. データベース接続問題

#### 症状
```
SQLSTATE[08006] [7] could not connect to server
```

#### 解決方法
```bash
# データベース接続テスト
sudo -u nginx php artisan tinker
# DB::connection()->getPdo();

# 設定確認
sudo -u nginx php artisan config:show database.connections.pgsql

# RDSセキュリティグループの確認
# - EC2のセキュリティグループからポート5432への接続を許可
```

### 5. 権限問題

#### 症状
```
Permission denied
```

#### 解決方法
```bash
# ファイル所有権の修正
sudo chown -R nginx:nginx /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 755 /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/bootstrap/cache

# SELinuxの確認（必要に応じて）
sudo setsebool -P httpd_can_network_connect 1
```

## 監視・メンテナンス

### 1. ログ監視

```bash
# アプリケーションログ
sudo tail -f /var/www/html/laravel12-otel-ec2-xray/storage/logs/laravel.log

# Nginxログ
sudo tail -f /var/log/nginx/laravel_access.log
sudo tail -f /var/log/nginx/laravel_error.log

# OpenTelemetryログ
sudo journalctl -u otel-collector -f

# X-Rayログ
sudo journalctl -u xray -f
```

### 2. パフォーマンス監視

```bash
# システムリソース
htop
free -h
df -h

# プロセス監視
sudo systemctl status nginx php-fpm xray otel-collector
```

### 3. AWS X-Rayコンソールでの確認

1. AWS X-Rayコンソールにアクセス
2. 「Service map」でサービス間の関係を確認
3. 「Traces」でトレースの詳細を確認
4. 「Analytics」でパフォーマンス分析

**X-Rayコンソール URL**: https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map

### 4. 定期メンテナンス

```bash
# ログローテーション
sudo logrotate -f /etc/logrotate.d/nginx

# キャッシュクリア
sudo -u nginx php artisan cache:clear
sudo -u nginx php artisan config:cache
sudo -u nginx php artisan route:cache

# セキュリティアップデート
sudo yum update -y
```

### 5. バックアップ

```bash
# アプリケーションのバックアップ
sudo tar -czf /tmp/laravel-backup-$(date +%Y%m%d).tar.gz /var/www/html/laravel12-otel-ec2-xray

# データベースのバックアップ（RDSスナップショット推奨）
pg_dump -h your-rds-endpoint -U your-username -d laravel > /tmp/db-backup-$(date +%Y%m%d).sql
```

## 自動化スクリプト

### 起動スクリプト

```bash
# /home/ec2-user/start-services.sh
#!/bin/bash
sudo systemctl start nginx php-fpm xray otel-collector
echo "All services started successfully"
```

### 停止スクリプト

```bash
# /home/ec2-user/stop-services.sh
#!/bin/bash
sudo systemctl stop nginx php-fpm xray otel-collector
echo "All services stopped successfully"
```

### 状態確認スクリプト

```bash
# /home/ec2-user/check-status.sh
#!/bin/bash
echo "=== Service Status ==="
sudo systemctl status nginx php-fpm xray otel-collector --no-pager

echo -e "\n=== Port Status ==="
sudo netstat -tlnp | grep -E '80|4317|4318|2000'

echo -e "\n=== Health Check ==="
curl -s http://localhost:13133/health && echo "OpenTelemetry Collector: OK"
curl -s http://localhost/ > /dev/null && echo "Application: OK"
```

## まとめ

このガイドに従うことで、EC2上でLaravel + OpenTelemetry + AWS X-Rayの完全な監視環境を構築できます。

### 重要なポイント
1. **セキュリティ**: 必要最小限の権限のみを付与
2. **監視**: 定期的なログ確認とパフォーマンス監視
3. **バックアップ**: 定期的なデータバックアップ
4. **更新**: セキュリティアップデートの定期実施

### 次のステップ
- CI/CD パイプラインの構築
- Auto Scaling の設定
- SSL証明書の設定
- CloudWatch Alarmの設定
- 追加のセキュリティ対策

このドキュメントを参考に、安全で効率的な監視環境を構築してください。 
