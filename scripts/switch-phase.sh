#!/bin/bash
# =============================================================
# Network Firewall フェーズ切り替えスクリプト
#
# 使い方:
#   ./scripts/switch-phase.sh <1|2|3> [outputs.json のパス]
#
# outputs.json は cdk deploy --outputs-file outputs.json で生成。
#
# フェーズ定義:
#   Phase 1: ステートレスルールのみ (statelessDefaultActions=aws:pass)
#   Phase 2: ステートフルルール追加 (statelessDefaultActions=aws:forward_to_sfe)
#   Phase 3: TLS検査有効化
#             自己署名証明書を生成 → ACMインポート → TLS inspection config作成
#             → TLS検査付きのポリシー bench-fw-policy-tls を作ってファイアウォールに関連付け
#             (TLS検査の設定は既存のポリシーへ後から付けられないため、ポリシーごと作る。
#              このポリシーは scripts/cleanup.sh が消す)
#
# ⚠️  フェーズ切り替え後、このスクリプトが30秒待機してから終了する
# =============================================================
set -euo pipefail

PHASE="${1:?Usage: $0 <1|2|3> [outputs.json]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUTS_FILE="${2:-${SCRIPT_DIR}/../outputs.json}"

if [ ! -f "${OUTPUTS_FILE}" ]; then
  echo "ERROR: outputs.json が見つかりません: ${OUTPUTS_FILE}"
  echo "  npx cdk deploy --outputs-file outputs.json を実行してください。"
  exit 1
fi

STACK_NAME="NfwLatencyBenchStack"
FIREWALL_NAME="bench-nfw"

POLICY_ARN=$(jq -r ".${STACK_NAME}.FirewallPolicyArn" "${OUTPUTS_FILE}")
STATELESS_RG_ARN=$(jq -r ".${STACK_NAME}.StatelessRuleGroupArn" "${OUTPUTS_FILE}")
STATEFUL_RG_ARN=$(jq -r ".${STACK_NAME}.StatefulRuleGroupArn" "${OUTPUTS_FILE}")
STRICT_STATEFUL_RG_ARN=$(jq -r ".${STACK_NAME}.StrictStatefulRuleGroupArn" "${OUTPUTS_FILE}")

echo "=== 設定値 ==="
echo "outputs.json: ${OUTPUTS_FILE}"
echo ""

# ----------------------------------------------------------
# ヘルパー: ファイアウォールに指定ポリシーを関連付ける
# ----------------------------------------------------------
associate_policy() {
  local policy_arn="$1"
  local update_token
  update_token=$(aws network-firewall describe-firewall \
    --firewall-name "${FIREWALL_NAME}" \
    --query 'UpdateToken' --output text)
  aws network-firewall associate-firewall-policy \
    --firewall-name "${FIREWALL_NAME}" \
    --firewall-policy-arn "${policy_arn}" \
    --update-token "${update_token}" \
    --query 'FirewallPolicyArn' --output text
}

# ----------------------------------------------------------
# ヘルパー: bench-fw-policy のコンテンツを更新する
# ----------------------------------------------------------
update_main_policy() {
  local policy_json="$1"
  local update_token
  update_token=$(aws network-firewall describe-firewall-policy \
    --firewall-policy-arn "${POLICY_ARN}" \
    --query 'UpdateToken' --output text)
  aws network-firewall update-firewall-policy \
    --firewall-policy-arn "${POLICY_ARN}" \
    --update-token "${update_token}" \
    --firewall-policy "${policy_json}" \
    --query 'FirewallPolicyResponse.FirewallPolicyStatus' --output text
}

