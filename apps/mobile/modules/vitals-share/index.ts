import { requireOptionalNativeModule } from "expo";
import { AppRegistry, Platform } from "react-native";

const TASK = "VitalsShare";

/** One file a native recent query found. Times are epoch ms. */
export interface NativeEntry {
  readonly path: string;
  readonly name: string;
  readonly size: number;
  readonly modifiedAt: number;
}

export interface NativePage {
  readonly entries: ReadonlyArray<NativeEntry>;
  readonly more: boolean;
}

export type PhotosAccess = "full" | "limited" | "ask" | "denied";
export type FolderRole = "downloads" | "documents" | "other";

/** A folder picked in Files on iPhone, readable through its bookmark. */
export interface SharedFolder {
  readonly id: string;
  readonly role: FolderRole;
  readonly name: string;
  readonly path: string;
}

interface Android {
  readonly start: () => Promise<boolean>;
  readonly stop: () => Promise<void>;
  readonly recent: (kind: "photos" | "screenshots" | "documents", offset: number, limit: number) => Promise<NativePage>;
  readonly thumbnail: (path: string, px: number) => Promise<string | null>;
  readonly toBack: () => Promise<boolean>;
  /** All files access; null before Android 11. Missing on builds from before it was added. */
  readonly fullStorage?: () => boolean | null;
}

interface Ios {
  readonly photosAccess: () => Promise<PhotosAccess>;
  readonly askPhotos: () => Promise<PhotosAccess>;
  readonly photos: (kind: "photos" | "screenshots" | "all", offset: number, limit: number) => Promise<NativePage & { readonly total: number }>;
  readonly thumbnail: (path: string, px: number) => Promise<string | null>;
  readonly exportPhoto: (path: string) => Promise<{ readonly uri: string; readonly name: string; readonly size: number }>;
  readonly folders: () => Promise<ReadonlyArray<SharedFolder>>;
  readonly pickFolder: (role: FolderRole) => Promise<SharedFolder | null>;
  readonly removeFolder: (id: string) => Promise<void>;
}

/** The Android half: background serving, MediaStore recents, thumbnails. Null elsewhere. */
export const androidShare = Platform.OS === "android" ? requireOptionalNativeModule<Android>("VitalsShare") : null;

/** The iPhone half: PhotoKit and picked folders. Null elsewhere. */
export const iosShare = Platform.OS === "ios" ? requireOptionalNativeModule<Ios>("VitalsShare") : null;

let wanted = false;
let release: (() => void) | null = null;

if (androidShare !== null) {
  AppRegistry.registerHeadlessTask(TASK, () => () =>
    new Promise<void>((resolve) => {
      if (wanted) release = resolve;
      else resolve();
    }),
  );
}

export const sharesInBackground = androidShare !== null;

const finish = (): void => {
  release?.();
  release = null;
  void androidShare?.stop();
};

export const holdSharing = async (): Promise<boolean> => {
  if (androidShare === null) return false;
  if (wanted) return true;
  wanted = true;
  const started = await androidShare.start();
  if (!started) wanted = false;
  else if (!wanted) finish();
  return started && wanted;
};

export const releaseSharing = (): void => {
  if (!wanted) return;
  wanted = false;
  finish();
};
