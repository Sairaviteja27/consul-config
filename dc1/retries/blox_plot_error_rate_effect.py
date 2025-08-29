import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# -----------------------------
# Helper: extract a specific HTTP code count from "StatusCodes" string
# Example "200:1780 503:20" -> extract_codes(row, 200) == 1780
# -----------------------------
def extract_codes(row, code):
    try:
        codes = dict(item.split(":") for item in row.split())
        return int(codes.get(str(code), 0))
    except Exception:
        return 0

# -----------------------------
# Load data and truncate to first 50 batches for comparability
# -----------------------------
df_25 = pd.read_csv("retries_summary_25err_updated.csv").head(50)
df_50 = pd.read_csv("retries_summary_enabled.csv").head(50)       # retries=5 at 50% error
df_75 = pd.read_csv("retries_summary_75err_updated.csv").head(50)

# -----------------------------
# Label and normalize status codes
# total_reqs correspond to the per-file batch volumes you used
# -----------------------------
for df, label, total_reqs in zip(
    [df_25, df_50, df_75],
    [25, 50, 75],
    [1800, 3600, 1800]  # per-batch request totals for each file
):
    df["ErrorRate"] = label
    df["Status_200"] = df["StatusCodes"].apply(lambda x: extract_codes(x, 200) / total_reqs)
    df["Status_503"] = df["StatusCodes"].apply(lambda x: extract_codes(x, 503) / total_reqs)

# Combine
df = pd.concat([df_25, df_50, df_75], ignore_index=True)

# Output dir
os.makedirs("retry_plots", exist_ok=True)

# -----------------------------
# Metric boxplots vs Error Rate
# -----------------------------
metrics = ["SuccessRate", "P50Latency(ms)", "MeanLatency(ms)", "BytesInTotal", "BytesInMean"]

for metric in metrics:
    plt.figure(figsize=(8, 5))
    sns.boxplot(data=df, x="ErrorRate", y=metric, palette="Set2")
    plt.title(f"{metric} vs. Error Rate (Retries = 5)", fontsize=13)
    plt.xlabel("Error Rate (%)")
    plt.ylabel(metric)
    plt.grid(True, linestyle="--", alpha=0.6)
    plt.tight_layout()
    path = f"retry_plots/{metric.replace('(', '').replace(')', '').replace('/', '_')}_vs_error_rate.png"
    plt.savefig(path, dpi=180)
    plt.close()

# -----------------------------
# Status code boxplot with distinct colors
# -----------------------------
df_status = pd.melt(
    df,
    id_vars=["ErrorRate"],
    value_vars=["Status_200", "Status_503"],
    var_name="Status",
    value_name="Fraction"
)
df_status["Status"] = df_status["Status"].replace({
    "Status_200": "Success (200)",
    "Status_503": "Error (503)"
})

plt.figure(figsize=(8, 5))
palette = {"Success (200)": "#4CAF50", "Error (503)": "#E74C3C"}  # green for success, red for error
sns.boxplot(
    data=df_status,
    x="ErrorRate",
    y="Fraction",
    hue="Status",
    palette=palette
)
plt.title("Normalized Status Codes by Error Rate", fontsize=13)
plt.xlabel("Error Rate (%)")
plt.ylabel("Fraction of Requests")
plt.ylim(0, 1)  # fractions between 0 and 1
plt.grid(True, linestyle="--", alpha=0.6)
plt.legend(title="HTTP Status", loc="upper right")
plt.tight_layout()
plt.savefig("retry_plots/status_code_boxplot_vs_error_rate.png", dpi=180)
plt.close()

