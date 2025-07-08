# AWS CLI設定ガイド

このドキュメントでは、AWS CLIを使用してAWS認証情報を設定し、本プロジェクトでX-Rayを使用するための完全な手順を説明します。

## 📋 **前提条件**

- Windows 10/11（PowerShell 5.1以降）
- 管理者権限（インストール時のみ）
- AWSアカウント

## 🔧 **手順1: AWS CLIのインストール**

### **方法1: 公式インストーラー（推奨）**

1. **AWS CLI公式サイトにアクセス**
   - URL: https://aws.amazon.com/cli/
   - 「Download and install the AWS CLI」をクリック

2. **Windows版をダウンロード**
   - 「AWS CLI MSI installer for Windows (64-bit)」をクリック
   - ファイル名: `AWSCLIV2.msi`

3. **インストーラーを実行**
   - ダウンロードした`AWSCLIV2.msi`をダブルクリック
   - 「Next」→「Next」→「Install」→「Finish」

4. **インストール確認**
   ```powershell
   # PowerShellを新しく開いて実行
   aws --version
   
   # 期待される出力
   aws-cli/2.x.x Python/3.x.x Windows/10 exe/AMD64 prompt/off
   ```

### **方法2: PowerShellでのダウンロード**

```powershell
# 管理者権限でPowerShellを開く
# ダウンロード
$url = "https://awscli.amazonaws.com/AWSCLIV2.msi"
$output = "$env:TEMP\AWSCLIV2.msi"
Invoke-WebRequest -Uri $url -OutFile $output

# インストール実行
Start-Process -FilePath $output -Wait

# インストール確認
aws --version
```

## 🔐 **手順2: AWS認証情報の取得**

### **AWSコンソールでの作業**

1. **AWSコンソールにログイン**
   - https://console.aws.amazon.com/

2. **IAMサービスに移動**
   - 上部検索バーで「IAM」と入力
   - 「IAM」をクリック

3. **ユーザーページに移動**
   - 左サイドバーで「ユーザー」をクリック
   - 既存のユーザーをクリック、または「ユーザーを作成」

4. **新しいユーザーを作成する場合**
   ```
   ユーザー名: laravel-local-dev
   AWSアクセスタイプ: プログラムによるアクセス
   権限: 既存のポリシーを直接アタッチ
   検索: AWSXRayDaemonWriteAccess
   ```

5. **アクセスキーの作成**
   - 「セキュリティ認証情報」タブ
   - 「アクセスキーを作成」
   - 用途: 「ローカルコード」を選択
   - 「アクセスキーを作成」をクリック

6. **認証情報をコピー**
   - **アクセスキーID**: `AKIA...`で始まる文字列
   - **シークレットアクセスキー**: 長い文字列（一度しか表示されない）
   - **重要**: 必ず両方をコピーして保存

## ⚙️ **手順3: AWS CLIの設定**

### **基本設定**

```powershell
# PowerShellで実行
aws configure

# 以下の項目を順番に入力
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: ap-northeast-1
Default output format [None]: json
```

### **設定の確認**

```powershell
# 設定内容の確認
aws configure list

# 期待される出力
      Name                    Value             Type    Location
      ----                    -----             ----    --------
   profile                <not set>             None    None
access_key     ****************MPLE shared-credentials-file
secret_key     ****************MPLE shared-credentials-file
    region           ap-northeast-1      config-file    ~/.aws/config
```

### **認証情報の動作確認**

```powershell
# AWS認証情報の確認
aws sts get-caller-identity

# 期待される出力
{
    "UserId": "AIDABC123DEFGHIJKLMN",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/laravel-local-dev"
}
```

### **X-Ray権限の確認**

```powershell
# X-Ray権限の確認
aws xray get-sampling-rules

# 期待される出力（権限があれば）
{
    "SamplingRuleRecords": []
}

# エラーが出た場合
# An error occurred (AccessDenied) when calling the GetSamplingRules operation: User: arn:aws:iam::123456789012:user/laravel-local-dev is not authorized to perform: xray:GetSamplingRules on resource: *
```

## 🔧 **手順4: 本プロジェクトでの設定**

### **.envファイルの作成**

```powershell
# プロジェクトルートで実行
Copy-Item .env.example .env

# .envファイルを編集（実際のエディタで開く）
notepad .env
```

### **.envファイルの内容**

