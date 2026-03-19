---
inclusion: always
---

# 技術スタック

## 言語・ランタイム

- TypeScript（strict mode 必須）
- Node.js 20.x LTS

## パッケージマネージャ

- npm（lock ファイルをコミットする）

## フレームワーク（PJに応じて選択）

<!-- 該当するものだけ残してください -->

### Web アプリ
- Next.js (App Router)
- React 19

### モバイルアプリ
- Expo (SDK 52+)
- React Native

### API / バックエンド
- AWS Lambda (Node.js 20.x)
- API Gateway (REST or HTTP API)

### インフラ
- AWS CDK v2 (TypeScript)
- CloudFormation

## データベース

- DynamoDB（シングルテーブルデザインを検討）
- 必要に応じて Aurora Serverless v2

## テスト

- ユニットテスト: Vitest
- E2E テスト: Playwright
- テストファイル: `__tests__/` または `*.test.ts`

## リンター・フォーマッター

- ESLint (flat config)
- Prettier

## CI/CD

- GitHub Actions

## 開発ツール

- Kiro IDE
- Git
