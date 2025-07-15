# X-Ray設定の動作確認スクリプト（PowerShell版）
# Usage: .\setup_xray.ps1

$ErrorActionPreference = "Stop"

Write-Host "🔍 X-Ray設定の動作確認を開始します..." -ForegroundColor Green

# 1. 環境変数の確認
Write-Host "📋 環境変数の確認..." -ForegroundColor Yellow
if (-not $env:AWS_ACCESS_KEY_ID) {
    Write-Host "❌ AWS_ACCESS_KEY_ID が設定されていません" -ForegroundColor Red
    Write-Host "   以下のコマンドで設定してください：" -ForegroundColor Yellow
    Write-Host "   `$env:AWS_ACCESS_KEY_ID=`"your-access-key-id`"" -ForegroundColor Cyan
    exit 1
}

if (-not $env:AWS_SECRET_ACCESS_KEY) {
    Write-Host "❌ AWS_SECRET_ACCESS_KEY が設定されていません" -ForegroundColor Red
    Write-Host "   以下のコマンドで設定してください：" -ForegroundColor Yellow
    Write-Host "   `$env:AWS_SECRET_ACCESS_KEY=`"your-secret-access-key`"" -ForegroundColor Cyan
    exit 1
}

if (-not $env:AWS_DEFAULT_REGION) {
    Write-Host "❌ AWS_DEFAULT_REGION が設定されていません" -ForegroundColor Red
    Write-Host "   以下のコマンドで設定してください：" -ForegroundColor Yellow
    Write-Host "   `$env:AWS_DEFAULT_REGION=`"ap-northeast-1`"" -ForegroundColor Cyan
    exit 1
}

Write-Host "✅ AWS環境変数が正しく設定されています" -ForegroundColor Green

# 2. AWS認証情報の確認
Write-Host "🔐 AWS認証情報の確認..." -ForegroundColor Yellow
if (Get-Command aws -ErrorAction SilentlyContinue) {
    Write-Host "AWS CLI が見つかりました" -ForegroundColor Green
    aws sts get-caller-identity --output table
    Write-Host "✅ AWS認証情報が正しく設定されています" -ForegroundColor Green
} else {
    Write-Host "⚠️  AWS CLI がインストールされていません" -ForegroundColor Yellow
    Write-Host "   認証情報は環境変数から使用されます" -ForegroundColor Yellow
}

# 3. X-Ray権限の確認
Write-Host "🔍 X-Ray権限の確認..." -ForegroundColor Yellow
if (Get-Command aws -ErrorAction SilentlyContinue) {
    try {
        aws xray get-sampling-rules --output table 2>$null
        Write-Host "✅ X-Ray権限が正しく設定されています" -ForegroundColor Green
    } catch {
        Write-Host "❌ X-Ray権限が不足しています" -ForegroundColor Red
        Write-Host "   以下の権限を追加してください：" -ForegroundColor Yellow
        Write-Host "   - AWSXRayDaemonWriteAccess" -ForegroundColor Cyan
        Write-Host "   - xray:PutTraceSegments" -ForegroundColor Cyan
        Write-Host "   - xray:PutTelemetryRecords" -ForegroundColor Cyan
        exit 1
    }
}

# 4. .envファイルの確認
Write-Host "📁 .envファイルの確認..." -ForegroundColor Yellow
if (Test-Path ".env") {
    Write-Host "✅ .envファイルが存在します" -ForegroundColor Green
    
    # 必要な設定の確認
    $requiredVars = @(
        "OTEL_SERVICE_NAME",
        "OTEL_XRAY_ENABLED",
        "OTEL_EXPORTERS",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_DEFAULT_REGION"
    )
    
    $envContent = Get-Content ".env"
    
    foreach ($var in $requiredVars) {
        if ($envContent -match "^$var=") {
            Write-Host "✅ $var が設定されています" -ForegroundColor Green
        } else {
            Write-Host "❌ $var が設定されていません" -ForegroundColor Red
            Write-Host "   .envファイルに以下を追加してください：" -ForegroundColor Yellow
            switch ($var) {
                "OTEL_SERVICE_NAME" { Write-Host "   OTEL_SERVICE_NAME=laravel-app" -ForegroundColor Cyan }
                "OTEL_XRAY_ENABLED" { Write-Host "   OTEL_XRAY_ENABLED=true" -ForegroundColor Cyan }
                "OTEL_EXPORTERS" { Write-Host "   OTEL_EXPORTERS=[debug, awsxray]" -ForegroundColor Cyan }
                "AWS_ACCESS_KEY_ID" { Write-Host "   AWS_ACCESS_KEY_ID=your-access-key-id" -ForegroundColor Cyan }
                "AWS_SECRET_ACCESS_KEY" { Write-Host "   AWS_SECRET_ACCESS_KEY=your-secret-access-key" -ForegroundColor Cyan }
                "AWS_DEFAULT_REGION" { Write-Host "   AWS_DEFAULT_REGION=ap-northeast-1" -ForegroundColor Cyan }
            }
        }
    }
} else {
    Write-Host "❌ .envファイルが見つかりません" -ForegroundColor Red
    Write-Host "   以下のコマンドで作成してください：" -ForegroundColor Yellow
    Write-Host "   Copy-Item .env.example .env" -ForegroundColor Cyan
    Write-Host "   その後、AWS認証情報を設定してください" -ForegroundColor Yellow
    exit 1
}

# 5. Docker Composeの確認
Write-Host "🐳 Docker Compose設定の確認..." -ForegroundColor Yellow
$dockerStatus = docker-compose ps
if ($dockerStatus -match "otel-collector") {
    Write-Host "✅ OpenTelemetry Collectorが動作中です" -ForegroundColor Green
} else {
    Write-Host "❌ OpenTelemetry Collectorが動作していません" -ForegroundColor Red
    Write-Host "   以下のコマンドで起動してください：" -ForegroundColor Yellow
    Write-Host "   docker-compose up -d" -ForegroundColor Cyan
    exit 1
}

# 6. テストリクエストの実行
Write-Host "🧪 テストリクエストの実行..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ アプリケーションが正常に動作しています" -ForegroundColor Green
        
        # OpenTelemetryテストの実行
        Write-Host "🔬 OpenTelemetryテストの実行..." -ForegroundColor Yellow
        docker-compose exec -T app php artisan otel:test
        
        Write-Host "🎉 X-Ray設定の動作確認が完了しました！" -ForegroundColor Green
        Write-Host ""
        Write-Host "次のステップ：" -ForegroundColor Yellow
        Write-Host "1. AWS X-Rayコンソールにアクセス" -ForegroundColor Cyan
        Write-Host "2. 'Traces' または 'Service map' でトレースを確認" -ForegroundColor Cyan
        Write-Host "3. 'laravel-app' サービスが表示されることを確認" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "X-Rayコンソール: https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map" -ForegroundColor Blue
    } else {
        throw "HTTP Status: $($response.StatusCode)"
    }
} catch {
    Write-Host "❌ アプリケーションが正常に動作していません" -ForegroundColor Red
    Write-Host "   以下のコマンドで問題を確認してください：" -ForegroundColor Yellow
    Write-Host "   docker-compose logs app" -ForegroundColor Cyan
    Write-Host "   docker-compose logs otel-collector" -ForegroundColor Cyan
    exit 1
} 
