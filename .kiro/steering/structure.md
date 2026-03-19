---
inclusion: always
---

# プロジェクト構造

<!-- ↓ PJに合わせて書き換えてください -->

## ディレクトリ構成

```
project-root/
├── src/                  # ソースコード
│   ├── index.ts          # エントリポイント
│   └── ...
├── __tests__/            # テストファイル（コロケーション配置も可: src/**/*.test.ts）
├── docs/                 # ドキュメント
│   ├── design/           # 設計書
│   └── impl/             # 実装計画書
├── .kiro/                # Kiro設定
├── .github/              # GitHub Actions
├── package.json
├── tsconfig.json
└── README.md
```

## 命名規約

### ファイル・ディレクトリ

- コンポーネント: PascalCase（`Button.tsx`）
- ユーティリティ・モジュール: camelCase（`dateUtils.ts`）
- テスト: `<対象ファイル名>.test.ts`
- 定数ファイル: camelCase（`constants.ts`）

### コード内

- 変数・関数: camelCase
- 型・インターフェース: PascalCase
- 定数: UPPER_SNAKE_CASE
- プライベートメンバー: `_` プレフィックスは使わない

## インポート順序

1. Node.js ビルトイン
2. 外部パッケージ
3. 内部モジュール（`@/` or 相対パス）
4. 型インポート（`type` キーワード付き）

## アーキテクチャ方針

<!-- PJに合わせて記載 -->

- （例: レイヤードアーキテクチャ、コロケーションパターン等）
