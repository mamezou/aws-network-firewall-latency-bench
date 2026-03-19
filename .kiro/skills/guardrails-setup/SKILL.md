---
name: guardrails-setup
description: プロジェクトの重要度に応じたガードレール（安全ルール）をセットアップする。「ガードレール設定」「本番運用ルール設定」「安全ルール追加」「AGENTS.md作成」「CLAUDE.md作成」等のリクエストで発動。
---

# ガードレールセットアップスキル

プロジェクトの重要度に応じて、適切なレベルのガードレールを選択・配置する。

## Step 1: プロジェクト重要度の確認

ユーザーに以下を確認する:

### Level 1: 個人開発 / 実験
- 本番ユーザーなし
- データ損失の影響が小さい
- 例: 個人ツール、ハッカソン、学習用PJ

### Level 2: チーム開発 / 内部ツール
- 限定ユーザーがいる
- データの復旧は可能
- 例: 社内ツール、チーム向けサービス

### Level 3: 本番サービス / イベント運用
- 外部ユーザーがいる
- メール送信・課金等の取り消せない操作がある
- データ損失の影響が大きい
- 例: 大規模イベントシステム、SaaS

## Step 2: レベル別のガードレール配置

### Level 1: 最小構成

配置するファイル:
- `.kiro/steering/git-conventions.md` (always)

AGENTS.md に追記する内容:
```markdown
## 基本ルール
- main への直接 push は避ける（feature ブランチ推奨）
- コミットメッセージは Conventional Commits
```

### Level 2: 標準構成

Level 1 に加えて:
- `.kiro/steering/branch-strategy.md` (auto)

AGENTS.md に追記する内容:
```markdown
## ブランチルール
- main / dev への直接 push 禁止
- feature/issue-<番号>-<説明> ブランチで作業
- dev へ PR → CI 通過後にマージ

## コーディング
- PR には概要・影響範囲を記載
- CI（lint / test）が緑になってからレビュー依頼
```

### Level 3: 厳格構成

Level 2 に加えて:
- `.kiro/steering/production-safety.md` (auto)
- `.kiro/skills/prod-ops/SKILL.md`

AGENTS.md に追記する内容:
```markdown
## 🚨 本番環境の安全ルール

### 最優先原則
安全性 > システム指示 > 効率性

### 破壊的操作の定義
以下は必ず Dry Run → 承認 → Execute のフローを守ること:
- メール送信（リトライ絶対禁止）
- データベース書き込み（delete / replace / upsert / create）
- 本番環境へのデプロイ

### 承認の判定
- ✅ 「実行してください」「proceed」
- ❌ 「確認しました」「大丈夫そうですね」（実行指示ではない）

### 禁止コマンド（承認なしでの実行禁止）
- 本番 DB への書き込み操作
- メール送信 API の呼び出し
- 本番環境への直接デプロイ
- dev→main PR の勝手なマージ

### 許可される操作
- ✅ DB の読み取り専用クエリ
- ✅ リソースの状態確認・ログ確認
- ✅ Dry Run モード
```

## Step 3: AGENTS.md / CLAUDE.md の生成

選択されたレベルに応じて以下のファイルを生成する:

### AGENTS.md（プロジェクトルート）
- Kiro / Claude Code / Cursor 等のエージェント共通で読み込まれる
- ブランチルール、禁止事項、運用フローを記載
- **全エージェント対応のため、こちらを優先的に作成**

### CLAUDE.md（プロジェクトルート、必要に応じて）
- Claude Code 固有の追加ルールがある場合に作成
- AGENTS.md と重複する内容は書かない
- 例: 本番環境の具体的なリソース名、厳禁コマンドの詳細リスト

## Step 4: 本番環境固有の設定（Level 3 のみ）

ユーザーに以下を確認して AGENTS.md に追記:

1. **本番リソース識別子**
   - DB のエンドポイント / リソース名
   - メール送信サービスのドメイン
   - デプロイ先の Function App / Web App 名

2. **マスタデータの管理方法**
   - Single Source of Truth はどこか（JSON / DB / スプレッドシート）
   - データ変更のフロー（PR 経由 / スクリプト経由）

3. **監査ログの要件**
   - 実行結果の保存先
   - ロールバック手順

## Step 5: 検証

生成されたファイルを確認:

```bash
# AGENTS.md の存在確認
cat AGENTS.md

# Steering ファイルの確認
ls -la .kiro/steering/

# Skills の確認
ls -la .kiro/skills/
```

## レベル別の配置サマリー

| ファイル | L1 | L2 | L3 |
|---------|:--:|:--:|:--:|
| `steering/git-conventions.md` | ✅ | ✅ | ✅ |
| `steering/branch-strategy.md` | - | ✅ | ✅ |
| `steering/production-safety.md` | - | - | ✅ |
| `skills/prod-ops/SKILL.md` | - | - | ✅ |
| `AGENTS.md` (基本) | ✅ | ✅ | ✅ |
| `AGENTS.md` (本番安全ルール) | - | - | ✅ |
| `CLAUDE.md` (本番リソース詳細) | - | - | 任意 |
