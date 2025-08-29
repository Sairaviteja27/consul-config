import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

def extract_codes(row, code):
    try:
        codes = dict(item.split(":") for item in row.split())
        return int(codes.get(str(code), 0))
    except:
        return 0

# Load and truncate
df_0 = pd.read_csv("retries_summary_disabled.csv").head(50)
df_2 = pd.read_csv("retries_summary_2_retries.csv").head(50)
df_5 = pd.read_csv("retries_summary_enabled.csv").head(50)
df_7 = pd.read_csv("retries_summary_7_retries.csv").head(50)

# Add retry count and normalize codes
for df, retry, total_reqs in zip(
    [df_0, df_2, df_5, df_7],
    [0, 2, 5, 7],
    [1800, 1800, 3600, 1800]
):
    df["RetryCount"] = retry
    df["Status_200"] = df["StatusCodes"].apply(lambda x: extract_codes(x, 200) / total_reqs)
    df["Status_503"] = df["StatusCodes"].apply(lambda x: extract_codes(x, 503) / total_reqs)

df = pd.concat([df_0, df_2, df_5, df_7], ignore_index=True)
os.makedirs("retry_plots", exist_ok=True)

metrics = ["SuccessRate", "P50Latency(ms)", "MeanLatency(ms)", "BytesInTotal", "BytesInMean"]

# Regular metrics vs Retry Count
for metric in metrics:
    plt.figure(figsize=(8, 5))
    sns.boxplot(data=df, x="RetryCount", y=metric, palette="Set3")
    plt.title(f"{metric} vs. Retry Count (Error Rate = 50%)")
    plt.xlabel("Retry Count")
    plt.ylabel(metric)
    plt.grid(True)
    plt.tight_layout()
    path = f"retry_plots/{metric.replace('(', '').replace(')', '').replace('/', '_')}_vs_retry_count.png"
    plt.savefig(path)
    plt.close()

# Status code box plot
df_status = pd.melt(
    df,
    id_vars=["RetryCount"],
    value_vars=["Status_200", "Status_503"],
    var_name="Status",
    value_name="Fraction"
)
df_status["Status"] = df_status["Status"].replace({"Status_200": "Success", "Status_503": "Error"})

plt.figure(figsize=(8, 5))
sns.boxplot(data=df_status, x="RetryCount", y="Fraction", hue="Status", palette="Set1")
plt.title("Normalized Status Codes by Retry Count")
plt.ylabel("Fraction of Requests")
plt.xlabel("Retry Count")
plt.grid(True)
plt.tight_layout()
plt.savefig("retry_plots/status_code_boxplot_vs_retry_count.png")
plt.close()

