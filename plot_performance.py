import matplotlib.pyplot as plt
import csv
import numpy as np
import os

def read_data(filename):
    data = {}
    if not os.path.exists(filename):
        print(f"Warning: {filename} not found.")
        return data
        
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            tc = row['testcase']
            data[tc] = {
                'seq_total': float(row['seq_total']),
                'cuda_total': float(row['cuda_total']),
                'cuda_compute': float(row['cuda_compute'])
            }
    return data

def plot_performance():
    ss_data = read_data('performance_SS.csv')
    sh_data = read_data('performance_SH.csv')

    if not ss_data or not sh_data:
        print("Error: Could not read data.")
        return

    # Get all unique testcases and sort them numerically
    all_testcases = set(ss_data.keys()) | set(sh_data.keys())
    testcases = sorted(list(all_testcases), key=lambda x: int(x))

    # Prepare data arrays
    ss_seq = []
    ss_cuda_total = []
    ss_cuda_compute = []
    
    sh_seq = []
    sh_cuda_total = []
    sh_cuda_compute = []

    for tc in testcases:
        # SS Data
        if tc in ss_data:
            ss_seq.append(ss_data[tc]['seq_total'])
            ss_cuda_total.append(ss_data[tc]['cuda_total'])
            ss_cuda_compute.append(ss_data[tc]['cuda_compute'])
        else:
            ss_seq.append(0)
            ss_cuda_total.append(0)
            ss_cuda_compute.append(0)
            
        # SH Data
        if tc in sh_data:
            sh_seq.append(sh_data[tc]['seq_total'])
            sh_cuda_total.append(sh_data[tc]['cuda_total'])
            sh_cuda_compute.append(sh_data[tc]['cuda_compute'])
        else:
            sh_seq.append(0)
            sh_cuda_total.append(0)
            sh_cuda_compute.append(0)

    # Convert to ms
    ss_seq = [x * 1000 for x in ss_seq]
    ss_cuda_total = [x * 1000 for x in ss_cuda_total]
    ss_cuda_compute = [x * 1000 for x in ss_cuda_compute]
    sh_seq = [x * 1000 for x in sh_seq]
    sh_cuda_total = [x * 1000 for x in sh_cuda_total]
    sh_cuda_compute = [x * 1000 for x in sh_cuda_compute]

    # Truncate logic
    TRUNCATE_THRESHOLD = 300 # ms
    
    def get_plot_data(data):
        return [min(x, TRUNCATE_THRESHOLD) for x in data]

    x = np.arange(len(testcases))
    width = 0.12  # width of the bars

    fig, ax = plt.subplots(figsize=(15, 8))

    # Plot bars
    # Order: SS Seq, SH Seq, SS CUDA Total, SH CUDA Total, SS Compute, SH Compute
    
    c_ss = 'tab:blue'
    c_sh = 'tab:orange'
    
    # SS Seq
    rects1 = ax.bar(x - 2.5*width, get_plot_data(ss_seq), width, label='SS Seq', color=c_ss)
    
    # SH Seq
    rects2 = ax.bar(x - 1.5*width, get_plot_data(sh_seq), width, label='SH Seq', color=c_sh)
    
    # SS CUDA Total
    rects3 = ax.bar(x - 0.5*width, get_plot_data(ss_cuda_total), width, label='SS CUDA Total', 
                    color='white', edgecolor=c_ss, hatch='xx')
    
    # SH CUDA Total
    rects4 = ax.bar(x + 0.5*width, get_plot_data(sh_cuda_total), width, label='SH CUDA Total', 
                    color='white', edgecolor=c_sh, hatch='xx')
    
    # SS CUDA Compute
    rects5 = ax.bar(x + 1.5*width, get_plot_data(ss_cuda_compute), width, label='SS CUDA Compute', 
                    color='white', edgecolor=c_ss, hatch='//')
    
    # SH CUDA Compute
    rects6 = ax.bar(x + 2.5*width, get_plot_data(sh_cuda_compute), width, label='SH CUDA Compute', 
                    color='white', edgecolor=c_sh, hatch='//')

    # Add 16ms line
    ax.axhline(y=16, color='black', linestyle='--', linewidth=1, label='16ms (60 FPS)')

    ax.set_ylabel('Time (ms)')
    ax.set_xlabel('Testcase')
    ax.set_title('Performance Comparison: Sort-and-Sweep (SS) vs Spatial Hashing (SH)')
    ax.set_xticks(x)
    ax.set_xticklabels(testcases)
    ax.legend()
    
    ax.grid(True, which='both', axis='y', linestyle='--', alpha=0.7)

    # Annotate truncated values
    def annotate_truncated(rects, original_data):
        for rect, val in zip(rects, original_data):
            if val > TRUNCATE_THRESHOLD:
                height = rect.get_height()
                ax.annotate(f'{val:.0f}',
                            xy=(rect.get_x() + rect.get_width() / 2, height),
                            xytext=(0, 3),  # 3 points vertical offset
                            textcoords="offset points",
                            ha='center', va='bottom', rotation=90, color='red', fontweight='bold')

    annotate_truncated(rects1, ss_seq)
    annotate_truncated(rects2, sh_seq)
    annotate_truncated(rects3, ss_cuda_total)
    annotate_truncated(rects4, sh_cuda_total)
    annotate_truncated(rects5, ss_cuda_compute)
    annotate_truncated(rects6, sh_cuda_compute)

    # Add a note about truncation
    plt.figtext(0.99, 0.01, f'* Values > {TRUNCATE_THRESHOLD}ms are truncated and annotated with actual value', 
                horizontalalignment='right', fontsize=10, color='red')

    # Save linear scale plot
    plt.tight_layout()
    plt.savefig('performance_comparison.png')
    print("Saved performance_comparison.png")

if __name__ == "__main__":
    plot_performance()
