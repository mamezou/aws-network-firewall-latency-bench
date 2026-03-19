---
inclusion: manual
---

# トラブルシューティングガイド

<!-- チャットで `#troubleshooting` と入力すると読み込まれます -->

## よくある問題

### ビルドエラー

1. `node_modules` を削除して再インストール
   ```bash
   rm -rf node_modules package-lock.json
   npm install
   ```

2. TypeScript のバージョン不整合
   ```bash
   npx tsc --version
   ```

### テスト失敗

1. テストキャッシュのクリア
   ```bash
   npx vitest run --reporter=verbose
   ```

2. E2E テストのブラウザ再インストール
   ```bash
   npx playwright install --with-deps chromium
   ```

### デプロイ失敗

1. 環境変数の確認
2. CI ログの確認
3. ロールバック手順の実行

## デバッグのコツ

- `console.log` よりも `debugger` + DevTools を活用
- ネットワークエラーは `curl` で直接確認
- 環境差異は Docker で再現
