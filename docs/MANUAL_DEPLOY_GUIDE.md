# 手動デプロイガイド

このドキュメントでは、SSH接続を使用してEC2インスタンスに手動でLaravelアプリケーションをデプロイする手順を説明します。

## 📋 前提条件

### 1. EC2インスタンス
- Amazon Linux 2023
- SSH接続が可能
- 基本パッケージがインストール済み（PHP、Nginx、Composer等）

### 2. ローカル環境
- SSH秘密鍵（.pemファイル）
- EC2のパブリックIPアドレス

### 3. セキュリティグループ設定
```
Type: SSH
Protocol: TCP
Port: 22
Source: あなたのIP/32  # 自分のIPのみ許可
```

## 🚀 デプロイ手順

### ステップ1: EC2への接続

```bash
# SSH接続
ssh -i your-key.pem ec2-user@your-ec2-ip
```

### ステップ2: 初回セットアップ（初回のみ）

```bash
# アプリケーションディレクトリが存在するか確認
if [ ! -d "/var/www/laravel12-otel-ec2-xray" ]; then
    echo "🔧 初回セットアップを実行します..."
    
    # ディレクトリ作成
    sudo mkdir -p /var/www
    cd /var/www
    
    # リポジトリクローン
    sudo git clone https://github.com/your-username/laravel12-otel-ec2-xray.git
    
    # 所有権設定
    sudo chown -R nginx:nginx /var/www/html/laravel12-otel-ec2-xray
    sudo chmod -R 755 /var/www/html/laravel12-otel-ec2-xray
    sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/storage
    sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/bootstrap/cache
    
    echo "✅ 初回セットアップ完了"
else
    echo "📁 アプリケーションディレクトリは既に存在します"
fi
```

### ステップ3: アプリケーションディレクトリに移動

```bash
cd /var/www/laravel12-otel-ec2-xray
```

### ステップ4: 最新コードの取得

```bash
# Git pullで最新コードを取得
echo "📥 最新コードを取得中..."
sudo -u nginx git pull origin main
```

### ステップ5: Composer依存関係の更新

```bash
# Composer依存関係のインストール
echo "📦 Composer依存関係をインストール中..."
sudo -u nginx composer install --no-dev --optimize-autoloader --no-interaction
```

### ステップ6: 環境設定ファイルの更新

```bash
# .envファイルの作成/更新
echo "⚙️  環境設定ファイルを更新中..."

# 本番環境用の.envファイルを作成
sudo -u nginx tee .env > /dev/null <<EOF
APP_NAME=Laravel
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://your-ec2-ip

LOG_CHANNEL=stack
LOG_LEVEL=info

DB_CONNECTION=pgsql
DB_HOST=your-rds-endpoint
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=postgres
DB_PASSWORD=your-db-password

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=database
SESSION_LIFETIME=120

# OpenTelemetry設定
OTEL_SERVICE_NAME=laravel-app
OTEL_SERVICE_VERSION=1.0.0
OTEL_ENVIRONMENT=production
OTEL_RESOURCE_ATTRIBUTES=service.name=laravel-app,service.version=1.0.0,deployment.environment=production
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
OTEL_LOGS_ENABLED=true

# X-Ray設定
OTEL_XRAY_ENABLED=true
OTEL_XRAY_DAEMON_ADDRESS=127.0.0.1:2000
OTEL_EXPORTERS=otlp,xray
EOF

# 実際の値に置換
sudo -u nginx sed -i "s/your-ec2-ip/$(curl -s http://checkip.amazonaws.com/)/g" .env
sudo -u nginx sed -i "s/your-rds-endpoint/YOUR_ACTUAL_RDS_ENDPOINT/g" .env
sudo -u nginx sed -i "s/your-db-password/YOUR_ACTUAL_DB_PASSWORD/g" .env
```

### ステップ7: APP_KEYの生成（初回のみ）

```bash
# APP_KEYが空の場合は生成
if grep -q "APP_KEY=$" .env; then
    echo "🔑 APP_KEYを生成中..."
    sudo -u nginx php artisan key:generate
    echo "✅ APP_KEY生成完了"
else
    echo "🔑 APP_KEYは既に設定されています"
fi
```

### ステップ8: Laravel設定の更新

```bash
echo "🔧 Laravel設定を更新中..."

# キャッシュのクリアと生成
sudo -u nginx php artisan config:cache
sudo -u nginx php artisan route:cache
sudo -u nginx php artisan view:cache
```

### ステップ9: データベースマイグレーション

```bash
echo "📊 データベースマイグレーションを実行中..."
sudo -u nginx php artisan migrate --force
```

### ステップ10: 権限設定

