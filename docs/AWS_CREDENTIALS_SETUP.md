# AWS認証情報の設定ガイド

AWS認証情報をローカル環境で適切に設定・管理する方法を説明します。**セキュリティ上の重要な注意点も含めて説明します。**

## 🔐 **方法1: AWS CLI設定（最も推奨）**

### AWS CLIのインストール

#### Windows
```powershell
# 方法1: 公式インストーラー（推奨）
# https://aws.amazon.com/cli/ からダウンロード

# 方法2: PowerShellでダウンロード
$url = "https://awscli.amazonaws.com/AWSCLIV2.msi"
$output = "$env:TEMP\AWSCLIV2.msi"
Invoke-WebRequest -Uri $url -OutFile $output
Start-Process -FilePath $output -Wait
```

#### Linux/Mac
```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Mac
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

### 設定方法

```bash
# 基本設定
aws configure

# 入力項目
AWS Access Key ID [None]: your-access-key-id
AWS Secret Access Key [None]: your-secret-access-key
Default region name [None]: ap-northeast-1
Default output format [None]: json
```

### 設定ファイルの場所

```
Windows: C:\Users\{username}\.aws\credentials
Linux/Mac: ~/.aws/credentials
```

### 設定内容の確認

```bash
# 設定内容の確認
aws configure list

# 認証情報の確認
aws sts get-caller-identity
```

### プロファイル機能の活用

```bash
# 複数のプロファイルを使い分け
aws configure --profile personal
aws configure --profile work

# プロファイル指定での実行
aws s3 ls --profile personal
```

### **メリット**
- ✅ **最も安全** - 認証情報がファイルに暗号化されて保存
- ✅ **標準的な方法** - AWS公式推奨
- ✅ **プロファイル機能** - 複数のアカウントを管理可能
- ✅ **自動更新** - 一時的な認証情報の自動取得

### **デメリット**
- ❌ **初期設定が必要** - AWS CLIのインストールが必要

## 🔐 **方法2: 環境変数（一時的な使用）**

### PowerShell
```powershell
# セッション中のみ有効
$env:AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
$env:AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
$env:AWS_DEFAULT_REGION="ap-northeast-1"

# 確認
$env:AWS_ACCESS_KEY_ID
```

### Bash/Zsh
```bash
# セッション中のみ有効
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="ap-northeast-1"

# 確認
echo $AWS_ACCESS_KEY_ID
```

### 永続的な設定

#### Windows
```powershell
# システム環境変数に設定（管理者権限が必要）
[System.Environment]::SetEnvironmentVariable("AWS_ACCESS_KEY_ID", "your-access-key-id", "Machine")
[System.Environment]::SetEnvironmentVariable("AWS_SECRET_ACCESS_KEY", "your-secret-access-key", "Machine")
[System.Environment]::SetEnvironmentVariable("AWS_DEFAULT_REGION", "ap-northeast-1", "Machine")
```

#### Linux/Mac
```bash
# ~/.bashrc または ~/.zshrc に追記
echo 'export AWS_ACCESS_KEY_ID="your-access-key-id"' >> ~/.bashrc
echo 'export AWS_SECRET_ACCESS_KEY="your-secret-access-key"' >> ~/.bashrc
echo 'export AWS_DEFAULT_REGION="ap-northeast-1"' >> ~/.bashrc
source ~/.bashrc
```

### **メリット**
- ✅ **簡単** - すぐに設定可能
- ✅ **Docker対応** - コンテナ内で利用可能

### **デメリット**
- ❌ **セキュリティリスク** - 環境変数が漏洩する可能性
- ❌ **管理困難** - 複数のプロジェクトで混在する可能性

## 🔐 **方法3: .envファイル（注意が必要）**

### .envファイルの作成

```env
# .env
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_DEFAULT_REGION=ap-northeast-1
```

### .gitignoreへの追加（必須）

```gitignore
# .gitignore
.env
.env.local
.env.*.local
```

### **メリット**
- ✅ **プロジェクト固有** - プロジェクトごとの設定
- ✅ **Docker対応** - docker-composeで読み込み可能

### **デメリット**
- ❌ **重大なセキュリティリスク** - 誤ってコミットする可能性
- ❌ **管理困難** - 複数の.envファイルの管理

## 🔐 **方法4: Docker Secrets（本格的な本番環境）**

### docker-compose.ymlでの設定

```yaml
version: '3.8'
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    secrets:
      - aws_access_key_id
      - aws_secret_access_key
    environment:
      - AWS_ACCESS_KEY_ID_FILE=/run/secrets/aws_access_key_id
      - AWS_SECRET_ACCESS_KEY_FILE=/run/secrets/aws_secret_access_key

secrets:
  aws_access_key_id:
    file: ./secrets/aws_access_key_id.txt
  aws_secret_access_key:
    file: ./secrets/aws_secret_access_key.txt
```

### Secretsファイルの作成

```bash
# secretsディレクトリの作成
mkdir -p secrets

