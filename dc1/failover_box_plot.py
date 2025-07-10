import pandas as pd
import matplotlib.pyplot as plt
import os

# Mapping of filenames to human-readable labels
file_labels = {
    "failover_summary_1min_10req.csv": "1 min 10 req",
    "failover_summary_1min_60req.csv": "1 min 60 req",
    "failover_summary_3min_10req.csv": "3 min 10 req",
    "failover_summary_3min_60req.csv": "3 min 60 req",
}

# Metrics to plot
metrics = ["SwitchTime", "MeanLatency(ms)", "P95(ms)", "P99(ms)"]

# Storage for data
data_by_metric = {metric: [] for metric in metrics}
labels = []

# Read and group data
for file, label in file_labels.items():
    df = pd.read_csv(file)
    labels.append(label)
    for metric in metrics:
        data_by_metric[metric].append(df[metric].dropna())

# Plot each metric as a separate boxplot
for metric in metrics:
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
    print(f" Boxplot saved to {filename}")

