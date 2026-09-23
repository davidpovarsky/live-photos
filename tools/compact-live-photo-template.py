#!/usr/bin/env python3
"""
Extract only metadata tracks from a compatible Live Photo MOV.

This intentionally supports the simple neutral-template shape used by this
project: constant-size samples, one chunk per metadata track.
"""

from pathlib import Path
import struct
import sys


def fail(message):
    raise SystemExit(message)


if len(sys.argv) != 3:
    fail("Usage: tools/compact-live-photo-template.py INPUT.mov OUTPUT.mov")

src = Path(sys.argv[1])
out = Path(sys.argv[2])
data = src.read_bytes()


def u32(buf, off):
    return struct.unpack(">I", buf[off:off + 4])[0]


def u64(buf, off):
    return struct.unpack(">Q", buf[off:off + 8])[0]


def p32(value):
    return struct.pack(">I", value)


def box_header(buf, off, end):
    if off + 8 > end:
        return None
    size = u32(buf, off)
    box_type = buf[off + 4:off + 8].decode("latin1")
    header = 8
    if size == 1:
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
        box = child(buf, box, box_type)
        if not box:
            return None
    return box


root = [0, len(data), "root", 0, 0, len(data)]
top = children(data, root)
ftyp = next((x for x in top if x[2] == "ftyp"), None)
moov = next((x for x in top if x[2] == "moov"), None)
if not ftyp or not moov:
    fail("Input is not a supported QuickTime/MP4 file.")

ftyp_bytes = data[ftyp[0]:ftyp[5]]
moov_children = children(data, moov)
mvhd = next((x for x in moov_children if x[2] == "mvhd"), None)
if not mvhd:
    fail("Missing mvhd box.")

tracks = []
for trak in (x for x in moov_children if x[2] == "trak"):
    mdia = path(data, trak, "mdia")
    hdlr = path(data, mdia, "hdlr") if mdia else None
    if not hdlr:
        continue
    handler_type = data[hdlr[4] + 8:hdlr[4] + 12].decode("latin1")
    if handler_type != "meta":
        continue

    stbl = path(data, mdia, "minf", "stbl")
    stsz = path(data, stbl, "stsz")
    stco = path(data, stbl, "stco") or path(data, stbl, "co64")
    stsc = path(data, stbl, "stsc")
    if not stsz or not stco or not stsc:
        fail("Unsupported metadata track sample tables.")

    sample_size = u32(data, stsz[4] + 4)
    sample_count = u32(data, stsz[4] + 8)
    if sample_size == 0:
        fail("Variable-size metadata samples are not supported by this helper.")

    entry_count = u32(data, stco[4] + 4)
    if entry_count != 1:
        fail("Only one-chunk metadata tracks are supported by this helper.")

    chunk_offset = (
        u64(data, stco[4] + 8)
        if stco[2] == "co64"
        else u32(data, stco[4] + 8)
    )

    stsc_count = u32(data, stsc[4] + 4)
    samples_per_chunk = u32(data, stsc[4] + 12)
    if stsc_count != 1 or samples_per_chunk != sample_count:
        fail("Unsupported metadata chunk layout.")

    payload_length = sample_size * sample_count
    payload = data[chunk_offset:chunk_offset + payload_length]
    if len(payload) != payload_length:
        fail("Metadata payload is truncated.")

    tracks.append(
        {
            "trak": trak,
            "stco": stco,
            "co64": stco[2] == "co64",
            "payload": payload,
        }
    )

if not tracks:
    fail("No metadata tracks found.")

track_copies = []
for track in tracks:
    copied = bytearray(data[track["trak"][0]:track["trak"][5]])
    relative_stco = track["stco"][0] - track["trak"][0]
    offset_field = relative_stco + 16
    copied[offset_field:offset_field + (8 if track["co64"] else 4)] = (
        b"\0" * (8 if track["co64"] else 4)
    )
    track_copies.append(copied)

mvhd_bytes = data[mvhd[0]:mvhd[5]]
moov_payload = mvhd_bytes + b"".join(track_copies)
moov_bytes = bytearray(p32(8 + len(moov_payload)) + b"moov" + moov_payload)

actual_moov = box_header(moov_bytes, 0, len(moov_bytes))
new_tracks = [x for x in children(moov_bytes, actual_moov) if x[2] == "trak"]
if len(new_tracks) != len(tracks):
    fail("Internal compact-template track count mismatch.")

payload_cursor = len(ftyp_bytes) + len(moov_bytes) + 8
for new_trak, source_track in zip(new_tracks, tracks):
    mdia = path(moov_bytes, new_trak, "mdia")
    stbl = path(moov_bytes, mdia, "minf", "stbl")
    stco = path(moov_bytes, stbl, "stco") or path(moov_bytes, stbl, "co64")
    offset_field = stco[4] + 8

    if stco[2] == "co64":
        moov_bytes[offset_field:offset_field + 8] = struct.pack(">Q", payload_cursor)
    else:
        moov_bytes[offset_field:offset_field + 4] = p32(payload_cursor)

    payload_cursor += len(source_track["payload"])

mdat_payload = b"".join(track["payload"] for track in tracks)
mdat_bytes = p32(8 + len(mdat_payload)) + b"mdat" + mdat_payload

out.write_bytes(ftyp_bytes + moov_bytes + mdat_bytes)
print(f"Wrote {out} ({out.stat().st_size} bytes, {len(tracks)} metadata tracks)")
