# EC2デプロイワークフロー設定ガイド

このガイドでは、GitHub Actionsを使用してEC2インスタンスに自動デプロイするための設定手順を説明します。

## 📋 前提条件

### 1. AWSリソース
- **EC2インスタンス**: Amazon Linux 2023, t3.medium以上
- **RDS PostgreSQL**: データベース
- **IAMロール**: X-Ray権限付き
- **セキュリティグループ**: 適切なポート開放

### 2. EC2の準備
- SSH接続が可能
- 適切なIAMロールがアタッチされている
- セキュリティグループでHTTP/HTTPSアクセスが許可されている

## 🔧 セットアップ手順

### ステップ1: EC2インスタンスの初期設定

#### 1.1 EC2インスタンスにSSH接続
```bash
ssh -i your-key.pem ec2-user@your-ec2-ip
```

#### 1.2 セットアップスクリプトの実行
```bash
# スクリプトをダウンロード
wget https://raw.githubusercontent.com/yourusername/laravel12-otel-ec2-xray/main/scripts/setup-ec2.sh

# スクリプトを実行可能にする
chmod +x setup-ec2.sh

# セットアップスクリプトを実行（リポジトリURLを更新してから）
nano setup-ec2.sh  # GitHubリポジトリURLを更新
./setup-ec2.sh
```

### ステップ2: GitHub Secretsの設定

#### 2.1 必要なSecrets一覧

| Secret名 | 説明 | 取得方法 |
|----------|------|----------|
| `AWS_ACCESS_KEY_ID` | AWS アクセスキーID | IAMユーザーから取得 |
| `AWS_SECRET_ACCESS_KEY` | AWS シークレットアクセスキー | IAMユーザーから取得 |
| `EC2_HOST` | EC2のパブリックIPアドレス | EC2コンソールから取得 |
| `EC2_USERNAME` | EC2のユーザー名 | `ec2-user` (Amazon Linux 2023) |
| `EC2_PRIVATE_KEY` | SSH秘密鍵 | EC2作成時のキーペア |
| `DB_HOST` | RDSエンドポイント | RDSコンソールから取得 |
| `DB_PASSWORD` | データベースパスワード | RDS作成時に設定 |
| `APP_KEY` | Laravel APPキー | `php artisan key:generate --show` |

#### 2.2 GitHub Secretsの設定方法

1. **GitHubリポジトリにアクセス**
   ```
   https://github.com/yourusername/laravel12-otel-ec2-xray
   ```

2. **Settings → Secrets and variables → Actions**

3. **"New repository secret"をクリックして以下を設定**

```bash
# AWS認証情報
AWS_ACCESS_KEY_ID: [AWS_ACCESS_KEY_ID]
AWS_SECRET_ACCESS_KEY: [AWS_SECRET_ACCESS_KEY]

# EC2接続情報
EC2_HOST: [EC2_HOST]
EC2_USERNAME: ec2-user
EC2_PRIVATE_KEY: |
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpAIBAAKCAQEA...
  ...
  -----END RSA PRIVATE KEY-----

# データベース情報
DB_HOST: [DB-HOST]
DB_PASSWORD: your-secure-database-password

# Laravel設定
APP_KEY: [APP_KEY]
```

### ステップ3: IAM権限の設定

#### 3.1 EC2インスタンス用IAMロール

EC2インスタンスには以下の権限が必要です：

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
        "xray:GetSamplingTargets"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

#### 3.2 GitHub Actions用IAMユーザー

デプロイ用のIAMユーザーには最低限の権限のみ付与：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

### ステップ4: セキュリティグループの設定

#### 4.1 EC2用セキュリティグループ

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| SSH | TCP | 22 | Your IP | SSH access |
| HTTP | TCP | 80 | 0.0.0.0/0 | Web access |
| HTTPS | TCP | 443 | 0.0.0.0/0 | Secure web access |

#### 4.2 RDS用セキュリティグループ

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| PostgreSQL | TCP | 5432 | EC2 SG | Database access |

## 🚀 デプロイの実行

### 初回デプロイ

1. **EC2セットアップの完了確認**
   ```bash
   # EC2にSSH接続して確認
   sudo systemctl status nginx
   sudo systemctl status php-fpm
   sudo systemctl status xray
   ```

2. **GitHub Secretsの設定確認**
   - 全ての必要なSecretsが設定されているか確認

3. **デプロイの実行**
   ```bash
   # mainブランチにpushするか、手動でワークフローを実行
   git push origin main
   ```

### 継続的デプロイ

mainブランチにpushするたびに自動でデプロイが実行されます。

```bash
# 変更をコミット
git add .
git commit -m "Update application"

# mainブランチにpush（自動デプロイが開始される）
git push origin main
```

## 📊 デプロイ後の確認

### 1. アプリケーションの動作確認

```bash
# ヘルスチェック
curl http://your-ec2-ip/

# API動作確認
curl http://your-ec2-ip/api/items
```

### 2. OpenTelemetryとX-Rayの確認

```bash
# EC2にSSH接続して確認
ssh -i your-key.pem ec2-user@your-ec2-ip

# サービス状態確認
sudo systemctl status otel-collector
sudo systemctl status xray

# ログ確認
sudo journalctl -u otel-collector -f
sudo journalctl -u xray -f
```

### 3. AWS X-Rayコンソールでの確認

[AWS X-Rayコンソール](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)でトレースを確認

## 🔧 トラブルシューティング

### デプロイが失敗する場合

#### 1. GitHub Actionsログの確認
```
GitHub Repository → Actions → 失敗したワークフロー → ログを確認
```

#### 2. よくあるエラーと解決方法

**SSH接続エラー**
```bash
# 秘密鍵の形式確認
# -----BEGIN RSA PRIVATE KEY----- で始まる必要がある
```

**権限エラー**
```bash
# EC2でのファイル権限確認
sudo chown -R nginx:nginx /var/www/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/laravel12-otel-ec2-xray/storage
```

**データベース接続エラー**
```bash
# RDSセキュリティグループ確認
# EC2からRDSへの5432ポートアクセスが許可されているか
```

#### 3. サービス再起動

```bash
# 全サービスを再起動
sudo systemctl restart nginx
sudo systemctl restart php-fpm
sudo systemctl restart otel-collector
sudo systemctl restart xray
```

## 📋 チェックリスト

### デプロイ前確認
- [ ] EC2インスタンスが起動している
- [ ] IAMロールが正しく設定されている
- [ ] セキュリティグループが適切に設定されている
- [ ] RDSが起動している
- [ ] GitHub Secretsが全て設定されている

### デプロイ後確認
- [ ] アプリケーションにアクセスできる
- [ ] データベース接続が正常
- [ ] X-Rayでトレースが確認できる
- [ ] CloudWatchでメトリクスが確認できる
- [ ] 全てのサービスが正常に動作している

## 🔗 関連リンク

- [EC2設定ガイド](EC2_SETUP.md)
- [GitHub Actions Deploy](GITHUB_ACTIONS_DEPLOY.md)
- [X-Rayトラブルシューティング](XRAY_TROUBLESHOOTING_GUIDE.md)
- [AWS IAM ユーザーガイド](https://docs.aws.amazon.com/IAM/latest/UserGuide/)
- [GitHub Actions ドキュメント](https://docs.github.com/en/actions) 
