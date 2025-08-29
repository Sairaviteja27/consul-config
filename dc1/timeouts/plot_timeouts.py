import os
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# =============================
# Paths / I/O
# =============================
INPUT_CSV = "timeouts_summary.csv"
OUT_DIR = "timeout_plots"
os.makedirs(OUT_DIR, exist_ok=True)

if not os.path.exists(INPUT_CSV):
    print(f"[ERROR] {INPUT_CSV} not found")
    raise SystemExit(1)

# =============================
# Read + cleanup
# =============================
df = pd.read_csv(INPUT_CSV)

# Columns to plot
METRICS = [
    "SuccessRatio(%)",
    "TimeoutHitRate(%)",
    "TimeoutAccuracyMean(ms)",
    "TimeoutAccuracyP95(ms)",
    "WastedTimeMean(ms)",
    "WastedTimeP95(ms)",
    "P95_200(ms)",
    "P99_200(ms)",
]

# Convert numeric columns safely
numeric_cols = ["Delay(s)", "Timeout(s)", "Rate"] + METRICS
for col in numeric_cols:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors="coerce")

if "Delay(s)" not in df.columns:
    print("[ERROR] 'Delay(s)' column missing in CSV")
    raise SystemExit(1)

# =============================
# Delay order (matches your bash DELAY_S_LIST)
# =============================
delay_order = [0.2, 0.5, 0.8, 1.0, 1.2, 1.5]
df = df[df["Delay(s)"].isin(delay_order)]

# =============================
# Outlier caps
# =============================
CAPS = {
    "SuccessRatio(%)":         dict(lower=0, upper=100),
    "TimeoutHitRate(%)":       dict(lower=0, upper=100),
    "TimeoutAccuracyMean(ms)": dict(lower=0, upper=2000),
    "TimeoutAccuracyP95(ms)":  dict(lower=0, upper=3000),
    "WastedTimeMean(ms)":      dict(lower=0, upper=3000),
    "WastedTimeP95(ms)":       dict(lower=0, upper=5000),
    "P95_200(ms)":             dict(lower=0, upper=5000),
    "P99_200(ms)":             dict(lower=0, upper=10000),
}

def apply_caps(data, col, lower=None, upper=None):
    if col not in data:
        return pd.DataFrame(columns=data.columns)
    s = pd.to_numeric(data[col], errors="coerce")
    mask = s.notna()
    if lower is not None:
        mask &= (s >= lower)
    if upper is not None:
        mask &= (s <= upper)
    return data.loc[mask].copy()

# =============================
# Plot style
# =============================
sns.set_theme(context="talk", style="whitegrid")
plt.rcParams.update({
    "figure.dpi": 200,
    "savefig.dpi": 200,
    "axes.titleweight": "bold",
    "axes.titlesize": 18,
    "axes.labelsize": 14,
    "xtick.labelsize": 12,
    "ytick.labelsize": 12,
    "font.family": "DejaVu Sans",
})
PALETTE = sns.color_palette("colorblind")

# =============================
# Helper: save boxplot
# =============================
def save_boxplot(data, x, y, order, ylabel, title, fname, y_is_percent=False):
    if data.empty or y not in data:
        print(f"[WARN] No valid rows for {y}. Skipping.")
        return

    plt.figure(figsize=(8, 6))
    ax = sns.boxplot(
        data=data,
        x=x,
        y=y,
        order=order,
        palette=PALETTE,
        linewidth=1.4,
        fliersize=2.5,
        width=0.6,
    )

    ax.set_title(title, pad=12)
    ax.set_xlabel("Delay (s)")
    ax.set_ylabel(ylabel)

    if y_is_percent:
        ax.set_ylim(0, 100)

    ax.grid(True, axis="y", linestyle="--", linewidth=0.8, alpha=0.6)
    sns.despine(offset=6, trim=True)

    # Clean fixed tick labels (no overlap with 3 values)
    ax.set_xticks(range(len(order)))
    ax.set_xticklabels([str(d) for d in order])

    plt.tight_layout()
    out_path = os.path.join(OUT_DIR, fname)
    plt.savefig(out_path)
    plt.close()
    print(f"[OK] Saved {out_path}")

# =============================
# Generate plots
# =============================
for m in METRICS:
    if m not in df.columns:
        print(f"[WARN] Column not found: {m}")
        continue
    dfm = apply_caps(df, m, **CAPS[m])
    save_boxplot(
        dfm,
        "Delay(s)",
        m,
        delay_order,
        ylabel=m,
        title=f"{m} vs Delay (n={dfm[m].notna().sum()})",
        fname=f"timeouts_{m.replace('%','pct').replace('(','').replace(')','').replace('/','_')}_boxplot.png",
        y_is_percent=("%" in m),
    )

print("[DONE] All plots attempted.")