```env
# 基本設定
APP_NAME=Laravel
APP_ENV=local
APP_KEY=base64:your-app-key-here
APP_DEBUG=true
APP_URL=http://localhost

# データベース設定
DB_CONNECTION=pgsql
DB_HOST=db
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=user
DB_PASSWORD=pass

# AWS設定（重要：Docker環境では.envファイルに記載が必要）
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_DEFAULT_REGION=ap-northeast-1

# OpenTelemetry設定
OTEL_SERVICE_NAME=laravel-app
OTEL_SERVICE_VERSION=1.0.0
OTEL_ENVIRONMENT=local
OTEL_RESOURCE_ATTRIBUTES=service.name=laravel-app,service.version=1.0.0,deployment.environment=local

# OpenTelemetry Collector設定
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
OTEL_TRACES_ENABLED=true
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_ENABLED=true
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_ENABLED=true
OTEL_LOGS_EXPORTER=otlp

# X-Ray設定
OTEL_XRAY_ENABLED=true
OTEL_XRAY_LOCAL_MODE=false
OTEL_XRAY_ENDPOINT=
# 注意：OTEL_EXPORTERS設定は文字列形式で指定（配列形式[debug, awsxray]は無効）
OTEL_EXPORTERS=debug,awsxray

# セッション設定
SESSION_DRIVER=database
SESSION_LIFETIME=120

# その他設定
LOG_CHANNEL=stack
LOG_LEVEL=debug
BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
```

### **⚠️ 重要な注意点**

#### **AWS認証情報の設定**
- **Docker環境の場合**: .envファイルに`AWS_ACCESS_KEY_ID`と`AWS_SECRET_ACCESS_KEY`の明示的な設定が必要
- **理由**: Docker内のOTel CollectorはホストのAWS CLI設定を直接参照できないため
- **セキュリティ**: .envファイルは.gitignoreに含まれており、Gitにコミットされません

#### **OTEL_EXPORTERS設定の形式**
- **正しい形式**: `OTEL_EXPORTERS=debug,awsxray`
- **間違った形式**: `OTEL_EXPORTERS=[debug, awsxray]`（配列形式は無効）
- **理由**: .envファイルでは文字列形式でのみ指定可能

#### **X-Rayエクスポーターの制限**
- **対応データ**: トレースのみ
- **非対応データ**: メトリクス、ログ
- **設定**: OTel Collectorでは、X-Rayエクスポーターをトレースパイプラインでのみ使用
- **メトリクス・ログ**: debugエクスポーターのみ使用

### **Docker環境の起動**

```powershell
# コンテナをビルド
docker-compose build

# コンテナを起動
docker-compose up -d

# 状態確認
docker-compose ps
```

### **Laravel初期設定**

```powershell
# Composer依存関係のインストール
docker-compose exec app composer install

# アプリケーションキーの生成
docker-compose exec app php artisan key:generate

# データベースマイグレーション
docker-compose exec app php artisan migrate

# キャッシュクリア
docker-compose exec app php artisan config:cache
```

## 🧪 **手順5: 動作確認**

### **設定確認スクリプトの実行**

```powershell
# PowerShell版確認スクリプト
.\setup_xray.ps1

# 期待される出力
🔍 X-Ray設定の動作確認を開始します...
📋 環境変数の確認...
✅ AWS環境変数が正しく設定されています
🔐 AWS認証情報の確認...
AWS CLI が見つかりました
✅ AWS認証情報が正しく設定されています
🔍 X-Ray権限の確認...
✅ X-Ray権限が正しく設定されています
📁 .envファイルの確認...
✅ .envファイルが存在します
🐳 Docker Compose設定の確認...
✅ OpenTelemetry Collectorが動作中です
🧪 テストリクエストの実行...
✅ アプリケーションが正常に動作しています
🔬 OpenTelemetryテストの実行...
🎉 X-Ray設定の動作確認が完了しました！
```

### **手動での動作確認**

```powershell
# アプリケーションの動作確認
Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing

# APIの動作確認
Invoke-WebRequest -Uri "http://localhost/api/items" -UseBasicParsing

# OpenTelemetryテストの実行
docker-compose exec app php artisan otel:test

# X-Ray Collectorログの確認
docker-compose logs otel-collector
```

### **X-Rayコンソールでの確認**

1. **AWS X-Rayコンソールにアクセス**
   - https://console.aws.amazon.com/xray/home?region=ap-northeast-1

2. **サービスマップの確認**
   - 「Service map」をクリック
   - `laravel-app`サービスが表示されることを確認

3. **トレースの確認**
   - 「Traces」をクリック
   - HTTPリクエストのトレースが表示されることを確認

## 🔄 **手順6: 複数プロジェクトの管理（オプション）**

### **プロファイルの作成**

```powershell
# プロジェクト専用プロファイルの作成
aws configure --profile laravel-project

# 入力項目
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: ap-northeast-1
Default output format [None]: json
```

### **プロファイルの使用**

```powershell
# 環境変数でプロファイルを指定
$env:AWS_PROFILE="laravel-project"

# または.envファイルに追加
# AWS_PROFILE=laravel-project
```

### **プロファイルの確認**

```powershell
# 現在のプロファイルを確認
aws configure list --profile laravel-project

# プロファイル指定で実行
aws sts get-caller-identity --profile laravel-project
```

