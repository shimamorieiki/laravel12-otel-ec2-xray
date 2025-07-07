# AWS リソースセットアップガイド

このドキュメントでは、Laravel + OpenTelemetry + AWS X-Ray環境を構築するために必要なAWSリソースの作成手順を説明します。

## アカウント
アカウントID: 18...
IAMユーザ: e_s...

## 必要なAWSリソース一覧

1. VPCとネットワーク
2. EC2インスタンス
3. RDS (PostgreSQL)
4. IAMロール
5. セキュリティグループ

## 1. VPCとネットワークの設定

### VPCの作成（既存のVPCを使用する場合はスキップ）

```
名前: laravel-otel-vpc
IPv4 CIDR: 10.0.0.0/16
```

### サブネットの作成

**パブリックサブネット（EC2用）:**
```
名前: laravel-otel-public-subnet
VPC: laravel-otel-vpc
IPv4 CIDR: 10.0.1.0/24
アベイラビリティゾーン: ap-northeast-1a
```

**プライベートサブネット（RDS用）2つ:**
```
名前: laravel-otel-private-subnet-1
VPC: laravel-otel-vpc
IPv4 CIDR: 10.0.2.0/24
アベイラビリティゾーン: ap-northeast-1a

名前: laravel-otel-private-subnet-2
VPC: laravel-otel-vpc
IPv4 CIDR: 10.0.3.0/24
アベイラビリティゾーン: ap-northeast-1c
```

### インターネットゲートウェイ

```
名前: laravel-otel-igw
VPCにアタッチ: laravel-otel-vpc
```

### ルートテーブル

パブリックサブネット用のルートテーブルに以下を追加：
```
送信先: 0.0.0.0/0
ターゲット: laravel-otel-igw
```

## 2. セキュリティグループの作成

### EC2用セキュリティグループ

```
名前: laravel-otel-ec2-sg
説明: Security group for Laravel EC2 instance
VPC: laravel-otel-vpc

インバウンドルール:
- タイプ: SSH
  ポート: 22
  ソース: あなたのIPアドレス/32

- タイプ: HTTP
  ポート: 80
  ソース: 0.0.0.0/0

- タイプ: HTTPS
  ポート: 443
  ソース: 0.0.0.0/0

アウトバウンドルール:
- すべてのトラフィック許可
```

### RDS用セキュリティグループ

```
名前: laravel-otel-rds-sg
説明: Security group for PostgreSQL RDS
VPC: laravel-otel-vpc

インバウンドルール:
- タイプ: PostgreSQL
  ポート: 5432
  ソース: laravel-otel-ec2-sg (EC2のセキュリティグループ)

アウトバウンドルール:
- すべてのトラフィック許可
```

## 3. IAMロールの作成

### EC2用IAMロール

1. **ロールの作成**
   ```
   エンティティタイプ: AWSのサービス
   ロール名: laravel-otel-ec2-role
   信頼されたエンティティ: EC2
   ```

2. **信頼ポリシー（Trust Policy）**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "ec2.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   ```

3. **ポリシーのアタッチ**
   - `AWSXRayDaemonWriteAccess`
   - `CloudWatchAgentServerPolicy`

4. **カスタムポリシー（必要に応じて）**
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
       },
       {
         "Effect": "Allow",
         "Action": [
           "cloudwatch:PutMetricData"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

## 4. EC2インスタンスの作成

### インスタンス設定

```
名前: laravel-otel-ec2
AMI: Amazon Linux 2023
インスタンスタイプ: t3.medium
キーペア: 新規作成または既存のものを選択

ネットワーク設定:
- VPC: laravel-otel-vpc
- サブネット: laravel-otel-public-subnet
- パブリックIPの自動割り当て: 有効
- セキュリティグループ: laravel-otel-ec2-sg

高度な詳細:
- IAMインスタンスプロファイル: laravel-otel-ec2-role

ストレージ:
- サイズ: 20 GiB
- タイプ: gp3
```

### ユーザーデータ（オプション）

EC2起動時に自動実行するスクリプト：

```bash
#!/bin/bash
yum update -y
yum install -y git
```

## 5. RDS PostgreSQLの作成

### データベース作成方法

標準作成を選択

### エンジンオプション

```
エンジンタイプ: PostgreSQL
エンジンバージョン: 15.x
```

### テンプレート

```
本番環境 または 開発/テスト（用途に応じて）
```

### 設定

```
DBインスタンス識別子: laravel-otel-db
マスターユーザー名: postgres
マスターパスワード: 安全なパスワードを設定
```

### インスタンスの設定

```
DBインスタンスクラス: db.t3.micro（開発環境）
                    db.t3.medium（本番環境）
```

### ストレージ

```
ストレージタイプ: gp3
割り当て済みストレージ: 20 GiB
ストレージの自動スケーリング: 有効（最大100 GiB）
```

### 接続

```
VPC: laravel-otel-vpc
DBサブネットグループ: 新規作成
サブネット: laravel-otel-private-subnet-1, laravel-otel-private-subnet-2
パブリックアクセス: なし
VPCセキュリティグループ: laravel-otel-rds-sg
```

### データベース認証

```
パスワード認証
```

### 追加設定

```
初期データベース名: laravel
バックアップ保持期間: 7日間
メンテナンスウィンドウ: 任意の時間帯
```

## 6. 作成後の確認事項

### EC2インスタンス

1. パブリックIPアドレスをメモ
2. SSHで接続可能か確認
   ```bash
   ssh -i your-key.pem ec2-user@<EC2-PUBLIC-IP>
   ```

### RDS

1. エンドポイントをメモ
   例: `laravel-otel-db.xxxxxxxxx.ap-northeast-1.rds.amazonaws.com`

2. EC2からRDSへの接続確認
   ```bash
   # EC2にSSH接続後
   sudo yum install -y postgresql15
   psql -h <RDS-ENDPOINT> -U postgres -d laravel
   ```

## 7. CloudWatchダッシュボードの作成（オプション）

### ダッシュボード設定

1. CloudWatchコンソールで新規ダッシュボードを作成
2. 以下のウィジェットを追加：
   - EC2メトリクス（CPU使用率、ネットワーク）
   - RDSメトリクス（接続数、CPU、ストレージ）
   - X-Rayサービスマップ
   - X-Rayトレース統計

## 8. コスト最適化のヒント

### 開発環境の場合

- EC2: t3.micro または t4g.micro
- RDS: db.t3.micro、シングルAZ
- 使用しない時はインスタンスを停止

### 本番環境の場合

- EC2: Auto Scaling Groupの設定を検討
- RDS: マルチAZ配置、自動バックアップ
- Reserved Instancesの購入を検討

## 9. セキュリティのベストプラクティス

1. **最小権限の原則**
   - IAMロールには必要最小限の権限のみ付与

2. **ネットワークセキュリティ**
   - セキュリティグループで必要なポートのみ開放
   - SSHアクセスは特定のIPからのみ許可

3. **データ保護**
   - RDSの暗号化を有効化
   - バックアップの定期実行

4. **監視とアラート**
   - CloudWatch Alarmsで異常を検知
   - AWS GuardDutyの有効化を検討

## 次のステップ

これらのリソースを作成したら、[EC2_SETUP.md](./EC2_SETUP.md)の手順に従ってアプリケーションをデプロイしてください。
