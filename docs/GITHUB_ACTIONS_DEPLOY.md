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

## 実際のデプロイ手順（ステップバイステップ）

### Phase 1: 情報収集

#### 1. EC2情報の確認

**SSH接続したEC2内で実行**：
```bash
# パブリックIPアドレス
curl http://checkip.amazonaws.com/

# システム情報
whoami
pwd
cat /etc/os-release
```

#### 2. RDS情報の確認

**RDSコンソールで確認**：
- エンドポイント：`laravel-otel-db.xxxxxxxxx.ap-northeast-1.rds.amazonaws.com`
- ポート：`5432`
- データベース名：`laravel`
- ユーザー名：`postgres`
- パスワード：作成時に設定したパスワード

#### 3. SSH キーペアの確認

**PowerShellで実行**：
```powershell
# プライベートキーの内容を表示
Get-Content "your-key-file.pem"
```

### Phase 2: EC2の初期設定

#### 1. 基本パッケージのインストール

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

#### 2. アプリケーションディレクトリの作成

```bash
# アプリケーションディレクトリを作成
sudo mkdir -p /var/www/html/laravel-app
sudo chown ec2-user:ec2-user /var/www/html/laravel-app

# 初回のgit clone
cd /var/www/html/laravel-app
git clone https://github.com/your-username/laravel12-otel-ec2-xray.git .
```

#### 3. Nginxの設定

```bash
# Nginx設定ファイルを作成
sudo nano /etc/nginx/conf.d/laravel.conf
```

**設定ファイル内容**：
```nginx
server {
    listen 80;
    server_name your-ec2-public-ip;
    root /var/www/html/laravel-app/public;

    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
```

```bash
# Nginxを再起動
sudo systemctl restart nginx
```

### Phase 3: Laravel設定

#### 1. 環境変数ファイルの作成

```bash
# .envファイルを作成
cd /var/www/html/laravel-app
cp .env.example .env
nano .env
```

**`.env`ファイル内容**：
```env
APP_NAME=Laravel
APP_ENV=production
APP_KEY=base64:your-app-key-here
APP_DEBUG=false
APP_URL=http://your-ec2-public-ip

DB_CONNECTION=pgsql
DB_HOST=your-rds-endpoint
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=postgres
DB_PASSWORD=your-rds-password

# OpenTelemetry設定
OTEL_SERVICE_NAME=laravel-app
OTEL_RESOURCE_ATTRIBUTES=service.name=laravel-app,service.version=1.0.0
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
```

#### 2. Laravel初期設定

```bash
# 依存関係をインストール
composer install --no-dev --optimize-autoloader

# APP_KEYを生成
php artisan key:generate

# 生成されたAPP_KEYを確認（GitHub Secretsで使用）
php artisan key:generate --show

# キャッシュをクリア
php artisan config:cache
php artisan route:cache
php artisan view:cache

# データベースマイグレーション
php artisan migrate

# 権限設定
sudo chown -R ec2-user:nginx /var/www/html/laravel-app
sudo chmod -R 755 /var/www/html/laravel-app
sudo chmod -R 775 /var/www/html/laravel-app/storage
sudo chmod -R 775 /var/www/html/laravel-app/bootstrap/cache
```

### Phase 4: GitHub Secretsの設定

#### 1. GitHub リポジトリでSecrets設定

**設定場所**：
```
GitHub リポジトリ → Settings → Secrets and variables → Actions → New repository secret
```

#### 2. 設定する値

```
EC2_HOST=your-ec2-public-ip
EC2_USERNAME=ec2-user
EC2_PRIVATE_KEY=your-private-key-content
DB_HOST=your-rds-endpoint
DB_PASSWORD=your-rds-password
APP_KEY=your-generated-app-key
```

**実際の値の例**：
```
EC2_HOST=54.168.131.150
EC2_USERNAME=ec2-user
EC2_PRIVATE_KEY=-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----
DB_HOST=laravel-otel-db.xxxxxxxxx.ap-northeast-1.rds.amazonaws.com
DB_PASSWORD=your-secure-password
APP_KEY=base64:abcdefghijklmnopqrstuvwxyz123456789
```

### Phase 5: GitHub Actions ワークフロー作成

#### 1. ワークフローファイルを作成

**ローカルで`.github/workflows/deploy.yml`を作成**：
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
          php artisan config:cache
          php artisan route:cache
          php artisan view:cache
          php artisan migrate --force
          sudo systemctl restart nginx
          sudo systemctl restart php-fpm
```

#### 2. ワークフローファイルのコミット

```bash
# ローカルで実行
git add .github/workflows/deploy.yml
git commit -m "Add GitHub Actions deploy workflow"
git push origin main
```

### Phase 6: デプロイテスト

#### 1. GitHub Actionsの実行確認

1. **GitHubリポジトリ**の「Actions」タブにアクセス
2. **ワークフローの実行状況**を確認
3. **エラーがあれば**ログを確認して修正

#### 2. デプロイ結果の確認

```bash
# ブラウザでアクセス
http://your-ec2-public-ip
```

**期待される結果**：
- Laravelのウェルカムページが表示される
- アプリケーションが正常に動作する

### Phase 7: 動作確認

#### 1. アプリケーションの動作確認

```bash
# EC2内でアプリケーションの状態を確認
cd /var/www/html/laravel-app
php artisan route:list
php artisan config:show
```

#### 2. データベース接続の確認

```bash
# データベース接続テスト
php artisan migrate:status
```

#### 3. ログの確認

```bash
# Laravel ログ
tail -f /var/www/html/laravel-app/storage/logs/laravel.log

# Nginx ログ
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## 完了チェックリスト

### 情報収集
- [ ] EC2のパブリックIPアドレス
- [ ] RDSエンドポイント
- [ ] プライベートキー
- [ ] データベースパスワード
- [ ] Laravel APP_KEY

### EC2設定
- [ ] 基本パッケージのインストール
- [ ] Nginxの設定
- [ ] アプリケーションディレクトリの作成
- [ ] Laravel初期設定
- [ ] データベース接続確認

### GitHub設定
- [ ] GitHub Secrets設定
- [ ] ワークフローファイル作成
- [ ] 初回デプロイ実行

### 動作確認
- [ ] GitHub Actions実行成功
- [ ] アプリケーションアクセス確認
- [ ] データベース接続確認

## 次のステップ

1. [AWS_RESOURCES_SETUP.md](./AWS_RESOURCES_SETUP.md) - AWSリソースのセットアップ
2. [EC2_SETUP.md](./EC2_SETUP.md) - EC2インスタンスの初期設定
3. このドキュメントの手順に従ってデプロイを実行

---

**注意**: 本番環境では、セキュリティ要件に応じて追加の設定が必要になる場合があります。 


cat >> ~/.ssh/authorized_keys << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCi6t2+gyopoPhDGp+9VgC0jzctGRc1bWYbWYtLTYtZ+WQfPUCMlMAV1bH7cTHn5kKcoukojuzUGbD/rL5wir/0r9I0rhPkJuFLmW7rJFntJDIvmoBR8qNIZEVjW+RaK+T+D5Mp/4O6RyDsyXzNsAbFgwzZcSfgNqDiWUcB2wvEihAEHMiJiYwECxnawkQ70bmXqo7+wzk7FkjpKaY2hmOljVgcY9G0BmQofesEj9PV5Zmtf7Rbwgbc0eMgz2O6y6HjByRKNBvCo54zTgzxliaxI7Xq/LPBJ+DfQ2yoXf72mbq7qQqgyOebTCI32POd0UWoUBNwBQ3XmiP14jKtPean
EOF
