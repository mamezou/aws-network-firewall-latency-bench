#!/bin/bash
# =============================================================
# 計測環境の削除スクリプト
#
# 使い方:
#   ./scripts/cleanup.sh
#
# CDKの外で作ったもの(setup-routes.sh のルート、switch-phase.sh 3 の
# TLS検査付きポリシー・TLS検査設定・ACM証明書)も消し、最後にNetwork Firewallなどが
# 残っていないかを確かめる。途中で止まっても、再実行すれば続きから消す。
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="NfwLatencyBenchStack"
FIREWALL_NAME="bench-nfw"
TLS_CONFIG_NAME="bench-tls-inspection"
TLS_POLICY_NAME="bench-fw-policy-tls"
CERT_DOMAIN="bench-server"

# 同じ処理を、成功するまで最大 tries 回(15秒間隔)繰り返す
retry() {
  local tries="$1"; shift
  local i
  for ((i = 1; i <= tries; i++)); do
    if "$@"; then return 0; fi
    echo "  まだ消せないので15秒待って再試行する (${i}/${tries})"
    sleep 15
  done
  return 1
}

stack_output() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  echo "=== 1. ファイアウォールをメインのポリシーに戻す ==="
  MAIN_POLICY_ARN=$(stack_output FirewallPolicyArn)
  if aws network-firewall describe-firewall --firewall-name "${FIREWALL_NAME}" >/dev/null 2>&1; then
    CURRENT_POLICY_ARN=$(aws network-firewall describe-firewall --firewall-name "${FIREWALL_NAME}" \
      --query 'Firewall.FirewallPolicyArn' --output text)
    if [ "${CURRENT_POLICY_ARN}" != "${MAIN_POLICY_ARN}" ]; then
      UPDATE_TOKEN=$(aws network-firewall describe-firewall --firewall-name "${FIREWALL_NAME}" \
        --query 'UpdateToken' --output text)
      aws network-firewall associate-firewall-policy \
        --firewall-name "${FIREWALL_NAME}" \
        --firewall-policy-arn "${MAIN_POLICY_ARN}" \
        --update-token "${UPDATE_TOKEN}" \
        --query 'FirewallPolicyArn' --output text
      echo "  関連付けの反映を待つ"
      sleep 30
    else
      echo "  メインのポリシーが関連付け済み"
    fi
  fi

  echo "=== 2. switch-phase.sh 3 が作ったTLS検査付きのポリシーを消す ==="
  # このポリシーはCDKのルールグループを参照するため、先に消さないとスタックの削除が「使用中」で失敗する
  TLS_POLICY_ARN=$(aws network-firewall list-firewall-policies \
    --query "FirewallPolicies[?Name=='${TLS_POLICY_NAME}'].Arn | [0]" --output text)
  if [ "${TLS_POLICY_ARN}" != "None" ] && [ -n "${TLS_POLICY_ARN}" ]; then
    retry 20 aws network-firewall delete-firewall-policy --firewall-policy-arn "${TLS_POLICY_ARN}" \
      --query 'FirewallPolicyResponse.FirewallPolicyStatus' --output text
    policy_gone() {
      [ "$(aws network-firewall list-firewall-policies \
        --query "FirewallPolicies[?Name=='${TLS_POLICY_NAME}'].Arn | [0]" --output text)" = "None" ]
    }
    retry 20 policy_gone
    echo "  ポリシーを削除: ${TLS_POLICY_NAME}"
  else
    echo "  TLS検査付きのポリシーはなし"
  fi

  echo "=== 3. setup-routes.sh で足したルートを消す ==="
  CLIENT_RT_ID=$(stack_output ClientSubnetRouteTableId)
  SERVER_RT_ID=$(stack_output ServerSubnetRouteTableId)
  aws ec2 delete-route --route-table-id "${CLIENT_RT_ID}" --destination-cidr-block 10.0.2.0/24 2>/dev/null \
    && echo "  Client RT のルートを削除" || echo "  Client RT のルートはなし"
  aws ec2 delete-route --route-table-id "${SERVER_RT_ID}" --destination-cidr-block 10.0.0.0/24 2>/dev/null \
    && echo "  Server RT のルートを削除" || echo "  Server RT のルートはなし"

  echo "=== 4. スタックを削除する ==="
  (cd "${SCRIPT_DIR}/.." && npx cdk destroy --force)
else
  echo "=== 1〜4. スタックはないので飛ばす ==="
fi

echo "=== 5. TLS検査設定とACM証明書を消す ==="
TLS_ARN=$(aws network-firewall list-tls-inspection-configurations \
  --query "TLSInspectionConfigurations[?Name=='${TLS_CONFIG_NAME}'].Arn | [0]" --output text)
if [ "${TLS_ARN}" != "None" ] && [ -n "${TLS_ARN}" ]; then
  retry 20 aws network-firewall delete-tls-inspection-configuration \
    --tls-inspection-configuration-arn "${TLS_ARN}" --query 'TLSInspectionConfigurationResponse.TLSInspectionConfigurationStatus' --output text
  tls_gone() {
    [ "$(aws network-firewall list-tls-inspection-configurations \
      --query "TLSInspectionConfigurations[?Name=='${TLS_CONFIG_NAME}'].Arn | [0]" --output text)" = "None" ]
  }
  retry 20 tls_gone
  echo "  TLS検査設定を削除: ${TLS_CONFIG_NAME}"
else
  echo "  TLS検査設定はなし"
fi
for CERT_ARN in $(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='${CERT_DOMAIN}'].CertificateArn" --output text); do
  retry 20 aws acm delete-certificate --certificate-arn "${CERT_ARN}"
  echo "  証明書を削除: ${CERT_ARN}"
done
rm -f /tmp/bench-phase3-server.key /tmp/bench-phase3-server.crt

echo "=== 6. 残っていないかを確かめる ==="
LEFT=0
check() {
  local label="$1" value="$2"
  if [ -n "${value}" ] && [ "${value}" != "None" ]; then
    echo "  残っている: ${label} ${value}"
    LEFT=1
  fi
}
check "スタック" "$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)"
check "ファイアウォール" "$(aws network-firewall list-firewalls \
  --query "Firewalls[?FirewallName=='${FIREWALL_NAME}'].FirewallName" --output text)"
check "ファイアウォールポリシー" "$(aws network-firewall list-firewall-policies \
  --query "FirewallPolicies[?starts_with(Name,'bench-')].Name" --output text)"
check "ルールグループ" "$(aws network-firewall list-rule-groups \
  --query "RuleGroups[?starts_with(Name,'bench-')].Name" --output text)"
check "TLS検査設定" "$(aws network-firewall list-tls-inspection-configurations \
  --query "TLSInspectionConfigurations[?Name=='${TLS_CONFIG_NAME}'].Name" --output text)"
check "ACM証明書" "$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='${CERT_DOMAIN}'].CertificateArn" --output text)"

if [ "${LEFT}" -eq 0 ]; then
  echo "  すべて削除済み"
else
  echo "  残っているものがある。しばらく待ってから再実行するか、コンソールで状態を確かめる"
  exit 1
fi