# 認証情報の保存
echo "AKIAIOSFODNN7EXAMPLE" > secrets/aws_access_key_id.txt
echo "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" > secrets/aws_secret_access_key.txt

# 権限の設定
chmod 600 secrets/*
```

### **メリット**
- ✅ **高セキュリティ** - Docker Secretsによる暗号化
- ✅ **本番環境対応** - 本格的な運用に適している

### **デメリット**
- ❌ **複雑** - 設定が複雑
- ❌ **開発環境では過剰** - 開発環境には不向き

## 🔐 **方法5: AWS SSOの活用（企業環境）**

### AWS SSOの設定

```bash
# AWS CLI v2でSSO設定
aws configure sso

# 入力項目
SSO start URL [None]: https://your-sso-portal.awsapps.com/start
SSO region [None]: ap-northeast-1
SSO account ID [None]: 123456789012
SSO role name [None]: DeveloperAccess
CLI default client region [None]: ap-northeast-1
CLI default output format [None]: json
```

### ログイン・ログアウト

```bash
# ログイン
aws sso login --profile your-profile

# ログアウト
aws sso logout
```

### **メリット**
- ✅ **最高セキュリティ** - 短期間の一時的な認証情報
- ✅ **企業対応** - 企業の認証システムと連携
- ✅ **自動更新** - 認証情報の自動更新

### **デメリット**
- ❌ **企業環境限定** - 個人アカウントでは利用不可
- ❌ **複雑** - 初期設定が複雑

## 🏗️ **各方法の推奨用途**

| 方法 | 推奨用途 | セキュリティ | 難易度 |
|------|----------|--------------|--------|
| AWS CLI設定 | **開発環境全般** | 🟢 高 | 🟡 中 |
| 環境変数 | **一時的なテスト** | 🟡 中 | 🟢 低 |
| .envファイル | **プロジェクト固有設定** | 🟠 低 | 🟢 低 |
| Docker Secrets | **本番環境** | 🟢 高 | 🔴 高 |
| AWS SSO | **企業環境** | 🟢 最高 | 🔴 高 |

## 🔧 **本プロジェクトでの推奨設定**

### 開発環境

```bash
# 1. AWS CLI設定（推奨）
aws configure

# 2. 環境変数での一時的な設定
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="ap-northeast-1"

# 3. Docker Composeの起動
docker-compose up -d
```

### 本番環境（EC2）

```bash
# IAMロールの使用（推奨）
# EC2インスタンスにIAMロールをアタッチ
# 環境変数や認証情報ファイルは不要
```

## ⚠️ **セキュリティ上の重要な注意点**

### 1. **絶対にやってはいけないこと**

❌ **認証情報をコードに直接記述**
```javascript
// 絶対にダメ
const credentials = {
  accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
};
```

❌ **認証情報をGitにコミット**
```bash
# 絶対にダメ
git add .env
git commit -m "Add AWS credentials"
```

❌ **認証情報をログに出力**
```bash
# 絶対にダメ
echo "AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
```

### 2. **推奨されるセキュリティ対策**

✅ **.gitignoreの適切な設定**
```gitignore
# 認証情報関連ファイル
.env
.env.local
.env.*.local
.aws/
credentials
config
secrets/
```

✅ **最小権限の原則**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ],
      "Resource": "*"
    }
  ]
}
```

✅ **認証情報の定期的な更新**
```bash
# 3ヶ月ごとに認証情報を更新
aws iam create-access-key --user-name your-username
aws iam delete-access-key --user-name your-username --access-key-id old-key-id
```

✅ **MFA（多要素認証）の有効化**
```bash
# MFAの設定
aws iam enable-mfa-device --user-name your-username --serial-number arn:aws:iam::123456789012:mfa/your-username --authentication-code1 123456 --authentication-code2 654321
```

## 🧪 **設定確認方法**

### 1. 認証情報の確認

```bash
# 現在の認証情報を確認
aws sts get-caller-identity

# 期待される出力
{
    "UserId": "AIDABC123DEFGHIJKLMN",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

### 2. 権限の確認

```bash
# X-Ray権限の確認
aws xray get-sampling-rules

# 期待される出力
{
    "SamplingRuleRecords": []
}
```

### 3. 本プロジェクトでの動作確認

```bash
# 設定確認スクリプトの実行
./setup_xray.sh      # Linux/Mac
.\setup_xray.ps1     # Windows PowerShell
```

## 🔄 **認証情報の切り替え**

### プロファイル機能の活用

```bash
# 開発用プロファイル
aws configure --profile development
export AWS_PROFILE=development

# 本番用プロファイル
aws configure --profile production
export AWS_PROFILE=production

# Docker Composeでの使用
docker-compose --env-file .env.development up -d
```

### プロジェクト固有の設定

```bash
# プロジェクトディレクトリでの設定
cd /path/to/your/project
export AWS_PROFILE=project-specific
docker-compose up -d
```

この設定により、セキュリティを保ちながら柔軟にAWS認証情報を管理できます。開発環境では**AWS CLI設定**、本番環境では**IAMロール**を使用することを強く推奨します。 
