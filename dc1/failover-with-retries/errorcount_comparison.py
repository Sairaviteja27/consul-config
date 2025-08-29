import pandas as pd
import matplotlib.pyplot as plt
import os

# File groups: (without_retries_file, with_retries_file)
file_pairs = {
    "1min_10req": (
        "failover_summary_1min_10req_wo_retries.csv",
        "failover_summary_1min_10req_new.csv"
    ),
    "1min_60req": (
        "failover_summary_1min_60req_wo_retries.csv",
        "failover_summary_1min_60req_new.csv"
    ),
}

# Data for plotting
scenarios = []
error_counts_wo_retries = []
error_counts_with_retries = []

# Extract mean ErrorCount from both files
for label, (wo_file, with_file) in file_pairs.items():
    if not os.path.exists(wo_file) or not os.path.exists(with_file):
        print(f"❌ One of the files for {label} is missing.")
        continue

    try:
        df_wo = pd.read_csv(wo_file, quotechar='"', on_bad_lines='skip')
        df_with = pd.read_csv(with_file, quotechar='"', on_bad_lines='skip')

        if 'ErrorCount' not in df_wo.columns or 'ErrorCount' not in df_with.columns:
            print(f"⚠️ 'ErrorCount' column missing in one of the files for {label}.")
            continue

        mean_wo = df_wo['ErrorCount'].dropna().mean()
        mean_with = df_with['ErrorCount'].dropna().mean()

        scenarios.append(label)
        error_counts_wo_retries.append(mean_wo)
        error_counts_with_retries.append(mean_with)

    except Exception as e:
        print(f"❌ Error processing {label}: {e}")

# Plot grouped bar chart
x = range(len(scenarios))
width = 0.35

plt.figure(figsize=(10, 6))
plt.bar([i - width/2 for i in x], error_counts_wo_retries, width=width, label='Without Retries', color='salmon')
plt.bar([i + width/2 for i in x], error_counts_with_retries, width=width, label='With Retries', color='seagreen')

plt.xlabel('Scenario')
plt.ylabel('Average ErrorCount')
plt.title('ErrorCount Comparison: With vs Without Retries')
plt.xticks(ticks=x, labels=scenarios)
plt.legend()
plt.grid(axis='y')

plt.tight_layout()
plt.savefig('error_count_comparison.png')
print("✅ Plot saved to error_count_comparison.png")

