#!/bin/bash

# EC2 Setup Script for Laravel + OpenTelemetry + X-Ray
# This script should be run on a fresh Amazon Linux 2023 EC2 instance

set -e

echo "=== Starting EC2 Setup ==="

# システムのアップデート
echo "Updating system packages..."
sudo yum update -y

# 必要なパッケージのインストール
echo "Installing required packages..."
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

# Composerのインストール
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer

# Node.js と npm のインストール（必要に応じて）
echo "Installing Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# AWS X-Ray Daemon のセットアップ
echo "Setting up AWS X-Ray Daemon..."
wget https://s3.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-linux-3.x.zip
unzip aws-xray-daemon-linux-3.x.zip -d /tmp/xray
sudo mkdir -p /opt/xray
sudo mv /tmp/xray/xray /opt/xray/
sudo chmod +x /opt/xray/xray

# X-Ray Daemon のsystemdサービス作成
echo "Creating X-Ray Daemon systemd service..."
sudo tee /etc/systemd/system/xray.service > /dev/null <<EOF
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

# OpenTelemetry Collector のセットアップ
echo "Setting up OpenTelemetry Collector..."
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.129.0/otelcol-contrib_0.129.0_linux_amd64.tar.gz
tar -xzf otelcol-contrib_0.129.0_linux_amd64.tar.gz
sudo mv otelcol-contrib /usr/local/bin/
sudo chmod +x /usr/local/bin/otelcol-contrib

# OpenTelemetry Collector の設定ディレクトリ作成
sudo mkdir -p /etc/otel-collector

# OpenTelemetry Collector のsystemdサービス作成
echo "Creating OpenTelemetry Collector systemd service..."
sudo tee /etc/systemd/system/otel-collector.service > /dev/null <<EOF
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

# PHP-FPM の設定
echo "Configuring PHP-FPM..."
sudo sed -i 's/^user = apache/user = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^listen.owner = apache/listen.owner = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/^listen.group = apache/listen.group = nginx/' /etc/php-fpm.d/www.conf

# Nginx の設定
echo "Configuring Nginx..."
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
        fastcgi_param HTTP_PROXY "";
    }

    location ~ /\.ht {
        deny all;
    }

    # Hide nginx version
    server_tokens off;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
}
EOF

# アプリケーションディレクトリの作成
echo "Creating application directory..."
sudo mkdir -p /var/www
cd /var/www

# アプリケーションの初期セットアップ（Git クローン）
echo "Cloning application repository..."
sudo git clone https://github.com/yourusername/laravel12-otel-ec2-xray.git
cd laravel12-otel-ec2-xray

# 所有権の設定
echo "Setting permissions..."
sudo chown -R nginx:nginx /var/www/laravel12-otel-ec2-xray
sudo chmod -R 755 /var/www/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/bootstrap/cache

# Composer の依存関係インストール
echo "Installing Composer dependencies..."
sudo -u nginx composer install --no-dev --optimize-autoloader

# .env ファイルの初期セットアップ
echo "Setting up environment file..."
sudo -u nginx cp .env.example .env

# Laravel の初期セットアップ
echo "Running Laravel setup..."
sudo -u nginx php artisan key:generate

# systemd の設定を再読み込み
echo "Reloading systemd configuration..."
sudo systemctl daemon-reload

# サービスの有効化
echo "Enabling services..."
sudo systemctl enable nginx
sudo systemctl enable php-fpm
sudo systemctl enable xray
sudo systemctl enable otel-collector

# ファイアウォール設定（必要に応じて）
echo "Configuring firewall..."
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

echo "=== EC2 Setup Completed ==="
echo ""
echo "Next steps:"
echo "1. Update the Git repository URL in this script"
echo "2. Set up your GitHub repository secrets"
echo "3. Configure your .env file with database credentials"
echo "4. Run the GitHub Actions deployment workflow"
echo ""
echo "Services will start automatically after the first deployment." 
