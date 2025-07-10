# Config
NAMESPACE="objs-fed"
DEPLOY_NAME="backend"
VEGETA_TARGET="http://172.18.0.2:31537/shuffle?error-rate=0&delay=0"
RATE="10"
DURATION="60s"
RESULTS_BIN="results.bin"
RESULTS_JSON="results.json"
DC3_POD="backend-5856944df4-rbqrx"

# Capture fail time
FAIL_TIME=$(date -Iseconds)
echo "[$FAIL_TIME] 🔴 Triggering health check failure..."

kubectl exec -n "$NAMESPACE" deploy/"$DEPLOY_NAME" -c health-controller -- \
  wget -qO- http://localhost:8081/fail

# Start Vegeta test
echo "[$(date)] 🚀 Running vegeta test on $VEGETA_TARGET"
echo "GET $VEGETA_TARGET" | vegeta attack -duration="$DURATION" -rate="$RATE" | tee "$RESULTS_BIN" | vegeta report > report.txt

# Restore health
echo "[$(date)] 🟢 Restoring health check..."
kubectl exec -n "$NAMESPACE" deploy/"$DEPLOY_NAME" -c health-controller -- \
  wget -qO- http://localhost:8081/ok

# Generate plot
vegeta plot < "$RESULTS_BIN" > plot.html
echo "📊 Plot saved to plot.html"

# Convert results to JSON
vegeta encode < "$RESULTS_BIN" > "$RESULTS_JSON"

# Convert ISO to epoch
to_epoch() {
  date -d "$1" +%s.%N
}

FAIL_EPOCH=$(to_epoch "$FAIL_TIME")

# Search for first dc3 response
SWITCH_INFO=$(jq -cr '. | @base64' "$RESULTS_JSON" | while IFS= read -r line; do
  decoded=$(echo "$line" | base64 --decode)

  TIMESTAMP=$(echo "$decoded" | jq -r '.timestamp')
  CODE=$(echo "$decoded" | jq -r '.code')
  BODY_BASE64=$(echo "$decoded" | jq -r '.body')

  if ! echo "$BODY_BASE64" | base64 --decode &>/dev/null; then
    continue
  fi

  BODY=$(echo "$BODY_BASE64" | base64 --decode)
  POD=$(echo "$BODY" | jq -r '.metadata.backendHostname' 2>/dev/null)

  if [[ "$CODE" == "200" && "$POD" == "$DC3_POD" ]]; then
    RESP_EPOCH=$(to_epoch "$TIMESTAMP")
    DIFF=$(echo "$RESP_EPOCH - $FAIL_EPOCH" | bc)
    echo "$TIMESTAMP|$DIFF"
    break
  fi
done)

if [[ -n "$SWITCH_INFO" ]]; then
  IFS="|" read -r TS DIFF <<< "$SWITCH_INFO"
  echo "✅ First 200 OK from dc3 pod ($DC3_POD) at $TS"
  echo "⏱️  Failover switch time: $DIFF seconds"
else
  echo "⚠️  No 200 OK response from dc3 pod ($DC3_POD) found after fail trigger."
fi

