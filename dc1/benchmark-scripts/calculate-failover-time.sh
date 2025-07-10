
DC3_POD="backend-7bf8c7dd8d-4xzpk"  # set this manually
NAMESPACE="objs-fed"
DEPLOY_NAME="backend"
CONTAINER_NAME="backend"
VEGETA_TARGET="http://172.18.0.2:31537/shuffle?error-rate=0&delay=0"
RATE="10"
DURATION="60s"
RESULTS_BIN="results.bin"
RESULTS_JSON="results.json"
SUMMARY_FILE="failover_summary.csv"

# === SIMULATE FAILOVER ===
FAIL_TIME=$(date -Iseconds)
echo "[$FAIL_TIME] 🔴 Triggering backend crash..."

kubectl exec -n "$NAMESPACE" deploy/"$DEPLOY_NAME" -c "$CONTAINER_NAME" -- curl -s -X POST http://localhost:7000/fail

echo "[$(date)] 🚀 Running vegeta test..."
echo "GET $VEGETA_TARGET" | vegeta attack -duration="$DURATION" -rate="$RATE" | tee "$RESULTS_BIN" > /dev/null

echo "[$(date)] 🟢 Restoring backend health..."
kubectl exec -n "$NAMESPACE" deploy/"$DEPLOY_NAME" -c "$CONTAINER_NAME" -- curl -s -X POST http://localhost:7000/ok

vegeta encode < "$RESULTS_BIN" > "$RESULTS_JSON"
FAIL_EPOCH=$(date -d "$FAIL_TIME" +%s.%N)

# === PROCESS RESULTS ===
SWITCH_INFO=$(jq -cr '. | @base64' "$RESULTS_JSON" | while IFS= read -r line; do
  decoded=$(echo "$line" | base64 --decode)
  TIMESTAMP=$(echo "$decoded" | jq -r '.timestamp')
  CODE=$(echo "$decoded" | jq -r '.code')
  BODY_BASE64=$(echo "$decoded" | jq -r '.body')

  # Make sure body is base64-decodable
  BODY=$(echo "$BODY_BASE64" | base64 --decode 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    continue
  fi

  POD=$(echo "$BODY" | jq -r '.metadata.backendHostname // empty' 2>/dev/null)

  if [[ "$CODE" == "200" && "$POD" == "$DC3_POD" ]]; then
    RESP_EPOCH=$(date -d "$TIMESTAMP" +%s.%N)
    DIFF=$(echo "$RESP_EPOCH - $FAIL_EPOCH" | bc)
    echo "$TIMESTAMP|$DIFF"
    break
  fi
done)

# === OUTPUT ===
if [[ -n "$SWITCH_INFO" ]]; then
  IFS="|" read -r TS DIFF <<< "$SWITCH_INFO"
  echo "✅ First 200 OK from dc3 pod ($DC3_POD) at $TS"
  echo "⏱️  Failover switch time: $DIFF seconds"
else
  echo "⚠️  No 200 OK response from dc3 pod ($DC3_POD) found after fail trigger."
  DIFF="NA"
fi

# === METRICS ===
METRICS_JSON=$(vegeta report -type=json < "$RESULTS_BIN")
MEAN_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies.mean // "NA"')
P95_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies["95th"] // "NA"')
P99_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies["99th"] // "NA"')
ERROR_RATE=$(echo "$METRICS_JSON" | jq -r '.errors // 0')

convert_ns_to_ms() {
  awk -v ns="$1" 'BEGIN { printf "%.3f", ns / 1000000 }'
}

MEAN_MS=$(convert_ns_to_ms "$MEAN_LATENCY")
P95_MS=$(convert_ns_to_ms "$P95_LATENCY")
P99_MS=$(convert_ns_to_ms "$P99_LATENCY")

# === CSV LOGGING ===
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "Batch,SwitchTime,ErrorRate,MeanLatency(ms),P95(ms),P99(ms)" > "$SUMMARY_FILE"
fi

BATCH_ID=$(($(wc -l < "$SUMMARY_FILE") ))
echo "$BATCH_ID,$DIFF,$ERROR_RATE,$MEAN_MS,$P95_MS,$P99_MS" >> "$SUMMARY_FILE"
