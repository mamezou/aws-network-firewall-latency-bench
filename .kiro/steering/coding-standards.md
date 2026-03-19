---
inclusion: always
---

# コーディング規約

## TypeScript

### 基本方針

- `strict: true` を必ず有効にする
- `any` 型は禁止。やむを得ない場合は `unknown` + 型ガードを使う
- アロー関数を基本とする（メソッド定義は除く）
- 戻り値の型は明示する（trivial な場合を除く）

### 型定義

- インターフェースよりも `type` を優先する（union type との一貫性のため）
- ジェネリクスは意味のある名前をつける（`T` ではなく `TItem` 等）
- `enum` は使わない。代わりに `as const` + `typeof` パターンを使う

```typescript
// ✅ Good
const Status = {
  Active: "active",
  Inactive: "inactive",
} as const;
type Status = (typeof Status)[keyof typeof Status];

// ❌ Bad
enum Status {
  Active = "active",
  Inactive = "inactive",
}
```

### エラーハンドリング

- カスタムエラークラスを定義する
- `try-catch` では具体的なエラー型を扱う
- エラーメッセージは英語で記述する

### 非同期処理

- `async/await` を基本とする
- Promise チェーン（`.then`）は避ける
- 並列実行可能な処理は `Promise.all` / `Promise.allSettled` を使う

## コメント

- コメントは日本語 OK
- 変数名・関数名・クラス名は英語
- JSDoc は公開 API に必須
- TODO コメントは `// TODO(<name>): 説明` 形式

## 関数設計

- 1関数の行数は50行以内を目安とする
- 引数が3つ以上の場合はオブジェクト引数にする
- 副作用のある関数と純粋関数を明確に分離する
