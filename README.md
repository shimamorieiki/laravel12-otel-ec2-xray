# Laravel 12 + OpenTelemetry + AWS X-Ray

Laravel 12アプリケーションにOpenTelemetryを統合し、EC2上で動作させてAWS X-Rayでトレースを可視化するプロジェクトです。

## 🎯 プロジェクト概要

このプロジェクトは以下を実現します：

- **Laravel 12** を使用したRESTful API（CRUD操作）
- **OpenTelemetry** によるアプリケーションの計装（HTTP、データベース、ログ）
- **AWS X-Ray** へのトレースデータ送信と可視化
- **Docker Compose** による開発環境
- **EC2** での本番環境デプロイ

## 🏗️ アーキテクチャ

### 本番環境（AWS）
```
User → EC2 (Nginx + Laravel) → OpenTelemetry → X-Ray Daemon → AWS X-Ray
                ↓
            RDS PostgreSQL
```

### 開発環境（Docker）
```
User → Nginx → Laravel → OpenTelemetry → OTel Collector → stdout
         ↓
    PostgreSQL (Docker)
```

## 🚀 クイックスタート

### 前提条件

- Docker & Docker Compose
- PHP 8.3+ (ローカル開発の場合)
- Composer (ローカル開発の場合)

### 開発環境のセットアップ

1. **リポジトリのクローン**
   ```bash
   git clone https://github.com/shimamorieiki/laravel12-otel-ec2-xray.git
   cd laravel12-otel-ec2-xray
   ```

2. **環境設定**
   ```bash
   cp .env.docker .env
   ```

3. **Dockerコンテナの起動**
   ```bash
   make setup  # 初回のみ
   make up     # 2回目以降
   ```

4. **動作確認**
   ```bash
   # ヘルスチェック
   curl http://localhost/up

   # Items API
   curl http://localhost/api/items
   ```

## 📚 API仕様

### Items CRUD API

| メソッド | エンドポイント | 説明 |
|---------|--------------|------|
| GET | `/api/items` | 全アイテムの取得 |
| GET | `/api/items/{id}` | 特定アイテムの取得 |
| POST | `/api/items` | 新規アイテムの作成 |
| PUT | `/api/items/{id}` | アイテムの更新 |
| DELETE | `/api/items/{id}` | アイテムの削除 |

#### リクエスト例

```bash
# アイテムの作成
curl -X POST http://localhost/api/items \
  -H "Content-Type: application/json" \
  -d '{
    "name": "サンプル商品",
    "description": "これはテスト商品です",
    "price": 1980,
    "quantity": 10
  }'

# アイテムの取得
curl http://localhost/api/items

# アイテムの更新
curl -X PUT http://localhost/api/items/1 \
  -H "Content-Type: application/json" \
  -d '{
    "quantity": 20
  }'

# アイテムの削除
curl -X DELETE http://localhost/api/items/1
```

## 🔧 OpenTelemetry設定

### トレース対象

1. **HTTPリクエスト/レスポンス**
   - リクエストメソッド、URL、ステータスコード
   - レスポンスタイム

2. **データベースクエリ**
   - SQL文、実行時間
   - バインドパラメータ

3. **ログエントリ**
   - ログレベル、メッセージ
   - コンテキスト情報

### 設定ファイル

- `config/opentelemetry.php` - OpenTelemetry設定
- `.env` - 環境変数による設定
- `docker/otel-collector/otel-collector-config.yaml` - ローカル用Collector設定
- `docker/otel-collector/otel-collector-config.ec2.yaml` - EC2用Collector設定

### X-Ray統合

#### ローカル環境での設定

1. **AWS認証情報の設定**
   ```bash
   # 環境変数で設定
   export AWS_ACCESS_KEY_ID="your-access-key-id"
   export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
   export AWS_DEFAULT_REGION="ap-northeast-1"
   ```

2. **`.env`ファイルの設定**
   ```env
   # X-Ray設定
   OTEL_XRAY_ENABLED=true
   OTEL_XRAY_LOCAL_MODE=false
   OTEL_XRAY_ENDPOINT=
   # 注意：OTEL_EXPORTERS設定は文字列形式で指定（配列形式[debug, awsxray]は無効）
   OTEL_EXPORTERS=debug,awsxray
   
   # AWS設定（重要：Docker環境では.envファイルに記載が必要）
   AWS_ACCESS_KEY_ID=your-access-key-id
   AWS_SECRET_ACCESS_KEY=your-secret-access-key
   AWS_DEFAULT_REGION=ap-northeast-1
   ```

3. **⚠️ 重要な注意点**
   - **AWS認証情報**: Docker環境では.envファイルに明示的に設定が必要
   - **OTEL_EXPORTERS形式**: 文字列形式で指定（配列形式は無効）
   - **X-Rayエクスポーター**: トレースのみをサポート（メトリクス・ログは非対応）

4. **詳細な設定手順**
   詳細は [LOCAL_XRAY_SETUP.md](docs/LOCAL_XRAY_SETUP.md) を参照してください。

#### EC2環境での設定

