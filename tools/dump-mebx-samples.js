#!/usr/bin/env node

const fs = require("fs");

const path = process.argv[2];
if (!path) {
  console.error("Usage: tools/dump-mebx-samples.js file.mov");
  process.exit(1);
}

const data = fs.readFileSync(path);

function u8(off) { return data.readUInt8(off); }
function u16(off) { return data.readUInt16BE(off); }
function u24(off) { return (data[off] << 16) | (data[off + 1] << 8) | data[off + 2]; }
function u32(off) { return data.readUInt32BE(off); }
function i32(off) { return data.readInt32BE(off); }
function u64(off) { return Number(data.readBigUInt64BE(off)); }
function ascii(off, len) { return data.subarray(off, off + len).toString("latin1"); }
function hex(buf, max = buf.length) {
  return buf.subarray(0, max).toString("hex").match(/.{1,2}/g)?.join(" ") ?? "";
}

function readBoxHeader(off, end) {
  if (off + 8 > end) return null;
  let size = u32(off);
  const type = ascii(off + 4, 4);
  let header = 8;
  if (size === 1) {
    size = u64(off + 8);
    header = 16;
  } else if (size === 0) {
    size = end - off;
  }
  if (size < header || off + size > end) return null;
  return { off, size, type, header, content: off + header, end: off + size };
}

function children(box, start = box.content) {
  const out = [];
  let p = start;
  while (p + 8 <= box.end) {
    const child = readBoxHeader(p, box.end);
    if (!child) break;
    out.push(child);
    p = child.end;
  }
  return out;
}

function findChildren(box, type, start) {
  return children(box, start).filter((child) => child.type === type);
}

function findFirst(box, path) {
  let current = [box];
  for (const type of path) {
    const next = [];
    for (const candidate of current) {
      next.push(...findChildren(candidate, type, type === "meta" ? candidate.content + 4 : candidate.content));
    }
    current = next;
  }
  return current[0];
}

function parseTkhd(box) {
  const version = u8(box.content);
  const p = box.content + 4;
  return version === 1 ? u32(p + 16) : u32(p + 8);
}

function parseMdhd(box) {
  const version = u8(box.content);
  const p = box.content + 4;
  return {
    timescale: version === 1 ? u32(p + 16) : u32(p + 8),
    duration: version === 1 ? u64(p + 20) : u32(p + 12),
  };
}

function parseHdlr(box) {
  return ascii(box.content + 8, 4);
}

function parseStts(box) {
  const entries = [];
  let p = box.content + 8;
  const count = u32(box.content + 4);
  for (let i = 0; i < count; i++, p += 8) {
    entries.push({ sampleCount: u32(p), sampleDelta: u32(p + 4) });
  }
  return entries;
}

function parseStsz(box) {
  const sampleSize = u32(box.content + 4);
  const sampleCount = u32(box.content + 8);
  const sizes = [];
  let p = box.content + 12;
  for (let i = 0; i < sampleCount; i++) {
    sizes.push(sampleSize || u32(p));
    if (!sampleSize) p += 4;
  }
  return sizes;
}

function parseStsc(box) {
  const entries = [];
  let p = box.content + 8;
  const count = u32(box.content + 4);
  for (let i = 0; i < count; i++, p += 12) {
    entries.push({ firstChunk: u32(p), samplesPerChunk: u32(p + 4), sampleDescriptionIndex: u32(p + 8) });
  }
  return entries;
}

function parseOffsets(box) {
  const offsets = [];
  const count = u32(box.content + 4);
  let p = box.content + 8;
  const is64 = box.type === "co64";
  for (let i = 0; i < count; i++) {
    offsets.push(is64 ? u64(p) : u32(p));
    p += is64 ? 8 : 4;
  }
  return offsets;
}

function chunkSampleLayout(stsc, chunkCount) {
  const layout = [];
  for (let chunk = 1; chunk <= chunkCount; chunk++) {
    let entry = stsc[0];
    for (const candidate of stsc) {
      if (candidate.firstChunk <= chunk) entry = candidate;
    }
    layout.push(entry.samplesPerChunk);
  }
  return layout;
}

function sampleTimes(stts) {
  const times = [];
  let t = 0;
  for (const entry of stts) {
    for (let i = 0; i < entry.sampleCount; i++) {
      times.push({ pts: t, delta: entry.sampleDelta });
      t += entry.sampleDelta;
    }
  }
  return times;
}

function parseSamples(stbl) {
  const stts = parseStts(findFirst(stbl, ["stts"]));
  const stsz = parseStsz(findFirst(stbl, ["stsz"]));
  const stsc = parseStsc(findFirst(stbl, ["stsc"]));
  const stco = findFirst(stbl, ["stco"]) || findFirst(stbl, ["co64"]);
  const offsets = parseOffsets(stco);
  const perChunk = chunkSampleLayout(stsc, offsets.length);
  const times = sampleTimes(stts);
  const samples = [];
  let sampleIndex = 0;
  for (let chunkIndex = 0; chunkIndex < offsets.length; chunkIndex++) {
    let offset = offsets[chunkIndex];
    for (let i = 0; i < perChunk[chunkIndex]; i++) {
      const size = stsz[sampleIndex];
      samples.push({
        index: sampleIndex + 1,
        offset,
        size,
        pts: times[sampleIndex]?.pts ?? null,
        delta: times[sampleIndex]?.delta ?? null,
        bytes: data.subarray(offset, offset + size),
      });
      offset += size;
      sampleIndex++;
    }
  }
  return samples;
}

function printableStrings(buf) {
  const text = buf.toString("latin1");
  return [...text.matchAll(/[ -~]{4,}/g)].map((m) => m[0]);
}

function walkTop() {
  const out = [];
  let p = 0;
  while (p + 8 <= data.length) {
    const box = readBoxHeader(p, data.length);
    if (!box) break;
    out.push(box);
    p = box.end;
  }
  return out;
}

const moov = walkTop().find((box) => box.type === "moov");
const traks = findChildren(moov, "trak");

for (const trak of traks) {
  const tkhd = findFirst(trak, ["tkhd"]);
  const mdia = findFirst(trak, ["mdia"]);
  const mdhd = findFirst(mdia, ["mdhd"]);
  const hdlr = findFirst(mdia, ["hdlr"]);
  const handler = parseHdlr(hdlr);
  if (handler !== "meta") continue;

  const trackId = parseTkhd(tkhd);
  const timing = parseMdhd(mdhd);
  const stbl = findFirst(mdia, ["minf", "stbl"]);
  const stsd = findFirst(stbl, ["stsd"]);
  const samples = parseSamples(stbl);

  console.log(`\nTRACK ${trackId} timescale=${timing.timescale} duration=${timing.duration} samples=${samples.length}`);
  console.log(`stsd head: ${hex(data.subarray(stsd.off, stsd.end), Math.min(256, stsd.size))}`);
  console.log(`stsd strings: ${JSON.stringify(printableStrings(data.subarray(stsd.off, stsd.end)))}`);

  for (const sample of samples.slice(0, 8)) {
    console.log(
      `sample ${sample.index} pts=${sample.pts} delta=${sample.delta} off=${sample.offset} size=${sample.size} ` +
      `hex=${hex(sample.bytes, Math.min(160, sample.size))} strings=${JSON.stringify(printableStrings(sample.bytes))}`
    );
  }
  if (samples.length > 8) {
    const last = samples[samples.length - 1];
    console.log(`... last sample ${last.index} pts=${last.pts} delta=${last.delta} off=${last.offset} size=${last.size} hex=${hex(last.bytes, Math.min(160, last.size))}`);
  }
}
