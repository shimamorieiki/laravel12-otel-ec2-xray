# データベース接続ガイド

このガイドでは、ローカル開発環境のPostgreSQLデータベースに接続する方法を説明します。

## 前提条件

- Docker環境が起動している（`docker-compose up -d`）
- TablePlusがインストールされている

## データベース接続情報

### Docker環境での接続情報

| 項目 | 値 |
|------|-----|
| **ホスト** | `localhost` |
| **ポート** | `5432` |
| **データベース名** | `laravel` |
| **ユーザー名** | `user` |
| **パスワード** | `pass` |
| **SSL** | `disable` |

## TablePlusでの接続方法

### 1. 新しい接続の作成

1. **TablePlusを起動**
2. **「Create a new connection」**をクリック
3. **「PostgreSQL」**を選択

### 2. 接続設定の入力

以下の情報を入力：

```
Name: Laravel Local DB
Host: localhost
Port: 5432
User: user
Password: pass
Database: laravel
```

### 3. 詳細設定

- **SSL Mode**: `disable`
- **Connection timeout**: `30` seconds
- **Query timeout**: `60` seconds

### 4. 接続テスト

- **「Test」**ボタンをクリックして接続を確認
- 成功したら**「Save」**をクリック

## psql（コマンドライン）での接続

### Docker内からの接続

```bash
# Dockerコンテナ内から接続
docker-compose exec db psql -h localhost -U user -d laravel
```

### ローカルマシンからの接続（psqlがインストールされている場合）

```bash
# ローカルマシンから接続
psql -h localhost -p 5432 -U user -d laravel
```

**パスワード**: `pass`

## 接続用のURL形式

```
postgresql://user:pass@localhost:5432/laravel
```

## よく使用するSQL文

### テーブル一覧の確認

```sql
-- すべてのテーブルを表示
\dt

-- または
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public';
```

### テーブル構造の確認

```sql
-- itemsテーブルの構造を確認
\d items

-- または
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'items';
```

### データの確認

```sql
-- 全アイテムを取得
SELECT * FROM items;

-- セッションテーブルを確認
SELECT * FROM sessions;

-- キャッシュテーブルを確認
SELECT * FROM cache;
```

### サンプルデータの挿入

```sql
-- サンプルアイテムを追加
INSERT INTO items (name, description, price, quantity, created_at, updated_at) 
VALUES 
  ('サンプル商品1', 'これはテスト用の商品です', 1500.00, 10, NOW(), NOW()),
  ('サンプル商品2', '別のテスト商品', 2500.00, 5, NOW(), NOW()),
  ('サンプル商品3', '3番目のテスト商品', 800.00, 20, NOW(), NOW());
```

## トラブルシューティング

### 接続できない場合

1. **Dockerコンテナの状態確認**
   ```bash
   docker-compose ps
   ```

2. **データベースコンテナのログ確認**
   ```bash
   docker-compose logs db
   ```

3. **ポートが使用されているか確認**
   ```bash
   netstat -an | findstr :5432
   ```

4. **Dockerコンテナの再起動**
   ```bash
   docker-compose restart db
   ```

### 権限エラーが発生する場合

```sql
-- ユーザーの権限を確認
SELECT * FROM pg_roles WHERE rolname = 'user';

-- データベースの権限を確認
\l
```

## GUI接続ツールの選択肢

### TablePlus（推奨）
- **公式サイト**: https://tableplus.com/
- **特徴**: 高速、直感的、マルチプラットフォーム

### 他のツール

| ツール | プラットフォーム | 特徴 |
|--------|---------------|------|
| **pgAdmin** | Web/Desktop | 公式PostgreSQLツール |
| **DBeaver** | Desktop | 無料、多機能 |
| **DataGrip** | Desktop | JetBrains製、有料 |
| **Postico** | macOS | macOS専用、シンプル |

## セキュリティに関する注意

⚠️ **開発環境専用**

現在の設定は開発環境専用です：

- パスワードが簡単（`pass`）
- SSL無効
- 外部からアクセス可能

本番環境では以下を実装してください：

- 強力なパスワード
- SSL接続
- ファイアウォール設定
- IPアドレス制限

## 接続文字列の例

### 各言語での接続例

#### PHP（Laravel）
```php
// .env ファイル
DB_CONNECTION=pgsql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=user
DB_PASSWORD=pass
```

#### Node.js
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 5432,
  database: 'laravel',
  user: 'user',
  password: 'pass',
});
```

#### Python
```python
import psycopg2

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    database="laravel",
    user="user",
    password="pass"
)
```

## マイグレーション状態の確認

```sql
-- Laravelマイグレーション履歴を確認
SELECT * FROM migrations ORDER BY batch, migration;
```

これでTablePlusを使用してローカルのPostgreSQLデータベースに簡単に接続できます！ 
