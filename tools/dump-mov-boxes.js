#!/usr/bin/env node

const fs = require("fs");

const path = process.argv[2];
if (!path) {
  console.error("Usage: tools/dump-mov-boxes.js file.mov");
  process.exit(1);
}

const data = fs.readFileSync(path);

const containers = new Set([
  "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "udta",
  "meta", "ilst", "mdra", "rmra", "tref", "ipro", "sinf", "schi",
]);

function u8(off) {
  return data.readUInt8(off);
}

function u16(off) {
  return data.readUInt16BE(off);
}

function u24(off) {
  return (data[off] << 16) | (data[off + 1] << 8) | data[off + 2];
}

function u32(off) {
  return data.readUInt32BE(off);
}

function i32(off) {
  return data.readInt32BE(off);
}

function u64(off) {
  return Number(data.readBigUInt64BE(off));
}

function ascii(off, len) {
  return data.subarray(off, off + len).toString("latin1");
}

function hex(off, len) {
  return data.subarray(off, Math.min(data.length, off + len)).toString("hex").match(/.{1,2}/g)?.join(" ") ?? "";
}

function readBoxHeader(off, end) {
  if (off + 8 > end) return null;
  let size = u32(off);
  const type = ascii(off + 4, 4);
  let header = 8;
  if (size === 1) {
    if (off + 16 > end) return null;
    size = u64(off + 8);
    header = 16;
  } else if (size === 0) {
    size = end - off;
  }
  if (size < header || off + size > end) return null;
  return { off, size, type, header, content: off + header, end: off + size };
}

function versionFlags(off) {
  return { version: u8(off), flags: u24(off + 1) };
}

function parseMvhd(box) {
  const vf = versionFlags(box.content);
  const p = box.content + 4;
  const timescale = vf.version === 1 ? u32(p + 16) : u32(p + 8);
  const duration = vf.version === 1 ? u64(p + 20) : u32(p + 12);
  return { timescale, duration };
}

function parseTkhd(box) {
  const vf = versionFlags(box.content);
  const p = box.content + 4;
  const trackId = vf.version === 1 ? u32(p + 16) : u32(p + 8);
  return { trackId };
}

function parseMdhd(box) {
  const vf = versionFlags(box.content);
  const p = box.content + 4;
  const timescale = vf.version === 1 ? u32(p + 16) : u32(p + 8);
  const duration = vf.version === 1 ? u64(p + 20) : u32(p + 12);
  return { timescale, duration };
}

function parseHdlr(box) {
  const p = box.content + 4;
  const handlerType = ascii(p + 4, 4);
  let name = "";
  const nameStart = p + 20;
  if (nameStart < box.end) {
    name = data.subarray(nameStart, box.end).toString("utf8").replace(/\0+$/, "");
  }
  return { handlerType, name };
}

function parseStsd(box) {
  const entries = [];
  let p = box.content + 8;
  const count = u32(box.content + 4);
  for (let i = 0; i < count && p + 8 <= box.end; i++) {
    const size = u32(p);
    const format = ascii(p + 4, 4);
    const entry = { index: i + 1, format, size, children: [] };
    if (format === "mebx") {
      // Metadata sample entries often contain key declaration boxes after the reserved fields.
      let child = p + 8;
      while (child + 8 <= p + size) {
        const maybe = readBoxHeader(child, p + size);
        if (!maybe) {
          child += 1;
          continue;
        }
        entry.children.push(summarizeBox(maybe));
        child = maybe.end;
      }
    }
    entries.push(entry);
    p += size;
  }
  return { entries };
}

function parseStts(box) {
  const entries = [];
  const count = u32(box.content + 4);
  let p = box.content + 8;
  for (let i = 0; i < count && p + 8 <= box.end; i++, p += 8) {
    entries.push({ sampleCount: u32(p), sampleDelta: u32(p + 4) });
  }
  return { entries };
}

function parseStsz(box) {
  const sampleSize = u32(box.content + 4);
  const sampleCount = u32(box.content + 8);
  const sizes = [];
  let p = box.content + 12;
  if (sampleSize === 0) {
    for (let i = 0; i < Math.min(sampleCount, 12) && p + 4 <= box.end; i++, p += 4) {
      sizes.push(u32(p));
    }
  }
  return { sampleSize, sampleCount, firstSizes: sizes };
}

function parseStco(box) {
  const count = u32(box.content + 4);
  const offsets = [];
  let p = box.content + 8;
  for (let i = 0; i < Math.min(count, 12) && p + 4 <= box.end; i++, p += 4) offsets.push(u32(p));
  return { entryCount: count, firstOffsets: offsets };
}

function parseCo64(box) {
  const count = u32(box.content + 4);
  const offsets = [];
  let p = box.content + 8;
  for (let i = 0; i < Math.min(count, 12) && p + 8 <= box.end; i++, p += 8) offsets.push(u64(p));
  return { entryCount: count, firstOffsets: offsets };
}

function parseStsc(box) {
  const count = u32(box.content + 4);
  const entries = [];
  let p = box.content + 8;
  for (let i = 0; i < Math.min(count, 12) && p + 12 <= box.end; i++, p += 12) {
    entries.push({ firstChunk: u32(p), samplesPerChunk: u32(p + 4), sampleDescriptionIndex: u32(p + 8) });
  }
  return { entryCount: count, entries };
}

function summarizeBox(box) {
  const summary = { type: box.type, off: box.off, size: box.size };
  try {
    if (box.type === "mvhd") Object.assign(summary, parseMvhd(box));
    if (box.type === "tkhd") Object.assign(summary, parseTkhd(box));
    if (box.type === "mdhd") Object.assign(summary, parseMdhd(box));
    if (box.type === "hdlr") Object.assign(summary, parseHdlr(box));
    if (box.type === "stsd") Object.assign(summary, parseStsd(box));
    if (box.type === "stts") Object.assign(summary, parseStts(box));
    if (box.type === "stsz") Object.assign(summary, parseStsz(box));
    if (box.type === "stco") Object.assign(summary, parseStco(box));
    if (box.type === "co64") Object.assign(summary, parseCo64(box));
    if (box.type === "stsc") Object.assign(summary, parseStsc(box));
    if (["keys", "ilst", "data", "mebx"].includes(box.type)) {
      summary.head = hex(box.content, Math.min(96, box.size - box.header));
    }
  } catch (err) {
    summary.parseError = err.message;
  }
  return summary;
}

function walk(off, end, depth = 0, ancestors = []) {
  const rows = [];
  let p = off;
  while (p + 8 <= end) {
    const box = readBoxHeader(p, end);
    if (!box) break;
    const summary = summarizeBox(box);
    rows.push({ depth, path: [...ancestors, box.type].join("/"), ...summary });
    const childStart = box.type === "meta" ? box.content + 4 : box.content;
    if (containers.has(box.type) && childStart < box.end) {
      rows.push(...walk(childStart, box.end, depth + 1, [...ancestors, box.type]));
    }
    p = box.end;
  }
  return rows;
}

const rows = walk(0, data.length);
for (const row of rows) {
  const indent = "  ".repeat(row.depth);
  const details = { ...row };
  delete details.depth;
  delete details.path;
  delete details.type;
  delete details.off;
  delete details.size;
  const detailText = Object.keys(details).length ? ` ${JSON.stringify(details)}` : "";
  console.log(`${indent}${row.path} @${row.off} size=${row.size}${detailText}`);
}
