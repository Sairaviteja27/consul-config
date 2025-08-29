import pandas as pd
import matplotlib.pyplot as plt
import os

# Mapping of filenames to human-readable labels
file_labels = {
    "failover_summary_1min_10req_new.csv": "1 min 10 req",
    "failover_summary_1min_60req_new.csv": "1 min 60 req",
    "failover_summary_3min_10req.csv": "3 min 10 req",
    "failover_summary_3min_60req.csv": "3 min 60 req",
}

# Metrics to plot
metrics = ["SwitchTime", "MeanLatency(ms)", "P95(ms)", "P99(ms)", "SuccessCount", "ErrorCount"]

# Storage for data
data_by_metric = {metric: [] for metric in metrics}
labels = []

# Read and group data
for file, label in file_labels.items():
    if not os.path.exists(file):
        print(f"⚠️ Warning: File not found - {file}")
        continue
    try:
        # Use quotechar and skip bad lines (Python 3.8-compatible)
        df = pd.read_csv(file, quotechar='"', on_bad_lines='skip')
        labels.append(label)
        for metric in metrics:
            if metric in df.columns:
                data_by_metric[metric].append(df[metric].dropna())
            else:
                print(f"⚠️ Warning: '{metric}' not found in {file}, skipping for this file.")
    except Exception as e:
        print(f"❌ Failed to read {file}: {e}")
        continue

# Plot each metric as a separate boxplot
for metric in metrics:
    if not data_by_metric[metric]:
        print(f"⚠️ No data to plot for {metric}")
        continue
    plt.figure(figsize=(10, 6))
    plt.boxplot(data_by_metric[metric], vert=True, patch_artist=True,
                labels=labels,
                boxprops=dict(facecolor="lightblue", color="blue"),
                medianprops=dict(color="red"),
                whiskerprops=dict(color="black"),
                capprops=dict(color="black"),
                flierprops=dict(markerfacecolor='orange', marker='o', markersize=6, linestyle='none'))

    plt.title(f"{metric} - Boxplot by Scenario")
    plt.ylabel(metric)
    plt.grid(True)
    filename = f"{metric.replace('(', '').replace(')', '').replace('/', '_')}_boxplot.png"
    plt.savefig(filename)
    print(f"✅ Boxplot saved to {filename}")

