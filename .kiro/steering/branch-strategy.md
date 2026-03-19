---
inclusion: auto
name: branch-strategy
description: ブランチ戦略、PR運用、マージルール。git操作、PR作成、ブランチ、デプロイ、CI/CDに関する会話で適用。
---

# ブランチ戦略と PR 運用

## ブランチルール

- `main` ブランチへの直接 push は**常に禁止**（例外なし）
- 開発統合ブランチ（`dev` or `develop`）への直接 push も**禁止**
- 作業は `feature/issue-<番号>-<説明>` ブランチで行う
- 開発統合ブランチから feature ブランチを作成し、開発統合ブランチへ PR を出す
- 開発統合ブランチ → `main` の PR は CI 成功後に GitHub Actions が自動生成

> **Note**: 開発統合ブランチの名前は PJ に合わせて `dev` または `develop` を選択する。
> どちらを使うかは PJ 初期に決め、`.kiro/steering/git-conventions.md` に明記すること。

## PR 運用

### 作成ルール
- feature ブランチから開発統合ブランチにドラフト PR を作成
- 概要・影響範囲・検証手順を記載
- UI 変更はスクリーンショットを添付
- `main` 向けに手動で PR を作成しない

### マージ前チェック
- CI（lint / テスト / ビルド）がすべて緑
- セルフレビュー完了
- レビュー承認後に通常マージ

### マージ後
- マージ済み PR への追いコミットは**禁止**
- 次の作業は必ず新しい feature ブランチから開始
- 1タスク = 1PR の原則

## 追いコミット前チェックリスト

追いコミットを行う前に**必ず**以下を確認:

```bash
# 1. ローカル変更の確認
git status

# 2. 現在のブランチが feature/ か確認
git branch --show-current

# 3. PR が OPEN か確認
gh pr view <番号> --json state
```

いずれかで不整合があれば作業を中断し、新しいブランチ・PR を作成する。

## 禁止事項

- `--force` / `--force-with-lease` による force-push
- CI を通さないデプロイ
- ユーザー承認なしの開発統合ブランチ → `main` PR マージ（本番デプロイ）

## 緊急対応（P0）

P0 であっても開発統合ブランチへの直 push は不可。必ず Draft PR を作成し、コメントで承認を得る。
