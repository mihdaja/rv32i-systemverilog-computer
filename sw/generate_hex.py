#!/usr/bin/env python3
"""
generate_hex.py - RV32I Software Hex Generator & Fallback Assembler

This tool converts compiled RISC-V binaries (ELF or raw binary) into 32-bit
hexadecimal memory initialization files formatted for Verilog $readmemh.
It also includes a pure-Python RV32I assembler so test programs can be assembled
and converted into Verilog memory images on systems without a GCC toolchain.

Memory Map:
  ROM: 0x00000000 - 0x00003FFF (16 KB = 4096 32-bit words)
  RAM: 0x10000000 - 0x1000FFFF (64 KB = 16384 32-bit words)
"""

import sys
import os
import struct
import argparse
import re

ROM_BASE = 0x00000000
ROM_SIZE = 16 * 1024       # 16 KB = 4096 words
RAM_BASE = 0x10000000
RAM_SIZE = 64 * 1024       # 64 KB = 16384 words

NOP_INSTRUCTION = 0x00000013  # addi x0, x0, 0

# ============================================================================
# Pure Python RV32I Assembler
# ============================================================================

ABI_REG_MAP = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7,
    's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13,
    'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 's8': 24, 's9': 25,
    's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31
}

def parse_reg(reg_str):
    reg = reg_str.strip().lower()
    if reg.startswith('x') and reg[1:].isdigit():
        idx = int(reg[1:])
        if 0 <= idx <= 31:
            return idx
    if reg in ABI_REG_MAP:
        return ABI_REG_MAP[reg]
    raise ValueError(f"Invalid register name: '{reg_str}'")

