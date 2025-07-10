SLEEP_TIME=60
BATCH_TOTAL=100

OUTPUT_FILE="failover_times.txt"
SUMMARY_FILE="failover_summary.csv"

mkdir -p batch-reports

# Reset switch times log
> "$OUTPUT_FILE"

# Initialize CSV summary with header if not present
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "Batch,SwitchTime,ErrorRate,MeanLatency(ms),P95(ms),P99(ms)" > "$SUMMARY_FILE"
fi

echo "📊 Starting batch failover test ($BATCH_TOTAL runs)..."

for i in $(seq 1 "$BATCH_TOTAL"); do
  echo "▶️ Test $i/$BATCH_TOTAL"

  # Pass batch number to calculate-failover-time.sh
  DIFF=$(bash calculate-failover-time.sh "$i" | grep "Failover switch time" | awk '{print $5}')

  if [[ -n "$DIFF" && "$DIFF" != "NA" ]]; then
    echo "$DIFF" >> "$OUTPUT_FILE"
    echo "✅ Switch time recorded: $DIFF seconds"
  else
    echo "⚠️  Switch time not recorded in test $i."
  fi

  echo "⏳ Waiting $SLEEP_TIME seconds before next test..."
  sleep "$SLEEP_TIME"
done

echo "✅ Batch complete. All switch times saved to $OUTPUT_FILE"
echo "📁 Summary report: $SUMMARY_FILE"
echo "📁 Individual batch files (if any): batch-reports/"

