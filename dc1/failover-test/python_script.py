import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

# === CONFIG ===
CSV_FILE = "failover_summary_60rps.csv"   # <-- set to your CSV path
OUT_DIR = "retry_plots"
AGG_CSV = "retry_summary_agg.csv"

os.makedirs(OUT_DIR, exist_ok=True)

# Load
df = pd.read_csv(CSV_FILE)

# Ensure numeric types
numeric_cols = [
    "SwitchTime","FullRecoveryTime",
    "FailoverMeanLatency(ms)","FailoverP95(ms)","FailoverP99(ms)",
    "MeanLatency(ms)","P95(ms)","P99(ms)",
    "Status200","Status503","SuccessCount","ErrorCount","CalculatedErrorRate"
]
for c in numeric_cols:
    if c in df.columns:
        df[c] = pd.to_numeric(df[c], errors="coerce")

# Availability = 1 - CalculatedErrorRate (fallback to counts if needed)
if "Availability" not in df.columns:
    if "CalculatedErrorRate" in df.columns and df["CalculatedErrorRate"].notna().any():
        df["Availability"] = 1.0 - df["CalculatedErrorRate"].astype(float)
    else:
        s = df.get("SuccessCount", np.nan)
        e = df.get("ErrorCount", np.nan)
        df["Availability"] = (s / (s + e)).where((s + e) > 0, np.nan)

# Metrics to visualize
metrics = [
    ("SwitchTime", "Switch Time (s)"),
    ("FullRecoveryTime", "Full Recovery Time (s)"),
    ("FailoverMeanLatency(ms)", "Failover Mean Latency (ms)"),
    ("FailoverP95(ms)", "Failover P95 (ms)"),
    ("FailoverP99(ms)", "Failover P99 (ms)"),
    ("MeanLatency(ms)", "Overall Mean Latency (ms)"),
    ("P95(ms)", "Overall P95 (ms)"),
    ("P99(ms)", "Overall P99 (ms)"),
    ("CalculatedErrorRate", "Calculated Error Rate"),
    ("Availability", "Availability"),
]

# --- Aggregation by Retries ---
agg_dict = {
    "SwitchTime": ["count","median","mean","std","min","max"],
    "FullRecoveryTime": ["median","mean","std","min","max"],
    "FailoverMeanLatency(ms)": ["median","mean","std","min","max"],
    "FailoverP95(ms)": ["median","mean","std","min","max"],
    "FailoverP99(ms)": ["median","mean","std","min","max"],
    "MeanLatency(ms)": ["median","mean","std","min","max"],
    "P95(ms)": ["median","mean","std","min","max"],
    "P99(ms)": ["median","mean","std","min","max"],
    "CalculatedErrorRate": ["median","mean","std","min","max"],
    "Availability": ["median","mean","std","min","max"],
    "SuccessCount": ["sum"],
    "ErrorCount": ["sum"],
}
present_agg = {k:v for k,v in agg_dict.items() if k in df.columns}
agg = df.groupby(["Retries"]).agg(present_agg)
agg.columns = ['_'.join([c for c in col if c]).rstrip('_') for col in agg.columns.values]
agg = agg.reset_index()
agg.to_csv(AGG_CSV, index=False)
print(f"✓ Aggregated summary written to {AGG_CSV}")

# --- Plot helpers (matplotlib only; one figure per chart; no custom colors) ---
def safe_name(s: str) -> str:
    return s.replace('%','pct').replace('/','_').replace('(','').replace(')','').replace(' ','_')

def boxplot_by_retries(df, metric_key: str, ylabel: str):
    if metric_key not in df.columns: return
    tmp = df[["Retries", metric_key]].dropna()
    if tmp.empty: return
    retries_sorted = sorted(tmp["Retries"].unique().tolist())
    data = [tmp.loc[tmp["Retries"] == r, metric_key].values for r in retries_sorted]
    plt.figure(figsize=(9,6))
    plt.boxplot(data)
    plt.title(f"{ylabel} by Retries")
    plt.xlabel("Retries")
    plt.ylabel(ylabel)
    plt.xticks(range(1, len(retries_sorted)+1), retries_sorted)
    plt.grid(True)
    out_path = os.path.join(OUT_DIR, f"{safe_name(metric_key)}_box_by_retries.png")
    plt.savefig(out_path, bbox_inches="tight")
    plt.close()
    print(f"✓ Saved {out_path}")

def median_line_by_retries(df, metric_key: str, ylabel: str):
    if metric_key not in df.columns: return
    tmp = df[["Retries", metric_key]].dropna()
    if tmp.empty: return
    med = tmp.groupby("Retries")[metric_key].median().reset_index()
    plt.figure(figsize=(9,6))
    plt.plot(med["Retries"], med[metric_key], marker="o")
    plt.title(f"Median {ylabel} vs Retries")
    plt.xlabel("Retries")
    plt.ylabel(ylabel)
    plt.grid(True)
    out_path = os.path.join(OUT_DIR, f"{safe_name(metric_key)}_median_vs_retries.png")
    plt.savefig(out_path, bbox_inches="tight")
    plt.close()
    print(f"✓ Saved {out_path}")

# Build all plots
for key, label in metrics:
    boxplot_by_retries(df, key, label)
    median_line_by_retries(df, key, label)

print(f"All plots saved under: {OUT_DIR}/")

