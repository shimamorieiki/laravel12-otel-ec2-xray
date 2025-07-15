#!/bin/bash

# X-Ray設定の動作確認スクリプト
# Usage: ./setup_xray.sh

set -e

echo "🔍 X-Ray設定の動作確認を開始します..."

# 1. 環境変数の確認
echo "📋 環境変数の確認..."
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "❌ AWS_ACCESS_KEY_ID が設定されていません"
    echo "   以下のコマンドで設定してください："
    echo "   export AWS_ACCESS_KEY_ID=\"your-access-key-id\""
    exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "❌ AWS_SECRET_ACCESS_KEY が設定されていません"
    echo "   以下のコマンドで設定してください："
    echo "   export AWS_SECRET_ACCESS_KEY=\"your-secret-access-key\""
    exit 1
fi

if [ -z "$AWS_DEFAULT_REGION" ]; then
    echo "❌ AWS_DEFAULT_REGION が設定されていません"
    echo "   以下のコマンドで設定してください："
    echo "   export AWS_DEFAULT_REGION=\"ap-northeast-1\""
    exit 1
fi

echo "✅ AWS環境変数が正しく設定されています"

# 2. AWS認証情報の確認
echo "🔐 AWS認証情報の確認..."
if command -v aws &> /dev/null; then
    echo "AWS CLI が見つかりました"
    aws sts get-caller-identity --output table
    echo "✅ AWS認証情報が正しく設定されています"
else
    echo "⚠️  AWS CLI がインストールされていません"
    echo "   認証情報は環境変数から使用されます"
fi

# 3. X-Ray権限の確認
echo "🔍 X-Ray権限の確認..."
if command -v aws &> /dev/null; then
    if aws xray get-sampling-rules --output table 2>/dev/null; then
        echo "✅ X-Ray権限が正しく設定されています"
    else
        echo "❌ X-Ray権限が不足しています"
        echo "   以下の権限を追加してください："
        echo "   - AWSXRayDaemonWriteAccess"
        echo "   - xray:PutTraceSegments"
        echo "   - xray:PutTelemetryRecords"
        exit 1
    fi
fi

# 4. .envファイルの確認
echo "📁 .envファイルの確認..."
if [ -f ".env" ]; then
    echo "✅ .envファイルが存在します"
    
    # 必要な設定の確認
    required_vars=(
        "OTEL_SERVICE_NAME"
        "OTEL_XRAY_ENABLED"
        "OTEL_EXPORTERS"
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "AWS_DEFAULT_REGION"
    )
    
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" .env; then
            echo "✅ ${var} が設定されています"
        else
            echo "❌ ${var} が設定されていません"
            echo "   .envファイルに以下を追加してください："
            case $var in
                "OTEL_SERVICE_NAME")
                    echo "   OTEL_SERVICE_NAME=laravel-app"
                    ;;
                "OTEL_XRAY_ENABLED")
                    echo "   OTEL_XRAY_ENABLED=true"
                    ;;
                "OTEL_EXPORTERS")
                    echo "   OTEL_EXPORTERS=[debug, awsxray]"
                    ;;
                "AWS_ACCESS_KEY_ID")
                    echo "   AWS_ACCESS_KEY_ID=your-access-key-id"
                    ;;
                "AWS_SECRET_ACCESS_KEY")
                    echo "   AWS_SECRET_ACCESS_KEY=your-secret-access-key"
                    ;;
                "AWS_DEFAULT_REGION")
                    echo "   AWS_DEFAULT_REGION=ap-northeast-1"
                    ;;
            esac
        fi
    done
else
    echo "❌ .envファイルが見つかりません"
    echo "   以下のコマンドで作成してください："
    echo "   cp .env.example .env"
    echo "   その後、AWS認証情報を設定してください"
    exit 1
fi

# 5. Docker Composeの確認
echo "🐳 Docker Compose設定の確認..."
if docker-compose ps | grep -q "otel-collector"; then
    echo "✅ OpenTelemetry Collectorが動作中です"
else
    echo "❌ OpenTelemetry Collectorが動作していません"
    echo "   以下のコマンドで起動してください："
    echo "   docker-compose up -d"
    exit 1
fi

# 6. テストリクエストの実行
echo "🧪 テストリクエストの実行..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200"; then
    echo "✅ アプリケーションが正常に動作しています"
    
    # OpenTelemetryテストの実行
    echo "🔬 OpenTelemetryテストの実行..."
    docker-compose exec -T app php artisan otel:test
    
    echo "🎉 X-Ray設定の動作確認が完了しました！"
    echo ""
    echo "次のステップ："
    echo "1. AWS X-Rayコンソールにアクセス"
    echo "2. 'Traces' または 'Service map' でトレースを確認"
    echo "3. 'laravel-app' サービスが表示されることを確認"
    echo ""
    echo "X-Rayコンソール: https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map"
else
    echo "❌ アプリケーションが正常に動作していません"
    echo "   以下のコマンドで問題を確認してください："
    echo "   docker-compose logs app"
    echo "   docker-compose logs otel-collector"
    exit 1
fi 
