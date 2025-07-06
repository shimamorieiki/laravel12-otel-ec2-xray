# EC2 Setup Guide for Laravel + OpenTelemetry + AWS X-Ray

このドキュメントでは、EC2インスタンス上でLaravelアプリケーションをOpenTelemetryとAWS X-Rayと連携して動作させるための手順を説明します。

## 前提条件

以下のAWSリソースが必要です（ユーザーが作成）：

1. **EC2インスタンス**
   - Amazon Linux 2023
   - t3.medium以上を推奨
   - セキュリティグループ設定：
     - SSH (22)
     - HTTP (80)
     - HTTPS (443)

2. **IAMロール**
   - EC2インスタンスにアタッチ
   - 必要なポリシー：
     - `AWSXRayDaemonWriteAccess`
     - `CloudWatchAgentServerPolicy`

3. **RDS PostgreSQL**
   - PostgreSQL 15
   - セキュリティグループでEC2からの接続を許可

## EC2セットアップ手順

### 1. システムの更新と基本ツールのインストール

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
  unzip \
  curl
```

### 2. Composerのインストール

```bash
# Composerのダウンロードとインストール
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer
```

### 3. AWS X-Ray Daemonのセットアップ

```bash
# X-Ray Daemonのダウンロード
curl https://s3.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-linux-3.x.zip -o xray.zip
unzip xray.zip -d /opt/xray
chmod +x /opt/xray/xray

# Systemdサービスの作成
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

# X-Ray Daemonの起動と自動起動設定
sudo systemctl daemon-reload
sudo systemctl enable xray
sudo systemctl start xray
```

### 4. アプリケーションのデプロイ

```bash
# アプリケーションディレクトリの作成
sudo mkdir -p /var/www
cd /var/www

# リポジトリのクローン
sudo git clone https://github.com/yourusername/laravel12-otel-ec2-xray.git
cd laravel12-otel-ec2-xray

# 所有権の設定
sudo chown -R nginx:nginx /var/www/laravel12-otel-ec2-xray

# Composerの依存関係インストール
sudo -u nginx composer install --no-dev --optimize-autoloader

# 環境設定ファイルの作成
sudo -u nginx cp .env.example .env
```

### 5. 環境変数の設定

`.env`ファイルを編集：

```bash
sudo -u nginx nano .env
```

以下の設定を更新：

```env
APP_NAME=Laravel
APP_ENV=production
APP_KEY=base64:YOUR_GENERATED_KEY_HERE
APP_DEBUG=false
APP_URL=http://your-ec2-public-ip

DB_CONNECTION=pgsql
DB_HOST=your-rds-endpoint.amazonaws.com
DB_PORT=5432
DB_DATABASE=your_database_name
DB_USERNAME=your_username
DB_PASSWORD=your_password

# OpenTelemetry設定（X-Ray直接送信）
OTEL_SERVICE_NAME=laravel-app
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_RESOURCE_ATTRIBUTES="service.name=laravel-app,deployment.environment=production"
OTEL_XRAY_ENABLED=true
OTEL_XRAY_DAEMON_ADDRESS=127.0.0.1:2000
```

### 6. Laravel初期設定

```bash
# アプリケーションキーの生成
sudo -u nginx php artisan key:generate

# データベースマイグレーション
sudo -u nginx php artisan migrate --force

# キャッシュのクリアと最適化
sudo -u nginx php artisan config:cache
sudo -u nginx php artisan route:cache
sudo -u nginx php artisan view:cache
```

### 7. PHP-FPMの設定

```bash
# PHP-FPM設定ファイルの編集
sudo nano /etc/php-fpm.d/www.conf
```

以下の設定を確認・更新：

```ini
user = nginx
group = nginx
listen = /var/run/php-fpm/www.sock
listen.owner = nginx
listen.group = nginx
listen.mode = 0660
```

### 8. Nginxの設定

```bash
# Nginx設定ファイルの作成
sudo tee /etc/nginx/conf.d/laravel.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/laravel12-otel-ec2-xray/public;

    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

