# Drop: file transfer protocol

Control messages travel over the existing RPC connection (`drop.*` in `src/rpc.ts`, types in `src/drop.ts`). File bytes travel over HTTPS.

## Where to connect

| Route | Base URL | Trust |
|---|---|---|
| Wi-Fi | `https://<lan host>:<routes.tls.port>` (Noise port + `DROP_LAN_TLS_OFFSET`) | Pin: base64 SHA-256 of the certificate's SubjectPublicKeyInfo equals `routes.tls.pin`. Any other certificate is refused. Hostname is not checked. |
| Tailscale | `routes.tailnet` (the `tailscale serve` HTTPS URL) | Normal WebPKI (`*.ts.net`). With built-in Tailscale, dial through tsnet. |

`routes.tls` reaches clients only over an authenticated channel (Noise or Tailscale), so the pin can be trusted.

## Auth

`Authorization: Drop <ticket>`. Tickets come from `drop.offer`, `drop.accept` or `drop.ticket`, are bound to one device and one drop, and expire after `DROP_LIMITS.ticketMs`. Tickets never appear in URLs or logs.

## Endpoints

All paths are `/api/drop/{dropId}/{fileId}`.

- **`PUT`** uploads one part.
  - Headers: `Content-Range: bytes {start}-{end}/{size}`. `start` is a multiple of `DROP_LIMITS.partBytes` (16 MiB), and `end - start + 1 = min(partBytes, size - start)`. The body is exactly those bytes. An empty file is a single `PUT` with `Content-Range: bytes */0` and no body.
  - Writes land at their offset. Parts may arrive in any order; a repeated part is harmless.
  - `204` with `X-Vitals-Done: <bytes of this file received>`.
  - `409`: the drop is waiting for the Mac to accept, or the file is already done.
  - `416`: bad range. `423`: the drop is paused. `507`: not enough space.
- **`HEAD`** returns `200` with `X-Vitals-Parts: <comma-separated received part indexes>` (empty when none) and `Content-Length: <size>`. A resumed upload sends only the missing parts.
- **`GET`** downloads a file the Mac sent to this device. It supports a single `Range: bytes=a-` or `bytes=a-b` and returns `200` or `206`. `Content-Type` is the file's mime.

When every part of a file has arrived, the server checks `sha256` (if the offer had one) and marks the file done. When every file is done, the drop is `done`.

For Mac-to-device drops, the device downloads each file, hashes it locally, and calls `drop.received`. The server hashes Mac files in the background after the send starts and fills in `DropFile.sha256` when it is ready. If it is set, the device must match it.

## States

`asking`: waiting for the receiver to accept. `waiting`: the receiver is not connected. `running`. `paused`: the sender or the Mac paused it, and bytes are refused with `423`. `done`, `failed`, `cancelled`, `declined`.

## Clients

Up to 4 parts in flight per file and 2 files at once. Back off on `423` and connection errors, then resume using `HEAD` (uploads) or `Range` (downloads). Try Wi-Fi first and fall back to Tailscale.
