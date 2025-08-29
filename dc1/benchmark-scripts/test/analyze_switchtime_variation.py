import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Use a clean theme
sns.set(style="whitegrid")

# Load CSVs
file_10 = "failover_summary_10req_23_07.csv"
file_60 = "failover_summary_60req_23_07.csv"

df_10 = pd.read_csv(file_10)
df_60 = pd.read_csv(file_60)

# Calculate ErrorRate
def calculate_error_rate(df):
    if 'Status200' in df.columns and 'Status503' in df.columns:
        total = df['Status200'] + df['Status503']
        df['ErrorRate(%)'] = (df['Status503'] / total) * 100
    else:
        print("⚠️  Warning: Status200/Status503 columns missing for ErrorRate.")
        df['ErrorRate(%)'] = None
    return df

df_10 = calculate_error_rate(df_10)
df_60 = calculate_error_rate(df_60)

# Add labels for grouping
df_10['Scenario'] = '10 req/sec'
df_60['Scenario'] = '60 req/sec'
combined = pd.concat([df_10, df_60], ignore_index=True)

# === 1. Histogram of SwitchTime comparison ===
plt.figure(figsize=(10, 6))
sns.histplot(data=combined, x='SwitchTime', hue='Scenario', kde=True, palette=['green', 'blue'], bins=12, alpha=0.6)
plt.title("SwitchTime Distribution - 10 vs 60 req/sec")
plt.xlabel("SwitchTime (seconds)")
plt.ylabel("Frequency")
plt.grid(True)
plt.tight_layout()
plt.savefig("histogram_switchtime_comparison.png")
plt.close()

# === 2. Boxplots for each latency metric ===
latency_metrics = ['MeanLatency(ms)', 'P95(ms)', 'P99(ms)', 'SwitchTime']
for metric in latency_metrics:
    plt.figure(figsize=(10, 6))
    sns.boxplot(data=combined, x='Scenario', y=metric, palette='Set2')
    plt.title(f"{metric} - Boxplot Comparison")
    plt.ylabel(metric)
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(f"boxplot_{metric.replace('(', '').replace(')', '').replace('/', '_')}.png")
    plt.close()

# === 3. Scatter plots (SwitchTime vs. Latency metrics) ===
for metric in ['MeanLatency(ms)', 'P95(ms)', 'P99(ms)']:
    plt.figure(figsize=(10, 6))
    sns.scatterplot(data=combined, x='SwitchTime', y=metric, hue='Scenario', palette=['green', 'blue'])
    plt.title(f"SwitchTime vs {metric}")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(f"scatter_SwitchTime_vs_{metric.replace('(', '').replace(')', '').replace('/', '_')}.png")
    plt.close()

# === 4. Error Rate Subgroup Comparison (60 req/sec only) ===
fast = df_60[df_60['SwitchTime'] < 26]
slow = df_60[df_60['SwitchTime'] > 29]

print("\n=== Fast Failover (<26s) Summary - 60 req/sec ===")
print(fast[['MeanLatency(ms)', 'P95(ms)', 'P99(ms)', 'ErrorRate(%)']].describe())

print("\n=== Slow Failover (>29s) Summary - 60 req/sec ===")
print(slow[['MeanLatency(ms)', 'P95(ms)', 'P99(ms)', 'ErrorRate(%)']].describe())

# === 5. Correlation Matrices ===
print("\n=== Correlation Matrix - 10 req/sec ===")
print(df_10.corr(numeric_only=True))

print("\n=== Correlation Matrix - 60 req/sec ===")
print(df_60.corr(numeric_only=True))

