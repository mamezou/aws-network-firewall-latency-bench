---
inclusion: fileMatch
fileMatchPattern: ["**/*.test.*", "**/*.spec.*", "**/playwright.config.*", "**/vitest.config.*"]
---

# テスト規約

## ユニットテスト（Vitest）

### 構成

- テストファイルは `__tests__/` に配置、または対象ファイルと同階層に `.test.ts` で配置
- テストヘルパーは `__tests__/helpers/` に集約

### 記述スタイル

```typescript
import { describe, it, expect, vi } from "vitest";

describe("関数名 or クラス名", () => {
  describe("メソッド名 or ユースケース", () => {
    it("should 期待される振る舞い when 条件", () => {
      // Arrange
      const input = "test";

      // Act
      const result = targetFunction(input);

      // Assert
      expect(result).toBe("expected");
    });
  });
});
```

### モック

- `vi.mock()` でモジュールモックを作成
- 外部サービス呼び出しは必ずモックする
- モックのリセットは `beforeEach` で `vi.clearAllMocks()`

### カバレッジ

- ビジネスロジック: 80% 以上
- ユーティリティ: 90% 以上
- UI コンポーネント: スナップショット + インタラクション

## E2E テスト（Playwright）

### 構成

- テストファイルは `e2e/` ディレクトリに配置
- Page Object パターンを使用する
- フィクスチャは `e2e/fixtures/` に配置

### 記述スタイル

```typescript
import { test, expect } from "@playwright/test";

test.describe("機能名", () => {
  test("ユーザーが〜したとき、〜が表示される", async ({ page }) => {
    await page.goto("/target-page");
    await page.getByRole("button", { name: "送信" }).click();
    await expect(page.getByText("完了")).toBeVisible();
  });
});
```

### ベストプラクティス

- `data-testid` よりも Accessible Role / Label でセレクタを書く
- `waitForTimeout` は使わない。`waitForSelector` や `expect` の自動リトライを活用
- テストは独立して実行可能にする（テスト間の依存を作らない）
- CI では `--retries=2` を設定してフレーキーテストに対処

### Playwright 設定の推奨

```typescript
// playwright.config.ts
export default defineConfig({
  testDir: "./e2e",
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: "http://localhost:3000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
});
```
