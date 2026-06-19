import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourcePng = path.join(rootDir, "assets", "tart-clock-icon.png");
const macIcon = path.join(rootDir, "assets", "tart-clock-icon.icns");
const windowsIcon = path.join(rootDir, "assets", "tart-clock-icon.ico");

const icnsEntries = [
  ["icp4", 16],
  ["icp5", 32],
  ["icp6", 64],
  ["ic07", 128],
  ["ic08", 256],
  ["ic09", 512],
  ["ic10", 1024],
];

const icoSizes = [16, 24, 32, 48, 64, 128, 256];
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const crcTable = new Uint32Array(256);

for (let i = 0; i < crcTable.length; i += 1) {
  let value = i;

  for (let bit = 0; bit < 8; bit += 1) {
    value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  }

  crcTable[i] = value >>> 0;
}

function ensureSourceExists() {
  if (!fs.existsSync(sourcePng)) {
    throw new Error(`missing source icon: ${sourcePng}`);
  }
}

function crc32(buffer) {
  let crc = 0xffffffff;

  for (const byte of buffer) {
    crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }

  return (crc ^ 0xffffffff) >>> 0;
}

function writePngChunk(type, data = Buffer.alloc(0)) {
  const typeBuffer = Buffer.from(type, "ascii");
  const chunk = Buffer.alloc(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  typeBuffer.copy(chunk, 4);
  data.copy(chunk, 8);
  chunk.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 8 + data.length);
  return chunk;
}

function readPngChunks(buffer) {
  if (!buffer.subarray(0, pngSignature.length).equals(pngSignature)) {
    throw new Error("source icon is not a PNG");
  }

  const chunks = [];
  let offset = pngSignature.length;

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;

    chunks.push({
      type,
      data: buffer.subarray(dataStart, dataEnd),
    });

    offset = dataEnd + 4;

    if (type === "IEND") {
      break;
    }
  }

  return chunks;
}

function paethPredictor(left, up, upLeft) {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upLeftDistance = Math.abs(estimate - upLeft);

  if (leftDistance <= upDistance && leftDistance <= upLeftDistance) {
    return left;
  }

  if (upDistance <= upLeftDistance) {
    return up;
  }

  return upLeft;
}

function decodeScanlines(inflated, width, height, channels) {
  const bytesPerPixel = channels;
  const rowSize = width * channels;
  const pixels = Buffer.alloc(rowSize * height);
  let sourceOffset = 0;
  let targetOffset = 0;
  let previousRow = Buffer.alloc(rowSize);

  for (let rowIndex = 0; rowIndex < height; rowIndex += 1) {
    const filter = inflated[sourceOffset];
    sourceOffset += 1;

    const row = Buffer.alloc(rowSize);
    const sourceRow = inflated.subarray(sourceOffset, sourceOffset + rowSize);
    sourceOffset += rowSize;

    for (let index = 0; index < rowSize; index += 1) {
      const left = index >= bytesPerPixel ? row[index - bytesPerPixel] : 0;
      const up = previousRow[index] || 0;
      const upLeft = index >= bytesPerPixel ? previousRow[index - bytesPerPixel] : 0;
      let value = sourceRow[index];

      if (filter === 1) {
        value += left;
      } else if (filter === 2) {
        value += up;
      } else if (filter === 3) {
        value += Math.floor((left + up) / 2);
      } else if (filter === 4) {
        value += paethPredictor(left, up, upLeft);
      } else if (filter !== 0) {
        throw new Error(`unsupported PNG filter: ${filter}`);
      }

      row[index] = value & 0xff;
    }

    row.copy(pixels, targetOffset);
    targetOffset += rowSize;
    previousRow = row;
  }

  return pixels;
}

