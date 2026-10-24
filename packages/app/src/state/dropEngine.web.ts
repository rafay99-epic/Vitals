import { DROP_LIMITS } from "@vitals/contracts";
import type { TransferEvent, UploadJob } from "@vitals/tailnet/drop";

import type { DropEngine } from "./drops.ts";
import { heldBlob } from "./heldBlobs.ts";

const IN_FLIGHT = 4;
const BACKOFF_MS: ReadonlyArray<number> = [1_000, 2_000, 5_000, 10_000, 20_000, 30_000];

const listeners = new Set<(event: TransferEvent) => void>();
const running = new Map<string, AbortController>();

const emit = (event: TransferEvent): void => {
  for (const listener of listeners) listener(event);
};

const retryable = (status: number): boolean => status === 408 || status === 409 || status === 423 || status === 429 || (status >= 500 && status !== 507);

const refusal = (status: number): Error =>
  new Error(status === 507 ? "Your Mac is out of space" : status === 401 || status === 403 ? "Your Mac refused this transfer" : `Your Mac could not take the file (${String(status)})`);

const sleep = (ms: number, signal: AbortSignal): Promise<void> =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    signal.addEventListener(
      "abort",
      () => {
        clearTimeout(timer);
        reject(signal.reason);
      },
      { once: true },
    );
  });

const attempt = async (run: () => Promise<Response>, signal: AbortSignal, tries = 0): Promise<Response> => {
  const response = await run().catch((error: unknown) => {
    if (signal.aborted) throw error;
    return null;
  });
  if (response !== null && (response.ok || !retryable(response.status))) {
    if (!response.ok) throw refusal(response.status);
    return response;
  }
  const wait = BACKOFF_MS[tries];
  if (wait === undefined) throw response === null ? new Error("Could not reach your Mac") : refusal(response.status);
  await sleep(wait, signal);
  return attempt(run, signal, tries + 1);
};

const send = async (job: UploadJob, base: string, signal: AbortSignal): Promise<void> => {
  const blob = heldBlob(job.uri);
  if (blob === undefined) throw new Error("This browser no longer has that file. Choose it again.");
  const url = `${base}/api/drop/${encodeURIComponent(job.dropId)}/${encodeURIComponent(job.fileId)}`;
  const auth = { Authorization: `Drop ${job.ticket}` };
  const size = blob.size;
  if (size === 0) {
    await attempt(() => fetch(url, { method: "PUT", headers: { ...auth, "Content-Range": "bytes */0" }, signal }), signal);
    return;
  }
  const head = await attempt(() => fetch(url, { method: "HEAD", headers: auth, signal }), signal);
  const have = new Set(
    (head.headers.get("X-Vitals-Parts") ?? "")
      .split(",")
      .filter((part) => part !== "")
      .map(Number),
  );
  const partOf = (index: number) => {
    const start = index * DROP_LIMITS.partBytes;
    return { start, end: Math.min(start + DROP_LIMITS.partBytes, size) - 1 };
  };
  const indexes = Array.from({ length: Math.ceil(size / DROP_LIMITS.partBytes) }, (_, index) => index);
  const queue = indexes.filter((index) => !have.has(index));
  let done = indexes.filter((index) => have.has(index)).reduce((sum, index) => sum + partOf(index).end - partOf(index).start + 1, 0);
  emit({ type: "progress", job: job.job, done, total: size, route: "tailnet" });
  const worker = async (): Promise<void> => {
    const index = queue.shift();
    if (index === undefined) return;
    const { start, end } = partOf(index);
    await attempt(() => fetch(url, { method: "PUT", headers: { ...auth, "Content-Range": `bytes ${String(start)}-${String(end)}/${String(size)}` }, body: blob.slice(start, end + 1), signal }), signal);
    done += end - start + 1;
    emit({ type: "progress", job: job.job, done, total: size, route: "tailnet" });
    return worker();
  };
  await Promise.all(Array.from({ length: Math.min(IN_FLIGHT, queue.length) }, worker));
};

export const dropEngine: DropEngine = {
  supported: true,
  upload: async (job) => {
    const endpoint = job.endpoints.find((candidate) => candidate.pin === null && !candidate.tsnet);
    if (endpoint === undefined) throw new Error("This browser reaches your Mac only over Tailscale");
    running.get(job.job)?.abort();
    const controller = new AbortController();
    running.set(job.job, controller);
    void send(job, endpoint.url, controller.signal)
      .then(
        () => emit({ type: "done", job: job.job, sha256: "", uri: null }),
        (error: unknown) => {
          if (!controller.signal.aborted) emit({ type: "error", job: job.job, message: error instanceof Error ? error.message : "The upload failed", retryable: false });
        },
      )
      .finally(() => {
        if (running.get(job.job) === controller) running.delete(job.job);
      });
  },
  download: async () => {
    throw new Error("Browsers don't take files from the Mac");
  },
  cancel: async (job) => {
    running.get(job)?.abort();
    running.delete(job);
  },
  listen: (listener) => {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },
};