case $PHASE in
  1)
    echo "=== Phase 1: ステートレスルールのみ ==="
    echo "bench-fw-policy を更新 (statelessDefaultActions=aws:pass, ステートフル無効)..."
    update_main_policy "{
      \"StatelessDefaultActions\": [\"aws:pass\"],
      \"StatelessFragmentDefaultActions\": [\"aws:pass\"],
      \"StatelessRuleGroupReferences\": [{
        \"ResourceArn\": \"${STATELESS_RG_ARN}\",
        \"Priority\": 1
      }]
    }"
    echo "bench-fw-policy をファイアウォールに関連付け..."
    associate_policy "${POLICY_ARN}"
    ;;

  2)
    echo "=== Phase 2: ステートフルルール追加 ==="
    echo "bench-fw-policy を更新 (statelessDefaultActions=aws:forward_to_sfe)..."
    update_main_policy "{
      \"StatelessDefaultActions\": [\"aws:forward_to_sfe\"],
      \"StatelessFragmentDefaultActions\": [\"aws:forward_to_sfe\"],
      \"StatelessRuleGroupReferences\": [{
        \"ResourceArn\": \"${STATELESS_RG_ARN}\",
        \"Priority\": 1
      }],
      \"StatefulRuleGroupReferences\": [{
        \"ResourceArn\": \"${STATEFUL_RG_ARN}\"
      }]
    }"
    echo "bench-fw-policy をファイアウォールに関連付け..."
    associate_policy "${POLICY_ARN}"
    ;;

  3)
    echo "=== Phase 3: TLS検査有効化 ==="
    REGION=$(aws configure get region 2>/dev/null || echo "ap-northeast-1")
    TLS_CONFIG_NAME="bench-tls-inspection"
    CERT_KEY="/tmp/bench-phase3-server.key"
    CERT_CRT="/tmp/bench-phase3-server.crt"

    # 1. 自己署名証明書を生成
    echo "[1/5] 自己署名証明書を生成..."
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -keyout "${CERT_KEY}" \
      -out "${CERT_CRT}" \
      -subj "/CN=bench-server" \
      -addext "subjectAltName=DNS:bench-server" 2>/dev/null
    echo "  OK: ${CERT_CRT}"

    # 2. ACMにインポート (既存があれば再インポート)
    echo "[2/5] ACMに証明書をインポート..."
    EXISTING_ACM_ARN=$(aws acm list-certificates \
      --query "CertificateSummaryList[?DomainName=='bench-server'].CertificateArn | [0]" \
      --output text 2>/dev/null || echo "None")

    if [ "${EXISTING_ACM_ARN}" != "None" ] && [ -n "${EXISTING_ACM_ARN}" ]; then
      ACM_ARN=$(aws acm import-certificate \
        --certificate-arn "${EXISTING_ACM_ARN}" \
        --certificate "fileb://${CERT_CRT}" \
        --private-key "fileb://${CERT_KEY}" \
        --query 'CertificateArn' --output text)
    else
      ACM_ARN=$(aws acm import-certificate \
        --certificate "fileb://${CERT_CRT}" \
        --private-key "fileb://${CERT_KEY}" \
        --query 'CertificateArn' --output text)
    fi
    echo "  ACM ARN: ${ACM_ARN}"

    # 3. TLS inspection configuration を作成または更新
    echo "[3/5] TLS inspection configuration を設定..."
    EXISTING_TLS=$(aws network-firewall list-tls-inspection-configurations \
      --query "TLSInspectionConfigurations[?Name=='${TLS_CONFIG_NAME}'].Arn | [0]" \
      --output text 2>/dev/null || echo "None")

    TLS_CONFIG_BODY="{
      \"ServerCertificateConfigurations\": [{
        \"ServerCertificates\": [{\"ResourceArn\": \"${ACM_ARN}\"}],
        \"Scopes\": [{
          \"Sources\": [{\"AddressDefinition\": \"10.0.0.0/24\"}],
          \"Destinations\": [{\"AddressDefinition\": \"10.0.2.0/24\"}],
          \"SourcePorts\": [{\"FromPort\": 0, \"ToPort\": 65535}],
          \"DestinationPorts\": [{\"FromPort\": 443, \"ToPort\": 443}],
          \"Protocols\": [6]
        }]
      }]
    }"

    if [ "${EXISTING_TLS}" != "None" ] && [ -n "${EXISTING_TLS}" ]; then
      TLS_UPDATE_TOKEN=$(aws network-firewall describe-tls-inspection-configuration \
        --tls-inspection-configuration-arn "${EXISTING_TLS}" \
        --query 'UpdateToken' --output text)
      TLS_CONFIG_ARN=$(aws network-firewall update-tls-inspection-configuration \
        --tls-inspection-configuration-arn "${EXISTING_TLS}" \
        --update-token "${TLS_UPDATE_TOKEN}" \
        --tls-inspection-configuration "${TLS_CONFIG_BODY}" \
        --tls-inspection-configuration-name "${TLS_CONFIG_NAME}" \
        --query 'TLSInspectionConfigurationResponse.TLSInspectionConfigurationArn' \
        --output text)
    else
      TLS_CONFIG_ARN=$(aws network-firewall create-tls-inspection-configuration \
        --tls-inspection-configuration-name "${TLS_CONFIG_NAME}" \
        --tls-inspection-configuration "${TLS_CONFIG_BODY}" \
        --query 'TLSInspectionConfigurationResponse.TLSInspectionConfigurationArn' \
        --output text)
    fi
    echo "  TLS Config ARN: ${TLS_CONFIG_ARN}"

    # 4. TLS検査付きのポリシーを作る(既にあれば使う)
    #    TLS検査の設定は既存のポリシーを更新して追加できないため、作るときに付ける
    echo "[4/5] TLS検査付きのポリシー bench-fw-policy-tls を用意..."
    TLS_POLICY_NAME="bench-fw-policy-tls"
    TLS_POLICY_ARN=$(aws network-firewall list-firewall-policies \
      --query "FirewallPolicies[?Name=='${TLS_POLICY_NAME}'].Arn | [0]" --output text)
    if [ "${TLS_POLICY_ARN}" = "None" ] || [ -z "${TLS_POLICY_ARN}" ]; then
      TLS_POLICY_ARN=$(aws network-firewall create-firewall-policy \
        --firewall-policy-name "${TLS_POLICY_NAME}" \
        --firewall-policy "{
          \"StatelessDefaultActions\": [\"aws:forward_to_sfe\"],
          \"StatelessFragmentDefaultActions\": [\"aws:forward_to_sfe\"],
          \"StatelessRuleGroupReferences\": [{
            \"ResourceArn\": \"${STATELESS_RG_ARN}\",
            \"Priority\": 1
          }],
          \"StatefulEngineOptions\": {\"RuleOrder\": \"STRICT_ORDER\"},
          \"StatefulRuleGroupReferences\": [{
            \"ResourceArn\": \"${STRICT_STATEFUL_RG_ARN}\",
            \"Priority\": 1
          }],
          \"TLSInspectionConfigurationArn\": \"${TLS_CONFIG_ARN}\"
        }" \
        --query 'FirewallPolicyResponse.FirewallPolicyArn' --output text)
    fi
    echo "  Policy ARN: ${TLS_POLICY_ARN}"

    # 5. TLS検査付きのポリシーをファイアウォールに関連付け
    echo "[5/5] bench-fw-policy-tls をファイアウォールに関連付け..."
    associate_policy "${TLS_POLICY_ARN}"
    ;;

  *)
    echo "ERROR: 不明なフェーズ: ${PHASE}"
    echo "Usage: $0 <1|2|3> [outputs.json]"
    exit 1
    ;;
esac

echo ""
echo "ポリシーを更新しました。反映待機中 (30秒)..."
sleep 30
echo "準備完了。bench.sh を実行してください。"
