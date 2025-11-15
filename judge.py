#!/usr/bin/env python3
"""Compare two text files of id pairs and check whether the pairs are the same (order-insensitive).

Usage: judge.py expected.out actual.out
Exit code 0 if they match, 2 if they differ.
"""
import os
import argparse
import csv
import sys
from collections import Counter
from aabb_io import read_pairs

def count_normalized_pairs(pairs):
    """Count occurrences of normalized pairs."""
    counter = Counter()
    for a, b in pairs:
        norm = tuple(sorted((a, b)))
        counter[norm] += 1
    return counter

def main():
    p = argparse.ArgumentParser(description="Compare two text files of id pairs (order-insensitive)")
    p.add_argument("testcase", help="testcase number")
    args = p.parse_args()

    exp_file = f"testcase/{args.testcase}.out"
    act_file = f"out/{args.testcase}.out"
    
    # Check if files exist
    if not os.path.isfile(exp_file):
        print(f"Expected file not found: {exp_file}")
        return 1
    if not os.path.isfile(act_file):
        print(f"Actual file not found: {act_file}")
        return 1
    
    exp = count_normalized_pairs(read_pairs(exp_file))
    act = count_normalized_pairs(read_pairs(act_file))
    if exp == act:
        print("OK: pairs match")
        return 0

    # compute differences using Counter subtraction
    missing = exp - act
    extra = act - exp

    # print 5 differences each
    if missing:
        print("Missing from actual:")
        for (a, b), cnt in list(missing.items())[:5]:
            print(f"  {a},{b}")
    if extra:
        print("Extra in actual:")
        for (a, b), cnt in list(extra.items())[:5]:
            print(f"  {a},{b}")

    return 2


if __name__ == "__main__":
    rc = main()
    sys.exit(rc)
