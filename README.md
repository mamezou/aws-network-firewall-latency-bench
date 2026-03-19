# kiro-template

[Kiro IDE](https://kiro.dev/) のプロジェクト立ち上げ用テンプレート。

Steering / Skills / Hooks を組み合わせた `.kiro/` ディレクトリをまるごとコピーして使います。

## クイックスタート

### 新規プロジェクトにコピー

```bash
# クローンしてコピー
git clone https://github.com/mamezou/kiro_project_template.git /tmp/kiro-template
cp -r /tmp/kiro-template/.kiro /path/to/your-project/.kiro
cp -r /tmp/kiro-template/docs /path/to/your-project/docs
cp -r /tmp/kiro-template/scripts /path/to/your-project/scripts
cp /tmp/kiro-template/CLAUDE.md.example /path/to/your-project/CLAUDE.md

# PJに合わせて書き換え
# 1. .kiro/steering/product.md — プロダクト概要
# 2. .kiro/steering/structure.md — ディレクトリ構成
# 3. .kiro/steering/tech.md — 技術スタック
# 4. CLAUDE.md — PJ固有のルール
```

### Kiro IDE からインポート（Skills 単体）

Kiro パネル → Agent Steering & Skills → **+** → Import a skill → GitHub URL:

```
https://github.com/mamezou/kiro_project_template/tree/main/.kiro/skills/update-docs
https://github.com/mamezou/kiro_project_template/tree/main/.kiro/skills/project-init
https://github.com/mamezou/kiro_project_template/tree/main/.kiro/skills/e2e-testing
```

## 構成

```
.kiro/
├── agents/                      # サブエージェント（専門AI）
│   ├── security-auditor.md         セキュリティ監査（read-only, Kiro IDE用）
│   ├── security-auditor.json       セキュリティ監査（kiro-cli用）
│   ├── spec-checker.md             仕様準拠チェック（read-only, Kiro IDE用）
│   ├── spec-checker.json           仕様準拠チェック（kiro-cli用）
│   ├── doc-updater.md              ADR・設計書更新（docs/のみ書込可）
│   ├── unit-tester.md              テスト作成・実行（Kiro IDE用）
│   └── unit-tester.json            テストレビュー（kiro-cli用）
│
├── steering/                    # エージェントへの常時コンテキスト
│   ├── product.md                  プロダクト概要          ← PJごとに書き換え
│   ├── tech.md                     技術スタック            ← PJごとに書き換え
│   ├── structure.md                ディレクトリ構成        ← PJごとに書き換え
│   ├── coding-standards.md         TypeScript コーディング規約
│   ├── pre-commit-checks.md        コミット前チェック（lint/format）
│   ├── testing.md                  テスト規約 (*.test.* 編集時のみ読込)
│   ├── git-conventions.md          Git / Conventional Commits 規約
│   ├── kiro-file-access.md         .kiro/ ファイル操作ルール
│   ├── branch-strategy.md          ブランチ戦略・PR運用    ← L2+
│   ├── production-safety.md        本番環境安全ルール      ← L3
│   └── troubleshooting.md          トラブルシューティング  ← manual
│
├── skills/                      # オンデマンドワークフロー
│   ├── update-docs/SKILL.md        ドキュメント一括最新化
│   ├── project-init/SKILL.md       プロジェクト初期セットアップ
│   ├── e2e-testing/SKILL.md        Playwright E2E テスト
│   ├── prod-ops/SKILL.md           本番運用操作手順        ← L3
│   └── guardrails-setup/SKILL.md   ガードレール選択・配置
│
├── hooks/                       # イベント駆動の自動化
│   ├── auto-test.kiro.hook         ソース変更時にテスト自動実行 ← patterns要カスタマイズ
│   └── auto-commit.kiro.hook       タスク完了時の自動コミット (default: off)
│
└── settings/
    └── mcp.json                    MCP サーバー設定

docs/
├── design/.gitkeep              # 設計書（第一ソース）
├── decisions/                   # ADR（設計判断記録）
│   └── 000-template.md             ADRテンプレート
└── impl/.gitkeep                # 実装計画書

scripts/
└── kiro-review.sh               # kiro-cli レビュー実行スクリプト

CLAUDE.md.example                # Claude Code 用ガードレールテンプレート
```

## Steering / Skills / Hooks / Agents の使い分け

| 機能 | 読み込みタイミング | 役割 |
|------|-------------------|------|
| **Steering** | 常時 or 条件マッチ時 | 「こう書け」— ルール・規約・文脈 |
| **Skills** | description マッチ時 | 「こうやれ」— 手順書・ワークフロー |
| **Hooks** | ファイル変更等イベント | 「勝手にやれ」— 自動化タスク |
| **Agents** | ユーザーが明示的に呼出 | 「専門家に任せろ」— 特化型サブエージェント |

## Steering 詳細

| ファイル | inclusion | 内容 |
|---------|-----------|------|
| `product.md` | `always` | プロダクト概要（テンプレート。PJごとに書き換え） |
| `tech.md` | `always` | TypeScript / Node.js 20 / Vitest / Playwright 等 |
| `structure.md` | `always` | ディレクトリ構成・命名規約（PJごとに書き換え） |
| `coding-standards.md` | `always` | strict, no any, no enum, arrow functions 等 |
| `pre-commit-checks.md` | `always` | コミット前の lint / format チェック必須 |
| `testing.md` | `fileMatch: **/*.test.*` | Vitest / Playwright の規約。テスト編集時のみ読込 |
| `git-conventions.md` | `always` | Conventional Commits・ブランチ戦略 |
| `kiro-file-access.md` | — | `.kiro/` ファイルの読み書きルール |
| `troubleshooting.md` | `manual` | トラブルシューティング（`#troubleshooting` で読込） |

> **💡 Tips**: `coding-standards.md` と `git-conventions.md` は全PJ共通なので `~/.kiro/steering/` にも配置しておくと便利です。

## Skills 詳細

### update-docs

実装完了後にドキュメントを一括更新するスキル。

- git diff から変更内容を把握
- 設計書 → README → チュートリアルの順に更新
- API比較表のステータス更新
- 一貫性チェック（型定義・エクスポート・日付）

**トリガー**: 「ドキュメント更新して」「README 最新化して」等

### project-init

新規プロジェクトの雛形を一括セットアップするスキル。

- プロジェクト種別の確認（Next.js / Expo / CDK / ライブラリ）
- TypeScript + ESLint + Prettier + Vitest 設定
- Playwright セットアップ
- GitHub Actions CI
- Kiro steering ファイルの初期化

**トリガー**: 「新しいプロジェクト作って」「PJ 立ち上げ」等

### e2e-testing

Playwright を使った E2E テストの作成・実行ガイド。

- Page Object Model パターン
- アクセシビリティベースのセレクタ優先
- CI 設定・デバッグ手順
- フレーキーテスト対策

**トリガー**: 「E2E テスト書いて」「Playwright」等

## Agents 詳細

サブエージェントは特定の専門領域に特化した AI です。メインのチャットから呼び出して使います。

| エージェント | tools | 用途 |
|---|---|---|
| `security-auditor` | read, shell | セキュリティ監査（OWASP, npm audit, 認証/認可チェック） |
| `spec-checker` | read | 仕様 vs 実装の乖離検出（read-only で安全） |
| `doc-updater` | read, write | ADR追記・設計書更新（docs/ のみ書込可） |
| `unit-tester` | read, write, shell | テスト作成・実行（TDD / 実装後テスト） |

全エージェントのモデルは `claude-sonnet-4-5-20250929` を推奨（速度とコスト重視）。
深い設計議論はメインチャット（Opus）で行い、エージェントはパターンマッチ主体のタスクに使う。

### PJ固有のエージェントを追加する場合

`.kiro/agents/` に `.md` ファイルを追加するだけで使えます:

```markdown
---
name: my-agent
description: エージェントの説明
tools: ["read", "write", "shell"]
model: claude-sonnet-4-5-20250929
resources:
  - "file://docs/design/*.md"
---

プロンプト本文をここに書く。
```

## kiro-cli レビュー統合

kiro-cli を使って、ターミナルからレビューエージェントを実行できます。CI/CD パイプラインや Claude Code のスラッシュコマンドからも呼び出せます。

### セットアップ

```bash
# 1. kiro-cli をインストール（未インストールの場合）
npm install -g @anthropic-ai/kiro-cli

# 2. ログイン
kiro-cli login

# 3. エージェント一覧を確認
bash scripts/kiro-review.sh --list
```

### 実行方法

```bash
# 全レビューエージェントを並列実行
bash scripts/kiro-review.sh

# 特定のエージェントのみ実行
bash scripts/kiro-review.sh security-auditor
bash scripts/kiro-review.sh spec-checker
bash scripts/kiro-review.sh unit-tester
```

レポートは `reviews/` ディレクトリにタイムスタンプ付きで保存されます（`.gitignore` 済み）。

### Claude Code との統合

`CLAUDE.md` に以下を追加すると、Claude Code からスラッシュコマンドでレビューを実行できます:

```markdown
## kiro-cli Review Integration

### Slash Commands
- `/review` — 全レビュー実行（セキュリティ・仕様準拠・テスト品質）
- `/review-security` — セキュリティ監査のみ
- `/review-spec` — 仕様準拠チェックのみ
- `/review-tests` — テストレビューのみ

### Manual Execution
\`\`\`bash
bash scripts/kiro-review.sh                    # 全レビュー
bash scripts/kiro-review.sh security-auditor   # セキュリティのみ
bash scripts/kiro-review.sh --list             # エージェント一覧
\`\`\`
```

### 推奨ワークフロー

1. 実装 → 2. `bash scripts/kiro-review.sh` → 3. 指摘修正 → 4. 再レビューで確認

### エージェントの`.md` と `.json` の違い

| 形式 | 用途 | 実行方法 |
|------|------|---------|
| `.md` | Kiro IDE のサブエージェント | Kiro IDE のチャットから呼び出し |
| `.json` | kiro-cli のエージェント | `kiro-cli chat --agent <name>` |

両方を配置しておくことで、IDE でもターミナルでもレビューを実行できます。

## カスタマイズ

### ガードレールレベル

PJ の重要度に応じて 3 段階のガードレールを選択できます。`guardrails-setup` スキルに「ガードレール設定して」と言うと対話的にセットアップされます。

| | L1: 個人開発 | L2: チーム開発 | L3: 本番サービス |
|---|:---:|:---:|:---:|
| `git-conventions.md` | ✅ | ✅ | ✅ |
| `branch-strategy.md` | - | ✅ | ✅ |
| `production-safety.md` | - | - | ✅ |
| `prod-ops/SKILL.md` | - | - | ✅ |
| `AGENTS.md` 生成 | 基本 | +ブランチルール | +本番安全ルール |

L3 は本番サービス運用で実際に発生しうるインシデント（承認なしの本番メール送信・データ削除等）を踏まえた厳格ルールです。

### PJに合わせて必ず編集するファイル

1. `.kiro/steering/product.md` — プロダクトの概要・目的
2. `.kiro/steering/structure.md` — 実際のディレクトリ構成
3. `.kiro/steering/tech.md` — 使わないフレームワークを削除
4. `CLAUDE.md` — `CLAUDE.md.example` をリネームしてPJ固有のルールを記載
5. `.kiro/hooks/auto-test.kiro.hook` — `patterns` をPJのディレクトリ構成に合わせて変更

### Hooks の有効化

`auto-commit.kiro.hook` はデフォルトで無効です。有効にするには:

```json
{
  "enabled": true
}
```

### MCP サーバー

テンプレートには以下の MCP サーバーが設定済みです:

| サーバー | 用途 |
|---------|------|
| `@anthropic-ai/mcp-fetch` | Web ページの取得 |
| `@modelcontextprotocol/server-github` | GitHub リポジトリ操作（gh CLI 相当） |

GitHub MCP サーバーを使うには環境変数 `GITHUB_TOKEN` に Personal Access Token を設定してください:

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
```

追加の MCP サーバーは `.kiro/settings/mcp.json` に追記できます。

### Kiro Powers

Kiro IDE の Powers パネルから以下を有効化すると、AWS 関連の開発がさらに便利になります:

- **aws-infrastructure-as-code** — CDK / CloudFormation のベストプラクティス、テンプレート検証、デプロイトラブルシュート
- **amazon-aurora-postgresql** — Aurora PostgreSQL のスキーマ設計・クエリ最適化

Powers パネル → 「+」 → 検索して有効化してください。

## ライセンス

MIT
