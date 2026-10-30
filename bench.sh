#!/bin/bash
# =============================================================
# AWS Network Firewall レイテンシーベンチマークスクリプト
#
# 使い方:
#   1. SSM Session Manager で ClientInstance に接続
#   2. このスクリプトを配置して実行
#      chmod +x bench.sh
#      sudo ./bench.sh <SERVER_IP> <BASELINE_IP>
#      (hping3はroot権限が必要)
#
# テストフェーズ:
#   Phase 0: ベースライン (同一サブネット内、Firewall経由なし) → BASELINE_IP 宛
#   Phase 1: ステートレスルールのみ          → SERVER_IP 宛 (NFW経由)
#   Phase 2: ステートフルルール追加          → SERVER_IP 宛 (NFW経由)
#   Phase 3: TLS検査有効化                  → SERVER_IP / BASELINE_IP 宛
#
# 各フェーズで以下を計測:
#   - TCP RTT (p50/p95/p99、nping。nping がなければ hping3) ← メイン計測
#   - ping ICMP RTT (avg)
#   - iperf3 スループット + リトランスミット
#
# 注意:
#   - フェーズ切り替え後は scripts/switch-phase.sh が30秒待機してから呼び出すこと
#   - hping3はroot権限が必要 (sudo)
# =============================================================

set -euo pipefail

SERVER_IP="${1:?Usage: sudo $0 <SERVER_IP> <BASELINE_IP>}"
BASELINE_IP="${2:?Usage: sudo $0 <SERVER_IP> <BASELINE_IP>}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="/tmp/nfw-bench-${TIMESTAMP}"
mkdir -p "${RESULT_DIR}"

HPING3_COUNT=100
PING_COUNT=100
IPERF3_DURATION=10

echo "=========================================="
echo " NFW Latency Benchmark - ${TIMESTAMP}"
echo "=========================================="
echo "Server IP  (via NFW): ${SERVER_IP}"
echo "Baseline IP (direct): ${BASELINE_IP}"
echo "Results dir: ${RESULT_DIR}"
echo ""

# ------------------------------------------
# 関数: パーセンタイル計算 (awk)
# 引数: ファイルパス (1行1値、ms単位の数値)
# ------------------------------------------
calc_percentiles() {
  local file="$1"
  awk '
  BEGIN { n=0 }
  /^[0-9]/ { vals[n++]=$1 }
  END {
    if (n == 0) { print "  (no data)"; exit }
    # バブルソート (N<=200程度なので許容)
    for (i=0; i<n-1; i++)
      for (j=0; j<n-i-1; j++)
        if (vals[j] > vals[j+1]) { t=vals[j]; vals[j]=vals[j+1]; vals[j+1]=t }
    p50 = vals[int(n*0.50)]
    p95 = vals[int(n*0.95)]
    p99 = vals[int(n*0.99)]
    sum=0; for(i=0;i<n;i++) sum+=vals[i]
    avg=sum/n
    printf "  count=%-4d  avg=%.3f  p50=%.3f  p95=%.3f  p99=%.3f (ms)\n", n, avg, p50, p95, p99
  }
  ' "${file}"
}