1. **IAMロールの設定**
   - `AWSXRayDaemonWriteAccess` ポリシーをEC2にアタッチ

2. **OpenTelemetry Collectorの設定**
   - EC2専用の設定ファイル（`otel-collector-config.ec2.yaml`）を使用
   - `local_mode: true` でX-Ray APIに直接送信

3. **詳細な設定手順**
   詳細は [EC2_SETUP.md](docs/EC2_SETUP.md) を参照してください。

### テストコマンド

```bash
# OpenTelemetry動作確認
docker-compose exec app php artisan otel:test

# X-Ray Collectorのログ確認
docker-compose logs otel-collector

# AWS認証情報の確認
aws sts get-caller-identity
```

## 📖 詳細ドキュメント

### 設定ガイド
- [AWS CLI設定ガイド](docs/AWS_CLI_SETUP_GUIDE.md) - AWS CLI設定と認証情報設定
- [ローカルX-Ray設定](docs/LOCAL_XRAY_SETUP.md) - ローカル環境でのX-Ray設定
- [OpenTelemetry監視ガイド](docs/OPENTELEMETRY_MONITORING_GUIDE.md) - 監視とログ確認方法

### デプロイガイド
- [AWSリソース設定](docs/AWS_RESOURCES_SETUP.md) - EC2、RDS、IAMロールの設定
- [EC2設定ガイド](docs/EC2_SETUP.md) - EC2でのアプリケーション設定
- [GitHub Actions Deploy](docs/GITHUB_ACTIONS_DEPLOY.md) - CI/CDパイプライン設定

### トラブルシューティング
- [X-Rayトラブルシューティング](docs/XRAY_TROUBLESHOOTING_GUIDE.md) - 問題解決と診断手順
- [AWS認証情報設定](docs/AWS_CREDENTIALS_SETUP.md) - 認証情報の詳細設定方法

## 🚢 本番環境へのデプロイ

### 1. AWSリソースの作成

[AWS_RESOURCES_SETUP.md](docs/AWS_RESOURCES_SETUP.md) を参照してください。

必要なリソース：
- EC2インスタンス（Amazon Linux 2023）
- RDS PostgreSQL
- IAMロール（X-Ray権限付き）
- VPC、セキュリティグループ

### 2. EC2セットアップ

[EC2_SETUP.md](docs/EC2_SETUP.md) の手順に従ってください。

主な手順：
1. 必要なソフトウェアのインストール
2. X-Ray Daemonのセットアップ
3. アプリケーションのデプロイ
4. Nginx/PHP-FPMの設定

### 3. 環境変数の設定

本番環境の`.env`ファイル：
```env
APP_ENV=production
APP_DEBUG=false

DB_CONNECTION=pgsql
DB_HOST=your-rds-endpoint.amazonaws.com
DB_DATABASE=laravel
DB_USERNAME=your_username
DB_PASSWORD=your_password

OTEL_SERVICE_NAME=laravel-app
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317
OTEL_XRAY_ENABLED=true
```

## 📊 モニタリング

### AWS X-Ray

1. AWS X-Rayコンソールにアクセス
2. サービスマップで`laravel-app`を確認
3. トレース詳細を確認

### CloudWatch

- EC2メトリクス（CPU、メモリ、ネットワーク）
- RDSメトリクス（接続数、クエリ性能）
- カスタムメトリクス（アプリケーション固有）

## 🛠️ 開発者向け情報

### Makeコマンド

```bash
make help       # ヘルプ表示
make up         # コンテナ起動
make down       # コンテナ停止
make logs       # ログ表示
make shell      # アプリコンテナにアクセス
make migrate    # マイグレーション実行
make artisan cmd="..."  # Artisanコマンド実行
```

### ディレクトリ構成

```
.
├── app/                    # Laravelアプリケーション
│   ├── Http/
│   │   ├── Controllers/    # APIコントローラー
│   │   └── Middleware/     # OpenTelemetryミドルウェア
│   ├── Models/            # Eloquentモデル
│   └── Providers/         # サービスプロバイダー
├── config/                # 設定ファイル
├── database/              # マイグレーション
├── docker/                # Docker関連ファイル
│   ├── nginx/            # Nginx設定
│   ├── php/              # PHP設定
│   └── otel-collector/   # OpenTelemetry Collector設定
├── docs/                  # ドキュメント
├── public/                # 公開ディレクトリ
├── routes/                # ルート定義
└── docker-compose.yml     # Docker Compose設定
```

## 🐛 トラブルシューティング

### よくある問題

1. **トレースが表示されない**
   - X-Ray DaemonとOTel Collectorの状態を確認
   - IAMロールの権限を確認

2. **データベース接続エラー**
   - RDSセキュリティグループの設定を確認
   - 環境変数の設定を確認

3. **パフォーマンスの問題**
   - OpenTelemetryのサンプリングレートを調整
   - バッチプロセッサーの設定を最適化

詳細は [EC2_SETUP.md](docs/EC2_SETUP.md) のトラブルシューティングセクションを参照してください。

## 📝 ライセンス

このプロジェクトはMITライセンスの下で公開されています。
