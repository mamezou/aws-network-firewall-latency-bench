# .kiro ディレクトリのファイル操作

- `.kiro/` 配下のファイルは readFile / strReplace / fsWrite ツールではアクセスできない
- 必ず executeBash（cat, sed, tee 等）経由で読み書きすること
- ファイル内容の確認には `cat file | tee /dev/stderr` を使うと出力検知が安定する
