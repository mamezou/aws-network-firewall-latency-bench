# AWS Network Firewall レイテンシーベンチマーク

## 目的

Network Firewall を経由した場合のレイテンシー増加を実測し、
以下の各段階での追加レイテンシーを数値化する。

| テスト段階 | 内容 | 期待される追加レイテンシー |
|---|---|---|
| Phase 0 | ベースライン（同一サブネット直接通信） | 基準値 |
| Phase 1 | ステートレスルールのみ（pass all） | サブms〜1ms |
| Phase 2 | ステートフルルール追加（Suricata pass） | 数ms |
| Phase 3 | TLS検査有効化 | 初回接続でシングルms台追加 |

## アーキテクチャ

```
同一 AZ 内:

┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│ Client       │     │ Firewall Subnet  │     │ Server       │
│ Subnet       │────▶│ (NFW Endpoint)   │────▶│ Subnet       │
│              │     │                  │     │              │
│ ClientInst   │     │                  │     │ ServerInst   │
│ BaselineInst │     │                  │     │              │
└──────────────┘     └──────────────────┘     └──────────────┘

経路A: ClientInst → NFW Endpoint → ServerInst  (Firewall経由)
経路B: ClientInst → BaselineInst              (同一サブネット直接)
```

## デプロイ手順

### 1. CDKデプロイ

```bash
npm install
# --outputs-file でCfnOutputをファイルに保存する (後続スクリプトが参照する)
npx cdk deploy --outputs-file outputs.json
```

`outputs.json` はプロジェクトルートに生成される。`.gitignore` に追加すること。

### 2. ルートテーブル設定

CDKではNFWエンドポイントIDをデプロイ時に取得できないため、デプロイ後に手動設定する。

```bash
./scripts/setup-routes.sh
# outputs.json を自動参照。パスを変えたい場合は引数で渡す:
# ./scripts/setup-routes.sh /path/to/outputs.json
```

### 3. ベンチマーク実行

```bash
# outputs.json からIPを取得
SERVER_IP=$(jq -r '.NfwLatencyBenchStack.ServerPrivateIp' outputs.json)
BASELINE_IP=$(jq -r '.NfwLatencyBenchStack.BaselinePrivateIp' outputs.json)
CLIENT_ID=$(jq -r '.NfwLatencyBenchStack.ClientInstanceId' outputs.json)

# bench.sh を SSM 経由で ClientInstance に転送して実行
aws ssm send-command \
  --instance-ids "${CLIENT_ID}" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    'curl -o /tmp/bench.sh https://...',
    'chmod +x /tmp/bench.sh',
    'sudo /tmp/bench.sh ${SERVER_IP} ${BASELINE_IP}'
  ]"

# または SSM セッションで直接実行
aws ssm start-session --target "${CLIENT_ID}"
# セッション内で:
# sudo ./bench.sh <SERVER_IP> <BASELINE_IP>
```

## テストフェーズの切り替え

```bash
./scripts/switch-phase.sh 1   # ステートレスのみ
./scripts/switch-phase.sh 2   # ステートフル追加
./scripts/switch-phase.sh 3   # TLS検査 (手順を案内)
# outputs.json を自動参照。パスを変えたい場合:
# ./scripts/switch-phase.sh 1 /path/to/outputs.json
```

切り替え後は **30秒の反映待機**が入るので、完了メッセージを確認してから `bench.sh` を実行する。

## 実行フロー

```
1. npx cdk deploy --outputs-file outputs.json
2. ./scripts/setup-routes.sh
3. ./scripts/switch-phase.sh 1  →  bench.sh
4. ./scripts/switch-phase.sh 2  →  bench.sh
5. (オプション) ./scripts/switch-phase.sh 3  →  bench.sh
6. npx cdk destroy
```

## 計測項目

| 項目 | ツール | 精度 |
|---|---|---|
| TCP RTT (p50/p95/p99) | hping3 --tcp -p 5201 -c 100 | μs単位 (メイン計測) |
| ICMP RTT (avg) | ping -c 100 | ms単位 (参考値) |
| スループット + リトランスミット | iperf3 -t 10 -J | - |
| HTTPS TCP/TLS接続時間 (p50/p95/p99) | curl | ms単位 (Phase 3) |

## コスト見積もり

| リソース | 単価（東京リージョン） |
|---|---|
| c5.large × 3 | ~$0.108/h × 3 = $0.324/h |
| NFWエンドポイント | $0.395/h |
| VPCエンドポイント × 3 (SSM用) | ~$0.014/h × 3 = $0.042/h |
| **合計** | **約 $0.76/h** |

**2時間で完了想定: 約 $1.50。終わったら必ず `npx cdk destroy` すること。**

## 参考リンク

- [TLS inspection configuration - AWS Security Blog](https://aws.amazon.com/blogs/security/tls-inspection-configuration-for-encrypted-traffic-and-aws-network-firewall/)
  - 公式で唯一の具体的数値: TLS検査時のシングルms台レイテンシー
- [Network Firewall FAQ](https://aws.amazon.com/network-firewall/faqs/)
  - FAQ: 独自テスト推奨の記載あり
- [Deployment models for AWS Network Firewall](https://aws.amazon.com/blogs/networking-and-content-delivery/deployment-models-for-aws-network-firewall/)
  - 分散型/集中型/コンバインドの比較
