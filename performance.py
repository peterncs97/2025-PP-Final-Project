#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Performance benchmark script for AABB collision detection algorithms.
Usage: python performance.py <algorithm>
    algorithm: SS (Sort-and-Sweep) or SH (Spatial Hashing)
"""

import argparse
import subprocess
import re
import os
import csv


def run_job(script, algorithm, testcase):
    """Run a SLURM job with --wait and return the job ID."""
    cmd = ["sbatch", "--wait", script, algorithm, str(testcase)]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate()
    stdout = stdout.decode('utf-8')
    stderr = stderr.decode('utf-8')
    
    # Parse job ID from output like "Submitted batch job 123456"
    # Check both stdout and stderr as sbatch may output to either
    combined_output = stdout + stderr
    match = re.search(r"Submitted batch job (\d+)", combined_output)
    if not match:
        raise RuntimeError("Could not parse job ID from stdout: '{}', stderr: '{}'".format(stdout.strip(), stderr.strip()))
    
    return int(match.group(1))


def parse_time_from_log(log_path):
    """Parse execution time from log file."""
    if not os.path.exists(log_path):
        return None
    
    with open(log_path, 'r') as f:
        content = f.read()
    
    # Match "Time elapsed: X.XXX seconds" (supports scientific notation like 3.7719e-05)
    match = re.search(r"Time elapsed:\s*([\d.]+(?:[eE][+-]?\d+)?)\s*seconds", content)
    if match:
        return float(match.group(1))
    
    return None


def run_benchmark(algorithm, testcases):
    """Run benchmarks for all testcases and return results."""
    results = {
        "seq": {},
        "cuda": {}
    }
    
    log_dir = "log"
    
    # Run all jobs sequentially with --wait
    print("Running jobs for algorithm: {}".format(algorithm))
    jobs = {"seq": {}, "cuda": {}}
    
    for tc in testcases:
        print("  Running testcase {}...".format(tc))
        
        # Run seq job
        try:
            print("    Running seq job (waiting)...")
            seq_job_id = run_job("./scripts/run_seq.sh", algorithm, tc)
            jobs["seq"][tc] = seq_job_id
            print("    seq job {} completed".format(seq_job_id))
        except Exception as e:
            print("    seq job failed: {}".format(e))
            jobs["seq"][tc] = None
        
        # Run cuda job
        try:
            print("    Running cuda job (waiting)...")
            cuda_job_id = run_job("./scripts/run_cuda.sh", algorithm, tc)
            jobs["cuda"][tc] = cuda_job_id
            print("    cuda job {} completed".format(cuda_job_id))
        except Exception as e:
            print("    cuda job failed: {}".format(e))
            jobs["cuda"][tc] = None
    
    # Parse results from log files
    print("\nParsing results...")
    for runner in ["seq", "cuda"]:
        for tc, job_id in jobs[runner].items():
            if job_id is None:
                results[runner][tc] = None
                continue
            
            log_path = os.path.join(log_dir, "{}_{}.out".format(runner, job_id))
            elapsed_time = parse_time_from_log(log_path)
            results[runner][tc] = elapsed_time
            
            if elapsed_time is not None:
                print("  {} testcase {}: {:.6f} seconds".format(runner, tc, elapsed_time))
            else:
                print("  {} testcase {}: FAILED (log: {})".format(runner, tc, log_path))
    
    return results


def save_results_to_csv(results, algorithm, testcases, output_path):
    """Save benchmark results to CSV file."""
    with open(output_path, 'w') as f:
        writer = csv.writer(f)
        writer.writerow(["testcase", "seq_time", "cuda_time"])
        
        for tc in testcases:
            seq_time = results["seq"].get(tc)
            cuda_time = results["cuda"].get(tc)
            
            seq_str = "{:.6f}".format(seq_time) if seq_time is not None else "N/A"
            cuda_str = "{:.6f}".format(cuda_time) if cuda_time is not None else "N/A"
            
            writer.writerow([tc, seq_str, cuda_str])
    
    print("\nResults saved to: {}".format(output_path))


def main():
    parser = argparse.ArgumentParser(
        description="Benchmark AABB collision detection algorithms"
    )
    parser.add_argument(
        "algorithm",
        choices=["SS", "SH"],
        help="Algorithm to benchmark: SS (Sort-and-Sweep) or SH (Spatial Hashing)"
    )
    parser.add_argument(
        "--testcases",
        type=str,
        default="1-6,11-20",
        help="Testcase list (default: 1-6,11-20)"
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Output CSV file path (default: performance_<algorithm>.csv)"
    )
    
    args = parser.parse_args()
    
    # Parse testcase list (supports formats like "1-6,11-20" or "1,2,3")
    testcases = []
    for part in args.testcases.split(","):
        if "-" in part:
            start, end = map(int, part.split("-"))
            testcases.extend(range(start, end + 1))
        else:
            testcases.append(int(part))
    
    # Set output path
    output_path = args.output if args.output else "performance_{}.csv".format(args.algorithm)
    
    print("Benchmarking algorithm: {}".format(args.algorithm))
    print("Testcases: {}".format(testcases))
    print("Output: {}".format(output_path))
    print()
    
    # Run benchmark
    results = run_benchmark(args.algorithm, testcases)
    
    # Save results
    save_results_to_csv(results, args.algorithm, testcases, output_path)
    
    # Print summary table
    print("\n" + "=" * 50)
    print("Performance Summary ({})".format(args.algorithm))
    print("=" * 50)
    print("{:<10} {:<15} {:<15} {:<10}".format("Testcase", "Sequential", "CUDA", "Speedup"))
    print("-" * 50)
    
    for tc in testcases:
        seq_time = results["seq"].get(tc)
        cuda_time = results["cuda"].get(tc)
        
        seq_str = "{:.6f}s".format(seq_time) if seq_time is not None else "N/A"
        cuda_str = "{:.6f}s".format(cuda_time) if cuda_time is not None else "N/A"
        
        if seq_time is not None and cuda_time is not None and cuda_time > 0:
            speedup = seq_time / cuda_time
            speedup_str = "{:.2f}x".format(speedup)
        else:
            speedup_str = "N/A"
        
        print("{:<10} {:<15} {:<15} {:<10}".format(tc, seq_str, cuda_str, speedup_str))
    
    print("=" * 50)


if __name__ == "__main__":
    main()