```bash
echo "🔒 ファイル権限を設定中..."

# 所有権と権限の再設定
sudo chown -R nginx:nginx /var/www/laravel12-otel-ec2-xray
sudo chmod -R 755 /var/www/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/bootstrap/cache
```

### ステップ11: OpenTelemetry Collector設定の更新

```bash
echo "📡 OpenTelemetry Collector設定を更新中..."

# 設定ファイルのコピー
if [ -f "/var/www/html/laravel12-otel-ec2-xray/docker/otel-collector/otel-collector-config.ec2.yaml" ]; then
    sudo cp /var/www/html/laravel12-otel-ec2-xray/docker/otel-collector/otel-collector-config.ec2.yaml /etc/otel-collector/config.yaml
    echo "✅ OpenTelemetry Collector設定更新完了"
else
    echo "⚠️  OpenTelemetry Collector設定ファイルが見つかりません"
fi
```

### ステップ12: サービスの再起動

```bash
echo "🔄 サービスを再起動中..."

# 各サービスの再起動
sudo systemctl restart php-fpm
sudo systemctl restart nginx
sudo systemctl restart otel-collector || echo "⚠️  OTel Collector再起動失敗"
sudo systemctl restart xray || echo "⚠️  X-Ray再起動失敗"

echo "✅ サービス再起動完了"
```

### ステップ13: サービス状態の確認

```bash
echo "🔍 サービス状態を確認中..."

# 各サービスの状態確認
echo "=== PHP-FPM ==="
sudo systemctl status php-fpm --no-pager -l

echo "=== Nginx ==="
sudo systemctl status nginx --no-pager -l

echo "=== OpenTelemetry Collector ==="
sudo systemctl status otel-collector --no-pager -l || echo "OTel Collector未起動"

echo "=== X-Ray Daemon ==="
sudo systemctl status xray --no-pager -l || echo "X-Ray未起動"
```

### ステップ14: 動作確認

```bash
echo "🏥 ヘルスチェックを実行中..."

# ローカルでのヘルスチェック
curl -f http://localhost/ && echo "✅ ローカルヘルスチェック成功" || echo "❌ ローカルヘルスチェック失敗"

# 外部からのヘルスチェック
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com/)
echo "🌐 外部アクセス確認: http://$PUBLIC_IP"
```

## 📝 ワンライナーデプロイスクリプト

上記の手順をワンライナーで実行する場合：

```bash
# EC2接続後に実行
cd /var/www/laravel12-otel-ec2-xray && \
sudo -u nginx git pull origin main && \
sudo -u nginx composer install --no-dev --optimize-autoloader --no-interaction && \
sudo -u nginx php artisan config:cache && \
sudo -u nginx php artisan route:cache && \
sudo -u nginx php artisan view:cache && \
sudo -u nginx php artisan migrate --force && \
sudo systemctl restart php-fpm nginx && \
echo "🚀 デプロイ完了!"
```

## 🔧 トラブルシューティング

### よくある問題と解決方法

#### 1. 権限エラー
```bash
sudo chown -R nginx:nginx /var/www/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/bootstrap/cache
```

#### 2. Composer依存関係エラー
```bash
sudo -u nginx composer clear-cache
sudo -u nginx composer install --no-dev --optimize-autoloader
```

#### 3. データベース接続エラー
```bash
# データベース接続テスト
sudo -u nginx php artisan migrate:status
```

#### 4. Nginxの設定確認
```bash
sudo nginx -t
sudo systemctl reload nginx
```

#### 5. ログの確認
```bash
# Laravel ログ
sudo tail -f /var/www/laravel12-otel-ec2-xray/storage/logs/laravel.log

# Nginx エラーログ
sudo tail -f /var/log/nginx/error.log

# PHP-FPM ログ
sudo journalctl -u php-fpm -f
```

## 📋 チェックリスト

デプロイ完了後の確認項目：

- [ ] アプリケーションが正常に表示される
- [ ] データベース接続が正常
- [ ] PHP-FPM、Nginxが起動中
- [ ] OpenTelemetry Collectorが起動中（オプション）
- [ ] X-Ray Daemonが起動中（オプション）
- [ ] ログにエラーがない

## 🔄 定期デプロイ

2回目以降のデプロイでは、以下の簡略化された手順を使用：

```bash
# 1. SSH接続
ssh -i your-key.pem ec2-user@your-ec2-ip

# 2. 簡単デプロイ
cd /var/www/laravel12-otel-ec2-xray
sudo -u nginx git pull origin main
sudo -u nginx composer install --no-dev --optimize-autoloader --no-interaction
sudo -u nginx php artisan migrate --force
sudo -u nginx php artisan config:cache
sudo systemctl restart php-fpm nginx
echo "🚀 デプロイ完了!"
```

これで手動デプロイが簡単にできるようになります！ 
