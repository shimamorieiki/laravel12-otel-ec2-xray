#!/bin/bash

# CloudWatch Agent設定修正スクリプト
# Purpose: traceセクションを削除してOpenTelemetry Collectorとの競合を解決
# Usage: sudo ./fix-cloudwatch-agent-config.sh

set -e

echo "🔧 CloudWatch Agent設定修正スクリプト"
echo "=========================================="
echo "目的: traceセクションを削除してOpenTelemetry Collectorとの競合を解決"
echo ""

# 権限チェック
if [[ $EUID -ne 0 ]]; then
   echo "❌ このスクリプトはroot権限で実行してください"
   echo "   使用方法: sudo ./fix-cloudwatch-agent-config.sh"
   exit 1
fi

CONFIG_FILE="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# CloudWatch Agentの設定ファイルが存在するかチェック
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ CloudWatch Agentの設定ファイルが見つかりません: $CONFIG_FILE"
    echo "   CloudWatch Agentがインストールされていない可能性があります"
    exit 1
fi

echo "📋 現在の設定を確認中..."

# traceセクションの存在確認
if grep -q '"traces"' "$CONFIG_FILE"; then
    echo "⚠️  traceセクションが見つかりました - 削除が必要です"
    NEEDS_FIX=true
else
    echo "✅ traceセクションは既に削除されています"
    NEEDS_FIX=false
fi

# ポート使用状況の確認
echo "🔍 ポート使用状況を確認中..."
if lsof -i :4317 -i :4318 >/dev/null 2>&1; then
    echo "⚠️  ポート4317/4318が使用中です："
    lsof -i :4317 -i :4318 | grep -E "(COMMAND|4317|4318)"
else
    echo "✅ ポート4317/4318は空いています"
fi

if [[ "$NEEDS_FIX" == "false" ]]; then
    echo ""
    echo "✅ 修正は不要です。現在の設定は正常です。"
    exit 0
fi

echo ""
echo "🛠️  修正を開始します..."

# ステップ1: バックアップ作成
echo "1. 設定ファイルのバックアップを作成中..."
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "   バックアップ作成完了: $BACKUP_FILE"

# ステップ2: traceセクションの削除
echo "2. traceセクションを削除中..."

# jqコマンドが使用可能かチェック
if command -v jq &> /dev/null; then
    echo "   jqコマンドを使用してtraceセクションを削除..."
    jq 'del(.traces)' "$CONFIG_FILE" > /tmp/cloudwatch-agent-config.json
    cp /tmp/cloudwatch-agent-config.json "$CONFIG_FILE"
    rm /tmp/cloudwatch-agent-config.json
    echo "   ✅ jqコマンドでtraceセクションを削除しました"
else
    echo "   jqコマンドが見つかりません - 手動での削除が必要です"
    echo "   以下のコマンドを実行してください："
    echo "   sudo nano $CONFIG_FILE"
    echo "   そして以下のセクションを削除してください："
    echo '   "traces": {'
    echo '     "traces_collected": {'
    echo '       "otlp": {'
    echo '         "grpc_endpoint": "127.0.0.1:4317",'
    echo '         "http_endpoint": "127.0.0.1:4318"'
    echo '       }'
    echo '     }'
    echo '   },'
    exit 1
fi

# ステップ3: 設定ファイルの検証
echo "3. 設定ファイルの検証中..."
if python3 -m json.tool "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "   ✅ JSON構文: 正常"
else
    echo "   ❌ JSON構文エラーが発生しました"
    echo "   設定ファイルをバックアップから復元します..."
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    exit 1
fi

# traceセクションが削除されたことを確認
if grep -q '"traces"' "$CONFIG_FILE"; then
    echo "   ❌ traceセクションの削除に失敗しました"
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    exit 1
else
    echo "   ✅ traceセクション削除: 完了"
fi

# ステップ4: サービスの再起動
echo "4. サービスの再起動中..."

# CloudWatch Agentを停止
echo "   CloudWatch Agentを停止中..."
systemctl stop amazon-cloudwatch-agent
sleep 2

# ポートが開放されたことを確認
if lsof -i :4317 -i :4318 >/dev/null 2>&1; then
    echo "   ⚠️  ポート4317/4318がまだ使用中です"
    lsof -i :4317 -i :4318 | grep -E "(COMMAND|4317|4318)"
    echo "   5秒待機してから再確認します..."
    sleep 5
fi

# CloudWatch Agentを起動
echo "   CloudWatch Agentを起動中..."
systemctl start amazon-cloudwatch-agent
sleep 2

# 起動状態の確認
if systemctl is-active --quiet amazon-cloudwatch-agent; then
    echo "   ✅ CloudWatch Agent: 正常に起動しました"
else
    echo "   ❌ CloudWatch Agentの起動に失敗しました"
    echo "   ログを確認してください: sudo journalctl -u amazon-cloudwatch-agent -f"
fi

# OpenTelemetry Collectorの起動確認
echo "   OpenTelemetry Collectorの起動を確認中..."
if systemctl is-active --quiet otel-collector; then
    echo "   ✅ OpenTelemetry Collector: 既に起動しています"
else
    echo "   OpenTelemetry Collectorを起動中..."
    systemctl start otel-collector
    sleep 2
    if systemctl is-active --quiet otel-collector; then
        echo "   ✅ OpenTelemetry Collector: 正常に起動しました"
    else
        echo "   ❌ OpenTelemetry Collectorの起動に失敗しました"
        echo "   ログを確認してください: sudo journalctl -u otel-collector -f"
    fi
fi

# ステップ5: 最終確認
echo "5. 最終確認中..."

# ポート使用状況の確認
echo "   ポート使用状況："
if lsof -i :4317 -i :4318 -i :2000 >/dev/null 2>&1; then
    lsof -i :4317 -i :4318 -i :2000 | grep -E "(COMMAND|4317|4318|2000)"
else
    echo "   ⚠️  必要なポートが開放されていません"
fi

# サービス状態の確認
echo "   サービス状態："
systemctl is-active amazon-cloudwatch-agent otel-collector xray | while read service status; do
    if [[ "$status" == "active" ]]; then
        echo "   ✅ $service: 正常"
    else
        echo "   ❌ $service: 異常 ($status)"
    fi
done

echo ""
echo "🎉 設定修正が完了しました！"
echo ""
echo "📋 確認事項："
echo "1. CloudWatch Agent: システムメトリクス + ログ収集のみ"
echo "2. OpenTelemetry Collector: トレース + 分散メトリクス処理"
echo "3. X-Ray Daemon: トレースの最終送信先"
echo ""
echo "🔍 動作確認："
echo "sudo journalctl -u otel-collector -f --lines=10 | grep -E 'awsxray|TracesExporter'"
echo ""
echo "📄 バックアップファイル: $BACKUP_FILE"
echo "   問題が発生した場合は以下のコマンドで復元できます："
echo "   sudo cp $BACKUP_FILE $CONFIG_FILE"
echo "   sudo systemctl restart amazon-cloudwatch-agent" 
