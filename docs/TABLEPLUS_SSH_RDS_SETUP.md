# TablePlusでSSH経由RDS接続セットアップガイド

## 目次
1. [概要](#概要)
2. [前提条件](#前提条件)
3. [システム構成](#システム構成)
4. [AWS設定](#aws設定)
5. [EC2設定](#ec2設定)
6. [SSH Local Port Forwarding設定](#ssh-local-port-forwarding設定)
7. [TablePlus設定](#tableplus設定)
8. [接続テスト](#接続テスト)
9. [トラブルシューティング](#トラブルシューティング)
10. [セキュリティ考慮事項](#セキュリティ考慮事項)

## 概要

このドキュメントでは、TablePlusを使用してSSH経由でAWS RDS PostgreSQLに接続する方法を説明します。この構成により、プライベートサブネットのRDSインスタンスに安全にアクセスできます。

### 接続方法

#### 方法1: SSH Local Port Forwarding（推奨）
```
ローカルマシン:5433 → SSH Tunnel → EC2インスタンス → RDS PostgreSQL:5432
```

#### 方法2: TablePlusのSSH Tunnel機能
```
ローカルマシン (TablePlus) → EC2インスタンス (SSHトンネル) → RDS PostgreSQL
```

**推奨理由**: 方法1の方が設定が簡単で、他のDBツールでも再利用可能です。

## 前提条件

### ローカル環境
- **TablePlus**: インストール済み
- **SSH秘密鍵**: EC2インスタンスへのアクセス用

### AWS環境
- **EC2インスタンス**: 起動済み（踏み台サーバーとして使用）
- **RDS PostgreSQL**: 起動済み
- **VPC**: 適切なネットワーク設定

### 必要な情報
- EC2インスタンスのパブリックIP
- RDSエンドポイント
- データベース認証情報
- SSH秘密鍵ファイル

## システム構成

```
┌─────────────────────────────────────────────────────────────────┐
│                     インターネット                                │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                        VPC                                       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                  パブリックサブネット                        │ │
│  │                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │            EC2インスタンス                               │ │ │
│  │  │          (踏み台サーバー)                               │ │ │
│  │  │                                                         │ │ │
│  │  │  - SSH Server (Port 22)                                │ │ │
│  │  │  - PostgreSQL Client                                   │ │ │
│  │  │  - Security Group: SSH允許                             │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                プライベートサブネット                        │ │
│  │                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │            RDS PostgreSQL                               │ │ │
│  │  │                                                         │ │ │
│  │  │  - Database Port: 5432                                 │ │ │
│  │  │  - Security Group: EC2からのみアクセス許可             │ │ │
│  │  │  - Multi-AZ対応                                        │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

接続フロー:
1. TablePlus → EC2 (SSH接続)
2. EC2 → RDS (PostgreSQL接続)
```

## AWS設定

### 1. EC2セキュリティグループの設定

#### EC2インスタンス用セキュリティグループ

```json
{
  "GroupName": "laravel-ec2-sg",
  "Description": "Security group for Laravel EC2 instance",
  "SecurityGroupRules": [
    {
      "IpProtocol": "tcp",
      "FromPort": 22,
      "ToPort": 22,
      "CidrIp": "0.0.0.0/0",
      "Description": "SSH access"
    },
    {
      "IpProtocol": "tcp",
      "FromPort": 80,
      "ToPort": 80,
      "CidrIp": "0.0.0.0/0",
      "Description": "HTTP access"
    },
    {
      "IpProtocol": "tcp",
      "FromPort": 443,
      "ToPort": 443,
      "CidrIp": "0.0.0.0/0",
      "Description": "HTTPS access"
    }
  ]
}
```

#### RDS用セキュリティグループ

```json
{
  "GroupName": "laravel-rds-sg",
  "Description": "Security group for Laravel RDS instance",
  "SecurityGroupRules": [
    {
      "IpProtocol": "tcp",
      "FromPort": 5432,
      "ToPort": 5432,
      "SourceSecurityGroupId": "sg-xxxxxxxxx",
      "Description": "PostgreSQL access from EC2"
    }
  ]
}
```

### 2. RDSサブネットグループの設定

```bash
# RDSサブネットグループの作成
aws rds create-db-subnet-group \
    --db-subnet-group-name laravel-subnet-group \
    --db-subnet-group-description "Subnet group for Laravel RDS" \
    --subnet-ids subnet-xxxxxxxxx subnet-yyyyyyyyy \
    --region ap-northeast-1
```

### 3. RDSパラメータグループの設定

```bash
# PostgreSQL用パラメータグループの作成
aws rds create-db-parameter-group \
    --db-parameter-group-name laravel-postgres-params \
    --db-parameter-group-family postgres15 \
    --description "Parameter group for Laravel PostgreSQL" \
    --region ap-northeast-1

# パラメータの設定
aws rds modify-db-parameter-group \
    --db-parameter-group-name laravel-postgres-params \
    --parameters "ParameterName=log_statement,ParameterValue=all,ApplyMethod=pending-reboot" \
    --region ap-northeast-1
```

## EC2設定

### 1. PostgreSQLクライアントのインストール

```bash
# EC2インスタンスにSSH接続後、PostgreSQLクライアントをインストール
sudo yum update -y
sudo yum install -y postgresql15

# インストール確認
psql --version
```

### 2. SSH設定の確認

```bash
# SSH設定ファイルの確認
sudo cat /etc/ssh/sshd_config

# 重要な設定項目
# Port 22
# PermitRootLogin no
# PasswordAuthentication no
# PubkeyAuthentication yes
# AuthorizedKeysFile .ssh/authorized_keys

# SSH サービスの再起動（設定変更した場合）
sudo systemctl restart sshd
```

### 3. RDS接続テスト

```bash
# EC2からRDSへの接続テスト
psql -h your-rds-endpoint.amazonaws.com -U your-username -d your-database

# 例：
psql -h laravel-db.c1234567890.ap-northeast-1.rds.amazonaws.com -U postgres -d laravel
```

### 4. 接続情報の確認

```bash
# RDSエンドポイントの確認
aws rds describe-db-instances \
    --db-instance-identifier your-db-instance-id \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text \
    --region ap-northeast-1

# セキュリティグループの確認
aws ec2 describe-security-groups \
    --group-ids sg-xxxxxxxxx \
    --region ap-northeast-1
```

## SSH Local Port Forwarding設定

### 1. SSH Configファイルの設定

SSH Local Port Forwardingを使用することで、ローカルマシンからRDSに直接アクセスできます。

#### ~/.ssh/configファイルの編集

```bash
# ~/.ssh/configファイルを作成・編集
nano ~/.ssh/config
```

#### 設定例

```bash
# Laravel RDS接続用のSSH設定
Host laravel-rds
    HostName your-ec2-public-ip
    User ec2-user
    IdentityFile ~/.ssh/your-private-key.pem
    LocalForward 5433 your-rds-endpoint:5432
    ServerAliveInterval 60
    ServerAliveCountMax 3
    
# 例：
Host laravel-rds
    HostName 54.123.456.789
    User ec2-user
    IdentityFile ~/.ssh/laravel-key.pem
    LocalForward 5433 laravel-db.c1234567890.ap-northeast-1.rds.amazonaws.com:5432
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

#### 設定項目の説明

- **Host**: 接続時に使用するエイリアス名
- **HostName**: EC2インスタンスのパブリックIP
- **User**: SSHユーザー名（通常は`ec2-user`）
- **IdentityFile**: SSH秘密鍵のパス
- **LocalForward**: ローカルポート → RDSエンドポイント:ポート
- **ServerAliveInterval**: 接続維持のためのハートビート間隔
- **ServerAliveCountMax**: 接続試行回数

### 2. SSH Tunnelの開始

```bash
# SSH Tunnelを開始
ssh laravel-rds

# バックグラウンドで実行する場合
ssh -f -N laravel-rds

# 確認
ps aux | grep ssh
```

### 3. 接続確認

```bash
# ローカルマシンからポート転送の確認
netstat -an | grep 5433

# PostgreSQLクライアントでの接続テスト
psql -h localhost -p 5433 -U your-username -d your-database
```

### 4. 自動接続スクリプト

#### 接続スクリプトの作成

```bash
#!/bin/bash
# connect-rds.sh

echo "Starting SSH tunnel to RDS..."
ssh -f -N laravel-rds

# 接続確認
if netstat -an | grep -q 5433; then
    echo "✅ SSH tunnel is active (localhost:5433)"
    echo "You can now connect to RDS using localhost:5433"
else
    echo "❌ SSH tunnel failed to start"
    exit 1
fi
```

#### 切断スクリプトの作成

```bash
#!/bin/bash
# disconnect-rds.sh

echo "Stopping SSH tunnel to RDS..."
pkill -f "ssh.*laravel-rds"

if ! netstat -an | grep -q 5433; then
    echo "✅ SSH tunnel stopped"
else
    echo "⚠️  SSH tunnel might still be running"
fi
```

### 5. 高度な設定

#### 複数のRDSインスタンスへの接続

```bash
# ~/.ssh/config
Host laravel-rds-prod
    HostName your-ec2-public-ip
    User ec2-user
    IdentityFile ~/.ssh/laravel-key.pem
    LocalForward 5433 prod-rds-endpoint:5432
    
Host laravel-rds-staging
    HostName your-ec2-public-ip
    User ec2-user
    IdentityFile ~/.ssh/laravel-key.pem
    LocalForward 5434 staging-rds-endpoint:5432
```

#### 自動再接続設定

```bash
# ~/.ssh/config
Host laravel-rds
    HostName your-ec2-public-ip
    User ec2-user
    IdentityFile ~/.ssh/laravel-key.pem
    LocalForward 5433 your-rds-endpoint:5432
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
    TCPKeepAlive yes
    ConnectTimeout 10
```

### 6. 接続状態の監視

```bash
#!/bin/bash
# monitor-ssh-tunnel.sh

while true; do
    if ! netstat -an | grep -q 5433; then
        echo "SSH tunnel is down. Reconnecting..."
        ssh -f -N laravel-rds
        sleep 5
    else
        echo "SSH tunnel is active"
    fi
    sleep 30
done
```

## TablePlus設定

### 方法1: SSH Local Port Forwarding使用時の設定（推奨）

SSH Local Port Forwardingを設定済みの場合の設定方法です。

#### 1. 新しい接続の作成

1. **TablePlusを起動**
2. **「Create a new connection」をクリック**
3. **「PostgreSQL」を選択**

#### 2. 基本設定

**General タブ**
```
Name: Laravel Production DB
Color: お好みの色を選択
```

**Connection タブ**
```
Host: localhost
Port: 5433 (SSH configで設定したLocalForwardポート)
User: your-database-username
Password: your-database-password
Database: your-database-name
```

**SSH タブ**
```
✅ SSHトンネルは使用しない（既にSSH tunnelが動作中のため）
```

#### 3. 接続手順

1. **SSH tunnelを開始**
   ```bash
   ssh -f -N laravel-rds
   ```

2. **TablePlusで接続**
   - 「Test Connection」をクリック
   - 接続成功を確認

3. **使用後はSSH tunnelを停止**
   ```bash
   pkill -f "ssh.*laravel-rds"
   ```

### 方法2: TablePlusのSSH Tunnel機能使用時の設定

#### 1. 新しい接続の作成

1. **TablePlusを起動**
2. **「Create a new connection」をクリック**
3. **「PostgreSQL」を選択**

#### 2. 基本設定

**General タブ**
```
Name: Laravel Production DB
Color: お好みの色を選択
```

**Connection タブ**
```
Host: localhost (重要: RDSエンドポイントではなくlocalhost)
Port: 5432
User: your-database-username
Password: your-database-password
Database: your-database-name
```

**注意**: HostはRDSエンドポイントではなく`localhost`を指定します。これはSSHトンネル経由でアクセスするためです。

#### 3. SSH設定

**SSH タブ**
```
✅ Use SSH Tunnel

SSH Host: your-ec2-public-ip
SSH Port: 22
SSH User: ec2-user (Amazon Linux 2の場合)
```

**SSH認証方法**

*秘密鍵認証の場合 (推奨)*:
```
Authentication: Public Key
Private Key: /path/to/your/private-key.pem
```

*パスワード認証の場合*:
```
Authentication: Password
Password: your-ssh-password
```

#### 4. 高度な設定

**Advanced タブ**
```
Connection Timeout: 30
Query Timeout: 30
SSL Mode: prefer (RDSでSSLを有効にしている場合)
```

### 設定比較

| 項目 | 方法1 (SSH Local Port Forwarding) | 方法2 (TablePlus SSH Tunnel) |
|------|-----------------------------------|------------------------------|
| 設定の簡単さ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 他ツールでの再利用 | ⭐⭐⭐⭐⭐ | ⭐ |
| 接続の安定性 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 複数DB接続 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 自動化 | ⭐⭐⭐⭐⭐ | ⭐⭐ |

### 接続設定の例

#### 方法1の設定例

```yaml
# SSH Config (~/.ssh/config)
Host laravel-rds
    HostName 54.123.456.789
    User ec2-user
    IdentityFile ~/.ssh/laravel-key.pem
    LocalForward 5433 laravel-db.c1234567890.ap-northeast-1.rds.amazonaws.com:5432

# TablePlus設定
Name: Laravel Production DB
Host: localhost
Port: 5433
User: laravel_user
Password: your_secure_password
Database: laravel
SSH Tunnel: 使用しない
```

#### 方法2の設定例

```yaml
# TablePlus設定
Name: Laravel Production DB
Host: localhost
Port: 5432
User: laravel_user
Password: your_secure_password
Database: laravel

# SSH設定
Use SSH Tunnel: ✅
SSH Host: 54.123.456.789
SSH Port: 22
SSH User: ec2-user
Authentication: Public Key
Private Key: /Users/username/.ssh/laravel-key.pem
```

## 接続テスト

### 方法1: SSH Local Port Forwardingを使用した接続テスト

#### 1. SSH Tunnelテスト

```bash
# SSH Tunnelを開始
ssh -f -N laravel-rds

# ポート転送の確認
netstat -an | grep 5433
# 出力例: tcp4   0      0  127.0.0.1.5433         *.*                    LISTEN

# SSH プロセスの確認
ps aux | grep ssh | grep laravel-rds
```

#### 2. データベース接続テスト

```bash
# PostgreSQLクライアントでの接続テスト
psql -h localhost -p 5433 -U your-username -d your-database

# 接続成功の確認
\l  # データベース一覧
\dt # テーブル一覧
\q  # 終了
```

#### 3. TablePlusでの接続テスト

1. **SSH Tunnelが動作中であることを確認**
   ```bash
   netstat -an | grep 5433
   ```

2. **TablePlusで接続**
   - Host: localhost
   - Port: 5433
   - 「Test Connection」ボタンをクリック

3. **成功メッセージの確認**

### 方法2: TablePlus SSH Tunnel機能を使用した接続テスト

#### 1. SSH接続テスト

```bash
# ローカルマシンからEC2への接続テスト
ssh -i /path/to/your-key.pem ec2-user@your-ec2-public-ip

# 接続成功後、EC2からRDSへの接続テスト
psql -h your-rds-endpoint -U your-username -d your-database
```

#### 2. TablePlusでの接続テスト

1. **「Test Connection」ボタンをクリック**
2. **成功メッセージの確認**
3. **データベースへの接続**

### 3. 接続確認クエリ

```sql
-- データベースバージョンの確認
SELECT version();

-- 現在の接続情報
SELECT 
    current_database(),
    current_user,
    inet_server_addr(),
    inet_server_port();

-- テーブル一覧
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public';

-- Laravelのマイグレーション状態確認
SELECT * FROM migrations ORDER BY batch DESC, migration DESC;
```

## トラブルシューティング

### 1. SSH Local Port Forwardingエラー

#### エラー: "bind: Address already in use"
```bash
# 解決方法
1. ポート5433が既に使用されているか確認
netstat -an | grep 5433

2. 使用中のプロセスを確認
lsof -i :5433

3. 既存のSSH tunnelを停止
pkill -f "ssh.*laravel-rds"

4. 別のポートを使用
# ~/.ssh/configでLocalForwardポートを変更
LocalForward 5434 your-rds-endpoint:5432
```

#### エラー: "Connection refused to localhost:5433"
```bash
# 解決方法
1. SSH tunnelが正常に動作しているか確認
ps aux | grep ssh

2. SSH tunnelを再起動
pkill -f "ssh.*laravel-rds"
ssh -f -N laravel-rds

3. ポート転送の確認
netstat -an | grep 5433
```

### 2. SSH接続エラー

#### エラー: "Connection refused"
```bash
# 解決方法
1. EC2インスタンスが起動しているか確認
2. セキュリティグループでポート22が開いているか確認
3. 正しいパブリックIPを使用しているか確認

# AWS CLIでの確認
aws ec2 describe-instances --instance-ids i-1234567890abcdef0
```

#### エラー: "Permission denied (publickey)"
```bash
# 解決方法
1. 秘密鍵ファイルの権限を確認
chmod 600 /path/to/your-key.pem

2. 正しいユーザー名を使用しているか確認
# Amazon Linux 2: ec2-user
# Ubuntu: ubuntu
# CentOS: centos

3. 秘密鍵が正しいか確認
ssh-keygen -y -f /path/to/your-key.pem
```

### 2. データベース接続エラー

#### エラー: "Connection timed out"
```bash
# 解決方法
1. RDSセキュリティグループの確認
2. EC2からRDSへの接続テスト
psql -h your-rds-endpoint -U your-username -d your-database

3. ネットワーク設定の確認
```

#### エラー: "Authentication failed"
```bash
# 解決方法
1. データベース認証情報の確認
2. RDSパラメータグループの確認
3. データベースユーザーの権限確認

# RDSでのユーザー作成例
CREATE USER laravel_user WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE laravel TO laravel_user;
```

### 3. SSL接続エラー

#### エラー: "SSL connection failed"
```bash
# 解決方法
1. SSL証明書のダウンロード
wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

2. TablePlusでのSSL設定
SSL Mode: require
SSL Certificate: /path/to/global-bundle.pem
```

### 4. パフォーマンス問題

#### 遅い接続
```bash
# 解決方法
1. 接続タイムアウトの調整
Connection Timeout: 60
Query Timeout: 120

2. SSH圧縮の有効化
SSH設定でCompression: yes

3. 接続プールの使用
Keep Alive: 60
```

## セキュリティ考慮事項

### 1. SSH設定のベストプラクティス

```bash
# /etc/ssh/sshd_config の推奨設定
Port 22
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 3
MaxSessions 10
```

### 2. セキュリティグループの最小権限原則

```bash
# EC2セキュリティグループ: 特定のIPからのみSSH許可
{
  "IpProtocol": "tcp",
  "FromPort": 22,
  "ToPort": 22,
  "CidrIp": "your-office-ip/32",
  "Description": "SSH access from office"
}

# RDSセキュリティグループ: EC2からのみアクセス許可
{
  "IpProtocol": "tcp",
  "FromPort": 5432,
  "ToPort": 5432,
  "SourceSecurityGroupId": "sg-ec2-instance",
  "Description": "PostgreSQL access from EC2"
}
```

### 3. 認証情報の管理

```bash
# AWS Secrets Managerの使用
aws secretsmanager create-secret \
    --name laravel/database \
    --description "Database credentials for Laravel" \
    --secret-string '{"username":"laravel_user","password":"secure_password"}'

# 秘密鍵の安全な管理
chmod 600 ~/.ssh/laravel-key.pem
# 秘密鍵はバージョン管理に含めない
echo "*.pem" >> .gitignore
```

### 4. 監査とログ

```bash
# SSH接続ログの確認
sudo tail -f /var/log/secure

# RDS接続ログの確認
# CloudWatch Logsでログを確認

# 接続履歴の記録
# TablePlusの接続ログを定期的に確認
```

## 自動化スクリプト

### 1. SSH Local Port Forwarding管理スクリプト

#### 統合管理スクリプト

```bash
#!/bin/bash
# rds-tunnel.sh

ACTION=$1
HOST_CONFIG="laravel-rds"
LOCAL_PORT=5433
DB_USER="your-db-user"
DB_NAME="your-db-name"

case $ACTION in
    start)
        echo "Starting SSH tunnel..."
        if netstat -an | grep -q $LOCAL_PORT; then
            echo "⚠️  Port $LOCAL_PORT is already in use"
            exit 1
        fi
        
        ssh -f -N $HOST_CONFIG
        
        # 接続確認
        sleep 2
        if netstat -an | grep -q $LOCAL_PORT; then
            echo "✅ SSH tunnel started successfully (localhost:$LOCAL_PORT)"
        else
            echo "❌ Failed to start SSH tunnel"
            exit 1
        fi
        ;;
    
    stop)
        echo "Stopping SSH tunnel..."
        pkill -f "ssh.*$HOST_CONFIG"
        
        # 停止確認
        sleep 1
        if ! netstat -an | grep -q $LOCAL_PORT; then
            echo "✅ SSH tunnel stopped successfully"
        else
            echo "⚠️  SSH tunnel might still be running"
        fi
        ;;
    
    status)
        if netstat -an | grep -q $LOCAL_PORT; then
            echo "✅ SSH tunnel is active (localhost:$LOCAL_PORT)"
            ps aux | grep ssh | grep $HOST_CONFIG
        else
            echo "❌ SSH tunnel is not active"
        fi
        ;;
    
    test)
        echo "Testing SSH tunnel connection..."
        if netstat -an | grep -q $LOCAL_PORT; then
            echo "✅ SSH tunnel is active"
            
            # データベース接続テスト
            if command -v psql &> /dev/null; then
                echo "Testing database connection..."
                if psql -h localhost -p $LOCAL_PORT -U $DB_USER -d $DB_NAME -c 'SELECT 1;' &> /dev/null; then
                    echo "✅ Database connection: OK"
                else
                    echo "❌ Database connection: FAILED"
                fi
            else
                echo "⚠️  psql not found, skipping database test"
            fi
        else
            echo "❌ SSH tunnel is not active"
        fi
        ;;
    
    restart)
        echo "Restarting SSH tunnel..."
        $0 stop
        sleep 2
        $0 start
        ;;
    
    *)
        echo "Usage: $0 {start|stop|status|test|restart}"
        echo ""
        echo "Commands:"
        echo "  start   - Start SSH tunnel"
        echo "  stop    - Stop SSH tunnel"
        echo "  status  - Check SSH tunnel status"
        echo "  test    - Test SSH tunnel and database connection"
        echo "  restart - Restart SSH tunnel"
        exit 1
        ;;
esac
```

#### 使用方法

```bash
# 実行権限を付与
chmod +x rds-tunnel.sh

# SSH tunnelを開始
./rds-tunnel.sh start

# 状態確認
./rds-tunnel.sh status

# 接続テスト
./rds-tunnel.sh test

# SSH tunnelを停止
./rds-tunnel.sh stop

# 再起動
./rds-tunnel.sh restart
```

### 2. 接続テストスクリプト

```bash
#!/bin/bash
# check-connection.sh

EC2_HOST="your-ec2-public-ip"
RDS_HOST="your-rds-endpoint"
SSH_KEY="/path/to/your-key.pem"
DB_USER="your-db-user"
DB_NAME="your-db-name"

echo "=== SSH Connection Test ==="
if ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$EC2_HOST "echo 'SSH connection successful'"; then
    echo "✅ SSH connection: OK"
else
    echo "❌ SSH connection: FAILED"
    exit 1
fi

echo "=== Database Connection Test ==="
if ssh -i $SSH_KEY ec2-user@$EC2_HOST "psql -h $RDS_HOST -U $DB_USER -d $DB_NAME -c 'SELECT 1;'"; then
    echo "✅ Database connection: OK"
else
    echo "❌ Database connection: FAILED"
    exit 1
fi

echo "=== All tests passed! ==="
```

### 2. 環境情報収集スクリプト

```bash
#!/bin/bash
# collect-info.sh

echo "=== AWS Environment Information ==="
echo "EC2 Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "EC2 Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "EC2 Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"

echo "=== RDS Information ==="
aws rds describe-db-instances --query 'DBInstances[].{DBInstanceIdentifier:DBInstanceIdentifier,Engine:Engine,DBInstanceStatus:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port}' --output table
```

## 定期メンテナンス

### 1. 接続情報の更新

```bash
# 週次での接続テスト
# 設定変更時の確認
# SSL証明書の更新確認
```

### 2. セキュリティ監査

```bash
# 月次でのセキュリティグループ確認
# SSH接続ログの確認  
# 不要な接続の削除
```

### 3. パフォーマンス監視

```bash
# 接続時間の監視
# クエリ実行時間の監視
# リソース使用量の確認
```

## まとめ

このガイドに従うことで、TablePlusを使用してSSH経由でAWS RDSに安全に接続できます。

### 推奨接続方法

**SSH Local Port Forwarding（方法1）を強く推奨します**

**理由**:
- 設定が簡単で直感的
- 他のデータベースツールでも再利用可能
- 接続の安定性が高い
- 複数のデータベースへの同時接続が容易
- 自動化スクリプトによる管理が可能

### 設定手順まとめ

#### 1. SSH Config設定
```bash
# ~/.ssh/config
Host laravel-rds
    HostName your-ec2-public-ip
    User ec2-user
    IdentityFile ~/.ssh/your-key.pem
    LocalForward 5433 your-rds-endpoint:5432
```

#### 2. SSH Tunnel開始
```bash
ssh -f -N laravel-rds
```

#### 3. TablePlus接続
```
Host: localhost
Port: 5433
SSH Tunnel: 使用しない
```

### 重要なポイント
1. **セキュリティ**: 最小権限の原則に従う
2. **監視**: 接続とアクセスログを定期的に確認
3. **メンテナンス**: 定期的な設定確認と更新
4. **バックアップ**: 設定情報の適切な管理
5. **自動化**: 管理スクリプトの活用

### 次のステップ
- SSL証明書の設定
- 読み取り専用レプリカへの接続設定
- 監視とアラートの設定
- 自動バックアップの確認
- 複数環境（dev/staging/prod）への対応

この設定により、安全で効率的なデータベース管理環境を構築できます。 
