# tants for your environment.
DC3_POD="backend-d84f54685-r7w7r"  # Set this manually to the pod name in dc3
NAMESPACE="objs-fed"
DEPLOY_NAME="backend"
CONTAINER_NAME="backend"
VEGETA_TARGET="http://172.18.0.2:31537/shuffle?error-rate=0&delay=0"
RATE="60"
DURATION="60s"

# Derive a stable prefix so restarts still match (drop the last -segment)
DC3_POD_PREFIX="${DC3_POD%-*}"

# File paths for output
RESULTS_BIN="results.bin"
RESULTS_JSON="results.json"
SUMMARY_FILE="failover_summary.csv"
PROM_QUERY_FILE="prometheus_metrics.log"
BATCH_REPORT_DIR="batch-reports"

# --- Permissions check and file creation ---
touch "$RESULTS_BIN" "$RESULTS_JSON" "$SUMMARY_FILE" "$PROM_QUERY_FILE"
mkdir -p "$BATCH_REPORT_DIR"
chmod 664 "$RESULTS_BIN" "$RESULTS_JSON" "$SUMMARY_FILE" "$PROM_QUERY_FILE" 2>/dev/null || true

if [ ! -w "$RESULTS_BIN" ] || [ ! -w "$RESULTS_JSON" ]; then
    echo "❌ Error: Permission denied. Cannot write to vegeta output files." >&2
    echo "Please check permissions for results.bin and results.json in the current directory." >&2
    exit 1
fi

# === SIMULATE FAILOVER ===
# Record both epoch (for math) and UTC string (for logs)
FAIL_EPOCH="$(date -u +%s.%N)"
FAIL_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "[$FAIL_TIME] 🔴 Triggering backend crash..."

# Execute a command to simulate a crash in the primary backend.
kubectl exec -n "$NAMESPACE" deploy/"$DEPLOY_NAME" -c "$CONTAINER_NAME" -- curl -s -X POST http://localhost:7000/fail

echo "[$(date)] 🚀 Running vegeta test for $DURATION at $RATE RPS..."
# Run the vegeta attack and save the raw binary output.
echo "GET $VEGETA_TARGET" | vegeta attack -duration="$DURATION" -rate="$RATE" > "$RESULTS_BIN"

echo "[$(date)] 🟢 Restoring backend health..."
kubectl exec -n "$NAMESPACE" deploy/"$DEPLOY_NAME" -c "$CONTAINER_NAME" -- curl -s -X POST http://localhost:7000/ok

# === PROCESS RESULTS ===
vegeta encode < "$RESULTS_BIN" > "$RESULTS_JSON"

# --- jq helpers: robust ISO-8601 to epoch + dc3 matcher ---
read -r -d '' JQ_DEFS <<'JQ'
def toepoch:
  (try (fromdateiso8601) catch
    ( . as $ts
    | ($ts | sub("\\.\\d+"; "")) as $s
    | if ($s | test("Z$")) then
        $s | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime
      else
        ($s | capture("^(?<date>\\d{4}-\\d{2}-\\d{2})T(?<time>\\d{2}:\\d{2}:\\d{2})(?<sign>[+-])(?<oh>\\d{2}):(?<om>\\d{2})$")) as $m
        | ($m.date + "T" + $m.time + $m.sign + $m.oh + $m.om)
        | strptime("%Y-%m-%dT%H:%M:%S%z") | mktime
      end) );

# Try to extract the backend hostname/pod name from body or headers
def extract_backend:
  ( .body | @base64d | fromjson? ) as $b
  | (
      $b.metadata.backendHostname? // $b.backendHostname? // $b.hostname? // $b.pod? // $b.podName? // empty
    ) as $from_body
  | (
      (.headers // {} | to_entries[]?
        | .key as $k
        | ( $k|ascii_downcase ) as $lk
        | select($lk=="x-backend-hostname" or $lk=="x-pod-name" or $lk=="x-backend-pod" or $lk=="x-upstream-pod" or $lk=="x-upstream-target")
        | .value[0]
      ) // empty
    ) as $from_hdr
  | [$from_body, $from_hdr] | map(select(.!=null and .!="")) | .[0];

