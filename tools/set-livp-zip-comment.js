#!/usr/bin/env node

const fs = require("fs");

const path = process.argv[2];
if (!path) {
  console.error("Usage: tools/set-livp-zip-comment.js file.livp");
  process.exit(2);
}

const buffer = fs.readFileSync(path);

function u16le(offset) {
  return buffer.readUInt16LE(offset);
}

function u32le(offset) {
  return buffer.readUInt32LE(offset);
}

function hex32(value) {
  return value.toString(16).toUpperCase().padStart(8, "0");
}

const entries = [];
let offset = 0;
while (offset + 30 <= buffer.length && u32le(offset) === 0x04034b50) {
  const compressedSize = u32le(offset + 18);
  const fileNameLength = u16le(offset + 26);
  const extraLength = u16le(offset + 28);
  const fileName = buffer.subarray(offset + 30, offset + 30 + fileNameLength).toString("utf8");
  const dataOffset = offset + 30 + fileNameLength + extraLength;
  entries.push({ fileName, dataOffset, compressedSize });
  offset = dataOffset + compressedSize;
}

const heic = entries.find((entry) => /\.hei[cf]$/i.test(entry.fileName));
const mov = entries.find((entry) => /\.mov$/i.test(entry.fileName));
if (!heic || !mov) {
  console.error("Expected one HEIC/HEIF file and one MOV file in the ZIP local entries.");
  process.exit(1);
}

const eocdSignature = Buffer.from([0x50, 0x4b, 0x05, 0x06]);
const eocdOffset = buffer.lastIndexOf(eocdSignature);
if (eocdOffset === -1) {
  console.error("Could not find ZIP end-of-central-directory record.");
  process.exit(1);
}

const comment = [
  "0002",
  hex32(heic.dataOffset),
  hex32(heic.compressedSize),
  "0003",
  hex32(mov.dataOffset),
  hex32(mov.compressedSize),
  "313030304C495650"
].join("");

if (Buffer.byteLength(comment, "utf8") > 0xffff) {
  console.error("ZIP comment is too long.");
  process.exit(1);
}

const withoutOldComment = buffer.subarray(0, eocdOffset + 22);
withoutOldComment.writeUInt16LE(Buffer.byteLength(comment, "utf8"), eocdOffset + 20);
fs.writeFileSync(path, Buffer.concat([withoutOldComment, Buffer.from(comment, "utf8")]));
console.log(comment);