## 🐛 **トラブルシューティング**

### **問題1: OTel Collectorが再起動を繰り返す**

**現象**
```
The "AWS_ACCESS_KEY_ID" variable is not set. Defaulting to a blank string.
The "AWS_SECRET_ACCESS_KEY" variable is not set. Defaulting to a blank string.
```

**原因**
- .envファイルにAWS認証情報が設定されていない
- Docker環境ではホストのAWS CLI設定を参照できない

**解決方法**
```env
# .envファイルに以下を追加
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_DEFAULT_REGION=ap-northeast-1
```

### **問題2: X-Rayエクスポーターでエラーが発生**

**現象**
```
Error: failed to build pipelines: failed to create "awsxray" exporter for data type "logs": telemetry type is not supported
Error: failed to build pipelines: failed to create "awsxray" exporter for data type "metrics": telemetry type is not supported
```

**原因**
- AWS X-Rayエクスポーターはトレースのみをサポート
- メトリクスとログでX-Rayエクスポーターを使用している

**解決方法**
`docker/otel-collector/otel-collector-config.yaml`を以下のように修正：
```yaml
service:
  pipelines:
    traces:
      exporters: [debug, awsxray]  # X-Rayはトレースのみ
    metrics:
      exporters: [debug]           # X-Rayは使用不可
    logs:
      exporters: [debug]           # X-Rayは使用不可
```

### **問題3: Laravel環境変数のパースエラー**

**現象**
```
The environment file is invalid!
Failed to parse dotenv file. Encountered unexpected whitespace at [[debug, awsxray]].
```

**原因**
- OTEL_EXPORTERS設定で配列形式を使用している
- .envファイルでは配列形式は無効

**解決方法**
```env
# 間違った形式
OTEL_EXPORTERS=[debug, awsxray]

# 正しい形式
OTEL_EXPORTERS=debug,awsxray
```

### **問題4: AWS CLIが認識されない**

**現象**
```powershell
aws : The term 'aws' is not recognized...
```

**解決方法**
```powershell
# PowerShellを再起動
# パスを確認
$env:PATH

# 手動でパスを追加（一時的）
$env:PATH += ";C:\Program Files\Amazon\AWSCLIV2"
```

### **問題5: 認証情報エラー**

**現象**
```powershell
Unable to locate credentials. You can configure credentials by running "aws configure".
```

**解決方法**
```powershell
# 設定の再実行
aws configure

# 設定ファイルの確認
Get-Content $env:USERPROFILE\.aws\credentials
Get-Content $env:USERPROFILE\.aws\config
```

### **問題6: X-Ray権限エラー**

**現象**
```powershell
AccessDenied: User is not authorized to perform: xray:PutTraceSegments
```

**解決方法**
1. AWSコンソールでIAMユーザーに移動
2. 「許可」タブで「許可を追加」
3. 「AWSXRayDaemonWriteAccess」ポリシーを追加

### **問題7: Docker環境でのAWS認証**

**現象**
```
OpenTelemetry Collector logs show authentication errors
```

**解決方法**
```powershell
# docker-compose.ymlの環境変数を確認
# AWS認証情報がCollectorコンテナに正しく渡されているか確認
docker-compose exec otel-collector env | grep AWS
```

## 📊 **設定ファイルの場所**

### **AWS CLI設定ファイル**
```
Windows: C:\Users\{username}\.aws\
├── credentials  # アクセスキーとシークレットキー
└── config      # リージョンとその他の設定
```

### **設定内容の例**
```ini
# credentials
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# config
[default]
region = ap-northeast-1
output = json
```

## 🎯 **完了チェックリスト**

設定が完了したら、以下の項目をチェックしてください：

- [ ] AWS CLIがインストールされている（`aws --version`）
- [ ] AWS認証情報が設定されている（`aws sts get-caller-identity`）
- [ ] X-Ray権限が設定されている（`aws xray get-sampling-rules`）
- [ ] `.env`ファイルが作成されている
- [ ] Docker環境が起動している（`docker-compose ps`）
- [ ] Laravelアプリケーションが動作している（`http://localhost/`）
- [ ] OpenTelemetryテストが成功している（`php artisan otel:test`）
- [ ] X-Rayコンソールでトレースが確認できる

## 🔒 **セキュリティ注意事項**

1. **認証情報の管理**
   - AWS CLIの設定ファイルは適切な権限で保護される
   - `.env`ファイルは絶対にGitにコミットしない

2. **最小権限の原則**
   - 必要最小限の権限のみを付与
   - 定期的なアクセスキーの更新

3. **認証情報の漏洩対策**
   - ログに認証情報を出力しない
   - 共有環境では個別のプロファイルを使用

これでAWS CLIを使用したX-Ray設定が完了です！ 
