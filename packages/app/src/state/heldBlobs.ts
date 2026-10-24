import { newId } from "@vitals/shared";

const held = new Map<string, Blob>();

export const holdBlob = (blob: Blob): string => {
  const key = `held:${newId()}`;
  held.set(key, blob);
  return key;
};

export const heldBlob = (key: string): Blob | undefined => held.get(key);

export const releaseBlobs = (keys: Iterable<string>): void => {
  for (const key of keys) held.delete(key);
};
