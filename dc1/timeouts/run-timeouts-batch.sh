#!/bin/bash
set -euo pipefail

# Hard-coded batch runner: 100 iterations per delay value.

NAMESPACE="objs-fed"
SERVICE_NAME="backend"
TIMEOUT_S="1"
RATE="60"
DURATION="60s"
DELAY_S_LIST=("1" "1.2" "1.5")

BASE_URL="http://172.18.0.2:31537/shuffle?error-rate=0&delay="
OUTDIR="timeouts_benchmark"
YAML_FILE="timeouts.yaml"
SLEEP_AFTER_APPLY=8
ITERATIONS_PER_DELAY="50"

mkdir -p "$OUTDIR"

ns2ms() { awk '{ printf "%.6f\n", $1/1000000.0 }'; }
mean_from_stream() { awk 'BEGIN{s=0;n=0} {s+=$1;n+=1} END{ if(n>0) printf "%.6f", s/n; else printf "0"}'; }
percentile_stream() {
  local PCT="$1"
  sort -n | awk -v p="$PCT" '
    { a[++n]=$1 }
    END {
      if (n==0) { print 0; exit }
      idx=int((p/100.0)*n); if (idx<1) idx=1; if (idx>n) idx=n;
      print a[idx]
    }'
}
parse_text_report() {
  local txt="$1"
  local total rate throughput
  read -r total rate throughput < <(grep -E '^Requests' "$txt" \
    | awk -F'[][]' '{print $3}' \
    | awk -F',' '{gsub(/ /,""); print $1, $2, $3}')

  local success_ratio
  success_ratio=$(grep -E '^Success' "$txt" | awk -F'[][% ]+' '{print $(NF-1)}')
  if [ -z "$success_ratio" ]; then success_ratio="0"; fi

  local status_line
  status_line=$(grep -E '^Status Codes' -A0 "$txt" || true)
  local success_cnt=0
  local timeout_cnt=0
  if [ -n "$status_line" ]; then
    while read -r pair; do
      local code="${pair%%:*}"
      local count="${pair##*:}"
      if [[ -n "$code" && -n "$count" ]]; then
        if (( code >= 200 && code < 300 )); then success_cnt=$((success_cnt + count)); fi
        if (( code == 504 )); then timeout_cnt=$((timeout_cnt + count)); fi
      fi
    done < <(echo "$status_line" | grep -oE '[0-9]+:[0-9]+')
  fi

  echo "$total" "$rate" "$throughput" "$success_ratio" "$success_cnt" "$timeout_cnt"
}
summarize_from_json() {
  local json="$1"
  local timeout_ms
  timeout_ms=$(awk -v t="$TIMEOUT_S" 'BEGIN{printf "%.6f", t*1000.0}')

  local ta_mean ta_p95
  if jq -e 'select(((.code|tonumber)==504) or ((.error|tostring)|test("(?i)timeout|deadline"))) | .latency' "$json" >/dev/null; then
    ta_mean=$(
      jq -r 'select(((.code|tonumber)==504) or ((.error|tostring)|test("(?i)timeout|deadline"))) | .latency' "$json" \
      | ns2ms | awk -v t="$timeout_ms" '{d=$1-t; if(d<0)d=-d; print d}' | mean_from_stream
    )
    ta_p95=$(
      jq -r 'select(((.code|tonumber)==504) or ((.error|tostring)|test("(?i)timeout|deadline"))) | .latency' "$json" \
      | ns2ms | awk -v t="$timeout_ms" '{d=$1-t; if(d<0)d=-d; print d}' | percentile_stream 95
    )
  else
    ta_mean="0"; ta_p95="0"
  fi

  local wt_mean wt_p95
  if jq -e 'select((.code|tonumber)<200 or (.code|tonumber)>=300) | .latency' "$json" >/dev/null; then
    wt_mean=$(jq -r 'select((.code|tonumber)<200 or (.code|tonumber)>=300) | .latency' "$json" | ns2ms | mean_from_stream)
    wt_p95=$(jq -r 'select((.code|tonumber)<200 or (.code|tonumber)>=300) | .latency' "$json" | ns2ms | percentile_stream 95)
  else
    wt_mean="0"; wt_p95="0"
  fi

  local p95_200 p99_200
  if jq -e 'select((.code|tonumber)>=200 and (.code|tonumber)<300) | .latency' "$json" >/dev/null; then
    p95_200=$(jq -r 'select((.code|tonumber)>=200 and (.code|tonumber)<300) | .latency' "$json" | ns2ms | percentile_stream 95)
    p99_200=$(jq -r 'select((.code|tonumber)>=200 and (.code|tonumber)<300) | .latency' "$json" | ns2ms | percentile_stream 99)
  else
    p95_200="0"; p99_200="0"
  fi

  echo "$ta_mean,$ta_p95,$wt_mean,$wt_p95,$p95_200,$p99_200"
}

