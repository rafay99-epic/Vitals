const SLICE = 0x8000;

/** Bytes to base64, through `btoa` (Hermes, browsers and Bun all have it). Works in slices so big chunks don't blow the call stack. */
export const toBase64 = (bytes: Uint8Array): string => {
  let binary = "";
  for (let at = 0; at < bytes.length; at += SLICE) binary += String.fromCharCode(...bytes.subarray(at, at + SLICE));
  return btoa(binary);
};

/** Base64 back to bytes. */
export const fromBase64 = (base64: string): Uint8Array<ArrayBuffer> => {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
};
