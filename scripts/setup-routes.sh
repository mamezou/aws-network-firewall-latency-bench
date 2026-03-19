#!/bin/bash
# =============================================================
# NFWエンドポイント経由のルートテーブル設定スクリプト
#
# 使い方:
#   ./scripts/setup-routes.sh [outputs.json のパス]
#
# outputs.json は cdk deploy --outputs-file outputs.json で生成:
#   npx cdk deploy --outputs-file outputs.json
#
# デフォルトでプロジェクトルートの outputs.json を参照する。
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUTS_FILE="${1:-${SCRIPT_DIR}/../outputs.json}"

if [ ! -f "${OUTPUTS_FILE}" ]; then
  echo "ERROR: outputs.json が見つかりません: ${OUTPUTS_FILE}"
  echo ""
  echo "先に以下を実行してください:"
  echo "  npx cdk deploy --outputs-file outputs.json"
  exit 1
fi

STACK_NAME="NfwLatencyBenchStack"

CLIENT_RT_ID=$(jq -r ".${STACK_NAME}.ClientSubnetRouteTableId" "${OUTPUTS_FILE}")
SERVER_RT_ID=$(jq -r ".${STACK_NAME}.ServerSubnetRouteTableId" "${OUTPUTS_FILE}")

if [ "${CLIENT_RT_ID}" = "null" ] || [ "${SERVER_RT_ID}" = "null" ]; then
  echo "ERROR: outputs.json に必要なキーがありません。"
  echo "  期待するキー: ${STACK_NAME}.ClientSubnetRouteTableId, ${STACK_NAME}.ServerSubnetRouteTableId"
  echo "  実際の内容:"
  jq . "${OUTPUTS_FILE}"
  exit 1
fi

echo "=== 設定値 ==="
echo "outputs.json: ${OUTPUTS_FILE}"
echo "Client RT:    ${CLIENT_RT_ID}"
echo "Server RT:    ${SERVER_RT_ID}"
echo ""

echo "=== NFWエンドポイントID取得 ==="
VPCE_ID=$(aws network-firewall describe-firewall \
  --firewall-name bench-nfw \
  --output json \
  | jq -r '.FirewallStatus.SyncStates[].Attachment.EndpointId')

if [ -z "${VPCE_ID}" ]; then
  echo "ERROR: NFWエンドポイントIDを取得できませんでした。"
  echo "  NFWの同期が完了していない可能性があります。数分待ってから再実行してください。"
  exit 1
fi

echo "NFW Endpoint ID: ${VPCE_ID}"
echo ""

echo "=== ルート設定 ==="

echo "[1/2] Client Subnet → Server Subnet (10.0.2.0/24) を NFW経由に設定..."
aws ec2 create-route \
  --route-table-id "${CLIENT_RT_ID}" \
  --destination-cidr-block 10.0.2.0/24 \
  --vpc-endpoint-id "${VPCE_ID}"
echo "  OK"

echo "[2/2] Server Subnet → Client Subnet (10.0.0.0/24) を NFW経由に設定 (対称ルーティング)..."
aws ec2 create-route \
  --route-table-id "${SERVER_RT_ID}" \
  --destination-cidr-block 10.0.0.0/24 \
  --vpc-endpoint-id "${VPCE_ID}"
echo "  OK"

echo ""
echo "=== 完了 ==="
echo "次のステップ: scripts/switch-phase.sh でフェーズを切り替えてベンチマークを実行してください。"
