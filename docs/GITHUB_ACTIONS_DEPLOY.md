# GitHub Actions デプロイガイド

このドキュメントでは、GitHub Actionsを使用してEC2インスタンスにLaravelアプリケーションをデプロイする際に必要な情報と手順を説明します。

## 必須情報一覧

### 1. EC2インスタンス情報

| 項目 | 値 | 取得方法 |
|------|-----|----------|
| EC2_HOST | EC2のパブリックIPアドレス | EC2コンソール または `curl http://checkip.amazonaws.com/` |
| EC2_USERNAME | `ec2-user` | Amazon Linux 2023の場合 |
| EC2_PORT | `22` | SSH接続ポート |

### 2. SSH接続情報

| 項目 | 値 | 取得方法 |
|------|-----|----------|
| EC2_PRIVATE_KEY | プライベートキー（PEM形式） | EC2作成時にダウンロードしたキーペア |

**プライベートキーの形式例**：
```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
...
-----END RSA PRIVATE KEY-----
```

### 3. データベース接続情報

| 項目 | 値 | 取得方法 |
|------|-----|----------|
| DB_HOST | RDSエンドポイント | RDSコンソール |
| DB_DATABASE | `laravel` | 作成時に指定したデータベース名 |
| DB_USERNAME | `postgres` | 作成時に指定したユーザー名 |
| DB_PASSWORD | RDSパスワード | 作成時に設定したパスワード |

**RDSエンドポイント例**：
```
laravel-otel-db.xxxxxxxxx.ap-northeast-1.rds.amazonaws.com
```

### 4. Laravel設定情報

| 項目 | 値 | 取得方法 |
|------|-----|----------|
| APP_KEY | Laravel APP_KEY | `php artisan key:generate --show` |
| APP_ENV | `production` | 本番環境用 |
| APP_DEBUG | `false` | 本番環境用 |
| APP_URL | `http://<EC2のパブリックIP>` | EC2のパブリックIPアドレス |

## GitHub Secrets設定

### 1. リポジトリ設定画面でのSecrets追加

**設定場所**：
```
GitHub リポジトリ → Settings → Secrets and variables → Actions → New repository secret
```

**必要なSecrets**：
```
EC2_HOST=<EC2のパブリックIPアドレス>
EC2_USERNAME=ec2-user
EC2_PRIVATE_KEY=<プライベートキーの内容>
DB_HOST=<RDSエンドポイント>
DB_PASSWORD=<RDSパスワード>
APP_KEY=<Laravel APP_KEY>
```

### 2. Secretsの設定例

```yaml
# GitHub Secrets に設定する値
EC2_HOST: 54.123.456.789
EC2_USERNAME: ec2-user
EC2_PRIVATE_KEY: |
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpAIBAAKCAQEA...
  -----END RSA PRIVATE KEY-----
DB_HOST: laravel-otel-db.xxxxxxxxx.ap-northeast-1.rds.amazonaws.com
DB_PASSWORD: your-secure-password
APP_KEY: base64:abcdefghijklmnopqrstuvwxyz123456789
```

## GitHub Actions ワークフロー

### 1. ワークフローファイルの作成

**ファイル場所**：`.github/workflows/deploy.yml`

```yaml
name: Deploy to EC2

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Deploy to EC2
      uses: appleboy/ssh-action@v1.0.0
      with:
        host: ${{ secrets.EC2_HOST }}
        username: ${{ secrets.EC2_USERNAME }}
        key: ${{ secrets.EC2_PRIVATE_KEY }}
        port: 22
        script: |
          cd /var/www/html/laravel-app
          git pull origin main
          composer install --no-dev --optimize-autoloader
          cp .env.example .env
          php artisan key:generate
          php artisan config:cache
          php artisan route:cache
          php artisan view:cache
          php artisan migrate --force
          sudo systemctl restart nginx
          sudo systemctl restart php-fpm
```

### 2. 環境変数の設定

**EC2上の`.env`ファイル**：
```bash
# SSH接続してEC2で実行
sudo nano /var/www/html/laravel-app/.env
```

