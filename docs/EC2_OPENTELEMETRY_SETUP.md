

## トラブルシューティング

### 1. OpenTelemetryが接続できない場合

#### 症状
```
OpenTelemetry: [error] Export failure [exception] Export retry limit exceeded
cURL error 7: Failed to connect to 127.0.0.1 port 4317
```

#### 解決方法
```bash
# 一時的にOpenTelemetryを無効化
OTEL_SDK_DISABLED=true php artisan migrate

# OpenTelemetry Collectorの起動確認
sudo systemctl status otel-collector
sudo journalctl -u otel-collector -f

# ポート確認
sudo netstat -tlnp | grep 4318

# サービスの再起動
sudo systemctl restart otel-collector
```

### 2. X-Ray Daemonが動作しない場合

#### 症状
```
X-Ray daemon connection failed
```

#### 解決方法
```bash
# X-Ray Daemonの状態確認
sudo systemctl status xray
sudo journalctl -u xray -f

# ポート確認
sudo netstat -tlnp | grep 2000

# 権限確認
aws sts get-caller-identity
aws xray get-sampling-rules

# サービスの再起動
sudo systemctl restart xray
```

### 3. Nginxの設定問題

#### 症状
```
502 Bad Gateway
```

#### 解決方法
```bash
# Nginxの設定テスト
sudo nginx -t

# PHP-FPMの確認
sudo systemctl status php-fpm

# ソケットファイルの確認
ls -la /var/run/php-fpm/www.sock

# ログの確認
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/php-fpm/www-error.log
```

### 4. データベース接続問題

#### 症状
```
SQLSTATE[08006] [7] could not connect to server
```

#### 解決方法
```bash
# データベース接続テスト
sudo -u nginx php artisan tinker
# DB::connection()->getPdo();

# 設定確認
sudo -u nginx php artisan config:show database.connections.pgsql

# RDSセキュリティグループの確認
# - EC2のセキュリティグループからポート5432への接続を許可
```

### 5. 権限問題

#### 症状
```
Permission denied
```

#### 解決方法
```bash
# ファイル所有権の修正
sudo chown -R nginx:nginx /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 755 /var/www/html/laravel12-otel-ec2-xray
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/storage
sudo chmod -R 775 /var/www/html/laravel12-otel-ec2-xray/bootstrap/cache

# SELinuxの確認（必要に応じて）
sudo setsebool -P httpd_can_network_connect 1
```

## 監視・メンテナンス

### 1. ログ監視

```bash
# アプリケーションログ
sudo tail -f /var/www/html/laravel12-otel-ec2-xray/storage/logs/laravel.log

# Nginxログ
sudo tail -f /var/log/nginx/laravel_access.log
sudo tail -f /var/log/nginx/laravel_error.log

# OpenTelemetryログ
sudo journalctl -u otel-collector -f

# X-Rayログ
sudo journalctl -u xray -f
```

### 2. パフォーマンス監視

```bash
# システムリソース
htop
free -h
df -h

# プロセス監視
sudo systemctl status nginx php-fpm xray otel-collector
```

### 3. AWS X-Rayコンソールでの確認

1. AWS X-Rayコンソールにアクセス
2. 「Service map」でサービス間の関係を確認
3. 「Traces」でトレースの詳細を確認
4. 「Analytics」でパフォーマンス分析

**X-Rayコンソール URL**: https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map

### 4. 定期メンテナンス

```bash
# ログローテーション
sudo logrotate -f /etc/logrotate.d/nginx

# キャッシュクリア
sudo -u nginx php artisan cache:clear
sudo -u nginx php artisan config:cache
sudo -u nginx php artisan route:cache

# セキュリティアップデート
sudo yum update -y
```

### 5. バックアップ

```bash
# アプリケーションのバックアップ
sudo tar -czf /tmp/laravel-backup-$(date +%Y%m%d).tar.gz /var/www/html/laravel12-otel-ec2-xray

# データベースのバックアップ（RDSスナップショット推奨）
pg_dump -h your-rds-endpoint -U your-username -d laravel > /tmp/db-backup-$(date +%Y%m%d).sql
```

## 自動化スクリプト

### 起動スクリプト

```bash
# /home/ec2-user/start-services.sh
#!/bin/bash
sudo systemctl start nginx php-fpm xray otel-collector
echo "All services started successfully"
```

### 停止スクリプト

```bash
# /home/ec2-user/stop-services.sh
#!/bin/bash
sudo systemctl stop nginx php-fpm xray otel-collector
echo "All services stopped successfully"
```

### 状態確認スクリプト

```bash
# /home/ec2-user/check-status.sh
#!/bin/bash
echo "=== Service Status ==="
sudo systemctl status nginx php-fpm xray otel-collector --no-pager

echo -e "\n=== Port Status ==="
sudo netstat -tlnp | grep -E '80|4317|4318|2000'

echo -e "\n=== Health Check ==="
curl -s http://localhost:13133/health && echo "OpenTelemetry Collector: OK"
curl -s http://localhost/ > /dev/null && echo "Application: OK"
```

## まとめ

このガイドに従うことで、EC2上でLaravel + OpenTelemetry + AWS X-Rayの完全な監視環境を構築できます。

### 重要なポイント
1. **セキュリティ**: 必要最小限の権限のみを付与
2. **監視**: 定期的なログ確認とパフォーマンス監視
3. **バックアップ**: 定期的なデータバックアップ
4. **更新**: セキュリティアップデートの定期実施

### 次のステップ
- CI/CD パイプラインの構築
- Auto Scaling の設定
- SSL証明書の設定
- CloudWatch Alarmの設定
- 追加のセキュリティ対策

このドキュメントを参考に、安全で効率的な監視環境を構築してください。 
