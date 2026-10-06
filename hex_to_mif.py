#!/usr/bin/env python3
"""
Convert raw 32-bit hex files (word-per-line) into Intel/Altera MIF (Memory Initialization File)
for synthesis in Quartus II / Quartus Prime.
"""

import sys
import argparse

def convert_hex_to_mif(hex_path, mif_path, depth_words=4096, width_bits=32):
    with open(hex_path, "r") as f:
        lines = [l.strip() for l in f if l.strip() and not l.strip().startswith("//")]

    words = []
    for l in lines:
        for token in l.split():
            words.append(token.strip())

    with open(mif_path, "w") as out:
        out.write(f"WIDTH={width_bits};\n")
        out.write(f"DEPTH={depth_words};\n")
        out.write("ADDRESS_RADIX=HEX;\n")
        out.write("DATA_RADIX=HEX;\n\n")
        out.write("CONTENT BEGIN\n")

        for idx in range(depth_words):
            if idx < len(words):
                val = words[idx]
            else:
                val = "00000000"
            out.write(f"    {idx:04X} : {val};\n")

        out.write("END;\n")

    print(f"Converted {hex_path} -> {mif_path} (Depth: {depth_words} words, Width: {width_bits} bits)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Verilog hex file to Quartus MIF format")
    parser.add_argument("hex_file", help="Input hex file path")
    parser.add_argument("mif_file", help="Output mif file path")
    parser.add_argument("--depth", type=int, default=4096, help="Memory depth in words (default 4096 for 16KB)")
    args = parser.parse_args()

    convert_hex_to_mif(args.hex_file, args.mif_file, depth_words=args.depth)
