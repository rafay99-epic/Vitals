import { open } from "node:fs/promises";

const READ_BYTES = 1024 * 1024;

export const hashFile = async (path: string, keepGoing: () => boolean = () => true): Promise<string | null> => {
  const handle = await open(path, "r");
  try {
    const hasher = new Bun.CryptoHasher("sha256");
    const buffer = Buffer.allocUnsafe(READ_BYTES);
    for (let position = 0; ; ) {
      if (!keepGoing()) return null;
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, position);
      if (bytesRead === 0) return hasher.digest("hex");
      hasher.update(buffer.subarray(0, bytesRead));
      position += bytesRead;
    }
  } finally {
    await handle.close();
  }
};
