DC3_POD="backend-7bf8c7dd8d-4xzpk"  # set this manually
NAMESPACE="objs-fed"
DEPLOY_NAME="backend"
CONTAINER_NAME="backend"
VEGETA_TARGET="http://172.18.0.2:31537/shuffle?error-rate=50&delay=0"
RATE="60"
DURATION="30s"
RESULTS_BIN="results.bin"
RESULTS_JSON="results.json"
SUMMARY_FILE="retries_summary.csv"

# Accept batch number as first argument
BATCH="$1"

echo "[$(date)] 🚀 Running vegeta test for batch $BATCH..."
echo "GET $VEGETA_TARGET" | vegeta attack -duration="$DURATION" -rate="$RATE" | tee "$RESULTS_BIN" > /dev/null

vegeta encode < "$RESULTS_BIN" > "$RESULTS_JSON"

# === METRICS ===
METRICS_JSON=$(vegeta report -type=json < "$RESULTS_BIN")
SUCCESS_RATE=$(echo "$METRICS_JSON" | jq -r '.success // "NA"')
P50_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies["50th"] // "NA"')
P50_LATENCY_MS=$(awk -v ns="$P50_LATENCY" 'BEGIN { printf "%.3f", ns / 1000000 }')
STATUS_CODES=$(echo "$METRICS_JSON" | jq -r '.status_codes | to_entries | map("\(.key):\(.value)") | join(" ")')
BYTES_IN_TOTAL=$(echo "$METRICS_JSON" | jq -r '.bytes_in.total // "NA"')
BYTES_IN_MEAN=$(echo "$METRICS_JSON" | jq -r '.bytes_in.mean // "NA"')

convert_ns_to_ms() {
  awk -v ns="$1" 'BEGIN { printf "%.3f", ns / 1000000 }'
}

# Convert mean latency as well for logging
MEAN_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies.mean // "NA"')
MEAN_MS=$(convert_ns_to_ms "$MEAN_LATENCY")

# === CSV LOGGING ===
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "Batch,SuccessRate,P50Latency(ms),MeanLatency(ms),StatusCodes,BytesInTotal,BytesInMean" > "$SUMMARY_FILE"
fi

echo "$BATCH,$SUCCESS_RATE,$P50_LATENCY_MS,$MEAN_MS,\"$STATUS_CODES\",$BYTES_IN_TOTAL,$BYTES_IN_MEAN" >> "$SUMMARY_FILE"

echo "✅ Benchmark for batch $BATCH completed."
echo "Success Rate: $SUCCESS_RATE"
echo "P50 Latency (ms): $P50_LATENCY_MS"
echo "Mean Latency (ms): $MEAN_MS"
echo "Status Codes: $STATUS_CODES"
echo "Bytes In Total: $BYTES_IN_TOTAL"
echo "Bytes In Mean: $BYTES_IN_MEAN"

