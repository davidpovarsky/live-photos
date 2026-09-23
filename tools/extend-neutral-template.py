#!/usr/bin/env python3
"""
Extend the compact neutral Live Photo metadata template to a target duration.

This preserves the original mebx sample descriptions byte-for-byte. It repeats
the known-neutral 144-byte live-photo-info payload at 60 Hz from 0.05s to the
requested endpoint, and moves the one-sample still-image metadata track to the
requested still-image time.

Usage:
  tools/extend-neutral-template.py INPUT.mov OUTPUT.mov DURATION [STILL_TIME]
"""

from pathlib import Path
import struct
import sys


def fail(message):
    raise SystemExit(message)


if len(sys.argv) not in (4, 5):
    fail(
        "Usage: tools/extend-neutral-template.py "
        "INPUT.mov OUTPUT.mov DURATION [STILL_TIME]"
    )

src = Path(sys.argv[1])
out = Path(sys.argv[2])
duration = float(sys.argv[3])
still = float(sys.argv[4]) if len(sys.argv) == 5 else duration / 2

if duration <= 0 or duration > 5:
    fail("DURATION must be > 0 and <= 5 seconds")
if still < 0 or still > duration:
    fail("STILL_TIME must be within the output duration")

data = bytearray(src.read_bytes())


def u32(buf, off):
    return struct.unpack(">I", buf[off:off + 4])[0]


def u64(buf, off):
    return struct.unpack(">Q", buf[off:off + 8])[0]


def p32(value):
    return struct.pack(">I", int(value))


def p64(value):
    return struct.pack(">Q", int(value))


def pi32(value):
    return struct.pack(">i", int(value))


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
    pos = box[4] + (4 if box[2] == "meta" else 0)
    result = []
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


def fullbox_version(box):
    return data[box[4]]


def mvhd_fields(mvhd):
    version = fullbox_version(mvhd)
    pos = mvhd[4] + 4
    if version == 0:
        return pos + 8, pos + 12, 4
    return pos + 16, pos + 20, 8


def tkhd_duration_field(tkhd):
    version = fullbox_version(tkhd)
    pos = tkhd[4] + 4
    return (pos + 16, 4) if version == 0 else (pos + 24, 8)


def mdhd_fields(mdhd):
    version = fullbox_version(mdhd)
    pos = mdhd[4] + 4
    if version == 0:
        return pos + 8, pos + 12, 4
    return pos + 16, pos + 20, 8


def set_uint(off, size, value):
    data[off:off + size] = p32(value) if size == 4 else p64(value)


root = [0, len(data), "root", 0, 0, len(data)]
top = children(data, root)
ftyp = next((x for x in top if x[2] == "ftyp"), None)
moov = next((x for x in top if x[2] == "moov"), None)
mdat = next((x for x in top if x[2] == "mdat"), None)

if not ftyp or not moov or not mdat:
    fail("Template must contain ftyp, moov and mdat boxes")

mvhd = child(data, moov, "mvhd")
if not mvhd:
    fail("Template is missing mvhd")

timescale_off, duration_off, duration_size = mvhd_fields(mvhd)
movie_timescale = u32(data, timescale_off)
movie_duration = round(duration * movie_timescale)
set_uint(duration_off, duration_size, movie_duration)

tracks = []
for trak in [x for x in children(data, moov) if x[2] == "trak"]:
    mdia = path(data, trak, "mdia")
    hdlr = path(data, mdia, "hdlr")
    if not hdlr:
        continue

    handler = bytes(data[hdlr[4] + 8:hdlr[4] + 12]).decode("latin1")
    if handler != "meta":
        continue

    tkhd = path(data, trak, "tkhd")
    mdhd = path(data, mdia, "mdhd")
    edts = path(data, trak, "edts")
    elst = path(data, edts, "elst") if edts else None
    stbl = path(data, mdia, "minf", "stbl")
    stts = path(data, stbl, "stts")
    stsc = path(data, stbl, "stsc")
    stsz = path(data, stbl, "stsz")
    stco = path(data, stbl, "stco") or path(data, stbl, "co64")

    if not all([tkhd, mdhd, elst, stts, stsc, stsz, stco]):
        fail("Unsupported metadata-track layout")

    sample_size = u32(data, stsz[4] + 4)
    sample_count = u32(data, stsz[4] + 8)

    entry_count = u32(data, stco[4] + 4)
    if entry_count != 1:
        fail("Expected one metadata chunk per track")

    chunk_offset = (
        u32(data, stco[4] + 8)
        if stco[2] == "stco"
        else u64(data, stco[4] + 8)
    )

    payload = bytes(
        data[chunk_offset:chunk_offset + sample_size * sample_count]
    )

    tracks.append(
        {
            "tkhd": tkhd,
            "mdhd": mdhd,
            "elst": elst,
            "stts": stts,
            "stsc": stsc,
            "stsz": stsz,
            "stco": stco,
            "sample_size": sample_size,
            "sample_count": sample_count,
            "payload": payload,
        }
    )

if len(tracks) != 2:
    fail(f"Expected exactly 2 metadata tracks, found {len(tracks)}")

