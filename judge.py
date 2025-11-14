#!/usr/bin/env python3
"""Compare two CSVs of id pairs and check whether the pairs are the same (order-insensitive).

Usage: judge.py expected.csv actual.csv
Exit code 0 if they match, 2 if they differ.
"""
import os
import argparse
import csv
import sys
from collections import Counter


def read_pairs(path):
    """Read pairs from a CSV file and return a Counter of normalized pairs.

    Normalization: each pair is sorted (so (a,b) == (b,a)).
    Handles an optional header if the first row starts with 'id'.
    """
    pairs = []
    with open(path, newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)
    if not rows:
        return Counter()
    # detect header like: id1,id2
    start = 0
    first = rows[0]
    if len(first) >= 2 and first[0].strip().lower().startswith("id") and first[1].strip().lower().startswith("id"):
        start = 1
    for r in rows[start:]:
        if not r or all(cell.strip() == "" for cell in r):
            continue
        a = r[0].strip()
        b = r[1].strip() if len(r) > 1 else ""
        norm = tuple(sorted((a, b)))
        pairs.append(norm)
    return Counter(pairs)


def main():
    p = argparse.ArgumentParser(description="Compare two CSVs of id pairs (order-insensitive)")
    p.add_argument("testcase", help="testcase number")
    args = p.parse_args()

    exp_file = f"testcase/{args.testcase}.csv"
    act_file = f"out/{args.testcase}.csv"
    
    # Check if files exist
    if not os.path.isfile(exp_file):
        print(f"Expected file not found: {exp_file}")
        return 1
    if not os.path.isfile(act_file):
        print(f"Actual file not found: {act_file}")
        return 1
    
    exp = read_pairs(exp_file)
    act = read_pairs(act_file)
    if exp == act:
        print("OK: pairs match")
        return 0

    # compute differences using Counter subtraction
    missing = exp - act
    extra = act - exp

    if missing:
        print("Missing from actual:")
        for (a, b), cnt in missing.items():
            print(f"  {a},{b}  x{cnt}")
    if extra:
        print("Extra in actual:")
        for (a, b), cnt in extra.items():
            print(f"  {a},{b}  x{cnt}")

    return 2


if __name__ == "__main__":
    rc = main()
    sys.exit(rc)
