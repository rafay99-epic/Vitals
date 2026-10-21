const HEX = Array.from({ length: 256 }, (_, value) => value.toString(16).padStart(2, "0"));

export const uuidv7 = (now: number, random: Uint8Array): string => {
  const bytes = new Uint8Array(16);
  bytes.set(random.subarray(0, 16));
  let time = now;
  for (let index = 5; index >= 0; index -= 1) {
    bytes[index] = time % 256;
    time = Math.floor(time / 256);
  }
  bytes[6] = 0x70 | ((bytes[6] ?? 0) & 0x0f);
  bytes[8] = 0x80 | ((bytes[8] ?? 0) & 0x3f);
  const hex = Array.from(bytes, (byte) => HEX[byte] ?? "00").join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

const randomBytes = (length: number): Uint8Array => {
  const bytes = new Uint8Array(length);
  const source: Crypto | undefined = globalThis.crypto;
  if (source !== undefined && typeof source.getRandomValues === "function") return source.getRandomValues(bytes);
  for (let index = 0; index < length; index += 1) bytes[index] = Math.floor(Math.random() * 256);
  return bytes;
};

export const newId = (): string => uuidv7(Date.now(), randomBytes(16));