CSV="timeouts_summary.csv"
if [ ! -f "$CSV" ]; then
  echo "Iteration,Timestamp,Namespace,Service,Timeout(s),Delay(s),Rate,Duration,Total,SuccessRatio(%),SuccessCount,Errors,TimeoutHits,TimeoutHitRate(%),TimeoutAccuracyMean(ms),TimeoutAccuracyP95(ms),WastedTimeMean(ms),WastedTimeP95(ms),P95_200(ms),P99_200(ms)" > "$CSV"
fi

echo "🛠️  Applying timeout ($TIMEOUT_S)s via ServiceRouter to $SERVICE_NAME in $NAMESPACE..."
kubectl -n "$NAMESPACE" apply -f "$YAML_FILE" >/dev/null
echo "⏳ Waiting ${SLEEP_AFTER_APPLY}s for Envoy to receive new config..."
sleep "$SLEEP_AFTER_APPLY"

ITER=1
for DELAY in "${DELAY_S_LIST[@]}"; do
  for ((i=1; i<=ITERATIONS_PER_DELAY; i++)); do
    TS=$(date +%Y%m%d_%H%M%S)
    URL="${BASE_URL}${DELAY}"

    BIN="$OUTDIR/timeout${TIMEOUT_S}s_delay${DELAY}s_r${RATE}_${TS}.bin"
    JSON="$OUTDIR/timeout${TIMEOUT_S}s_delay${DELAY}s_r${RATE}_${TS}.json"
    TXT="$OUTDIR/timeout${TIMEOUT_S}s_delay${DELAY}s_r${RATE}_${TS}_text.txt"
    HIST="$OUTDIR/timeout${TIMEOUT_S}s_delay${DELAY}s_r${RATE}_${TS}_hist.txt"

    echo "▶️  Iteration $i/100, delay=${DELAY}s"
    echo "🚀 Vegeta attack ${RATE} rps for ${DURATION} → ${URL}"
    echo "GET ${URL}" | vegeta attack -duration="$DURATION" -rate="$RATE" | tee "$BIN" >/dev/null
    vegeta encode < "$BIN" > "$JSON"
    vegeta report -type=text < "$BIN" > "$TXT"
    vegeta report -type='hist[0,5ms,10ms,25ms,50ms,100ms,250ms,500ms,1s,2s]' < "$BIN" > "$HIST"
    echo "📄 Saved: $TXT and $HIST"

    read -r TOTAL RATE_OBS THROUGHPUT SUCCESS_RATIO SUCCESS_CNT TIMEOUT_CNT < <(parse_text_report "$TXT")
    ERRORS=$(( TOTAL - SUCCESS_CNT ))
    if [ "$SUCCESS_CNT" -eq 0 ]; then
      sc=$(awk -v t="$TOTAL" -v r="$SUCCESS_RATIO" 'BEGIN{ printf "%.0f", t*(r/100.0) }')
      ERRORS=$(( TOTAL - sc ))
      SUCCESS_CNT="$sc"
    fi
    if [ "$TOTAL" -gt 0 ]; then
      THR=$(awk -v t="$TIMEOUT_CNT" -v n="$TOTAL" 'BEGIN{ printf "%.6f", (t*100.0)/n }')
    else
      THR="0"
    fi

    read -r TA_MEAN TA_P95 WT_MEAN WT_P95 P95_OK P99_OK < <(summarize_from_json "$JSON")

    echo "$ITER,$TS,$NAMESPACE,$SERVICE_NAME,$TIMEOUT_S,$DELAY,$RATE,$DURATION,$TOTAL,$SUCCESS_RATIO,$SUCCESS_CNT,$ERRORS,$TIMEOUT_CNT,$THR,$TA_MEAN,$TA_P95,$WT_MEAN,$WT_P95,$P95_OK,$P99_OK" >> "$CSV"
    ITER=$((ITER+1))
  done
  sleep 2
done

echo "✅ Done. Summary → $CSV"

