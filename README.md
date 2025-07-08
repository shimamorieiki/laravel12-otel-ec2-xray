# Laravel 12 + OpenTelemetry + AWS X-Ray on EC2

このプロジェクトは、Laravel 12アプリケーションにOpenTelemetryを統合し、AWS X-RayとEC2環境での監視を実現するサンプルプロジェクトです。

## 🚀 主な機能

- **Laravel 12** - 最新のLaravelフレームワーク
- **OpenTelemetry** - トレース、メトリクス、ログの統合観測
- **AWS X-Ray** - AWSネイティブの分散トレーシング
- **Docker Compose** - 開発環境の簡単セットアップ
- **PostgreSQL** - データベース
- **Nginx** - ウェブサーバー
- **GitHub Actions** - EC2への自動デプロイ

## ⚠️ 重要な注意事項

### AWS認証情報の設定
**必須**: AWS認証情報を正しく設定しないと、X-Rayエクスポーターが動作しません。

1. **`.env`ファイルに必須設定**:
   ```env
   AWS_ACCESS_KEY_ID=your-access-key-id
   AWS_SECRET_ACCESS_KEY=your-secret-access-key
   AWS_DEFAULT_REGION=ap-northeast-1
   ```

2. **`docker-compose.yml`での環境変数設定**:
   - `env_file: - .env`でファイルを明示的に指定
   - `AWS_DEFAULT_REGION=ap-northeast-1`でリージョンを強制指定（システム環境変数を上書き）

### X-Rayエクスポーターの制限事項
- **トレースのみサポート**: X-Rayエクスポーターはメトリクスとログをサポートしていません
- **OTEL_EXPORTERS形式**: `OTEL_EXPORTERS=debug,awsxray`（配列形式 `[debug, awsxray]` は無効）

### 環境変数の優先順位
Docker Composeでは以下の優先順位で環境変数が適用されます：
1. システムの環境変数（最優先）
2. `docker-compose.yml`の`environment`セクション
3. `.env`ファイル（最低優先）

**注意**: システムに`AWS_DEFAULT_REGION`が設定されている場合、`.env`ファイルの設定が無視される場合があります。

## 📦 ローカル開発環境のセットアップ

### 前提条件
- Docker & Docker Compose
- AWS CLI設定済み
- Git

### 1. プロジェクトのクローン
```bash
git clone <repository-url>
cd laravel12-otel-ec2-xray
```

### 2. 環境変数設定
```bash
cp .env.example .env
# .envファイルを編集してAWS認証情報を設定
```

### 3. アプリケーション起動
```bash
docker-compose up -d
```

### 4. 初期セットアップ
```bash
# Laravelのキー生成
docker-compose exec app php artisan key:generate

# データベースマイグレーション
docker-compose exec app php artisan migrate

# サンプルデータ投入
docker-compose exec app php artisan db:seed
```

## 🚀 EC2への自動デプロイ

このプロジェクトには、GitHub Actionsを使用したEC2への自動デプロイ機能が含まれています。

### デプロイアーキテクチャ
```
GitHub Repository → GitHub Actions → EC2 Instance
                                    ├── Nginx + PHP-FPM
                                    ├── OpenTelemetry Collector
                                    ├── AWS X-Ray Daemon
                                    └── RDS PostgreSQL
```

### デプロイの設定手順

1. **EC2インスタンスの準備**
   - Amazon Linux 2023
   - 適切なIAMロールをアタッチ
   - セキュリティグループの設定

2. **初期セットアップスクリプトの実行**
   ```bash
   # EC2にSSH接続
   ssh -i your-key.pem ec2-user@your-ec2-ip
   
   # セットアップスクリプトの実行
   wget https://raw.githubusercontent.com/yourusername/laravel12-otel-ec2-xray/main/scripts/setup-ec2.sh
   chmod +x setup-ec2.sh
   ./setup-ec2.sh
   ```

