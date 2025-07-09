#!/bin/bash

# wget問題修正スクリプト
# Purpose: EC2環境でのwgetエラーを診断・修正
# Usage: ./fix-wget-issues.sh

set -e

echo "🔧 wget問題診断・修正スクリプト"
echo "=================================="
echo ""

# 基本的な診断
echo "📋 基本診断を実行中..."

# 1. wgetの存在確認
echo "1. wgetコマンドの確認..."
if command -v wget &> /dev/null; then
    echo "   ✅ wgetが見つかりました: $(which wget)"
    echo "   バージョン: $(wget --version | head -1)"
else
    echo "   ❌ wgetが見つかりません - インストールします"
    
    # OS判定とインストール
    if command -v yum &> /dev/null; then
        echo "   Amazon Linux/CentOS detected - yumでインストール"
        sudo yum install -y wget
    elif command -v apt-get &> /dev/null; then
        echo "   Ubuntu/Debian detected - aptでインストール"
        sudo apt-get update && sudo apt-get install -y wget
    else
        echo "   ❌ サポートされていないOS"
        exit 1
    fi
    
    # インストール確認
    if command -v wget &> /dev/null; then
        echo "   ✅ wget インストール完了"
    else
        echo "   ❌ wget インストール失敗"
        exit 1
    fi
fi

# 2. ネットワーク接続の確認
echo "2. ネットワーク接続の確認..."
if ping -c 3 8.8.8.8 &> /dev/null; then
    echo "   ✅ インターネット接続: 正常"
else
    echo "   ❌ インターネット接続: 異常"
    echo "   セキュリティグループの設定を確認してください"
    exit 1
fi

# 3. DNS解決の確認
echo "3. DNS解決の確認..."
if nslookup github.com &> /dev/null; then
    echo "   ✅ DNS解決: 正常"
else
    echo "   ❌ DNS解決: 異常"
    echo "   DNS設定を確認してください"
    exit 1
fi

# 4. 時刻設定の確認
echo "4. 時刻設定の確認..."
CURRENT_TIME=$(date +%s)
if [ "$CURRENT_TIME" -gt 1640995200 ]; then  # 2022-01-01以降
    echo "   ✅ 時刻設定: 正常 ($(date))"
else
    echo "   ❌ 時刻設定: 異常 - 修正します"
    sudo timedatectl set-timezone Asia/Tokyo
    if command -v ntpdate &> /dev/null; then
        sudo ntpdate -s time.nist.gov
    fi
    echo "   ✅ 時刻設定修正完了: $(date)"
fi

# 5. CA証明書の確認
echo "5. CA証明書の確認..."
if [ -f /etc/ssl/certs/ca-certificates.crt ] || [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
    echo "   ✅ CA証明書: 存在します"
    
    # CA証明書の更新
    if command -v yum &> /dev/null; then
        sudo yum update -y ca-certificates
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y ca-certificates
    fi
    echo "   ✅ CA証明書更新完了"
else
    echo "   ❌ CA証明書が見つかりません"
    exit 1
fi

# 6. プロキシ設定の確認
echo "6. プロキシ設定の確認..."
if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
    echo "   ⚠️  プロキシ設定が検出されました:"
    echo "   http_proxy: $http_proxy"
    echo "   https_proxy: $https_proxy"
    echo "   必要に応じて解除してください"
else
    echo "   ✅ プロキシ設定: なし"
fi

echo ""
echo "🧪 実際のダウンロードテストを実行中..."

# テストURL一覧
declare -A test_urls=(
    ["GitHub API"]="https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases/latest"
    ["OpenTelemetry Collector"]="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.129.0/otelcol-contrib_0.129.0_linux_amd64.tar.gz"
    ["X-Ray Daemon"]="https://s3.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-linux-3.x.zip"
    ["AWS CLI"]="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
)

# 各URLのテスト
for name in "${!test_urls[@]}"; do
    url="${test_urls[$name]}"
    echo "テスト: $name"
    echo "URL: $url"
    
    # HEADリクエストでテスト
    if curl -I -s --max-time 10 "$url" &> /dev/null; then
        echo "   ✅ curl HEAD: 成功"
    else
        echo "   ❌ curl HEAD: 失敗"
        continue
    fi
    
    # wgetでテスト（スパイダーモード）
    if wget --spider --quiet --timeout=10 "$url" &> /dev/null; then
        echo "   ✅ wget spider: 成功"
    else
        echo "   ❌ wget spider: 失敗"
        
        # 詳細エラー情報を取得
        echo "   詳細エラー情報:"
        wget --spider --timeout=10 "$url" 2>&1 | head -5 | sed 's/^/   /'
    fi
    
    echo ""
done

echo "🔧 修正済みダウンロードコマンド"
echo "==============================="

# 修正済みコマンドの提供
cat << 'EOF'
# OpenTelemetry Collectorのダウンロード（修正版）
wget --timeout=30 --tries=3 \
    "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.129.0/otelcol-contrib_0.129.0_linux_amd64.tar.gz"

# 代替方法（curlを使用）
curl -L -o otelcol-contrib.tar.gz \
    "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.129.0/otelcol-contrib_0.129.0_linux_amd64.tar.gz"

# X-Ray Daemonのダウンロード（修正版）
wget --timeout=30 --tries=3 \
    "https://s3.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-linux-3.x.zip"

# 代替方法（curlを使用）
curl -o xray-daemon.zip \
    "https://s3.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-linux-3.x.zip"

# SSL証明書の問題がある場合（一時的な対処）
wget --no-check-certificate --timeout=30 \
    "https://example.com/file.zip"

# プロキシ環境の場合
wget --proxy=off --timeout=30 \
    "https://example.com/file.zip"
EOF

echo ""
echo "📋 追加の診断コマンド"
echo "===================="

cat << 'EOF'
# 詳細な診断
wget --debug --verbose --timeout=30 "https://example.com/file.zip"

# curlでの代替テスト
curl -v -I --max-time 30 "https://example.com/file.zip"

# ネットワーク経路の確認
traceroute github.com

# DNS設定の確認
cat /etc/resolv.conf

# セキュリティグループの確認（AWS CLI）
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
EOF

echo ""
echo "🎯 よくある問題と解決方法"
echo "========================"

cat << 'EOF'
1. **SSL証明書エラー**
   - 時刻設定の確認: timedatectl status
   - CA証明書の更新: yum update ca-certificates

2. **DNS解決エラー**
   - DNS設定の確認: cat /etc/resolv.conf
   - 代替DNS: echo "nameserver 8.8.8.8" >> /etc/resolv.conf

3. **タイムアウトエラー**
   - --timeout=60 オプションを追加
   - --tries=3 オプションで再試行

4. **プロキシエラー**
   - unset http_proxy https_proxy
   - --proxy=off オプションを使用

5. **セキュリティグループエラー**
   - アウトバウンドルールでHTTPS(443)を許可
   - HTTPSの送信先を0.0.0.0/0に設定
EOF

echo ""
echo "✅ 診断完了！"
echo "問題が解決しない場合は、具体的なエラーメッセージを確認してください。" 
