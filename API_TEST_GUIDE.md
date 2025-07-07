# Laravel API テストガイド

このガイドでは、ローカル環境でLaravel APIをテストする方法を説明します。

## 前提条件

- Docker Desktop for Windows がインストールされている
- プロジェクトディレクトリに移動している

## 1. ローカル環境の起動

### クイックスタート（推奨）

```bash
# 1. 環境設定とDockerの起動
make setup

# 2. ブラウザでアクセス確認
# http://localhost にアクセス
```

### 手動での起動

```bash
# 1. 環境設定ファイルをコピー
cp .env.docker .env

# 2. Dockerコンテナをビルド
make build

# 3. コンテナを起動
make up

# 4. 依存関係をインストール
make composer

# 5. データベースマイグレーション
make migrate
```

## 2. 利用可能なAPIエンドポイント

### 基本情報
- **ベースURL**: `http://localhost`
- **API プレフィックス**: `/api`

### エンドポイント一覧

| メソッド | URL | 説明 |
|---------|-----|------|
| GET | `/` | Laravel情報取得（ヘルスチェック） |
| GET | `/api/items` | 全アイテム取得 |
| POST | `/api/items` | 新しいアイテム作成 |
| GET | `/api/items/{id}` | 特定アイテム取得 |
| PUT | `/api/items/{id}` | アイテム更新 |
| DELETE | `/api/items/{id}` | アイテム削除 |

### アイテムのデータ形式

```json
{
  "id": 1,
  "name": "商品名",
  "description": "商品説明",
  "price": 1500.00,
  "quantity": 10,
  "created_at": "2025-01-06T12:00:00.000000Z",
  "updated_at": "2025-01-06T12:00:00.000000Z"
}
```

### バリデーションルール

- `name`: 必須、文字列、最大255文字
- `description`: 任意、文字列
- `price`: 必須、数値、0以上
- `quantity`: 必須、整数、0以上

## 3. APIテスト方法

### 方法1: 自動テストスクリプト（推奨）

#### PowerShellスクリプト

```powershell
# 基本テスト
.\test_api.ps1

# 異なるURLでテスト
.\test_api.ps1 -BaseUrl "http://localhost:8080"
```

#### Bashスクリプト

```bash
# 基本テスト
./test_api.sh

# 異なるURLでテスト
./test_api.sh "http://localhost:8080"
```

### 方法2: 手動テスト

#### cURLを使用

```bash
# 1. ヘルスチェック
curl -X GET http://localhost/

# 2. 全アイテム取得
curl -X GET http://localhost/api/items

# 3. 新しいアイテム作成
curl -X POST http://localhost/api/items \
  -H "Content-Type: application/json" \
  -d '{
    "name": "テスト商品",
    "description": "これはテスト用の商品です",
    "price": 1500.00,
    "quantity": 10
  }'

# 4. 特定のアイテム取得（ID=1の場合）
curl -X GET http://localhost/api/items/1

# 5. アイテム更新（ID=1の場合）
curl -X PUT http://localhost/api/items/1 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "更新された商品",
    "description": "更新されました",
    "price": 2000.00,
    "quantity": 5
  }'

# 6. アイテム削除（ID=1の場合）
curl -X DELETE http://localhost/api/items/1
```

#### PowerShellを使用

```powershell
# 1. ヘルスチェック
Invoke-RestMethod -Uri "http://localhost/" -Method Get

# 2. 全アイテム取得
Invoke-RestMethod -Uri "http://localhost/api/items" -Method Get

# 3. 新しいアイテム作成
$body = @{
    name = "テスト商品"
    description = "これはテスト用の商品です"
    price = 1500.00
    quantity = 10
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost/api/items" -Method Post -Body $body -ContentType "application/json"

# 4. 特定のアイテム取得
Invoke-RestMethod -Uri "http://localhost/api/items/1" -Method Get

# 5. アイテム更新
$updateBody = @{
    name = "更新された商品"
    description = "更新されました"
    price = 2000.00
    quantity = 5
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost/api/items/1" -Method Put -Body $updateBody -ContentType "application/json"

# 6. アイテム削除
Invoke-RestMethod -Uri "http://localhost/api/items/1" -Method Delete
```

## 4. 期待される結果

### 成功時のHTTPステータスコード

- `GET /`: 200 OK
- `GET /api/items`: 200 OK
- `POST /api/items`: 201 Created
- `GET /api/items/{id}`: 200 OK
- `PUT /api/items/{id}`: 200 OK
- `DELETE /api/items/{id}`: 204 No Content

### エラー時のHTTPステータスコード

- `404 Not Found`: 存在しないアイテムのアクセス
- `422 Unprocessable Entity`: バリデーションエラー
- `500 Internal Server Error`: サーバーエラー

## 5. トラブルシューティング

### 接続エラー

```bash
# コンテナの状態確認
docker-compose ps

# ログの確認
make logs

# コンテナを再起動
make restart
```

### データベースエラー

```bash
# データベースの状態確認
make artisan cmd="migrate:status"

# マイグレーションの実行
make migrate

# データベースの初期化
make fresh
```

### 権限エラー

```bash
# コンテナ内でのファイル権限確認
make shell
ls -la storage/
```

## 6. 便利なコマンド

### 開発用コマンド

```bash
# コンテナの起動
make up

# コンテナの停止
make down

# ログの確認
make logs

# アプリケーションコンテナに接続
make shell

# Artisanコマンドの実行
make artisan cmd="route:list"
make artisan cmd="tinker"
```

### デバッグ用コマンド

```bash
# ルート一覧の確認
make artisan cmd="route:list"

# 設定の確認
make artisan cmd="config:show"

# キャッシュのクリア
make artisan cmd="cache:clear"
make artisan cmd="config:clear"
```

## 7. OpenTelemetryの確認

このプロジェクトにはOpenTelemetryによる分散トレーシングが組み込まれています。

### OpenTelemetry Collector エンドポイント

- **HTTP**: `http://localhost:4318`
- **gRPC**: `http://localhost:4317`
- **Prometheus メトリクス**: `http://localhost:8888`

### トレーシングの確認

```bash
# OpenTelemetryテストコマンド
make artisan cmd="test:otel"

# コレクターのログ確認
docker-compose logs otel-collector
```

## 8. 実行例

### 成功例

```bash
PS C:\Users\aifor\prog\laravel12-otel-ec2-xray> .\test_api.ps1
=== Laravel API テスト ===
ベースURL: http://localhost

1. ヘルスチェック
✓ Laravel バージョン: 12.0.0

2. 全アイテム取得
✓ アイテム数: 0

3. 新しいアイテム作成
✓ 作成されたアイテム ID: 1
  名前: テスト商品_20250106_143022
  価格: ¥1500.00

4. 特定のアイテム取得 (ID: 1)
✓ 取得成功: テスト商品_20250106_143022

5. アイテム更新 (ID: 1)
✓ 更新成功: 更新されたテスト商品
  新しい価格: ¥2000.00

6. アイテム削除 (ID: 1)
✓ 削除成功

7. 最終確認 - 全アイテム取得
✓ 最終アイテム数: 0

=== テスト完了 ===
```

これでローカル環境でのAPI開発とテストが完了しました！ 
