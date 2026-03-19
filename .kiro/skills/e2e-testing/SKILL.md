---
name: e2e-testing
description: Playwright を使った E2E テストの作成・実行・デバッグを行う。「E2Eテスト」「Playwright」「ブラウザテスト」「結合テスト」「画面テスト」等のリクエストで発動。
---

# Playwright E2E テストスキル

Playwright を使用した E2E テストの作成・実行・デバッグの手順。

## 前提

- Playwright がインストール済みであること
- `playwright.config.ts` が設定済みであること

未セットアップの場合は先にセットアップする:

```bash
npm install -D @playwright/test
npx playwright install --with-deps chromium
```

## テスト作成の方針

### ディレクトリ構成

```
e2e/
├── fixtures/          # テストフィクスチャ・カスタム設定
├── pages/             # Page Object Model
│   ├── BasePage.ts
│   └── <PageName>Page.ts
├── <feature>.spec.ts  # テストファイル
└── global-setup.ts    # グローバルセットアップ（認証等）
```

### Page Object Model

画面ごとに Page Object を作成して再利用性を高める:

```typescript
// e2e/pages/LoginPage.ts
import { type Page, type Locator } from "@playwright/test";

export class LoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.emailInput = page.getByLabel("メールアドレス");
    this.passwordInput = page.getByLabel("パスワード");
    this.submitButton = page.getByRole("button", { name: "ログイン" });
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }
}
```

### テストの書き方

```typescript
import { test, expect } from "@playwright/test";
import { LoginPage } from "./pages/LoginPage";

test.describe("ログイン機能", () => {
  test("正しい認証情報でログインできる", async ({ page }) => {
    const loginPage = new LoginPage(page);
    await page.goto("/login");

    await loginPage.login("user@example.com", "password123");

    await expect(page).toHaveURL("/dashboard");
    await expect(page.getByText("ようこそ")).toBeVisible();
  });

  test("不正なパスワードでエラーが表示される", async ({ page }) => {
    const loginPage = new LoginPage(page);
    await page.goto("/login");

    await loginPage.login("user@example.com", "wrong");

    await expect(page.getByText("認証に失敗しました")).toBeVisible();
  });
});
```

## セレクタの優先順位

以下の優先順位でセレクタを選ぶ（アクセシビリティ重視）:

1. `page.getByRole()` — ボタン、リンク、テキストボックス等
2. `page.getByLabel()` — フォーム要素
3. `page.getByText()` — テキスト内容
4. `page.getByPlaceholder()` — プレースホルダー
5. `page.getByTestId()` — 最終手段（`data-testid` 属性）

**使わない:**
- CSS セレクタ（壊れやすい）
- XPath（読みにくい）
- `page.waitForTimeout()`（フレーキーテストの原因）

## テスト実行

```bash
# 全テスト実行
npx playwright test

# 特定ファイル
npx playwright test e2e/login.spec.ts

# headed モード（ブラウザ表示）
npx playwright test --headed

# UI モード（インタラクティブ）
npx playwright test --ui

# デバッグモード
npx playwright test --debug

# 失敗時のトレース確認
npx playwright show-trace test-results/*/trace.zip
```

## CI での実行

```yaml
# GitHub Actions
- name: Install Playwright
  run: npx playwright install --with-deps chromium
- name: Run E2E tests
  run: npx playwright test
- uses: actions/upload-artifact@v4
  if: failure()
  with:
    name: playwright-report
    path: playwright-report/
```

## トラブルシューティング

### フレーキーテスト対策

- `expect` の自動リトライを活用する（デフォルト5秒）
- `toBeVisible()` は要素が DOM にあり、表示されていることを確認する
- ネットワークリクエストの完了を待つ: `page.waitForResponse()`
- アニメーション完了を待つ: `page.waitForLoadState("networkidle")` は避け、具体的な要素の出現を待つ

### デバッグのコツ

- `--trace on` でトレースを記録し、失敗原因を視覚的に確認
- `page.screenshot()` をテスト途中に挟んで状態確認
- `test.slow()` でタイムアウトを延長（遅い環境向け）
