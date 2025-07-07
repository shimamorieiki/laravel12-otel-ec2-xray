#!/bin/bash

# Laravel API テストスクリプト
BASE_URL=${1:-"http://localhost"}

echo "=== Laravel API テスト ==="
echo "ベースURL: $BASE_URL"
echo ""

# 1. ヘルスチェック
echo "1. ヘルスチェック"
response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/")
if [ "$response" -eq 200 ]; then
    version=$(curl -s "$BASE_URL/" | grep -o '"Laravel":"[^"]*"' | cut -d'"' -f4)
    echo "✓ Laravel バージョン: $version"
else
    echo "✗ サーバーに接続できません (HTTP $response)"
    exit 1
fi

# 2. 全アイテム取得
echo ""
echo "2. 全アイテム取得"
response=$(curl -s "$BASE_URL/api/items")
count=$(echo "$response" | grep -o '"id"' | wc -l)
echo "✓ アイテム数: $count"

# 3. 新しいアイテム作成
echo ""
echo "3. 新しいアイテム作成"
timestamp=$(date +%Y%m%d_%H%M%S)
create_response=$(curl -s -X POST "$BASE_URL/api/items" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "テスト商品_'$timestamp'",
    "description": "cURLスクリプトから作成されたテスト商品",
    "price": 1500.00,
    "quantity": 10
  }')

if echo "$create_response" | grep -q '"id"'; then
    item_id=$(echo "$create_response" | grep -o '"id":[0-9]*' | cut -d':' -f2)
    item_name=$(echo "$create_response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    echo "✓ 作成されたアイテム ID: $item_id"
    echo "  名前: $item_name"
else
    echo "✗ アイテム作成に失敗しました"
    echo "$create_response"
    exit 1
fi

# 4. 特定のアイテム取得
echo ""
echo "4. 特定のアイテム取得 (ID: $item_id)"
item_response=$(curl -s "$BASE_URL/api/items/$item_id")
if echo "$item_response" | grep -q '"id"'; then
    echo "✓ 取得成功"
else
    echo "✗ アイテム取得に失敗しました"
fi

# 5. アイテム更新
echo ""
echo "5. アイテム更新 (ID: $item_id)"
update_response=$(curl -s -X PUT "$BASE_URL/api/items/$item_id" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "更新されたテスト商品",
    "description": "cURLスクリプトから更新されました",
    "price": 2000.00,
    "quantity": 5
  }')

if echo "$update_response" | grep -q '"id"'; then
    updated_name=$(echo "$update_response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    updated_price=$(echo "$update_response" | grep -o '"price":"[^"]*"' | cut -d'"' -f4)
    echo "✓ 更新成功: $updated_name"
    echo "  新しい価格: ¥$updated_price"
else
    echo "✗ アイテム更新に失敗しました"
fi

# 6. アイテム削除
echo ""
echo "6. アイテム削除 (ID: $item_id)"
delete_response=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/api/items/$item_id")
if [ "$delete_response" -eq 204 ]; then
    echo "✓ 削除成功"
else
    echo "✗ 削除に失敗しました (HTTP $delete_response)"
fi

# 7. 最終確認
echo ""
echo "7. 最終確認 - 全アイテム取得"
final_response=$(curl -s "$BASE_URL/api/items")
final_count=$(echo "$final_response" | grep -o '"id"' | wc -l)
echo "✓ 最終アイテム数: $final_count"

echo ""
echo "=== テスト完了 ===" 
