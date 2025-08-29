import pandas as pd

df = pd.read_csv("timeouts_summary.csv")
print(df.columns.tolist())

metrics = [
    "SuccessRatio(%)",
    "TimeoutHitRate(%)",
    "TimeoutAccuracyMean(ms)",
    "TimeoutAccuracyP95(ms)",
    "WastedTimeMean(ms)",
    "WastedTimeP95(ms)",
    "P95_200(ms)",
    "P99_200(ms)",
]

for m in metrics:
    if m in df:
        print(m, "min:", df[m].min(), "max:", df[m].max(), "count:", df[m].notna().sum())
    else:
        print("MISSING:", m)

