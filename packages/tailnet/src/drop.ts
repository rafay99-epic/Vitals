import { requireOptionalNativeModule } from "expo";

export interface DropEndpoint {
  readonly url: string;
  readonly pin: string | null;
  readonly tsnet: boolean;
}

export interface DropJob {
  readonly job: string;
  readonly title: string;
  readonly endpoints: ReadonlyArray<DropEndpoint>;
  readonly ticket: string;
  readonly dropId: string;
  readonly fileId: string;
  readonly size: number;
}

export interface UploadJob extends DropJob {
  readonly uri: string;
}

export interface DownloadJob extends DropJob {
  readonly name: string;
  readonly path: string | null;
  readonly mime: string | null;
}

export type TransferEvent =
  | { readonly type: "progress"; readonly job: string; readonly done: number; readonly total: number; readonly route: "lan" | "tailnet" }
  | { readonly type: "done"; readonly job: string; readonly sha256: string; readonly uri: string | null }
  | { readonly type: "error"; readonly job: string; readonly message: string; readonly retryable: boolean };

interface NativeDrop {
  readonly canInstallApps: boolean;
  upload(job: string): Promise<void>;
  download(job: string): Promise<void>;
  cancel(job: string): Promise<void>;
  installApk(uri: string): Promise<void>;
  openFile(uri: string, mime: string | null): Promise<void>;
  addListener(event: "transfer", listener: (event: TransferEvent) => void): { remove(): void };
}

const native = requireOptionalNativeModule<NativeDrop>("VitalsDrop");

export const dropSupported = native !== null;

export const canInstallApps = native?.canInstallApps ?? false;

const missing = (): never => {
  throw new Error("File transfer is not in this build");
};

export const uploadFile = async (job: UploadJob): Promise<void> => (native === null ? missing() : native.upload(JSON.stringify(job)));

export const downloadFile = async (job: DownloadJob): Promise<void> => (native === null ? missing() : native.download(JSON.stringify(job)));

export const cancelTransfer = async (job: string): Promise<void> => {
  await native?.cancel(job);
};

export const installApk = async (uri: string): Promise<void> => (native === null ? missing() : native.installApk(uri));

export const openFile = async (uri: string, mime: string | null): Promise<void> => (native === null ? missing() : native.openFile(uri, mime));

export const addTransferListener = (listener: (event: TransferEvent) => void): (() => void) => {
  const subscription = native?.addListener("transfer", listener);
  return () => subscription?.remove();
};
