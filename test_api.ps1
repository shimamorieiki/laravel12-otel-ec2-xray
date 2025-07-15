# Laravel API テストスクリプト
param(
    [string]$BaseUrl = "http://localhost"
)

Write-Host "=== Laravel API テスト ===" -ForegroundColor Green
Write-Host "ベースURL: $BaseUrl" -ForegroundColor Yellow
Write-Host ""

# 1. ヘルスチェック
Write-Host "1. ヘルスチェック" -ForegroundColor Blue
try {
    $health = Invoke-RestMethod -Uri "$BaseUrl/" -Method Get
    Write-Host "✓ Laravel バージョン: $($health.Laravel)" -ForegroundColor Green
} catch {
    Write-Host "✗ サーバーに接続できません: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 2. 全アイテム取得
Write-Host "`n2. 全アイテム取得" -ForegroundColor Blue
try {
    $items = Invoke-RestMethod -Uri "$BaseUrl/api/items" -Method Get
    Write-Host "✓ アイテム数: $($items.Count)" -ForegroundColor Green
    if ($items.Count -gt 0) {
        $items | ForEach-Object { Write-Host "  - $($_.name): ¥$($_.price)" }
    }
} catch {
    Write-Host "✗ エラー: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. 新しいアイテム作成
Write-Host "`n3. 新しいアイテム作成" -ForegroundColor Blue
$newItem = @{
    name = "テスト商品_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    description = "PowerShellスクリプトから作成されたテスト商品"
    price = 1500.00
    quantity = 10
} | ConvertTo-Json

try {
    $createdItem = Invoke-RestMethod -Uri "$BaseUrl/api/items" -Method Post -Body $newItem -ContentType "application/json"
    Write-Host "✓ 作成されたアイテム ID: $($createdItem.id)" -ForegroundColor Green
    Write-Host "  名前: $($createdItem.name)" 
    Write-Host "  価格: ¥$($createdItem.price)"
    $testItemId = $createdItem.id
} catch {
    Write-Host "✗ エラー: $($_.Exception.Message)" -ForegroundColor Red
    $testItemId = $null
}

# 4. 特定のアイテム取得
if ($testItemId) {
    Write-Host "`n4. 特定のアイテム取得 (ID: $testItemId)" -ForegroundColor Blue
    try {
        $item = Invoke-RestMethod -Uri "$BaseUrl/api/items/$testItemId" -Method Get
        Write-Host "✓ 取得成功: $($item.name)" -ForegroundColor Green
    } catch {
        Write-Host "✗ エラー: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 5. アイテム更新
    Write-Host "`n5. アイテム更新 (ID: $testItemId)" -ForegroundColor Blue
    $updateItem = @{
        name = "更新されたテスト商品"
        description = "PowerShellスクリプトから更新されました"
        price = 2000.00
        quantity = 5
    } | ConvertTo-Json

    try {
        $updatedItem = Invoke-RestMethod -Uri "$BaseUrl/api/items/$testItemId" -Method Put -Body $updateItem -ContentType "application/json"
        Write-Host "✓ 更新成功: $($updatedItem.name)" -ForegroundColor Green
        Write-Host "  新しい価格: ¥$($updatedItem.price)"
    } catch {
        Write-Host "✗ エラー: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 6. アイテム削除
    Write-Host "`n6. アイテム削除 (ID: $testItemId)" -ForegroundColor Blue
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/items/$testItemId" -Method Delete
        Write-Host "✓ 削除成功" -ForegroundColor Green
    } catch {
        Write-Host "✗ エラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 7. 最終確認
Write-Host "`n7. 最終確認 - 全アイテム取得" -ForegroundColor Blue
try {
    $finalItems = Invoke-RestMethod -Uri "$BaseUrl/api/items" -Method Get
    Write-Host "✓ 最終アイテム数: $($finalItems.Count)" -ForegroundColor Green
} catch {
    Write-Host "✗ エラー: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== テスト完了 ===" -ForegroundColor Green 
