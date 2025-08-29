
DC_NAME="$1"           # e.g., dc1 or dc3
RATE="$2"              # e.g., 60
SUFFIX="$3"            # Optional, e.g., error, fail, etc.

NAMESPACE="objs-fed"
DEPLOY_NAME="backend"
CONTAINER_NAME="backend"
VEGETA_TARGET="http://172.18.0.2:31537/shuffle?error-rate=0&delay=0"
DURATION="60s"

# === VALIDATION ===
if [[ -z "$DC_NAME" || -z "$RATE" ]]; then
  echo "❌ Usage: $0 <dc_name> <rate> [suffix]"
  exit 1
fi

# === BUILD SUFFIX ===
if [[ -n "$SUFFIX" ]]; then
  FILE_TAG="_${DC_NAME}_r${RATE}_${SUFFIX}"
else
  FILE_TAG="_${DC_NAME}_r${RATE}"
fi

# === FILES ===
RESULTS_BIN="results${FILE_TAG}.bin"
RESULTS_JSON="results${FILE_TAG}.json"
SUMMARY_FILE="latency_summary.csv"
REPORT_HIST_FILE="report${FILE_TAG}_hist.txt"
REPORT_TEXT_FILE="report${FILE_TAG}_text.txt"

# === ATTACK ===
echo "🚀 Sending traffic at rate $RATE RPS to $VEGETA_TARGET"
echo "GET $VEGETA_TARGET" | vegeta attack -duration="$DURATION" -rate="$RATE" | tee "$RESULTS_BIN" > /dev/null

# === ENCODE ===
vegeta encode < "$RESULTS_BIN" > "$RESULTS_JSON"

# === CONVERT NS TO MS ===
convert_ns_to_ms() {
  awk -v ns="$1" 'BEGIN { printf "%.3f", ns / 1000000 }'
}

# === EXTRACT METRICS PER STATUS ===
extract_metrics_for_status() {
  local STATUS_CODE="$1"
  local FILTERED=$(jq -cr --arg CODE "$STATUS_CODE" 'select(type == "object" and .code == $CODE)' "$RESULTS_JSON")

  if [[ -z "$FILTERED" ]]; then
    echo "0|0|0|0"
    return
  fi

  local LATENCIES=$(echo "$FILTERED" | jq -r '.latency')

  local MEAN=$(echo "$LATENCIES" | awk '{sum+=$1} END{if(NR>0) print sum/NR; else print 0}')
  local P95=$(echo "$LATENCIES" | sort -n | awk 'BEGIN{n=0} {a[n++]=$1} END{idx=int(n*0.95); print a[idx]}')
  local P99=$(echo "$LATENCIES" | sort -n | awk 'BEGIN{n=0} {a[n++]=$1} END{idx=int(n*0.99); print a[idx]}')
  local COUNT=$(echo "$LATENCIES" | wc -l)

  echo "$COUNT|$MEAN|$P95|$P99"
}

# === WRITE HEADER IF NOT EXISTS ===
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "Datacenter,Rate,Status,Count,Mean(ms),P95(ms),P99(ms),Suffix" > "$SUMMARY_FILE"
fi

# === FORMAT METRICS AND APPEND TO CSV ===
log_metrics() {
  local STATUS="$1"
  local METRICS="$2"
  IFS="|" read -r COUNT MEAN P95 P99 <<< "$METRICS"

  MEAN_MS=$(convert_ns_to_ms "$MEAN")
  P95_MS=$(convert_ns_to_ms "$P95")
  P99_MS=$(convert_ns_to_ms "$P99")

  echo "$DC_NAME,$RATE,$STATUS,$COUNT,$MEAN_MS,$P95_MS,$P99_MS,$SUFFIX"
}

# === COLLECT METRICS FOR STATUS CODES ===
for status in 200 503; do
  METRICS=$(extract_metrics_for_status "$status")
  log_metrics "$status" "$METRICS" >> "$SUMMARY_FILE"
done

# === GENERATE VEGETA REPORTS ===
vegeta report -type='hist[0,5ms,10ms,25ms,50ms,100ms,250ms,500ms,1s]' < "$RESULTS_BIN" > "$REPORT_HIST_FILE"
vegeta report -type='text' < "$RESULTS_BIN" > "$REPORT_TEXT_FILE"

echo "📄 Histogram report saved to $REPORT_HIST_FILE"
echo "📄 Text summary report saved to $REPORT_TEXT_FILE"
echo "✅ All done!"

