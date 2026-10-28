import { Store } from "@vitals/client-runtime";
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

/** A folder's visible entries as parallel arrays. Times are epoch ms. */
export interface NativeListing {
  readonly names: ReadonlyArray<string>;
  readonly dirs: ReadonlyArray<boolean>;
  readonly sizes: ReadonlyArray<number>;
  readonly times: ReadonlyArray<number>;
}

/** Part of a file as base64: `read` bytes of a `total`-byte file. */
export interface NativeChunk {
  readonly data: string;
  readonly read: number;
  readonly total: number;
}

/** Reading files and drawing PDF pages off the JS thread. Each is missing on builds from before it was added. */
interface Native {
  readonly list?: (path: string) => Promise<NativeListing>;
  readonly readChunk?: (path: string, offset: number, length: number) => Promise<NativeChunk>;
  /** Each page's height over its width. */
  readonly pdfPages?: (path: string) => Promise<ReadonlyArray<number>>;
  /** A `file://` PNG of one page, `width` pixels wide. */
  readonly pdfPage?: (path: string, index: number, width: number) => Promise<string>;
  readonly pdfClose?: () => Promise<void>;
}

interface Android extends Native {
  readonly start: () => Promise<boolean>;
  readonly stop: () => Promise<void>;
  /** Sets the link notification's text. Missing on builds from before it was added. */
  readonly update?: (title: string, text: string) => void;
  readonly addListener?: (event: "onLinkStopped", listener: () => void) => { readonly remove: () => void };
  readonly recent: (kind: "photos" | "screenshots" | "documents", offset: number, limit: number) => Promise<NativePage>;
  readonly thumbnail: (path: string, px: number) => Promise<string | null>;
  readonly toBack: () => Promise<boolean>;
  /** All files access; null before Android 11. Missing on builds from before it was added. */
  readonly fullStorage?: () => boolean | null;
  /** Opens Vitals' own All files access switch. False when it couldn't. Missing on builds from before it was added. */
  readonly openFullStorage?: () => Promise<boolean>;
}

interface Ios extends Native {
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

/** True while the link service runs. It turns false on its own when Disconnect is tapped or Android stops it. */
export const linkHeld = new Store<boolean>(false);

if (androidShare !== null) {
  AppRegistry.registerHeadlessTask(TASK, () => () =>
    new Promise<void>((resolve) => {
      if (wanted) release = resolve;
      else resolve();
    }),
  );
}

/** Whichever half this phone has. */
export const nativeFiles: Native | null = androidShare ?? iosShare;

/** Android keeps the link (and sharing) going after the app closes; iPhone pauses it. */
export const holdsInBackground = androidShare !== null;

const ended = (): void => {
  wanted = false;
  release?.();
  release = null;
  linkHeld.set(false);
};

androidShare?.addListener?.("onLinkStopped", ended);

/**
 * Starts the foreground service that keeps the link to the Mac alive while the app is closed,
 * with its ongoing notification. Only works while the app is on screen (Android rule).
 */
export const holdLink = async (): Promise<boolean> => {
  if (androidShare === null) return false;
  if (wanted) return true;
  wanted = true;
  const started = await androidShare.start();
  if (!started || !wanted) {
    if (started) void androidShare.stop();
    ended();
    return false;
  }
  linkHeld.set(true);
  return true;
};

export const releaseLink = (): void => {
  if (!wanted) return;
  ended();
  void androidShare?.stop();
};

/** The link notification: the Mac's name and how it's connected. */
export const describeLink = (title: string, text: string): void => androidShare?.update?.(title, text);