# デフォルト設定の無効化
sudo mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled

# Nginx設定のテスト
sudo nginx -t
```

### 9. サービスの起動

```bash
# PHP-FPMの起動
sudo systemctl enable php-fpm
sudo systemctl start php-fpm

# Nginxの起動
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 10. ストレージディレクトリの権限設定

```bash
# ストレージディレクトリの権限設定
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/bootstrap/cache
```

## OpenTelemetry Collector for X-Rayの設定

EC2でX-Rayに直接送信するための設定：

```bash
# OpenTelemetry Collectorの設定ファイル作成
sudo tee /etc/otel-collector-config.yaml > /dev/null <<'EOF'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317
      http:
        endpoint: 127.0.0.1:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 50
  
  resource:
    attributes:
    - key: cloud.provider
      value: aws
      action: insert
    - key: cloud.platform
      value: aws_ec2
      action: insert

exporters:
  awsxray:
    region: ap-northeast-1
    no_verify_ssl: false
    local_mode: true

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [awsxray]
EOF
```

### OpenTelemetry Collectorのインストールと起動

```bash
# OpenTelemetry Collectorのダウンロード
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.96.0/otelcol-contrib_0.96.0_linux_amd64.tar.gz
tar -xvf otelcol-contrib_0.96.0_linux_amd64.tar.gz
sudo mv otelcol-contrib /usr/local/bin/

# Systemdサービスの作成
sudo tee /etc/systemd/system/otel-collector.service > /dev/null <<EOF
[Unit]
Description=OpenTelemetry Collector
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/otelcol-contrib --config=/etc/otel-collector-config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# サービスの起動
sudo systemctl daemon-reload
sudo systemctl enable otel-collector
sudo systemctl start otel-collector
```

## 動作確認

### 1. アプリケーションの動作確認

```bash
# ヘルスチェック
curl http://localhost/up

# APIエンドポイントのテスト
curl http://localhost/api/items
```

### 2. OpenTelemetryの動作確認

```bash
# テストコマンドの実行
cd /var/www/laravel12-otel-ec2-xray
sudo -u nginx php artisan otel:test
```

### 3. X-Rayでのトレース確認

1. AWS X-Rayコンソールにアクセス
2. サービスマップで`laravel-app`を確認
3. トレースが正しく送信されていることを確認

## トラブルシューティング

### ログの確認

```bash
# X-Ray Daemonのログ
sudo journalctl -u xray -f

# OpenTelemetry Collectorのログ
sudo journalctl -u otel-collector -f

# PHP-FPMのログ
sudo tail -f /var/log/php-fpm/error.log

# Nginxのログ
sudo tail -f /var/log/nginx/error.log

# Laravelのログ
sudo tail -f /var/www/laravel12-otel-ec2-xray/storage/logs/laravel.log
```

### よくある問題と解決方法

1. **トレースが表示されない**
   - X-Ray DaemonとOpenTelemetry Collectorが正常に動作しているか確認
   - IAMロールの権限を確認

2. **データベース接続エラー**
   - RDSのセキュリティグループ設定を確認
   - `.env`ファイルの接続情報を確認

3. **パーミッションエラー**
   - ストレージディレクトリの権限を再設定
   - PHP-FPMのユーザー設定を確認

## メンテナンス

### アプリケーションの更新

```bash
cd /var/www/laravel12-otel-ec2-xray
sudo -u nginx git pull
sudo -u nginx composer install --no-dev --optimize-autoloader
sudo -u nginx php artisan migrate --force
sudo -u nginx php artisan config:cache
sudo -u nginx php artisan route:cache
sudo -u nginx php artisan view:cache
sudo systemctl restart php-fpm
```

### ログのローテーション

Laravelのログローテーションは自動的に行われますが、必要に応じて手動でクリアできます：

```bash
sudo -u nginx truncate -s 0 /var/www/laravel12-otel-ec2-xray/storage/logs/laravel.log
```