def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_i(imm, rs1, funct3, rd, opcode):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_s(imm, rs2, rs1, funct3, opcode):
    imm12 = imm & 0xFFF
    imm11_5 = (imm12 >> 5) & 0x7F
    imm4_0 = imm12 & 0x1F
    return (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           (imm4_0 << 7) | (opcode & 0x7F)

def encode_b(imm, rs2, rs1, funct3, opcode):
    imm13 = imm & 0x1FFF
    b12 = (imm13 >> 12) & 0x1
    b10_5 = (imm13 >> 5) & 0x3F
    b4_1 = (imm13 >> 1) & 0xF
    b11 = (imm13 >> 11) & 0x1
    return (b12 << 31) | (b10_5 << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           (b4_1 << 8) | (b11 << 7) | (opcode & 0x7F)

def encode_u(imm, rd, opcode):
    if imm > 0xFFFFF or imm < -0x80000:
        imm20 = (imm >> 12) & 0xFFFFF
    else:
        imm20 = imm & 0xFFFFF
    return (imm20 << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_j(imm, rd, opcode):
    imm21 = imm & 0x1FFFFF
    j20 = (imm21 >> 20) & 0x1
    j10_1 = (imm21 >> 1) & 0x3FF
    j11 = (imm21 >> 11) & 0x1
    j19_12 = (imm21 >> 12) & 0xFF
    return (j20 << 31) | (j10_1 << 21) | (j11 << 20) | \
           (j19_12 << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

class RV32IAssembler:
    def __init__(self):
        self.labels = {}
        self.numeric_labels = [] # list of (num, addr)

    def eval_expr(self, expr_str, current_pc=0, forward_resolve=False):
        expr_str = expr_str.strip()
        # Check numeric local labels e.g. 1b, 1f
        m_num = re.match(r'^(\d+)([bf])$', expr_str)
        if m_num:
            num = int(m_num.group(1))
            dir_flag = m_num.group(2)
            if dir_flag == 'b':
                # find closest previous numeric label
                cand = [addr for (n, addr) in self.numeric_labels if n == num and addr <= current_pc]
                if cand:
                    return cand[-1]
            elif dir_flag == 'f':
                # find closest forward numeric label
                cand = [addr for (n, addr) in self.numeric_labels if n == num and addr > current_pc]
                if cand:
                    return cand[0]
            if not forward_resolve:
                return 0

        # Replace label names with addresses
        for lbl, addr in sorted(self.labels.items(), key=lambda x: len(x[0]), reverse=True):
            if re.search(r'\b' + re.escape(lbl) + r'\b', expr_str):
                expr_str = re.sub(r'\b' + re.escape(lbl) + r'\b', str(addr), expr_str)

        try:
            return eval(expr_str, {"__builtins__": None}, {})
        except Exception:
            if forward_resolve:
                raise ValueError(f"Could not resolve expression: '{expr_str}'")
            return 0

    def parse_offset_reg(self, token):
        # Format: offset(reg) or (reg)
        m = re.match(r'^(.*)\(([^)]+)\)$', token.strip())
        if m:
            off_str = m.group(1).strip()
            reg_str = m.group(2).strip()
            off_val = off_str if off_str else '0'
            return off_val, parse_reg(reg_str)
        raise ValueError(f"Expected offset(reg), got: '{token}'")

    def parse_string_literal(self, s):
        s = s.strip()
        if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
            s = s[1:-1]
        import codecs
        try:
            return codecs.escape_decode(bytes(s, "utf-8"))[0]
        except Exception:
            return s.encode("utf-8")

    def assemble(self, source_text):
        # Preprocess lines: strip comments
        raw_lines = source_text.splitlines()
        clean_items = []
        for line in raw_lines:
            # strip # and // comments
            code = line
            idx_hash = code.find('#')
            if idx_hash != -1:
                code = code[:idx_hash]
            idx_slash = code.find('//')
            if idx_slash != -1:
                code = code[:idx_slash]
            code = code.strip()
            if not code:
                continue

            # check for labels
            while ':' in code:
                # Watch out for colons inside strings
                in_quote = False
                quote_char = None
                colon_idx = -1
                for i, ch in enumerate(code):
                    if ch in ('"', "'") and (i == 0 or code[i-1] != '\\'):
                        if not in_quote:
                            in_quote = True
                            quote_char = ch
                        elif quote_char == ch:
                            in_quote = False
                    elif ch == ':' and not in_quote:
                        colon_idx = i
                        break
                if colon_idx != -1:
                    lbl = code[:colon_idx].strip()
                    code = code[colon_idx+1:].strip()
                    clean_items.append(('label', lbl))
                else:
                    break
            if code:
                clean_items.append(('line', code))

        # Pass 1: compute addresses and collect labels
        rom_bytes = bytearray(ROM_SIZE)
        ram_bytes = bytearray(RAM_SIZE)
        curr_segment = 'ROM'
        curr_pc = 0

        parsed_tokens = []

        for item_type, content in clean_items:
            if item_type == 'label':
                if content.isdigit():
                    self.numeric_labels.append((int(content), curr_pc))
                else:
                    self.labels[content] = curr_pc
                continue

            line = content
            tokens = [t.strip() for t in line.replace(',', ' ').split() if t.strip()]
            if not tokens:
                continue

            mnemonic = tokens[0].lower()

            if mnemonic == '.section':
                sec = tokens[1].lower() if len(tokens) > 1 else ''
                if '.rodata' in sec or '.text' in sec:
                    curr_segment = 'ROM'
                elif '.data' in sec or '.bss' in sec:
                    curr_segment = 'RAM'
                continue
            elif mnemonic in ('.text', '.text.init', '.rodata'):
                curr_segment = 'ROM'
                continue
            elif mnemonic in ('.data', '.bss'):
                curr_segment = 'RAM'
                continue
            elif mnemonic in ('.equ', '.set'):
                sym_name = tokens[1]
                sym_val = self.eval_expr(tokens[2], curr_pc)
                self.labels[sym_name] = sym_val
                continue
            elif mnemonic in ('.globl', '.global', '.type', '.size'):
                continue
            elif mnemonic in ('.align', '.balign'):
                align = int(tokens[1])
                mask = align - 1
                curr_pc = (curr_pc + mask) & ~mask
                continue
            elif mnemonic == '.org':
                curr_pc = self.eval_expr(tokens[1], curr_pc)
                continue
            elif mnemonic == '.string' or mnemonic == '.asciz' or mnemonic == '.ascii':
                # find original string literal
                first_space = line.find(' ')
                str_lit = line[first_space:].strip() if first_space != -1 else ''
                b = self.parse_string_literal(str_lit)
                if mnemonic in ('.string', '.asciz'):
                    b += b'\x00'
                parsed_tokens.append((curr_segment, curr_pc, 'data_bytes', b))
                curr_pc += len(b)
                continue
            elif mnemonic == '.byte':
                vals = [self.eval_expr(x, curr_pc) & 0xFF for x in tokens[1:]]
                b = bytes(vals)
                parsed_tokens.append((curr_segment, curr_pc, 'data_bytes', b))
                curr_pc += len(b)
                continue
            elif mnemonic == '.word':
                parsed_tokens.append((curr_segment, curr_pc, 'data_words', tokens[1:]))
                curr_pc += 4 * len(tokens[1:])
                continue

            # Instructions
            # Pseudo-instructions expanding to 2 instructions (e.g. li/la with large immediate)
            if mnemonic in ('li', 'la'):
                rd = tokens[1]
                val_str = tokens[2]
                parsed_tokens.append((curr_segment, curr_pc, mnemonic, tokens[1:]))
                curr_pc += 8  # reserve 8 bytes (lui + addi)
            elif mnemonic == 'call':
                parsed_tokens.append((curr_segment, curr_pc, mnemonic, tokens[1:]))
                curr_pc += 4
            else:
                parsed_tokens.append((curr_segment, curr_pc, mnemonic, tokens[1:]))
                curr_pc += 4

        # Pass 2: generate binary bytes
        for seg, pc, mnemonic, args in parsed_tokens:
            target_mem = rom_bytes if seg == 'ROM' else ram_bytes
            base_offset = ROM_BASE if seg == 'ROM' else RAM_BASE
            mem_idx = pc - base_offset

            if mnemonic == 'data_bytes':
                target_mem[mem_idx:mem_idx+len(args)] = args
                continue
            elif mnemonic == 'data_words':
                for i, w_expr in enumerate(args):
                    w_val = self.eval_expr(w_expr, pc + i*4, forward_resolve=True) & 0xFFFFFFFF
                    target_mem[mem_idx+i*4:mem_idx+i*4+4] = struct.pack('<I', w_val)
                continue

            inst_word = None

            # R-type
            r_ops = {
                'add': (0x00, 0, 0x33), 'sub': (0x20, 0, 0x33),
                'sll': (0x00, 1, 0x33), 'slt': (0x00, 2, 0x33),
                'sltu': (0x00, 3, 0x33), 'xor': (0x00, 4, 0x33),
                'srl': (0x00, 5, 0x33), 'sra': (0x20, 5, 0x33),
                'or':  (0x00, 6, 0x33), 'and': (0x00, 7, 0x33)
            }
            if mnemonic in r_ops:
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                f7, f3, opc = r_ops[mnemonic]
                inst_word = encode_r(f7, rs2, rs1, f3, rd, opc)

            # I-type ALU
            i_ops = {
                'addi': (0, 0x13), 'slti': (2, 0x13), 'sltiu': (3, 0x13),
                'xori': (4, 0x13), 'ori': (6, 0x13), 'andi': (7, 0x13)
            }
            if mnemonic in i_ops:
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                imm = self.eval_expr(args[2], pc, forward_resolve=True)
                f3, opc = i_ops[mnemonic]
                inst_word = encode_i(imm, rs1, f3, rd, opc)

            # Shift immediate
            if mnemonic in ('slli', 'srli', 'srai'):
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                shamt = self.eval_expr(args[2], pc, forward_resolve=True) & 0x1F
                f7 = 0x20 if mnemonic == 'srai' else 0x00
                f3 = 1 if mnemonic == 'slli' else 5
                inst_word = ((f7 & 0x7F) << 25) | (shamt << 20) | \
                            ((rs1 & 0x1F) << 15) | (f3 << 12) | \
                            ((rd & 0x1F) << 7) | 0x13

            # Loads
            load_ops = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
            if mnemonic in load_ops:
                rd = parse_reg(args[0])
                off_expr, rs1 = self.parse_offset_reg(args[1])
                imm = self.eval_expr(off_expr, pc, forward_resolve=True)
                inst_word = encode_i(imm, rs1, load_ops[mnemonic], rd, 0x03)

            # Stores
            store_ops = {'sb': 0, 'sh': 1, 'sw': 2}
            if mnemonic in store_ops:
                rs2 = parse_reg(args[0])
                off_expr, rs1 = self.parse_offset_reg(args[1])
                imm = self.eval_expr(off_expr, pc, forward_resolve=True)
                inst_word = encode_s(imm, rs2, rs1, store_ops[mnemonic], 0x23)

            # Branches
            b_ops = {
                'beq': 0, 'bne': 1, 'blt': 4,
                'bge': 5, 'bltu': 6, 'bgeu': 7
            }
            if mnemonic in b_ops:
                rs1 = parse_reg(args[0])
                rs2 = parse_reg(args[1])
                target = self.eval_expr(args[2], pc, forward_resolve=True)
                offset = target - pc
                inst_word = encode_b(offset, rs2, rs1, b_ops[mnemonic], 0x63)

            # JAL and JALR
            if mnemonic == 'jal':
                if len(args) == 1:
                    rd = 1 # ra
                    target = self.eval_expr(args[0], pc, forward_resolve=True)
                else:
                    rd = parse_reg(args[0])
                    target = self.eval_expr(args[1], pc, forward_resolve=True)
                offset = target - pc
                inst_word = encode_j(offset, rd, 0x6F)

            if mnemonic == 'jalr':
                if len(args) == 1:
                    rd = 1 # ra
                    off_expr, rs1 = self.parse_offset_reg(args[0])
                    imm = self.eval_expr(off_expr, pc, forward_resolve=True)
                else:
                    rd = parse_reg(args[0])
                    off_expr, rs1 = self.parse_offset_reg(args[1])
                    imm = self.eval_expr(off_expr, pc, forward_resolve=True)
                inst_word = encode_i(imm, rs1, 0, rd, 0x67)

            # U-type: LUI and AUIPC
            if mnemonic == 'lui':
                rd = parse_reg(args[0])
                imm = self.eval_expr(args[1], pc, forward_resolve=True)
                inst_word = encode_u(imm, rd, 0x37)

            if mnemonic == 'auipc':
                rd = parse_reg(args[0])
                imm = self.eval_expr(args[1], pc, forward_resolve=True)
                inst_word = encode_u(imm, rd, 0x17)

            # Pseudo-instructions
            if mnemonic == 'nop':
                inst_word = encode_i(0, 0, 0, 0, 0x13)
            elif mnemonic == 'mv':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                inst_word = encode_i(0, rs1, 0, rd, 0x13)
            elif mnemonic == 'not':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                inst_word = encode_i(-1, rs1, 4, rd, 0x13)
            elif mnemonic == 'neg':
                rd = parse_reg(args[0])
                rs2 = parse_reg(args[1])
                inst_word = encode_r(0x20, rs2, 0, 0, rd, 0x33)
            elif mnemonic == 'j':
                target = self.eval_expr(args[0], pc, forward_resolve=True)
                inst_word = encode_j(target - pc, 0, 0x6F)
            elif mnemonic == 'jr':
                rs1 = parse_reg(args[0])
                inst_word = encode_i(0, rs1, 0, 0, 0x67)
            elif mnemonic == 'ret':
                inst_word = encode_i(0, 1, 0, 0, 0x67)
            elif mnemonic == 'call':
                target = self.eval_expr(args[0], pc, forward_resolve=True)
                inst_word = encode_j(target - pc, 1, 0x6F)
            elif mnemonic in ('beqz', 'bnez', 'blez', 'bgez', 'bltz', 'bgtz'):
                rs1 = parse_reg(args[0])
                target = self.eval_expr(args[1], pc, forward_resolve=True)
                offset = target - pc
                if mnemonic == 'beqz': inst_word = encode_b(offset, 0, rs1, 0, 0x63)
                elif mnemonic == 'bnez': inst_word = encode_b(offset, 0, rs1, 1, 0x63)
                elif mnemonic == 'blez': inst_word = encode_b(offset, rs1, 0, 5, 0x63) # bge x0, rs1
                elif mnemonic == 'bgez': inst_word = encode_b(offset, 0, rs1, 5, 0x63) # bge rs1, x0
                elif mnemonic == 'bltz': inst_word = encode_b(offset, 0, rs1, 4, 0x63) # blt rs1, x0
                elif mnemonic == 'bgtz': inst_word = encode_b(offset, rs1, 0, 4, 0x63) # blt x0, rs1
            elif mnemonic in ('bgt', 'ble', 'bgtu', 'bleu'):
                rs1 = parse_reg(args[0])
                rs2 = parse_reg(args[1])
                target = self.eval_expr(args[2], pc, forward_resolve=True)
                offset = target - pc
                if mnemonic == 'bgt': inst_word = encode_b(offset, rs1, rs2, 4, 0x63) # blt rs2, rs1
                elif mnemonic == 'ble': inst_word = encode_b(offset, rs1, rs2, 5, 0x63) # bge rs2, rs1
                elif mnemonic == 'bgtu': inst_word = encode_b(offset, rs1, rs2, 6, 0x63) # bltu rs2, rs1
                elif mnemonic == 'bleu': inst_word = encode_b(offset, rs1, rs2, 7, 0x63) # bgeu rs2, rs1

            elif mnemonic in ('li', 'la'):
                rd = parse_reg(args[0])
                val = self.eval_expr(args[1], pc, forward_resolve=True) & 0xFFFFFFFF
                # Check if it fits in signed 12-bit immediate
                # Sign extend 12 bits
                signed_val = val if val < 0x80000000 else val - 0x100000000
                if -2048 <= signed_val <= 2047:
                    inst_word = encode_i(signed_val, 0, 0, rd, 0x13)
                    # Second instruction is nop to match reserved 8 bytes
                    target_mem[mem_idx:mem_idx+4] = struct.pack('<I', inst_word)
                    target_mem[mem_idx+4:mem_idx+8] = struct.pack('<I', NOP_INSTRUCTION)
                    continue
                else:
                    # LUI + ADDI
                    # hi = (val + 0x800) >> 12
                    hi = ((val + 0x800) >> 12) & 0xFFFFF
                    lo = val & 0xFFF
                    lo_signed = lo if lo < 0x800 else lo - 0x1000
                    i1 = encode_u(hi, rd, 0x37)
                    i2 = encode_i(lo_signed, rd, 0, rd, 0x13)
                    target_mem[mem_idx:mem_idx+4] = struct.pack('<I', i1)
                    target_mem[mem_idx+4:mem_idx+8] = struct.pack('<I', i2)
                    continue

            if inst_word is not None:
                target_mem[mem_idx:mem_idx+4] = struct.pack('<I', inst_word)
            else:
                raise ValueError(f"Unrecognized instruction: {mnemonic} {args}")

        return bytes(rom_bytes), bytes(ram_bytes)

# ============================================================================
# ELF32 Parser
# ============================================================================

def parse_elf32(file_path):
    """
    Pure Python ELF32 loader.
    Extracts loadable segments for ROM (0x00000000) and RAM (0x10000000).
    """
    with open(file_path, 'rb') as f:
        data = f.read()

    if data[:4] != b'\x7fELF':
        raise ValueError(f"File {file_path} is not a valid ELF file")

    ei_class = data[4]
    if ei_class != 1:
        raise ValueError("Only 32-bit ELF files are supported")

    ei_data = data[5]
    if ei_data != 1:
        raise ValueError("Only little-endian ELF files are supported")

    # Read ELF header
    e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum = struct.unpack_from('<IIIIHH', data, 28)

    rom_bytes = bytearray(ROM_SIZE)
    ram_bytes = bytearray(RAM_SIZE)

    for i in range(e_phnum):
        ph_offset = e_phoff + i * e_phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from('<IIIIIIII', data, ph_offset)

        if p_type == 1: # PT_LOAD
            seg_data = data[p_offset : p_offset + p_filesz]
            # Use physical address (p_paddr) for LMA
            lma = p_paddr if p_paddr != 0 else p_vaddr

            # Place into ROM if within ROM bounds
            if ROM_BASE <= lma < ROM_BASE + ROM_SIZE:
                off = lma - ROM_BASE
                rom_bytes[off : off + len(seg_data)] = seg_data

            # Place into RAM if VMA is within RAM bounds and filesz > 0
            if RAM_BASE <= p_vaddr < RAM_BASE + RAM_SIZE:
                off = p_vaddr - RAM_BASE
                ram_bytes[off : off + len(seg_data)] = seg_data

    return bytes(rom_bytes), bytes(ram_bytes)

# ============================================================================
# Verilog $readmemh Hex File Generator
# ============================================================================

def write_verilog_hex(byte_data, out_path, num_words=None, pad_val=0):
    """
    Writes 32-bit little-endian words as 8-character hex strings per line.
    """
    total_words = len(byte_data) // 4
    if num_words is None:
        num_words = total_words

    with open(out_path, 'w') as f:
        for i in range(num_words):
            if i < total_words:
                word = struct.unpack_from('<I', byte_data, i * 4)[0]
            else:
                word = pad_val
            f.write(f"{word:08x}\n")

# ============================================================================
# Main CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="Convert ELF/bin/asm to Verilog $readmemh hex files.")
    parser.add_argument("input", help="Input file (.elf, .bin, or .s/.S)")
    parser.add_argument("--rom-out", default="rom.hex", help="ROM output hex file (default: rom.hex)")
    parser.add_argument("--ram-out", default="ram.hex", help="RAM output hex file (default: ram.hex)")
    parser.add_argument("--rom-words", type=int, default=4096, help="ROM depth in 32-bit words (default: 4096 = 16KB)")
    parser.add_argument("--ram-words", type=int, default=16384, help="RAM depth in 32-bit words (default: 16384 = 64KB)")
    parser.add_argument("--pad-nop", action="store_true", help="Pad ROM unused space with NOP (0x00000013) instead of 0")

    args = parser.parse_args()

    input_file = args.input
    if not os.path.exists(input_file):
        print(f"Error: Input file {input_file} not found", file=sys.stderr)
        sys.exit(1)

    pad_word = NOP_INSTRUCTION if args.pad_nop else 0

    if input_file.endswith('.s') or input_file.endswith('.S'):
        print(f"Assembling assembly file using built-in RV32I assembler: {input_file}")
        with open(input_file, 'r') as f:
            source = f.read()
        assembler = RV32IAssembler()
        rom_bytes, ram_bytes = assembler.assemble(source)
    elif input_file.endswith('.elf') or open(input_file, 'rb').read(4) == b'\x7fELF':
        print(f"Parsing ELF file: {input_file}")
        rom_bytes, ram_bytes = parse_elf32(input_file)
    else:
        print(f"Reading raw binary file: {input_file}")
        with open(input_file, 'rb') as f:
            raw = f.read()
        rom_bytes = raw.ljust(ROM_SIZE, b'\x00')
        ram_bytes = bytes(RAM_SIZE)

    write_verilog_hex(rom_bytes, args.rom_out, num_words=args.rom_words, pad_val=pad_word)
    print(f"Generated ROM hex: {args.rom_out} ({args.rom_words} words)")

    write_verilog_hex(ram_bytes, args.ram_out, num_words=args.ram_words, pad_val=0)
    print(f"Generated RAM hex: {args.ram_out} ({args.ram_words} words)")

if __name__ == '__main__':
    main()