# True if the extracted name equals dc3 pod or starts with its stable prefix
def is_dc3($name; $prefix):
  (extract_backend // "") as $who
  | ($who == $name) or ( ($prefix != "") and ($who | startswith($prefix)) );
JQ

# --- CALCULATE FIRST SUCCESSFUL FAILOVER RESPONSE AND LAST ERROR TIME ---
RESULTS_DATA=$(
  jq -cr --arg fail_epoch "$FAIL_EPOCH" --arg dc3_pod "$DC3_POD" --arg dc3_prefix "$DC3_POD_PREFIX" "
    $JQ_DEFS
    select(type == \"object\") |
    if (.code == 200 and is_dc3(\$dc3_pod; \$dc3_prefix)) then
      { type: \"switch\", timestamp: .timestamp, diff: ((.timestamp | toepoch) - (\$fail_epoch | tonumber)) }
    elif (.code >= 500) then
      { type: \"error\", timestamp: .timestamp }
    else
      empty
    end
  " "$RESULTS_JSON"
)

SWITCH_INFO=$(echo "$RESULTS_DATA" | jq -r 'select(.type == "switch") | "\(.timestamp)|\(.diff)"' | head -n 1)
LAST_5XX_TIME=$(echo "$RESULTS_DATA" | jq -r 'select(.type == "error") | .timestamp' | tail -n 1)

# --- Fallback DC3 detection (your previous working logic) ---
# Only run if the current jq-based logic didn't find a DC3 switch.
if [[ -z "${SWITCH_INFO:-}" || "$SWITCH_INFO" == "null" ]]; then
  SWITCH_INFO=$(
    jq -cr '. | @base64' "$RESULTS_JSON" | while IFS= read -r line; do
      decoded=$(echo "$line" | base64 --decode)
      TIMESTAMP=$(echo "$decoded" | jq -r '.timestamp')
      CODE=$(echo "$decoded" | jq -r '.code')
      BODY_BASE64=$(echo "$decoded" | jq -r '.body')

      BODY=$(echo "$BODY_BASE64" | base64 --decode 2>/dev/null) || continue
      POD=$(echo "$BODY" | jq -r '.metadata.backendHostname // empty' 2>/dev/null)

      if [[ "$CODE" == "200" && "$POD" == "$DC3_POD" ]]; then
        RESP_EPOCH=$(date -u -d "$TIMESTAMP" +%s.%N 2>/dev/null || date -d "$TIMESTAMP" +%s.%N)
        DIFF=$(echo "$RESP_EPOCH - $FAIL_EPOCH" | bc)
        echo "$TIMESTAMP|$DIFF"
        break
      fi
    done
  )
fi

# --- CALCULATE FULL RECOVERY TIME ---
if [[ -n "$LAST_5XX_TIME" && "$LAST_5XX_TIME" != "null" ]]; then
    LAST_5XX_EPOCH=$(date -u -d "$LAST_5XX_TIME" +%s.%N)
    FULL_RECOVERY_TIME=$(echo "$LAST_5XX_EPOCH - $FAIL_EPOCH" | bc)
else
    FULL_RECOVERY_TIME="0"
fi

# === OUTPUT ===
if [[ -n "$SWITCH_INFO" ]]; then
  IFS="|" read -r TS DIFF <<< "$SWITCH_INFO"
  echo "✅ First 200 OK from dc3 pod ($DC3_POD) at $TS"
  echo "⏱️  Failover switch time: $DIFF seconds"
else
  echo "⚠️  No 200 OK response from dc3 pod ($DC3_POD) found after fail trigger."
  DIFF="NA"
fi

echo "🟢 Full recovery time (until last error): $FULL_RECOVERY_TIME seconds"

# === LATENCY SPIKE ANALYSIS ===
echo "Analyzing latency during failover event..."
if [[ -n "$LAST_5XX_EPOCH" ]]; then
  FAILOVER_LATENCY_JSON=$(
    jq -c --arg start_time "$FAIL_EPOCH" --arg end_time "$LAST_5XX_EPOCH" "
      $JQ_DEFS
      select(type == \"object\")
      | select((.code >= 500) or ((.timestamp | toepoch) >= (\$start_time|tonumber)
                                  and (.timestamp | toepoch) <= (\$end_time|tonumber)))
    " "$RESULTS_JSON" \
    | vegeta report --type=json
  )

  if [[ $(echo "$FAILOVER_LATENCY_JSON" | jq '.latencies.mean') != "null" ]]; then
    FAILOVER_MEAN_LATENCY=$(echo "$FAILOVER_LATENCY_JSON" | jq -r '.latencies.mean // 0')
    FAILOVER_P95_LATENCY=$(echo "$FAILOVER_LATENCY_JSON" | jq -r '.latencies["95th"] // 0')
    FAILOVER_P99_LATENCY=$(echo "$FAILOVER_LATENCY_JSON" | jq -r '.latencies["99th"] // 0')

    convert_ns_to_ms() { awk -v ns="$1" 'BEGIN { printf "%.3f", ns / 1000000 }'; }

    FAILOVER_MEAN_MS=$(convert_ns_to_ms "$FAILOVER_MEAN_LATENCY")
    FAILOVER_P95_MS=$(convert_ns_to_ms "$FAILOVER_P95_LATENCY")
    FAILOVER_P99_MS=$(convert_ns_to_ms "$FAILOVER_P99_LATENCY")

    echo "📈 Latency during failover window:"
    echo "  - Mean Latency: $FAILOVER_MEAN_MS ms"
    echo "  - P95 Latency: $FAILOVER_P95_MS ms"
    echo "  - P99 Latency: $FAILOVER_P99_MS ms"
  fi
fi

# === METRICS (Overall) ===
METRICS_JSON=$(vegeta report --type=json < "$RESULTS_BIN")
MEAN_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies.mean // 0')
P95_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies["95th"] // 0')
P99_LATENCY=$(echo "$METRICS_JSON" | jq -r '.latencies["99th"] // 0')
ERROR_TEXT=$(echo "$METRICS_JSON" | jq -r '[.errors[]] | join(", ") // "None"')
STATUS_200=$(echo "$METRICS_JSON" | jq -r '.status_codes["200"] // 0')
STATUS_503=$(echo "$METRICS_JSON" | jq -r '.status_codes["503"] // 0')

SUCCESS_COUNT=$STATUS_200
ERROR_COUNT=$STATUS_503

TOTAL=$((SUCCESS_COUNT + ERROR_COUNT))
if [[ "$TOTAL" -gt 0 ]]; then
    CALC_ERROR_RATE=$(awk -v e="$ERROR_COUNT" -v t="$TOTAL" 'BEGIN { printf "%.6f", e / t }')
else
    CALC_ERROR_RATE="NA"
fi

convert_ns_to_ms() {
    awk -v ns="$1" 'BEGIN { printf "%.3f", ns / 1000000 }'
}

MEAN_MS=$(convert_ns_to_ms "$MEAN_LATENCY")
P95_MS=$(convert_ns_to_ms "$P95_LATENCY")
P99_MS=$(convert_ns_to_ms "$P99_LATENCY")

# === PROMETHEUS METRICS (optional) ===
START_TS=$(date +%s)
END_TS=$((START_TS + 30))
cat <<EOF > "$PROM_QUERY_FILE"
Time: $(date)
Query Window: $START_TS to $END_TS
EOF
curl -s "http://localhost:9090/api/v1/query?query=rate(http_server_requests_total[1m])" >> "$PROM_QUERY_FILE"

# === LOGGING ===
BATCH_ID="$1"
RETRIES="$2"

mkdir -p "$BATCH_REPORT_DIR"
BATCH_JSON="batch-reports/batch_$BATCH_ID-$RETRIES.json"
cp "$RESULTS_JSON" "$BATCH_JSON"

if [[ ! -f "$SUMMARY_FILE" ]]; then
    echo "Retries,Batch,SwitchTime,FullRecoveryTime,FailoverMeanLatency(ms),FailoverP95(ms),FailoverP99(ms),ErrorRate,MeanLatency(ms),P95(ms),P99(ms),Status200,Status503,SuccessCount,ErrorCount,CalculatedErrorRate" > "$SUMMARY_FILE"
fi

echo "$RETRIES,$BATCH_ID,$DIFF,$FULL_RECOVERY_TIME,$FAILOVER_MEAN_MS,$FAILOVER_P95_MS,$FAILOVER_P99_MS,\"$ERROR_TEXT\",$MEAN_MS,$P95_MS,$P99_MS,$STATUS_200,$STATUS_503,$SUCCESS_COUNT,$ERROR_COUNT,$CALC_ERROR_RATE" >> "$SUMMARY_FILE"

# === VISUALIZATION ===
echo "Creating latency plot for visual analysis..."
vegeta plot < "$RESULTS_BIN" > "batch-reports/batch_$BATCH_ID-$RETRIES.html"

