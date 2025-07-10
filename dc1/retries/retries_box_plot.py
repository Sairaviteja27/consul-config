import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Load CSVs
df_enabled = pd.read_csv("retries_summary_enabled.csv")
df_disabled = pd.read_csv("retries_summary_disabled.csv")

# Add label for retry setting
df_enabled['Retries'] = 'Enabled'
df_disabled['Retries'] = 'Disabled'

# Combine both datasets
df = pd.concat([df_enabled, df_disabled], ignore_index=True)

# Parse status codes into separate columns
def extract_codes(row, code):
    try:
        codes = dict(item.split(":") for item in row.split())
        return int(codes.get(str(code), 0))
    except:
        return 0

for code in [200, 503]:
    df[f"Status_{code}"] = df['StatusCodes'].apply(lambda x: extract_codes(x, code))

# Create output directory
os.makedirs("retry_plots", exist_ok=True)

# Metrics to plot as horizontal boxplots
metrics = ["SuccessRate", "P50Latency(ms)", "MeanLatency(ms)", "BytesInTotal", "BytesInMean"]

# Horizontal boxplots
for metric in metrics:
    plt.figure(figsize=(10, 5))
    sns.boxplot(data=df, y='Retries', x=metric, palette="Set2", orient='h')
    plt.title(f"{metric} by Retry Setting")
    plt.xlabel(metric)
    plt.ylabel("Retries")
    plt.grid(True, axis='x')
    plt.tight_layout()
    filename = f"retry_plots/{metric.replace('(', '').replace(')', '').replace('/', '_')}_hboxplot.png"
    plt.savefig(filename)
    print(f"Saved {filename}")
    plt.close()

# Stacked bar plot for status codes
status_summary = df.groupby('Retries')[['Status_200', 'Status_503']].sum()

status_summary.plot(kind='bar', stacked=True, figsize=(10, 6), colormap='tab20')
plt.title("Total Status Codes by Retry Setting")
plt.ylabel("Count")
plt.xticks(rotation=0)
plt.tight_layout()
filename = "retry_plots/status_codes_stacked_bar.png"
plt.savefig(filename)
print(f"Saved {filename}")
plt.close()