**`.env`ファイルの内容**：
```env
APP_NAME=Laravel
APP_ENV=production
APP_KEY=base64:your-app-key
APP_DEBUG=false
APP_URL=http://your-ec2-ip

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

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
SESSION_DRIVER=file
SESSION_LIFETIME=120

MEMCACHED_HOST=127.0.0.1

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=ap-northeast-1
AWS_BUCKET=

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_HOST=
PUSHER_PORT=443
PUSHER_SCHEME=https
PUSHER_APP_CLUSTER=mt1

VITE_PUSHER_APP_KEY="${PUSHER_APP_KEY}"
VITE_PUSHER_HOST="${PUSHER_HOST}"
VITE_PUSHER_PORT="${PUSHER_PORT}"
VITE_PUSHER_SCHEME="${PUSHER_SCHEME}"
VITE_PUSHER_APP_CLUSTER="${PUSHER_APP_CLUSTER}"

# OpenTelemetry設定
OTEL_SERVICE_NAME=laravel-app
OTEL_RESOURCE_ATTRIBUTES=service.name=laravel-app,service.version=1.0.0
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_HEADERS=
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
```

## セキュリティ考慮事項

### 1. SSH接続の制限

**セキュリティグループの設定**：
```
タイプ: SSH
ポート: 22
ソース: GitHub Actions のIPレンジ
または: 特定のIPアドレス
```

### 2. プライベートキーの管理

**注意点**：
- プライベートキーはGitHub Secretsで暗号化して保存
- キーペアの権限を適切に設定（600）
- 定期的なキーローテーションを実施

### 3. 環境変数の管理

**ベストプラクティス**：
- 機密情報はGitHub Secretsで管理
- EC2の`.env`ファイルで設定
- `.env`ファイルは`.gitignore`に追加

## デプロイ前の準備

### 1. EC2の初期設定

```bash
# SSH接続してEC2で実行
sudo yum update -y
sudo yum install -y git nginx php php-fpm composer

# アプリケーションディレクトリの作成
sudo mkdir -p /var/www/html/laravel-app
sudo chown ec2-user:ec2-user /var/www/html/laravel-app

# 初回のgit clone
cd /var/www/html/laravel-app
git clone https://github.com/your-username/your-repo.git .
```

### 2. データベースの初期設定

```bash
# EC2からRDSへの接続確認
sudo yum install -y postgresql15
psql -h your-rds-endpoint -U postgres -d laravel

# 初回のマイグレーション
php artisan migrate
```

### 3. Webサーバーの設定

**Nginx設定**：
```bash
sudo nano /etc/nginx/conf.d/laravel.conf
```

**設定ファイル内容**：
```nginx
server {
    listen 80;
    server_name your-ec2-ip;
    root /var/www/html/laravel-app/public;

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
}
```

## デプロイ手順

### 1. 必要情報の収集

- [ ] EC2のパブリックIPアドレス
- [ ] RDSエンドポイント
- [ ] プライベートキー
- [ ] データベースパスワード
- [ ] Laravel APP_KEY

### 2. GitHub Secretsの設定

- [ ] EC2_HOST
- [ ] EC2_USERNAME
- [ ] EC2_PRIVATE_KEY
- [ ] DB_HOST
- [ ] DB_PASSWORD
- [ ] APP_KEY

### 3. ワークフローファイルの作成

- [ ] `.github/workflows/deploy.yml`を作成
- [ ] デプロイスクリプトを設定

### 4. 初回デプロイ

- [ ] `main`ブランチにプッシュ
- [ ] GitHub Actionsの実行確認
- [ ] デプロイ結果の確認

## トラブルシューティング

### よくある問題と解決方法

1. **SSH接続エラー**
   - セキュリティグループの設定確認
   - プライベートキーの形式確認

2. **データベース接続エラー**
   - RDSエンドポイントの確認
   - セキュリティグループの確認

3. **Laravel エラー**
   - `.env`ファイルの設定確認
   - APP_KEYの確認

4. **権限エラー**
   - ファイル権限の確認
   - ディレクトリ所有者の確認

## 次のステップ

1. [AWS_RESOURCES_SETUP.md](./AWS_RESOURCES_SETUP.md) - AWSリソースのセットアップ
2. [EC2_SETUP.md](./EC2_SETUP.md) - EC2インスタンスの初期設定
3. このドキュメントの手順に従ってデプロイを実行

---

**注意**: 本番環境では、セキュリティ要件に応じて追加の設定が必要になる場合があります。 
