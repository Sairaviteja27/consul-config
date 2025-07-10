import matplotlib.pyplot as plt
import numpy as np

# Read data
with open("failover_times.txt") as f:
    times = [float(line.strip()) for line in f if line.strip()]

# Plot boxplot
plt.figure(figsize=(10, 6))
plt.boxplot(times, vert=False, patch_artist=True,
            boxprops=dict(facecolor="lightblue", color="blue"),
            medianprops=dict(color="red"),
            whiskerprops=dict(color="black"),
            capprops=dict(color="black"),
            flierprops=dict(markerfacecolor='orange', marker='o', markersize=6, linestyle='none'))

plt.title("Failover Switch Time - Box and Whiskers Plot")
plt.xlabel("Switch Time (seconds)")
plt.grid(True)
plt.savefig("failover_boxplot.png")

print("📦 Boxplot saved to failover_boxplot.png")
