#!/usr/bin/env python3
"""Checks a rebuilt ntdll.so against the GE-Proton release it replaces.

  verify-ntdll.py <release ntdll.dll> <built ntsyscalls.h> <release ntdll.so> <built ntdll.so>

1. Syscall numbers. The PE ntdll.dll from the release enters the unix side by
   number (`mov eax, N` in each Nt* stub); the rebuilt ntdll.so dispatches by
   the table generated into ntsyscalls.h. Every number must name the same call.
2. Dynamic exports. Other unix modules of the release link against ntdll.so,
   so the rebuilt one must export exactly the same symbols.
"""
import re
import struct
import subprocess
import sys


def pe_syscalls(path):
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    optsz = struct.unpack_from("<H", d, pe + 20)[0]
    opt = pe + 24
    exp_rva = struct.unpack_from("<I", d, opt + 112)[0]
    secs = []
    for i in range(nsec):
        o = opt + optsz + i * 40
        vsize, va = struct.unpack_from("<II", d, o + 8)
        raw = struct.unpack_from("<I", d, o + 20)[0]
        secs.append((va, max(vsize, 1), raw))

    def off(rva):
        for va, vs, raw in secs:
            if va <= rva < va + vs:
                return rva - va + raw
        raise ValueError(hex(rva))

    eo = off(exp_rva)
    _, nnames, funcs, names, ords = struct.unpack_from("<IIIII", d, eo + 20)
    out = {}
    for i in range(nnames):
        nr = struct.unpack_from("<I", d, off(names) + 4 * i)[0]
        o = struct.unpack_from("<H", d, off(ords) + 2 * i)[0]
        name = d[off(nr):d.index(b"\0", off(nr))].decode()
        if not name.startswith("Nt"):
            continue
        stub = d[off(struct.unpack_from("<I", d, off(funcs) + 4 * o)[0]):][:32]
        # mov r10, rcx ; mov eax, imm32
        k = stub.find(b"\x4c\x8b\xd1\xb8")
        if k >= 0:
            out[name] = struct.unpack_from("<I", stub, k + 4)[0]
    return out


def header_syscalls(path):
    text = open(path).read()
    # Only the 64-bit table; a few calls have their own wrapper macro,
    # SYSCALL_ENTRY_<name>( id, name, args ).
    m = re.search(r"#define ALL_SYSCALLS64 \\\n((?:.*\\\n)*.*)", text)
    block = m.group(1) if m else text
    entries = re.findall(r"SYSCALL_ENTRY(?:_\w+)?\(\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(\w+)", block)
    return {name: int(num, 0) for num, name in entries}


def exports(path):
    out = subprocess.run(["nm", "-D", "--defined-only", path], check=True,
                         capture_output=True, text=True).stdout
    return {line.split()[-1] for line in out.splitlines() if line.strip()}


def main():
    dll, header, rel_so, new_so = sys.argv[1:5]
    ok = True

    pe, hdr = pe_syscalls(dll), header_syscalls(header)
    if len(pe) < 200 or len(hdr) < 200:
        print(f"syscall tables look wrong: {len(pe)} in ntdll.dll, {len(hdr)} in ntsyscalls.h")
        ok = False
    bad = sorted(n for n in pe if hdr.get(n) != pe[n])
    if bad:
        ok = False
        for n in bad[:20]:
            print(f"syscall mismatch: {n} release={pe[n]:#x} built={hdr.get(n)}")
    else:
        print(f"syscalls: {len(pe)} numbers in ntdll.dll match ntsyscalls.h")

    a, b = exports(rel_so), exports(new_so)
    if a != b:
        ok = False
        print("exports only in release:", sorted(a - b)[:20])
        print("exports only in build:", sorted(b - a)[:20])
    else:
        print(f"exports: {len(a)} dynamic symbols identical")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
