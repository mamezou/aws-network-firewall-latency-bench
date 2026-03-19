---
name: prod-ops
description: 本番環境での運用操作手順。データベース修正、メール送信、デプロイ、本番スクリプト実行、暫定調整、突合、orphanスキャン等の運用タスクで使用。
---

# 本番運用操作スキル

本番環境での運用操作を安全に実行するための手順書。

## 大原則

1. **Dry Run → 承認 → Execute** のフローを必ず守る
2. 監査ログを必ず残す
3. ロールバック手順を事前に確認する

## 運用スクリプト実行フロー

### Step 1: 環境変数の設定

```bash
# PROD 環境の場合（リソース名は PJ に合わせて変更）
# 例: AWS DynamoDB
export AWS_REGION="ap-northeast-1"
export TABLE_NAME="<prod-table-name>"

# 例: その他のデータベース
export DB_ENDPOINT="<prod-db-endpoint>"
export DB_NAME="<prod-db-name>"
```

### Step 2: Dry Run

```bash
# --execute フラグなしで実行
node <script>.js [options]
```

確認事項:
- 影響を受けるレコード数
- 変更前後の値
- 対象ユーザー/リソースの一覧

### Step 3: ユーザーに確認依頼

以下の情報を提示して承認を求める:
- 実行するスクリプト名
- 影響範囲（件数、対象ID等）
- 変更内容の before / after
- ロールバック可否

### Step 4: 承認後に実行

```bash
node <script>.js [options] --execute
```

### Step 5: 監査ログ確認

```bash
cat results.json | python3 -m json.tool
```

## メール送信の特別ルール

メール送信は**最も危険な操作**として扱う:

1. **リトライ絶対禁止** — タイムアウトでも再送信しない
2. **1件ずつ実行** — バッチ送信はタイムアウトリスクがある
3. **送信前にログ確認** — ログで送信済みか確認
4. **タイムアウト ≠ 失敗** — バックグラウンドで完了している可能性

```bash
# 送信済み確認（PJ のログ基盤に合わせて変更）
# 例: CloudWatch Logs
aws logs filter-log-events \
  --log-group-name "<log-group>" \
  --filter-pattern '"email" "sent"' \
  --limit 10
```

## データ修正フロー

### 直接修正が必要な場合

1. 修正スクリプトを `scripts/` に配置
2. PR でレビューを受ける
3. Dry Run → 承認 → Execute

### マスタデータの変更

**データベースへの直接書き込みは原則禁止。**

正しいフロー:
1. データソースファイル（JSON / CSV 等）を編集
2. PR 作成 → レビュー → マージ
3. デプロイワークフローを手動実行

理由:
- データソースファイルが Single Source of Truth
- Git で変更履歴が管理される
- デプロイ時にバリデーションが自動実行される
- 直接変更すると次回デプロイで上書きされる

## 定期突合（Reconciliation）

データ不整合を解消する定期タスク:

```bash
# 特定リソース
node <reconcile-script>.js <resource-id>

# 全リソース
node <reconcile-script>.js --all

# 承認後に実行
node <reconcile-script>.js --all --execute
```

## Orphan スキャン

データ整合性の監視:

```bash
# スキャン実行
node <scan-script>.js

# 結果確認
cat <scan-results>.json | python3 -m json.tool

# 判断基準
# 0件: OK
# 1-5件: 個別対応
# 6件以上: Issue 作成して調査
```

## ロールバック

実行結果は `results.json` に記録される。ロールバック時:

1. `results.json` から変更前の値を確認
2. 手動で元の値に戻す（or ロールバックスクリプトを実行）
3. 管理者にデータ整合性の検証を依頼

## 監査ログのフォーマット

```json
{
  "timestamp": "ISO8601",
  "action": "操作名",
  "target": "対象リソース",
  "before": {},
  "after": {},
  "executor": "実行者",
  "mode": "dry-run | execute"
}
```
