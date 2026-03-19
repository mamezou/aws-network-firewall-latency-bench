---
inclusion: always
---

# Git 規約

## ブランチ戦略

- `main` : 本番リリース用（直接 push 禁止）
- `dev` : 開発統合ブランチ（必要に応じて）
- `feature/<issue-id>-<短い説明>` : 機能開発
- `fix/<issue-id>-<短い説明>` : バグ修正
- `chore/<説明>` : メンテナンス作業

## コミットメッセージ

Conventional Commits に従う:

```
<type>(<scope>): <description>

[optional body]
```

### type

- `feat` : 新機能
- `fix` : バグ修正
- `docs` : ドキュメントのみの変更
- `style` : コードの意味に影響しない変更（空白、フォーマット等）
- `refactor` : バグ修正でも新機能でもないコード変更
- `test` : テストの追加・修正
- `chore` : ビルドプロセスや補助ツールの変更

### 例

```
feat(auth): add Google OAuth login
fix(api): handle null response from DynamoDB
docs: update README with new API endpoints
test(cache): add unit tests for TTL expiration
```

## PR（Pull Request）

- タイトルは Conventional Commits 形式
- 本文にはやったこと・やらなかったことを簡潔に書く
- レビュー前にセルフレビューする
