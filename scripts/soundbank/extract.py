#!/usr/bin/env python3
"""Extract a few General MIDI presets from SoundFont 2 banks into one small SF2.

Stdlib only (run with `uv run --no-project python -I`). A minimal RIFF/SF2 reader and
writer: each chosen preset is copied with its zones, the instruments they use and the
samples those use (stereo partners included), sample data re-packed with the 46 zero
points the SF2 spec asks for after each sample. 24-bit `sm24` data is dropped (16-bit
only is valid SF2). Programs and bank numbers are kept, so the bundle answers the same
`loadSoundBankInstrument(program:bankMSB:bankLSB:)` calls as the source bank.

Usage:
  extract.py OUT.sf2 --name "Segue Sounds" SOURCE.sf2:0,27 OTHER.sf2:33,34 ...

Each SOURCE:PROGRAMS argument takes bank-0 presets with those program numbers from that
file. A program may come from one source only.
"""

from __future__ import annotations

import argparse
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

PADDING_POINTS = 46
GEN_INSTRUMENT = 41
GEN_SAMPLE_ID = 53
ROM_SAMPLE = 0x8000


def chunks(data: bytes, offset: int, end: int):
    while offset + 8 <= end:
        cid = data[offset : offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        yield cid, offset + 8, size
        offset += 8 + size + (size & 1)


def records(blob: bytes, fmt: str) -> list[tuple]:
    size = struct.calcsize(fmt)
    return [struct.unpack_from(fmt, blob, i) for i in range(0, len(blob) - size + 1, size)]


@dataclass
class Bank:
    path: Path
    info: dict[bytes, bytes] = field(default_factory=dict)
    smpl: bytes = b""
    phdr: list[tuple] = field(default_factory=list)
    pbag: list[tuple] = field(default_factory=list)
    pmod: list[bytes] = field(default_factory=list)
    pgen: list[tuple] = field(default_factory=list)
    inst: list[tuple] = field(default_factory=list)
    ibag: list[tuple] = field(default_factory=list)
    imod: list[bytes] = field(default_factory=list)
    igen: list[tuple] = field(default_factory=list)
    shdr: list[tuple] = field(default_factory=list)


def read_bank(path: Path) -> Bank:
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"sfbk":
        sys.exit(f"{path}: not a SoundFont (RIFF sfbk)")
    bank = Bank(path)
    pdta: dict[bytes, bytes] = {}
    for cid, offset, size in chunks(data, 12, len(data)):
        if cid != b"LIST":
            continue
        kind = data[offset : offset + 4]
        for sub, sub_offset, sub_size in chunks(data, offset + 4, offset + size):
            blob = data[sub_offset : sub_offset + sub_size]
            if kind == b"INFO":
                bank.info[sub] = blob
            elif kind == b"sdta" and sub == b"smpl":
                bank.smpl = blob
            elif kind == b"pdta":
                pdta[sub] = blob
    major = struct.unpack("<HH", bank.info.get(b"ifil", b"\0\0\0\0"))[0]
    if major != 2:
        sys.exit(f"{path}: ifil major {major}, only SF2 is supported (never SF3)")
    bank.phdr = records(pdta[b"phdr"], "<20sHHHIII")
    bank.pbag = records(pdta[b"pbag"], "<HH")
    bank.pmod = [pdta[b"pmod"][i : i + 10] for i in range(0, len(pdta[b"pmod"]), 10)]
    bank.pgen = records(pdta[b"pgen"], "<HH")
    bank.inst = records(pdta[b"inst"], "<20sH")
    bank.ibag = records(pdta[b"ibag"], "<HH")
    bank.imod = [pdta[b"imod"][i : i + 10] for i in range(0, len(pdta[b"imod"]), 10)]
    bank.igen = records(pdta[b"igen"], "<HH")
    bank.shdr = records(pdta[b"shdr"], "<20sIIIIIBbHH")
    return bank


@dataclass
class Writer:
    phdr: list[tuple] = field(default_factory=list)
    pbag: list[tuple] = field(default_factory=list)
    pmod: list[bytes] = field(default_factory=list)
    pgen: list[tuple] = field(default_factory=list)
    inst: list[tuple] = field(default_factory=list)
    ibag: list[tuple] = field(default_factory=list)
    imod: list[bytes] = field(default_factory=list)
    igen: list[tuple] = field(default_factory=list)
    shdr: list[tuple] = field(default_factory=list)
    smpl: bytearray = field(default_factory=bytearray)
    # (source path, source index) -> new index
    inst_map: dict[tuple[str, int], int] = field(default_factory=dict)
    sample_map: dict[tuple[str, int], int] = field(default_factory=dict)

    def add_sample(self, bank: Bank, index: int) -> int:
        key = (str(bank.path), index)
        if key in self.sample_map:
            return self.sample_map[key]
        name, start, end, loop_start, loop_end, rate, pitch, correction, link, kind = (
            bank.shdr[index]
        )
        if kind & ROM_SAMPLE:
            sys.exit(f"{bank.path}: sample {index} is a ROM sample, cannot extract")
        new_index = len(self.shdr)
        self.sample_map[key] = new_index
        new_start = len(self.smpl) // 2
        self.smpl += bank.smpl[start * 2 : end * 2]
        self.smpl += b"\0\0" * PADDING_POINTS
        self.shdr.append(
            [
                name,
                new_start,
                new_start + (end - start),
                new_start + (loop_start - start),
                new_start + (loop_end - start),
                rate,
                pitch,
                correction,
                link,
                kind,
            ]
        )
        # Stereo and linked samples point at their partner: copy it and remap the link.
        if kind & 0x000E and link < len(bank.shdr) - 1:
            partner = self.add_sample(bank, link)
            self.shdr[new_index][8] = partner
        else:
            self.shdr[new_index][8] = 0
        return new_index

    def add_instrument(self, bank: Bank, index: int) -> int:
        key = (str(bank.path), index)
        if key in self.inst_map:
            return self.inst_map[key]
        new_index = len(self.inst)
        self.inst_map[key] = new_index
        name, first_bag = bank.inst[index]
        self.inst.append((name, len(self.ibag)))
        for bag in range(first_bag, bank.inst[index + 1][1]):
            gen_start, mod_start = bank.ibag[bag]
            gen_end, mod_end = bank.ibag[bag + 1]
            self.ibag.append((len(self.igen), len(self.imod)))
            self.imod.extend(bank.imod[mod_start:mod_end])
            for oper, amount in bank.igen[gen_start:gen_end]:
                if oper == GEN_SAMPLE_ID:
                    amount = self.add_sample(bank, amount)
                self.igen.append((oper, amount))
        return new_index

    def add_preset(self, bank: Bank, index: int) -> None:
        name, program, bank_number, first_bag, library, genre, morphology = bank.phdr[index]
        self.phdr.append(
            (name, program, bank_number, len(self.pbag), library, genre, morphology)
        )
        for bag in range(first_bag, bank.phdr[index + 1][3]):
            gen_start, mod_start = bank.pbag[bag]
            gen_end, mod_end = bank.pbag[bag + 1]
            self.pbag.append((len(self.pgen), len(self.pmod)))
            self.pmod.extend(bank.pmod[mod_start:mod_end])
            for oper, amount in bank.pgen[gen_start:gen_end]:
                if oper == GEN_INSTRUMENT:
                    amount = self.add_instrument(bank, amount)
                self.pgen.append((oper, amount))

    def build(self, info_name: str, credits: str) -> bytes:
        def chunk(cid: bytes, payload: bytes) -> bytes:
            pad = b"\0" if len(payload) & 1 else b""
            return cid + struct.pack("<I", len(payload)) + payload + pad

        def zstr(text: str) -> bytes:
            raw = text.encode("ascii", "replace") + b"\0"
            return raw + (b"\0" if len(raw) & 1 else b"")

        def pack(fmt: str, rows) -> bytes:
            return b"".join(struct.pack(fmt, *row) for row in rows)

        info = b"INFO" + b"".join(
            [
                chunk(b"ifil", struct.pack("<HH", 2, 1)),
                chunk(b"isng", zstr("EMU8000")),
                chunk(b"INAM", zstr(info_name)),
                chunk(b"ICOP", zstr(credits[:255])),
                chunk(b"ISFT", zstr("Segue extract.py")),
            ]
        )
        sdta = b"sdta" + chunk(b"smpl", bytes(self.smpl))
        phdr = self.phdr + [(b"EOP", 0, 0, len(self.pbag), 0, 0, 0)]
        pbag = self.pbag + [(len(self.pgen), len(self.pmod))]
        inst = self.inst + [(b"EOI", len(self.ibag))]
        ibag = self.ibag + [(len(self.igen), len(self.imod))]
        shdr = [tuple(row) for row in self.shdr] + [(b"EOS", 0, 0, 0, 0, 0, 0, 0, 0, 0)]
        pdta = b"pdta" + b"".join(
            [
                chunk(b"phdr", pack("<20sHHHIII", phdr)),
                chunk(b"pbag", pack("<HH", pbag)),
                chunk(b"pmod", b"".join(self.pmod) + b"\0" * 10),
                chunk(b"pgen", pack("<HH", self.pgen + [(0, 0)])),
                chunk(b"inst", pack("<20sH", inst)),
                chunk(b"ibag", pack("<HH", ibag)),
                chunk(b"imod", b"".join(self.imod) + b"\0" * 10),
                chunk(b"igen", pack("<HH", self.igen + [(0, 0)])),
                chunk(b"shdr", pack("<20sIIIIIBbHH", shdr)),
            ]
        )
        body = chunk(b"LIST", info) + chunk(b"LIST", sdta) + chunk(b"LIST", pdta)
        return b"RIFF" + struct.pack("<I", 4 + len(body)) + b"sfbk" + body


def bank_name(bank: Bank) -> str:
    return bank.info.get(b"INAM", bank.path.name.encode()).split(b"\0")[0].decode(
        "latin1"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("output", type=Path)
    parser.add_argument("--name", default="Segue Sounds")
    parser.add_argument("sources", nargs="+", help="SOURCE.sf2:PROGRAM,PROGRAM")
    args = parser.parse_args()

    writer = Writer()
    chosen: list[tuple[int, Bank, int]] = []
    credits: list[str] = []
    for spec in args.sources:
        path_text, _, programs_text = spec.rpartition(":")
        programs = [int(p) for p in programs_text.split(",") if p]
        bank = read_bank(Path(path_text))
        credits.append(f"{bank_name(bank)} programs {programs_text}")
        for program in programs:
            if any(taken == program for taken, _, _ in chosen):
                sys.exit(f"program {program} named twice")
            matches = [
                i
                for i, row in enumerate(bank.phdr[:-1])
                if row[1] == program and row[2] == 0
            ]
            if not matches:
                sys.exit(f"{bank.path}: no bank-0 preset for program {program}")
            chosen.append((program, bank, matches[0]))
    # The SF2 spec wants presets sorted by bank, then program.
    for _, bank, index in sorted(chosen, key=lambda item: item[0]):
        writer.add_preset(bank, index)
    data = writer.build(args.name, "Samples from " + "; ".join(credits))
    args.output.write_bytes(data)
    print(
        f"{args.output}: {len(data) / 1e6:.2f} MB, {len(writer.phdr)} presets, "
        f"{len(writer.inst)} instruments, {len(writer.shdr)} samples"
    )


if __name__ == "__main__":
    main()