live, still_track = tracks

if live["sample_size"] != 144:
    fail("First metadata track is not the 144-byte neutral live-photo-info track")
if still_track["sample_size"] != 89:
    fail("Second metadata track is not the 89-byte still-image metadata track")

live_count = max(1, round((duration - 0.05) * 60))
live_payload = live["payload"][:live["sample_size"]] * live_count
still_payload = still_track["payload"][:still_track["sample_size"]]

# live-photo-info media timing
mdts_off, md_duration_off, md_duration_size = mdhd_fields(live["mdhd"])
live_timescale = u32(data, mdts_off)
live_delta = round(live_timescale / 60)
live_media_duration = live_count * live_delta
set_uint(md_duration_off, md_duration_size, live_media_duration)

tk_duration_off, tk_duration_size = tkhd_duration_field(live["tkhd"])
set_uint(tk_duration_off, tk_duration_size, movie_duration)

# edit list: 0.05s empty edit, then live metadata media
version = fullbox_version(live["elst"])
pos = live["elst"][4] + 4
entry_count = u32(data, pos)
pos += 4
if entry_count != 2:
    fail("Live metadata edit list must contain two entries")

empty_movie = round(0.05 * movie_timescale)
media_movie = movie_duration - empty_movie

if version == 0:
    data[pos:pos + 4] = p32(empty_movie)
    data[pos + 4:pos + 8] = pi32(-1)
    pos += 12
    data[pos:pos + 4] = p32(media_movie)
    data[pos + 4:pos + 8] = pi32(0)
else:
    data[pos:pos + 8] = p64(empty_movie)
    data[pos + 8:pos + 16] = struct.pack(">q", -1)
    pos += 20
    data[pos:pos + 8] = p64(media_movie)
    data[pos + 8:pos + 16] = struct.pack(">q", 0)

# live stts: one fixed 60-Hz timing entry
pos = live["stts"][4] + 4
entry_count = u32(data, pos)
pos += 4
if entry_count != 1:
    fail("Live metadata stts must contain one entry")
data[pos:pos + 4] = p32(live_count)
data[pos + 4:pos + 8] = p32(live_delta)

# live stsc: one chunk with all live-info samples
pos = live["stsc"][4] + 4
entry_count = u32(data, pos)
pos += 4
if entry_count != 1:
    fail("Live metadata stsc must contain one entry")
data[pos + 4:pos + 8] = p32(live_count)

# live stsz sample count
data[live["stsz"][4] + 8:live["stsz"][4] + 12] = p32(live_count)

# still-image metadata remains a single sample, moved to requested still time
still_ts_off, still_duration_off, still_duration_size = mdhd_fields(
    still_track["mdhd"]
)
still_timescale = u32(data, still_ts_off)
set_uint(still_duration_off, still_duration_size, 1)

still_start_movie = round(still * movie_timescale)
still_media_movie = max(1, round(movie_timescale / still_timescale))
still_track_duration = still_start_movie + still_media_movie

tk_duration_off, tk_duration_size = tkhd_duration_field(still_track["tkhd"])
set_uint(tk_duration_off, tk_duration_size, still_track_duration)

version = fullbox_version(still_track["elst"])
pos = still_track["elst"][4] + 4
entry_count = u32(data, pos)
pos += 4
if entry_count != 2:
    fail("Still-image metadata edit list must contain two entries")

if version == 0:
    data[pos:pos + 4] = p32(still_start_movie)
    data[pos + 4:pos + 8] = pi32(-1)
    pos += 12
    data[pos:pos + 4] = p32(still_media_movie)
    data[pos + 4:pos + 8] = pi32(0)
else:
    data[pos:pos + 8] = p64(still_start_movie)
    data[pos + 8:pos + 16] = struct.pack(">q", -1)
    pos += 20
    data[pos:pos + 8] = p64(still_media_movie)
    data[pos + 8:pos + 16] = struct.pack(">q", 0)

# Rebuild mdat with repeated neutral payload. moov size is unchanged, so mdat
# begins at the same byte offset and we only need to update chunk offsets.
mdat_content = mdat[4]
new_live_offset = mdat_content
new_still_offset = new_live_offset + len(live_payload)

for track, offset in (
    (live, new_live_offset),
    (still_track, new_still_offset),
):
    stco = track["stco"]
    data[stco[4] + 4:stco[4] + 8] = p32(1)
    if stco[2] == "stco":
        data[stco[4] + 8:stco[4] + 12] = p32(offset)
    else:
        data[stco[4] + 8:stco[4] + 16] = p64(offset)

new_payload = live_payload + still_payload

if mdat[3] != 8:
    fail("Extended-size mdat is not supported")

new_mdat = p32(8 + len(new_payload)) + b"mdat" + new_payload
result = bytes(data[:mdat[0]]) + new_mdat + bytes(data[mdat[5]:])

out.write_bytes(result)

print(
    f"duration={duration:.3f}s still={still:.3f}s "
    f"live_samples={live_count} movie_timescale={movie_timescale} "
    f"size={len(result)}"
)
