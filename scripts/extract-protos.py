#!/usr/bin/env python3
"""
Extract ProPresenter protobuf schema from ProCore.framework.

Scans the ProCore binary for embedded FileDescriptorProto blobs,
walks the dependency tree from presentation.proto, and outputs
a FileDescriptorSet binary that protoc can consume.

Usage:
    python3 scripts/extract-protos.py

Output:
    Proto/descriptor.binpb
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

from google.protobuf import descriptor_pb2
from google.protobuf.internal.decoder import _DecodeVarint

PROCORE_PATH = "/Applications/ProPresenter.app/Contents/Frameworks/ProCore.framework/ProCore"
ROOT_PROTO = "presentation.proto"
OUTPUT_PATH = Path(__file__).parent.parent / "Proto" / "descriptor.binpb"


def find_descriptor_end(data: bytes, start: int, max_len: int = 200000) -> int:
    """Walk protobuf fields to find where a FileDescriptorProto ends."""
    pos = start
    end = min(start + max_len, len(data))
    valid_fields = {1, 2, 3, 4, 5, 6, 7, 8, 9, 12}

    while pos < end:
        try:
            tag, new_pos = _DecodeVarint(data, pos)
        except (IndexError, ValueError):
            return pos

        field_number = tag >> 3
        wire_type = tag & 0x7

        if field_number not in valid_fields or field_number == 0:
            return pos

        pos = new_pos

        if wire_type == 0:  # varint
            while pos < end and data[pos] & 0x80:
                pos += 1
            pos += 1
        elif wire_type == 2:  # length-delimited
            try:
                length, pos = _DecodeVarint(data, pos)
                pos += length
            except (IndexError, ValueError):
                return start
        elif wire_type == 5:  # 32-bit
            pos += 4
        elif wire_type == 1:  # 64-bit
            pos += 8
        else:
            return pos

    return pos


def extract_descriptors(data: bytes) -> dict[str, descriptor_pb2.FileDescriptorProto]:
    """Extract all FileDescriptorProto blobs from binary data."""
    # Find all potential descriptor starts
    starts = []
    for m in re.finditer(rb"\x0a([\x01-\x7f])([a-zA-Z][a-zA-Z0-9_/]*\.proto)\x12[\x01-\x7f]", data):
        offset = m.start()
        name_len = data[offset + 1]
        name = data[offset + 2 : offset + 2 + name_len].decode("ascii", errors="ignore")
        if name.endswith(".proto"):
            starts.append((offset, name))

    # Parse each, keep the richest version per name
    best: dict[str, tuple[int, descriptor_pb2.FileDescriptorProto]] = {}

    for offset, name in starts:
        end = find_descriptor_end(data, offset)
        chunk = data[offset:end]

        desc = descriptor_pb2.FileDescriptorProto()
        try:
            desc.ParseFromString(chunk)
        except Exception:
            continue

        if desc.name != name:
            continue

        # Score by content richness
        score = len(desc.message_type) + len(desc.enum_type)
        for m in desc.message_type:
            score += len(m.field) + len(m.nested_type) + len(m.enum_type)

        if name not in best or score > best[name][0]:
            best[name] = (score, desc)

    return {name: desc for name, (_, desc) in best.items()}


def walk_dependencies(
    root: str, all_descs: dict[str, descriptor_pb2.FileDescriptorProto]
) -> set[str]:
    """Walk the dependency tree from a root proto file."""
    needed: set[str] = set()

    def walk(name: str) -> None:
        if name in needed or name not in all_descs:
            return
        needed.add(name)
        for dep in all_descs[name].dependency:
            walk(dep)

    walk(root)
    return needed


def strip_source_code_info(desc: descriptor_pb2.FileDescriptorProto) -> None:
    """Remove source_code_info to reduce size (not needed for code generation)."""
    desc.ClearField("source_code_info")


def main() -> None:
    print(f"Reading {PROCORE_PATH}...")
    try:
        with open(PROCORE_PATH, "rb") as f:
            data = f.read()
    except FileNotFoundError:
        print(f"ERROR: ProPresenter not found at {PROCORE_PATH}")
        sys.exit(1)

    print(f"Binary size: {len(data) / 1024 / 1024:.1f} MB")

    print("Extracting proto descriptors...")
    all_descs = extract_descriptors(data)
    print(f"Found {len(all_descs)} unique descriptors")

    print(f"Walking dependency tree from {ROOT_PROTO}...")
    needed = walk_dependencies(ROOT_PROTO, all_descs)

    # Filter out google/protobuf/* (protoc provides these natively)
    needed = {n for n in needed if not n.startswith("google/")}
    print(f"Need {len(needed)} files (excluding google/protobuf/*)")

    # Build FileDescriptorSet
    fds = descriptor_pb2.FileDescriptorSet()
    for name in sorted(needed):
        desc = all_descs[name]
        strip_source_code_info(desc)
        # Remove google/protobuf/* dependencies (protoc resolves these)
        deps_to_keep = [d for d in desc.dependency if not d.startswith("google/")]
        desc.ClearField("dependency")
        desc.dependency.extend(deps_to_keep)
        fds.file.append(desc)

    # Write output
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "wb") as f:
        f.write(fds.SerializeToString())

    print(f"\nWrote {OUTPUT_PATH} ({OUTPUT_PATH.stat().st_size} bytes)")
    print(f"Contains {len(fds.file)} proto files:")
    for fd in fds.file:
        msgs = [m.name for m in fd.message_type]
        enums = [e.name for e in fd.enum_type]
        items = msgs + enums
        print(f"  {fd.name:40s} {', '.join(items[:4])}")


if __name__ == "__main__":
    main()