# ------------------------------------------
# 関数: TCP RTT 計測 (nping / hping3 を自動選択)
# nping は root権限が必要
# ------------------------------------------
run_hping3_test() {
  local label="$1"
  local target_ip="$2"
  local port="${3:-5201}"
  local output_file="${RESULT_DIR}/hping3_${label}.txt"
  local parsed_file="${RESULT_DIR}/hping3_${label}_rtt.txt"

  if command -v nping &>/dev/null; then
    # nping (nmapパッケージ): --rate 100 で 100pps
    echo "[${label}] nping --tcp -p ${port} -c ${HPING3_COUNT} --rate 100 ${target_ip}"
    nping --tcp -p "${port}" -c "${HPING3_COUNT}" --rate 100 "${target_ip}" > "${output_file}" 2>&1 || true
    # RTT計算: SENT(Ts) と RCVD(Tr) のペアから (Tr-Ts)*1000 ms
    awk '
      /^SENT/ { match($2, /\(([0-9.]+)s\)/, a); sent=a[1] }
      /^RCVD/ { match($2, /\(([0-9.]+)s\)/, a); if (sent!="") { printf "%.3f\n", (a[1]-sent)*1000; sent="" } }
    ' "${output_file}" > "${parsed_file}" || true

  elif command -v hping3 &>/dev/null; then
    echo "[${label}] hping3 --tcp --fast -p ${port} -c ${HPING3_COUNT} ${target_ip}"
    hping3 --tcp --fast -p "${port}" -c "${HPING3_COUNT}" "${target_ip}" > "${output_file}" 2>&1 || true
    grep -oP 'rtt=\K[0-9.]+' "${output_file}" > "${parsed_file}" || true

  else
    echo "  WARNING: nping/hping3 not found, skipping TCP RTT test"
    return
  fi

  echo "--- ${label} TCP RTT (nping) ---"
  calc_percentiles "${parsed_file}"
  echo ""
}

# ------------------------------------------
# 関数: ping ICMP RTT 計測
# ------------------------------------------
run_ping_test() {
  local label="$1"
  local target_ip="$2"
  local output_file="${RESULT_DIR}/ping_${label}.txt"

  echo "[${label}] ping -c ${PING_COUNT} -i 0.1 ${target_ip}"
  ping -c "${PING_COUNT}" -i 0.1 "${target_ip}" > "${output_file}" 2>&1 || true

  echo "--- ${label} ping ICMP RTT ---"
  grep "rtt min" "${output_file}" | sed 's/^/  /' || echo "  (no data)"
  echo ""
}

# ------------------------------------------
# 関数: iperf3 スループット計測
# ------------------------------------------
run_iperf3_test() {
  local label="$1"
  local target_ip="$2"
  local output_file="${RESULT_DIR}/iperf3_${label}.json"

  echo "[${label}] iperf3 -c ${target_ip} -t ${IPERF3_DURATION} -J"
  iperf3 -c "${target_ip}" -t "${IPERF3_DURATION}" -J > "${output_file}" 2>&1 || true

  echo "--- ${label} iperf3 ---"
  if command -v jq &>/dev/null && [ -s "${output_file}" ]; then
    jq -r '"  sent=\(.end.sum_sent.bits_per_second/1000000 | . * 100 | round / 100) Mbps  recv=\(.end.sum_received.bits_per_second/1000000 | . * 100 | round / 100) Mbps  retransmits=\(.end.sum_sent.retransmits)"' \
      "${output_file}" 2>/dev/null || echo "  (parse error)"
  else
    echo "  (jq not found or empty output)"
  fi
  echo ""
}

# ------------------------------------------
# 関数: curl HTTPS 接続時間計測 (Phase 3用)
# ------------------------------------------
run_https_test() {
  local label="$1"
  local target_ip="$2"
  local count=50
  local output_file="${RESULT_DIR}/https_${label}.txt"
  local connect_file="${RESULT_DIR}/https_connect_${label}.txt"
  local tls_file="${RESULT_DIR}/https_tls_${label}.txt"

  echo "[${label}] HTTPS connect x${count} to ${target_ip}"
  echo "# time_connect (s)" > "${output_file}"

  for i in $(seq 1 ${count}); do
    curl -sk \
      -w "%{time_connect} %{time_appconnect}\n" \
      -o /dev/null \
      "https://${target_ip}/" 2>/dev/null >> "${output_file}" || echo "FAIL" >> "${output_file}"
  done

  # time_connect と time_appconnect (TLS完了まで) を ms に変換して分離
  awk '/^[0-9]/ { printf "%.3f\n", $1*1000 }' "${output_file}" > "${connect_file}"
  awk '/^[0-9]/ { printf "%.3f\n", $2*1000 }' "${output_file}" > "${tls_file}"

  echo "--- ${label} HTTPS TCP connect (ms) ---"
  calc_percentiles "${connect_file}"
  echo "--- ${label} HTTPS TLS handshake (ms) ---"
  calc_percentiles "${tls_file}"
  echo ""
}