function normalizePngToRgba(filePath) {
  const chunks = readPngChunks(fs.readFileSync(filePath));
  const ihdr = chunks.find((chunk) => chunk.type === "IHDR");

  if (!ihdr) {
    throw new Error(`missing PNG header: ${filePath}`);
  }

  const width = ihdr.data.readUInt32BE(0);
  const height = ihdr.data.readUInt32BE(4);
  const bitDepth = ihdr.data[8];
  const colorType = ihdr.data[9];
  const compression = ihdr.data[10];
  const filterMethod = ihdr.data[11];
  const interlace = ihdr.data[12];

  if (bitDepth !== 8 || compression !== 0 || filterMethod !== 0 || interlace !== 0) {
    throw new Error(`unsupported PNG format: ${filePath}`);
  }

  if (colorType !== 2 && colorType !== 6) {
    throw new Error(`unsupported PNG color type ${colorType}: ${filePath}`);
  }

  const channels = colorType === 6 ? 4 : 3;
  const idat = Buffer.concat(chunks.filter((chunk) => chunk.type === "IDAT").map((chunk) => chunk.data));
  const pixels = decodeScanlines(zlib.inflateSync(idat), width, height, channels);
  const rgbaPixels = Buffer.alloc(width * height * 4);

  for (let source = 0, target = 0; source < pixels.length; source += channels, target += 4) {
    rgbaPixels[target] = pixels[source];
    rgbaPixels[target + 1] = pixels[source + 1];
    rgbaPixels[target + 2] = pixels[source + 2];
    rgbaPixels[target + 3] = colorType === 6 ? pixels[source + 3] : 255;
  }

  const filtered = Buffer.alloc(height * (1 + width * 4));

  for (let row = 0; row < height; row += 1) {
    const filteredOffset = row * (1 + width * 4);
    const pixelOffset = row * width * 4;

    filtered[filteredOffset] = 0;
    rgbaPixels.copy(filtered, filteredOffset + 1, pixelOffset, pixelOffset + width * 4);
  }

  const normalizedIhdr = Buffer.alloc(13);
  normalizedIhdr.writeUInt32BE(width, 0);
  normalizedIhdr.writeUInt32BE(height, 4);
  normalizedIhdr[8] = 8;
  normalizedIhdr[9] = 6;
  normalizedIhdr[10] = 0;
  normalizedIhdr[11] = 0;
  normalizedIhdr[12] = 0;

  fs.writeFileSync(filePath, Buffer.concat([
    pngSignature,
    writePngChunk("IHDR", normalizedIhdr),
    writePngChunk("IDAT", zlib.deflateSync(filtered, { level: 9 })),
    writePngChunk("IEND"),
  ]));
}

function resizePng(size, outPath) {
  execFileSync("sips", ["-z", String(size), String(size), sourcePng, "--out", outPath], {
    stdio: "ignore",
  });
  normalizePngToRgba(outPath);
}

function writeIcnsChunk(type, data) {
  const chunk = Buffer.alloc(8 + data.length);
  chunk.write(type, 0, 4, "ascii");
  chunk.writeUInt32BE(chunk.length, 4);
  data.copy(chunk, 8);
  return chunk;
}

function generateMacIcon(tempDir) {
  const chunks = icnsEntries.map(([type, size]) => {
    const pngPath = path.join(tempDir, `icns-${size}.png`);
    resizePng(size, pngPath);
    return writeIcnsChunk(type, fs.readFileSync(pngPath));
  });
  const totalLength = 8 + chunks.reduce((length, chunk) => length + chunk.length, 0);
  const header = Buffer.alloc(8);

  header.write("icns", 0, 4, "ascii");
  header.writeUInt32BE(totalLength, 4);
  fs.writeFileSync(macIcon, Buffer.concat([header, ...chunks], totalLength));
}

function writeUint16LE(buffer, value, offset) {
  buffer.writeUInt16LE(value, offset);
}

function writeUint32LE(buffer, value, offset) {
  buffer.writeUInt32LE(value, offset);
}

function generateWindowsIcon(tempDir) {
  const pngEntries = icoSizes.map((size) => {
    const pngPath = path.join(tempDir, `icon-${size}.png`);
    resizePng(size, pngPath);
    return {
      data: fs.readFileSync(pngPath),
      size,
    };
  });

  const headerSize = 6;
  const directorySize = pngEntries.length * 16;
  let imageOffset = headerSize + directorySize;
  const chunks = [];

  const header = Buffer.alloc(headerSize);
  writeUint16LE(header, 0, 0);
  writeUint16LE(header, 1, 2);
  writeUint16LE(header, pngEntries.length, 4);
  chunks.push(header);

  for (const entry of pngEntries) {
    const directory = Buffer.alloc(16);
    directory[0] = entry.size === 256 ? 0 : entry.size;
    directory[1] = entry.size === 256 ? 0 : entry.size;
    directory[2] = 0;
    directory[3] = 0;
    writeUint16LE(directory, 1, 4);
    writeUint16LE(directory, 32, 6);
    writeUint32LE(directory, entry.data.length, 8);
    writeUint32LE(directory, imageOffset, 12);
    imageOffset += entry.data.length;
    chunks.push(directory);
  }

  for (const entry of pngEntries) {
    chunks.push(entry.data);
  }

  fs.writeFileSync(windowsIcon, Buffer.concat(chunks));
}

function main() {
  ensureSourceExists();

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "tart-icons-"));

  try {
    generateMacIcon(tempDir);
    generateWindowsIcon(tempDir);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }

  process.stdout.write(`Generated ${path.relative(rootDir, macIcon)}\n`);
  process.stdout.write(`Generated ${path.relative(rootDir, windowsIcon)}\n`);
}

main();
