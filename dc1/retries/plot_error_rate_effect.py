import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Function to extract codes
def extract_codes(row, code):
    try:
        codes = dict(item.split(":") for item in row.split())
        return int(codes.get(str(code), 0))
    except:
        return 0

# Load and truncate
df_25 = pd.read_csv("retries_summary_25err_updated.csv").head(50)
df_50 = pd.read_csv("retries_summary_enabled.csv").head(50)
df_75 = pd.read_csv("retries_summary_75err_updated.csv").head(50)

# Label and normalize status codes
for df, label, total_reqs in zip(
    [df_25, df_50, df_75],
    [25, 50, 75],
    [1800, 3600, 1800]  # Per batch request volume
):
    df["ErrorRate"] = label
    df["Status_200"] = df["StatusCodes"].apply(lambda x: extract_codes(x, 200) / total_reqs)
    df["Status_503"] = df["StatusCodes"].apply(lambda x: extract_codes(x, 503) / total_reqs)

df = pd.concat([df_25, df_50, df_75], ignore_index=True)
os.makedirs("retry_plots", exist_ok=True)

metrics = ["SuccessRate", "P50Latency(ms)", "MeanLatency(ms)", "BytesInTotal", "BytesInMean"]

# Regular metrics vs Error Rate
for metric in metrics:
    plt.figure(figsize=(8, 5))
    sns.boxplot(data=df, x="ErrorRate", y=metric, palette="Set2")
    plt.title(f"{metric} vs. Error Rate (Retries = 5)")
    plt.xlabel("Error Rate (%)")
    plt.ylabel(metric)
    plt.grid(True)
    plt.tight_layout()
    path = f"retry_plots/{metric.replace('(', '').replace(')', '').replace('/', '_')}_vs_error_rate.png"
    plt.savefig(path)
    plt.close()

# Status code box plot
df_status = pd.melt(
    df,
    id_vars=["ErrorRate"],
    value_vars=["Status_200", "Status_503"],
    var_name="Status",
    value_name="Fraction"
)
df_status["Status"] = df_status["Status"].replace({"Status_200": "Success", "Status_503": "Error"})

plt.figure(figsize=(8, 5))
sns.boxplot(data=df_status, x="ErrorRate", y="Fraction", hue="Status", palette="Set1")
plt.title("Normalized Status Codes by Error Rate")
plt.ylabel("Fraction of Requests")
plt.xlabel("Error Rate (%)")
plt.grid(True)
plt.tight_layout()
plt.savefig("retry_plots/status_code_boxplot_vs_error_rate.png")
plt.close()

