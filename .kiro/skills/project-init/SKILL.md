---
name: project-init
description: 新規プロジェクトの初期セットアップを行う。「プロジェクト作成」「PJ立ち上げ」「init」「新しいアプリを作る」等のリクエストで発動。package.json生成、TypeScript設定、リンター、テスト環境、CI設定を一括で構築する。
---

# プロジェクト初期セットアップスキル

新規プロジェクトの立ち上げ時に、必要な設定ファイルとディレクトリ構造を一括で構築する。

## Step 1: プロジェクト種別の確認

ユーザーに以下を確認する:

1. **プロジェクト種別**: Web (Next.js) / モバイル (Expo) / API (Lambda+CDK) / ライブラリ (npm package)
2. **プロジェクト名**
3. **追加要件**: 認証、DB、デプロイ先等

## Step 2: 共通セットアップ

すべてのプロジェクト種別で実行する:

### package.json の生成

```bash
npm init -y
```

### TypeScript 設定

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  }
}
```

### ESLint (flat config)

```bash
npm install -D eslint @typescript-eslint/eslint-plugin @typescript-eslint/parser
```

### Prettier

```bash
npm install -D prettier
```

`.prettierrc`:
```json
{
  "semi": true,
  "singleQuote": false,
  "tabWidth": 2,
  "trailingComma": "all",
  "printWidth": 100
}
```

### Vitest

```bash
npm install -D vitest
```

### Git 初期設定

```bash
git init
```

`.gitignore` を生成（node_modules, dist, .env 等）

## Step 3: プロジェクト種別固有のセットアップ

### Web (Next.js)

```bash
npx create-next-app@latest --typescript --tailwind --eslint --app --src-dir
```

追加パッケージ:
- Playwright（E2E テスト）

### モバイル (Expo)

```bash
npx create-expo-app --template tabs
```

### API (Lambda + CDK)

```bash
npx cdk init app --language typescript
```

ディレクトリ構成:
```
├── lib/           # CDK スタック定義
├── lambda/        # Lambda 関数
│   └── handlers/
├── __tests__/
└── cdk.json
```

### ライブラリ (npm package)

ディレクトリ構成:
```
├── src/
│   └── index.ts
├── __tests__/
├── tsconfig.json
└── package.json   # "type": "module"
```

## Step 4: Playwright セットアップ（Web / API の場合）

```bash
npm install -D @playwright/test
npx playwright install --with-deps chromium
```

`playwright.config.ts` を生成:
```typescript
import { defineConfig } from "@playwright/test";

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

## Step 5: GitHub Actions

`.github/workflows/ci.yml` を生成:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm test
```

## Step 6: ドキュメント初期化

- `README.md` を生成（英語、プロジェクト名・概要・セットアップ手順）
- `docs/` ディレクトリを作成

## Step 7: Kiro Steering の更新

`.kiro/steering/product.md` と `.kiro/steering/structure.md` をプロジェクトの内容に合わせて更新する。

## 完了チェックリスト

- [ ] `npm install` が成功する
- [ ] `npm run build` が成功する（ビルドがある場合）
- [ ] `npm test` が実行できる
- [ ] `npm run lint` がエラーなし
- [ ] Git リポジトリが初期化されている
- [ ] `.kiro/steering/` がプロジェクトに合わせて更新されている
