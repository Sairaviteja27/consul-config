import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os
import glob

# Directory where CSVs are stored
input_dir = "."
output_dir = "failover_plots"
os.makedirs(output_dir, exist_ok=True)

# Collect all failover_summary CSVs
files = glob.glob(os.path.join(input_dir, "failover_summary_*s.csv"))
if not files:
    print("[ERROR] No failover_summary_*s.csv files found")
    exit(1)

df_list = []
for f in files:
    tmp = pd.read_csv(f)
    tmp["SourceFile"] = os.path.basename(f)
    # Extract probe period from filename (e.g., failover_summary_5s.csv → "5s")
    period = f.split("_")[-1].replace(".csv", "")
    tmp["ProbePeriod"] = period
    df_list.append(tmp)

df = pd.concat(df_list, ignore_index=True)

# Convert numeric columns safely
df["SwitchTime"] = pd.to_numeric(df["SwitchTime"], errors="coerce")
df["MeanLatency(ms)"] = pd.to_numeric(df["MeanLatency(ms)"], errors="coerce")

# === Apply Outlier Filters ===
before = len(df)
df = df[(df["SwitchTime"] <= 50) & (df["MeanLatency(ms)"] <= 750)]
after = len(df)
print(f"[INFO] Filtered out {before - after} outlier rows (>{before} total)")

# --- Ensure Correct X-axis Order ---
order = ["1s", "3s", "5s", "7s", "10s"]

# --- Plot 1: Switch Time ---
if df["SwitchTime"].notna().any():
    plt.figure(figsize=(8, 6))
    sns.boxplot(data=df, x="ProbePeriod", y="SwitchTime", order=order, palette="Set2")
    plt.title("Failover Switch Time vs Probe Period")
    plt.xlabel("Probe Period (s)")
    plt.ylabel("Switch Time (s)")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "failover_switch_time_boxplot.png"))
    plt.close()
    print("[OK] Saved failover_plots/failover_switch_time_boxplot.png")
else:
    print("[WARN] No valid data for SwitchTime")

# --- Plot 2: Mean Latency ---
if df["MeanLatency(ms)"].notna().any():
    plt.figure(figsize=(8, 6))
    sns.boxplot(data=df, x="ProbePeriod", y="MeanLatency(ms)", order=order, palette="Set3")
    plt.title("Mean Latency vs Probe Period")
    plt.xlabel("Probe Period (s)")
    plt.ylabel("Mean Latency (ms)")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "failover_mean_latency_boxplot.png"))
    plt.close()
    print("[OK] Saved failover_plots/failover_mean_latency_boxplot.png")
else:
    print("[WARN] No valid data for MeanLatency(ms)")

