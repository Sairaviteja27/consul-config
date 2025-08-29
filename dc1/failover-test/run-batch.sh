#!/bin/bash

# CONFIGURATION ---
SLEEP_TIME=60
BATCH_TOTAL_PER_RETRY=25
RETRY_VALUES=(1 3 5 10)  # Array of retry values to test

# --- FILE PATHS ---
SERVICE_ROUTER_YAML="service-router.yaml"
CALC_SCRIPT="./calculate-failover-time.sh"
SUMMARY_FILE="failover_summary.csv"

# --- SETUP ---
mkdir -p batch-reports

# Initialize CSV summary with a new header that includes the 'Retries' column
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "Retries,Batch,SwitchTime,FullRecoveryTime,FailoverMeanLatency(ms),FailoverP95(ms),FailoverP99(ms),ErrorRate,MeanLatency(ms),P95(ms),P99(ms),Status200,Status503,SuccessCount,ErrorCount,CalculatedErrorRate" > "$SUMMARY_FILE"
fi

# --- MAIN LOOP ---
echo "📊 Starting automated failover test with varying retries..."

# Loop through each retry value in the array
for RETRIES in "${RETRY_VALUES[@]}"; do
  echo "🔄 Configuring ServiceRouter for $RETRIES retries..."

  # Dynamically update the service-router.yaml file with the new retry count
  sed -i "s/numRetries: [0-9]*/numRetries: $RETRIES/" "$SERVICE_ROUTER_YAML"

  echo "🚀 Applying ServiceRouter configuration..."
  kubectl apply -f "$SERVICE_ROUTER_YAML"

  echo "Test batch for numRetries: $RETRIES"

  # Run a batch of tests for the current retry value
  for i in $(seq 1 "$BATCH_TOTAL_PER_RETRY"); do
    echo "▶️ Test $i/$BATCH_TOTAL_PER_RETRY with $RETRIES retries"

    # Pass both the retry value and batch number to the calculation script
    bash "$CALC_SCRIPT" "$i" "$RETRIES"

    echo "⏳ Waiting $SLEEP_TIME seconds before next test..."
    sleep "$SLEEP_TIME"
  done
done

echo "✅ All automated tests complete."
echo "📁 Summary report: $SUMMARY_FILE"
echo "📁 Individual batch files: batch-reports/"
