import { addTransferListener, cancelTransfer, downloadFile, dropSupported, uploadFile } from "@vitals/tailnet/drop";

import type { DropEngine } from "./drops.ts";

export const dropEngine: DropEngine = {
  supported: dropSupported,
  upload: uploadFile,
  download: downloadFile,
  cancel: cancelTransfer,
  listen: addTransferListener,
};
