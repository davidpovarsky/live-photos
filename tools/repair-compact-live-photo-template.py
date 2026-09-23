#!/usr/bin/env python3
"""
Repair/normalize a compact metadata-only Live Photo MOV template.

The first compact-template helper in this fork accidentally zeroed the stco
entry-count field while redacting source chunk offsets. The metadata payloads
were still preserved in mdat. This tool rebuilds one chunk offset per metadata
track from the preserved sample tables and mdat payload, so existing secrets
created with that helper remain usable.
"""

from pathlib import Path
import struct
import sys


def fail(message):
    raise SystemExit(message)


if len(sys.argv) != 3:
    fail("Usage: tools/repair-compact-live-photo-template.py INPUT.mov OUTPUT.mov")

src = Path(sys.argv[1])
out = Path(sys.argv[2])
data = bytearray(src.read_bytes())


def u32(buf, off):
    return struct.unpack(">I", buf[off:off + 4])[0]


def u64(buf, off):
    return struct.unpack(">Q", buf[off:off + 8])[0]


def p32(value):
    return struct.pack(">I", value)


def p64(value):
    return struct.pack(">Q", value)


def box_header(buf, off, end):
    if off + 8 > end:
        return None
    size = u32(buf, off)
    box_type = bytes(buf[off + 4:off + 8]).decode("latin1")
    header = 8
    if size == 1:
        if off + 16 > end:
            return None
        size = u64(buf, off + 8)
        header = 16
    elif size == 0:
        size = end - off
    if size < header or off + size > end:
        return None
    return [off, size, box_type, header, off + header, off + size]


def children(buf, box):
    start = box[4] + (4 if box[2] == "meta" else 0)
    result = []
    pos = start
    while pos + 8 <= box[5]:
        child = box_header(buf, pos, box[5])
        if not child:
            break
        result.append(child)
        pos = child[5]
    return result


def child(buf, box, box_type):
    return next((x for x in children(buf, box) if x[2] == box_type), None)


def path(buf, box, *types):
    for box_type in types:
        if box is None:
            return None
        box = child(buf, box, box_type)
    return box


root = [0, len(data), "root", 0, 0, len(data)]
top = children(data, root)
moov = next((x for x in top if x[2] == "moov"), None)
mdat = next((x for x in top if x[2] == "mdat"), None)
if not moov or not mdat:
    fail("Input is not a supported compact QuickTime template.")

metadata_tracks = []
for trak in (x for x in children(data, moov) if x[2] == "trak"):
    mdia = path(data, trak, "mdia")
    hdlr = path(data, mdia, "hdlr")
    if not hdlr:
        continue
    handler_type = bytes(data[hdlr[4] + 8:hdlr[4] + 12]).decode("latin1")
    if handler_type != "meta":
        continue

    stbl = path(data, mdia, "minf", "stbl")
    stsz = path(data, stbl, "stsz")
    stsc = path(data, stbl, "stsc")
    stco = path(data, stbl, "stco") or path(data, stbl, "co64")
    if not stsz or not stsc or not stco:
        fail("Metadata track is missing required sample-table boxes.")

    sample_size = u32(data, stsz[4] + 4)
    sample_count = u32(data, stsz[4] + 8)
    if sample_size == 0 or sample_count == 0:
        fail("Compact template must use fixed-size metadata samples.")

    stsc_count = u32(data, stsc[4] + 4)
    if stsc_count < 1:
        fail("Metadata track has no stsc entries.")
    samples_per_chunk = u32(data, stsc[4] + 12)
    if samples_per_chunk != sample_count:
        fail("Compact template must keep each metadata track in one chunk.")

    metadata_tracks.append(
        {
            "stco": stco,
            "payload_length": sample_size * sample_count,
            "sample_count": sample_count,
            "sample_size": sample_size,
        }
    )

if not metadata_tracks:
    fail("No metadata tracks found.")

payload_cursor = mdat[4]
payload_end = mdat[5]

for index, track in enumerate(metadata_tracks, start=1):
    length = track["payload_length"]
    if payload_cursor + length > payload_end:
        fail("Metadata payload is truncated.")

    stco = track["stco"]
    entry_count_off = stco[4] + 4
    first_offset_off = stco[4] + 8

    data[entry_count_off:entry_count_off + 4] = p32(1)
    if stco[2] == "co64":
        if stco[1] < 24:
            fail("co64 box is too small for one chunk offset.")
        data[first_offset_off:first_offset_off + 8] = p64(payload_cursor)
    else:
        if stco[1] < 20:
            fail("stco box is too small for one chunk offset.")
        data[first_offset_off:first_offset_off + 4] = p32(payload_cursor)

    print(
        f"track {index}: samples={track['sample_count']} "
        f"sample_size={track['sample_size']} chunk_offset={payload_cursor}"
    )
    payload_cursor += length

if payload_cursor > payload_end:
    fail("Computed metadata payload extends past mdat.")

out.write_bytes(data)
print(f"Wrote repaired template: {out} ({len(data)} bytes)")
