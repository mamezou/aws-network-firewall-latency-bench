---
inclusion: always
---

# コミット前チェック（必須）

git commit を実行する前に、以下を必ず実行すること:

1. `npx eslint <変更対象ディレクトリ>` — lint エラーがあれば修正
2. `npx prettier --write <変更対象ファイル>` — フォーマット適用
3. `git add` で再ステージ

これにより CI の lint / format:check ステップの失敗を防ぐ。