# ------------------------------------------
# ヘルパー: 1ファイルからp50を取り出す
# ------------------------------------------
get_p50() {
  local file="$1"
  awk '
  BEGIN { n=0 }
  /^[0-9]/ { vals[n++]=$1 }
  END {
    if (n == 0) { print "N/A"; exit }
    for (i=0; i<n-1; i++)
      for (j=0; j<n-i-1; j++)
        if (vals[j] > vals[j+1]) { t=vals[j]; vals[j]=vals[j+1]; vals[j+1]=t }
    printf "%.3f", vals[int(n*0.50)]
  }' "${file}" 2>/dev/null || echo "N/A"
}

get_p95() {
  local file="$1"
  awk '
  BEGIN { n=0 }
  /^[0-9]/ { vals[n++]=$1 }
  END {
    if (n == 0) { print "N/A"; exit }
    for (i=0; i<n-1; i++)
      for (j=0; j<n-i-1; j++)
        if (vals[j] > vals[j+1]) { t=vals[j]; vals[j]=vals[j+1]; vals[j+1]=t }
    printf "%.3f", vals[int(n*0.95)]
  }' "${file}" 2>/dev/null || echo "N/A"
}

get_p99() {
  local file="$1"
  awk '
  BEGIN { n=0 }
  /^[0-9]/ { vals[n++]=$1 }
  END {
    if (n == 0) { print "N/A"; exit }
    for (i=0; i<n-1; i++)
      for (j=0; j<n-i-1; j++)
        if (vals[j] > vals[j+1]) { t=vals[j]; vals[j]=vals[j+1]; vals[j+1]=t }
    printf "%.3f", vals[int(n*0.99)]
  }' "${file}" 2>/dev/null || echo "N/A"
}

get_ping_avg() {
  local file="$1"
  # 形式: rtt min/avg/max/mdev = 0.059/0.080/0.482/0.040 ms
  grep "rtt min" "${file}" 2>/dev/null | grep -oP 'min/avg/max/mdev = [0-9.]+/\K[0-9.]+' || echo "N/A"
}

get_iperf3_mbps() {
  local file="$1"
  if command -v jq &>/dev/null && [ -s "${file}" ]; then
    jq -r '(.end.sum_received.bits_per_second/1000000 | . * 10 | round / 10 | tostring) + " Mbps"' \
      "${file}" 2>/dev/null || echo "N/A"
  else
    echo "N/A"
  fi
}

calc_delta() {
  local baseline="$1"
  local via_nfw="$2"
  if [ "${baseline}" = "N/A" ] || [ "${via_nfw}" = "N/A" ]; then
    echo "N/A"
    return
  fi
  echo "${via_nfw} ${baseline}" | awk '{
    d = $1 - $2
    if (d >= 0) printf "+%.3f", d
    else printf "%.3f", d
  }'
}

# ===========================================
# Phase 0 (Baseline): 同一サブネット、NFW経由なし
# ===========================================
echo "=========================================="
echo " Phase 0: Baseline (Direct, same subnet)"
echo "=========================================="
run_hping3_test "baseline" "${BASELINE_IP}"
run_ping_test "baseline" "${BASELINE_IP}"
run_iperf3_test "baseline" "${BASELINE_IP}"

# ===========================================
# Via NFW: 現在のフェーズ設定でNFW経由計測
# ===========================================
echo "=========================================="
echo " Via NFW (current phase setting)"
echo "=========================================="
run_hping3_test "via_nfw" "${SERVER_IP}"
run_ping_test "via_nfw" "${SERVER_IP}"
run_iperf3_test "via_nfw" "${SERVER_IP}"