3. **GitHub Secretsの設定**
   - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
   - `EC2_HOST` / `EC2_USERNAME` / `EC2_PRIVATE_KEY`
   - `DB_HOST` / `DB_PASSWORD`
   - `APP_KEY`

4. **自動デプロイの実行**
   ```bash
   # mainブランチにpushすると自動デプロイが開始
   git push origin main
   ```

### デプロイワークフローの機能
- **自動コードデプロイ**: Git pullによる最新コード取得
- **依存関係管理**: Composer install自動実行
- **環境設定**: 本番環境用.envファイルの自動生成
- **データベース**: マイグレーション自動実行
- **サービス管理**: Nginx, PHP-FPM, OpenTelemetry, X-Rayの自動再起動
- **ヘルスチェック**: デプロイ後の動作確認
- **ログ監視**: デプロイ状況の詳細ログ出力

## 🧪 動作確認

### API テスト
```bash
# Windows PowerShell
.\test_api.ps1

# Linux/macOS
./test_api.sh
```

### OpenTelemetryテスト
```bash
docker-compose exec app php artisan otel:test
```

### X-Ray確認
[AWS X-Rayコンソール](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)でトレースを確認

## 🔧 トラブルシューティング

### X-Rayにトレースが表示されない場合

1. **環境変数確認**:
   ```bash
   docker-compose config | Select-String -Pattern 'AWS_'
   ```

2. **OTel Collectorログ確認**:
   ```bash
   docker-compose logs otel-collector | Select-String -Pattern 'awsxray'
   ```

3. **詳細ログ確認**:
   OTel Collectorの設定でデバッグレベルを有効化済み

### よくある問題
- **AWS認証エラー**: `.env`ファイルのAWS認証情報を確認
- **リージョン不一致**: `AWS_DEFAULT_REGION=ap-northeast-1`が正しく設定されているか確認
- **X-Rayエクスポーター未初期化**: 環境変数がコンテナに正しく渡されているか確認

詳細なトラブルシューティングガイド: [docs/XRAY_TROUBLESHOOTING_GUIDE.md](docs/XRAY_TROUBLESHOOTING_GUIDE.md)

## 📚 ドキュメント

### 開発・設定ガイド
- [AWS CLI設定ガイド](docs/AWS_CLI_SETUP_GUIDE.md)
- [ローカルX-Ray設定](docs/LOCAL_XRAY_SETUP.md)
- [OpenTelemetry監視ガイド](docs/OPENTELEMETRY_MONITORING_GUIDE.md)
- [X-Rayトラブルシューティング](docs/XRAY_TROUBLESHOOTING_GUIDE.md)

### デプロイ・本番環境ガイド
- [EC2デプロイワークフロー設定](docs/EC2_DEPLOY_SETUP.md)
- [EC2セットアップ](docs/EC2_SETUP.md)
- [GitHub Actions デプロイ](docs/GITHUB_ACTIONS_DEPLOY.md)

## 🏗️ プロジェクト構成

### ローカル開発環境
```
Docker Compose
├── Laravel App (PHP-FPM)
├── Nginx
├── PostgreSQL
└── OpenTelemetry Collector → AWS X-Ray API
```

### 本番環境（EC2）
```
EC2 Instance
├── Nginx + PHP-FPM
├── Laravel Application
├── OpenTelemetry Collector
├── AWS X-Ray Daemon
└── RDS PostgreSQL
```

## 🚀 主要な改善点

### パフォーマンス最適化
- OpenTelemetryバッチ処理の最適化
- PHP-FPMとNginxの設定調整
- データベース接続プールの最適化

### 監視機能
- AWS X-Rayによる分散トレーシング
- CloudWatchによるメトリクス監視
- 包括的なログ収集

### 自動化
- GitHub Actionsによる継続的デプロイ
- 自動テストとヘルスチェック
- 環境固有の設定管理
