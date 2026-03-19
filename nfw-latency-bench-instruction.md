# AWS Network Firewall レイテンシーベンチマーク検証 — Claude Code 指示書

## ゴール

AWS Network Firewall を経由した場合のレイテンシー増加を実測し、以下の段階ごとの追加レイテンシーを数値化する。結果は口頭説明の補足資料として使う。

| Phase | 構成 | 期待値（参考） |
|-------|------|---------------|
| 0 | ベースライン（同一サブネット直接通信） | 基準値 |
| 1 | ステートレスルールのみ（pass all） | サブms〜1ms |
| 2 | ステートフル追加（Suricata pass all） | 数ms |
| 3 | TLS検査有効（HTTPS通信で計測） | 初回接続でシングルms台追加 |

---

## 背景と公式情報

- AWS公式で唯一の具体的数値: TLS検査時「シングルミリ秒台」（[AWS Security Blog](https://aws.amazon.com/blogs/security/tls-inspection-configuration-for-encrypted-traffic-and-aws-network-firewall/)）
- FAQ: 「お客様がルールセットを使用して独自のテストを実施することをお勧めします」（[Network Firewall FAQ](https://aws.amazon.com/network-firewall/faqs/)）
- 各種ブログでは「low milliseconds（数ms）」の追加レイテンシーという記載が複数

→ ステートレス/ステートフル個別の計測データは公式にもサードパーティにも存在しない。自前で計測する価値がある。

---

## 1. インフラ構築（CDK）

### 1-1. プロジェクト初期化

```bash
mkdir nfw-latency-bench && cd nfw-latency-bench
npx cdk init app --language typescript
```

### 1-2. アーキテクチャ

同一AZ内に3サブネットを配置。NFWエンドポイントの有無でレイテンシーを比較する。

```
同一 AZ:
┌────────────────┐   ┌──────────────────┐   ┌────────────────┐
│ Client Subnet  │──▶│ Firewall Subnet  │──▶│ Server Subnet  │
│ 10.0.0.0/24    │   │ 10.0.1.0/24      │   │ 10.0.2.0/24    │
│                │   │ (NFW Endpoint)   │   │                │
│ ClientInst     │   │                  │   │ ServerInst     │
│ BaselineInst   │   │                  │   │                │
└────────────────┘   └──────────────────┘   └────────────────┘

経路A: ClientInst → NFW Endpoint → ServerInst  (Firewall経由)
経路B: ClientInst → BaselineInst               (同一サブネット直接)
```

### 1-3. CDKスタック要件

以下をCDKで作成すること。

**VPC**
- CIDR: 10.0.0.0/16
- maxAzs: 1（同一AZで比較）
- サブネット: Client (PRIVATE_ISOLATED), Firewall (PRIVATE_ISOLATED), Server (PRIVATE_ISOLATED)

**VPCエンドポイント（SSM用、インターネット不要）**
- SSM, SSM_MESSAGES, EC2_MESSAGES の3つ

**セキュリティグループ**
- VPC内 (10.0.0.0/16) から ICMP, TCP 5201 (iperf3), TCP 443 (HTTPS) を許可

**EC2インスタンス × 3**
- **インスタンスタイプ: c5.large**（t3.microはバースト制でベンチマーク不向き）
- AMI: Amazon Linux 2023
- IAMロール: AmazonSSMManagedInstanceCore
- UserData で以下をインストール:
  - iperf3
  - hping3
  - nginx（ServerInst と BaselineInst のみ。TLS計測のPhase 3で使用）
  - jq, bc
- 配置:
  - ClientInst → Client Subnet
  - BaselineInst → Client Subnet（NFW経由しない直接通信の比較用）
  - ServerInst → Server Subnet

**Network Firewall**
- Firewall Subnet に配置
- ステートレスルールグループ: TCP + ICMP を pass
- ステートフルルールグループ: Suricata形式で ICMP, TCP 5201, TCP 443 を pass
- ファイアウォールポリシー: デフォルトで `aws:forward_to_sfe`
- フローログを CloudWatch Logs に出力（retention: 1 week）

**ルートテーブル**
- ⚠️ NFWエンドポイントIDはデプロイ後にしか取得できない
- CDKデプロイ後に以下を手動実行するスクリプトを `scripts/setup-routes.sh` として用意:

```bash
#!/bin/bash
# NFWエンドポイントID取得
VPCE_ID=$(aws network-firewall describe-firewall \
  --firewall-name bench-nfw \
  --query 'FirewallStatus.SyncStates.*.Attachment.EndpointId' \
  --output text)

# Client Subnet → Server Subnet 宛を NFW 経由に
aws ec2 create-route \
  --route-table-id <CLIENT_RT_ID> \
  --destination-cidr-block 10.0.2.0/24 \
  --vpc-endpoint-id $VPCE_ID

# Server Subnet → Client Subnet 宛を NFW 経由に（対称ルーティング）
aws ec2 create-route \
  --route-table-id <SERVER_RT_ID> \
  --destination-cidr-block 10.0.0.0/24 \
  --vpc-endpoint-id $VPCE_ID
```

→ RT IDはCDKのCfnOutputで出力しておくこと。

**タグ**
- 全リソースに `Project: nfw-latency-bench`, `Purpose: benchmark`

**CfnOutput**
- ClientInstanceId, ServerInstanceId, BaselineInstanceId
- ServerPrivateIp, BaselinePrivateIp
- FirewallId, VpcId
- ClientSubnetRouteTableId, ServerSubnetRouteTableId

---

## 2. ベンチマークスクリプト（bench.sh）

### 2-1. 計測ツールと精度

| ツール | 計測対象 | 精度 | 備考 |
|--------|----------|------|------|
| hping3 --tcp -p 5201 -c 100 | TCP RTT | μs単位 | pingよりFirewall経由の実態に近い |
| ping -c 100 -i 0.1 | ICMP RTT | ms単位 | 参考値（ICMPはステートフル処理が異なる場合あり） |
| iperf3 -c <IP> -t 10 -J | スループット + リトランスミット | - | 帯域影響の確認 |
| curl -w '%{time_connect}\n' -o /dev/null | TCP接続時間 | ms単位 | Phase 3でHTTPS計測にも使う |

### 2-2. スクリプト要件

- 引数: `./bench.sh <SERVER_IP> <BASELINE_IP>`
- 各計測を100回以上繰り返し
- 結果からp50, p95, p99を自動算出して表示
- 全rawデータを `/tmp/nfw-bench-<timestamp>/` に保存
- 最後に比較サマリーを出力:

```
======= COMPARISON SUMMARY =======

                  Baseline     Via NFW      Delta
hping3 TCP p50:   0.xxx ms     0.xxx ms     +0.xxx ms
hping3 TCP p95:   0.xxx ms     0.xxx ms     +0.xxx ms
hping3 TCP p99:   0.xxx ms     0.xxx ms     +0.xxx ms
ping ICMP avg:    0.xxx ms     0.xxx ms     +0.xxx ms
iperf3 Mbps:      xxxx         xxxx         -xx
```

### 2-3. Phase切り替え

Phase 1～3 の切り替えはファイアウォールポリシーの更新で行う。ポリシー更新用のスクリプト `scripts/switch-phase.sh` を用意:

```bash
#!/bin/bash
PHASE="${1:?Usage: $0 <1|2|3>}"

case $PHASE in
  1)
    echo "Phase 1: ステートレスのみ"
    # statelessDefaultActions を aws:pass にし、statefulRuleGroupReferences を空に
    ;;
  2)
    echo "Phase 2: ステートフル追加"
    # statelessDefaultActions を aws:forward_to_sfe に戻す
    ;;
  3)
    echo "Phase 3: TLS検査追加"
    # TLS inspection configuration を追加
    # ServerInst / BaselineInst の nginx を HTTPS化 (self-signed cert)
    # bench.sh の計測に curl HTTPS を追加
    ;;
esac
```

---

## 3. Phase 3（TLS検査）の追加要件

- ServerInst と BaselineInst に nginx + self-signed cert を設定
- ACMに証明書をインポート（TLS検査設定で必要）
- bench.sh に HTTPS計測を追加:

```bash
# HTTPS接続時間（TCP + TLS handshake）
curl -sk -w 'tcp_connect: %{time_connect}\ntls_handshake: %{time_appconnect}\ntotal: %{time_total}\n' \
  -o /dev/null https://<SERVER_IP>/
```

- 50回繰り返してp50/p95/p99を算出

---

## 4. 実行手順まとめ

```
1. CDKデプロイ           → cdk deploy
2. ルートテーブル設定     → scripts/setup-routes.sh
3. Phase 1 に切り替え    → scripts/switch-phase.sh 1
4. ベンチマーク実行      → bench.sh (SSM経由)
5. Phase 2 に切り替え    → scripts/switch-phase.sh 2
6. ベンチマーク実行      → bench.sh
7. Phase 3 に切り替え    → scripts/switch-phase.sh 3
8. ベンチマーク実行      → bench.sh
9. 結果を記録
10. クリーンアップ        → cdk destroy
```

---

## 5. コスト見積もり

| リソース | 単価（東京リージョン） | 備考 |
|----------|----------------------|------|
| c5.large × 3 | ~$0.108/h × 3 = $0.324/h | |
| NFWエンドポイント | $0.395/h | |
| VPCエンドポイント × 3 | ~$0.014/h × 3 = $0.042/h | SSM用 |
| データ処理 | $0.065/GB | ベンチ程度なら無視できる |
| **合計** | **約 $0.76/h** | |

**2時間で完了想定: 約 $1.50。終わったら必ず `cdk destroy` すること。**

---

## 6. 注意事項

- hping3 は root 権限が必要（`sudo hping3`）
- Network Firewall は非対称ルーティング非対応。ルートテーブルは必ず双方向設定する
- ポリシー更新後、反映まで数十秒かかる場合がある。切り替え後30秒待ってから計測開始
- c5.large はENA対応でネットワーク性能が安定しているが、Placement Groupは不要（異なるサブネット間の計測のため）
- TLS検査（Phase 3）はセットアップが複雑。Phase 1, 2 の結果だけでも十分な検証データになる

---

## 7. 期待される成果物

- Phase 0/1/2/3 の比較サマリー（hping3 TCP RTT の p50/p95/p99 + Delta）
- 口頭説明用のワンライナー: 「実測では、ステートレスのみで +Xms、ステートフル追加で +Xms、TLS検査追加で初回接続に +Xms の追加レイテンシーを確認しました」