# ===========================================
# HTTPS計測 (Phase 3向け。nginxが起動していれば計測)
# ===========================================
if curl -sk --connect-timeout 2 "https://${SERVER_IP}/" -o /dev/null 2>/dev/null; then
  echo "=========================================="
  echo " HTTPS (TLS inspection)"
  echo "=========================================="
  run_https_test "baseline_https" "${BASELINE_IP}"
  run_https_test "via_nfw_https" "${SERVER_IP}"
fi

# ===========================================
# 比較サマリー
# ===========================================
echo ""
echo "======= COMPARISON SUMMARY ======="
echo ""

BL_H_P50=$(get_p50 "${RESULT_DIR}/hping3_baseline_rtt.txt" 2>/dev/null || echo "N/A")
BL_H_P95=$(get_p95 "${RESULT_DIR}/hping3_baseline_rtt.txt" 2>/dev/null || echo "N/A")
BL_H_P99=$(get_p99 "${RESULT_DIR}/hping3_baseline_rtt.txt" 2>/dev/null || echo "N/A")
NF_H_P50=$(get_p50 "${RESULT_DIR}/hping3_via_nfw_rtt.txt" 2>/dev/null || echo "N/A")
NF_H_P95=$(get_p95 "${RESULT_DIR}/hping3_via_nfw_rtt.txt" 2>/dev/null || echo "N/A")
NF_H_P99=$(get_p99 "${RESULT_DIR}/hping3_via_nfw_rtt.txt" 2>/dev/null || echo "N/A")

BL_PING=$(get_ping_avg "${RESULT_DIR}/ping_baseline.txt" 2>/dev/null || echo "N/A")
NF_PING=$(get_ping_avg "${RESULT_DIR}/ping_via_nfw.txt" 2>/dev/null || echo "N/A")

BL_IPERF=$(get_iperf3_mbps "${RESULT_DIR}/iperf3_baseline.json" 2>/dev/null || echo "N/A")
NF_IPERF=$(get_iperf3_mbps "${RESULT_DIR}/iperf3_via_nfw.json" 2>/dev/null || echo "N/A")

printf "%-24s %-14s %-14s %s\n" "" "Baseline" "Via NFW" "Delta"
printf "%-24s %-14s %-14s %s\n" "hping3 TCP p50 (ms):" "${BL_H_P50}" "${NF_H_P50}" "$(calc_delta "${BL_H_P50}" "${NF_H_P50}") ms"
printf "%-24s %-14s %-14s %s\n" "hping3 TCP p95 (ms):" "${BL_H_P95}" "${NF_H_P95}" "$(calc_delta "${BL_H_P95}" "${NF_H_P95}") ms"
printf "%-24s %-14s %-14s %s\n" "hping3 TCP p99 (ms):" "${BL_H_P99}" "${NF_H_P99}" "$(calc_delta "${BL_H_P99}" "${NF_H_P99}") ms"
printf "%-24s %-14s %-14s\n"    "ping ICMP avg (ms):"  "${BL_PING}"   "${NF_PING}"
printf "%-24s %-14s %-14s\n"    "iperf3 recv (Mbps):"  "${BL_IPERF}"  "${NF_IPERF}"

# HTTPS計測結果があれば追加
if [ -f "${RESULT_DIR}/https_connect_baseline_https.txt" ]; then
  BL_TLS=$(get_p50 "${RESULT_DIR}/https_tls_baseline_https.txt" 2>/dev/null || echo "N/A")
  NF_TLS=$(get_p50 "${RESULT_DIR}/https_tls_via_nfw_https.txt" 2>/dev/null || echo "N/A")
  printf "%-24s %-14s %-14s %s\n" "HTTPS TLS p50 (ms):" "${BL_TLS}" "${NF_TLS}" "$(calc_delta "${BL_TLS}" "${NF_TLS}") ms"
fi

echo ""
echo "All raw results saved in: ${RESULT_DIR}"
echo "=================================="
