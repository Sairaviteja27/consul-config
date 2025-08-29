SLEEP_TIME=0
BATCH_TOTAL=50

SUMMARY_FILE="retries_summary.csv"
BENCHMARK_SCRIPT="./benchmark_retries.sh"  

mkdir -p batch-reports

# Initialize CSV summary with header if not present
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "Batch,SuccessRate,P50Latency(ms),MeanLatency(ms),StatusCodes,BytesInTotal,BytesInMean" > "$SUMMARY_FILE"
fi

echo "📊 Starting batch retry test ($BATCH_TOTAL runs)..."

for i in $(seq 1 "$BATCH_TOTAL"); do
  echo "▶️ Test $i/$BATCH_TOTAL"

  # Pass batch number as argument to benchmark script
  bash "$BENCHMARK_SCRIPT" "$i"

  echo "⏳ Waiting $SLEEP_TIME seconds before next test..."
  sleep "$SLEEP_TIME"
done

echo "✅ Batch complete."
echo "📁 Summary report: $SUMMARY_FILE"

