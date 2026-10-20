import type { Database, Statement } from "bun:sqlite";
import {
  type CommandReceipt,
  type Device,
  type DeviceInfo,
  type Scope,
  CommandId,
  DeviceId,
  PAIRING_ALPHABET,
  PAIRING_CODE_LENGTH,
  Scope as ScopeSchema,
} from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Schema from "effect/Schema";

const SESSION_TTL_MS = 90 * 86_400_000;
const PAIRING_TTL_MS = 5 * 60_000;

const decodeScopes = Schema.decodeUnknownSync(Schema.Array(ScopeSchema));
const makeDeviceId = Schema.decodeUnknownSync(DeviceId);
const makeCommandId = Schema.decodeUnknownSync(CommandId);

const sha256 = (value: string): Uint8Array => new Bun.CryptoHasher("sha256").update(value).digest();

const base64Url = (bytes: Uint8Array): string => Buffer.from(bytes).toString("base64url");

export const randomToken = (): string => base64Url(crypto.getRandomValues(new Uint8Array(32)));

const randomPairingCode = (): string => {
  const bytes = crypto.getRandomValues(new Uint8Array(PAIRING_CODE_LENGTH));
  return Array.from(bytes, (byte) => PAIRING_ALPHABET[byte % PAIRING_ALPHABET.length] ?? "2").join("");
};

interface DeviceRow {
  readonly id: string;
  readonly name: string;
  readonly platform: string;
  readonly model: string;
  readonly app_version: string;
  readonly scopes: string;
  readonly created_at: number;
  readonly last_seen_at: number | null;
  readonly revoked_at: number | null;
}

interface CommandRow {
  readonly id: string;
  readonly device_id: string;
  readonly kind: string;
  readonly status: string;
  readonly created_at: number;
  readonly deadline_at: number | null;
  readonly finished_at: number | null;
  readonly error: string | null;
}

export interface SessionMatch {
  readonly sessionId: string;
  readonly device: Omit<Device, "connected">;
}

const isPlatform = (value: string): value is Device["platform"] =>
  value === "android" || value === "ios" || value === "web";

const toDevice = (row: DeviceRow): Omit<Device, "connected"> => ({
  id: makeDeviceId(row.id),
  name: row.name,
  platform: isPlatform(row.platform) ? row.platform : "web",
  model: row.model,
  appVersion: row.app_version,
  scopes: decodeScopes(JSON.parse(row.scopes)),
  createdAt: row.created_at,
  lastSeenAt: row.last_seen_at,
  revokedAt: row.revoked_at,
});

const isStatus = (value: string): value is CommandReceipt["status"] =>
  ["pending", "running", "done", "failed", "cancelled", "rejected"].includes(value);

const toReceipt = (row: CommandRow): CommandReceipt => ({
  id: makeCommandId(row.id),
  kind: row.kind,
  deviceId: makeDeviceId(row.device_id),
  status: isStatus(row.status) ? row.status : "failed",
  createdAt: row.created_at,
  deadlineAt: row.deadline_at,
  finishedAt: row.finished_at,
  error: row.error,
});

export class RemoteStore {
  private readonly db: Database;
  private readonly statements: Record<
    | "insertGrant"
    | "findGrant"
    | "consumeGrant"
    | "insertDevice"
    | "insertSession"
    | "findSession"
    | "touchSession"
    | "touchDevice"
    | "listDevices"
    | "getDevice"
    | "revokeDevice"
    | "revokeSessions"
    | "setScopes"
    | "upsertPush"
    | "listPush"
    | "insertCommand"
    | "getCommand"
    | "updateCommand"
    | "recentCommands",
    Statement
  >;

  constructor(db: Database) {
    this.db = db;
    const prepare = (sql: string) => db.prepare(sql);
    this.statements = {
      insertGrant: prepare("INSERT INTO pairing_grants (id, code_hash, created_at, expires_at) VALUES (?, ?, ?, ?)"),
      findGrant: prepare("SELECT id, expires_at, consumed_at FROM pairing_grants WHERE code_hash = ?"),
      consumeGrant: prepare("UPDATE pairing_grants SET consumed_at = ?, device_id = ? WHERE id = ? AND consumed_at IS NULL"),
      insertDevice: prepare(
        "INSERT INTO devices (id, name, platform, model, app_version, scopes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ),
      insertSession: prepare(
        "INSERT INTO sessions (id, device_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
      ),
      findSession: prepare(
        `SELECT s.id AS session_id, s.expires_at, d.* FROM sessions s JOIN devices d ON d.id = s.device_id
         WHERE s.token_hash = ? AND s.revoked_at IS NULL AND d.revoked_at IS NULL`,
      ),
      touchSession: prepare("UPDATE sessions SET last_used_at = ?, expires_at = ? WHERE id = ?"),
      touchDevice: prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?"),
      listDevices: prepare("SELECT * FROM devices WHERE revoked_at IS NULL ORDER BY created_at"),
      getDevice: prepare("SELECT * FROM devices WHERE id = ?"),
      revokeDevice: prepare("UPDATE devices SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL"),
      revokeSessions: prepare("UPDATE sessions SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL"),
      setScopes: prepare("UPDATE devices SET scopes = ? WHERE id = ?"),
      upsertPush: prepare(
        `INSERT INTO push_tokens (device_id, provider, token, updated_at) VALUES (?, 'expo', ?, ?)
         ON CONFLICT (device_id) DO UPDATE SET token = excluded.token, updated_at = excluded.updated_at`,
      ),
      listPush: prepare(
        "SELECT p.device_id, p.token FROM push_tokens p JOIN devices d ON d.id = p.device_id WHERE d.revoked_at IS NULL",
      ),
      insertCommand: prepare(
        "INSERT INTO commands (id, device_id, kind, args_json, status, created_at) VALUES (?, ?, ?, ?, 'pending', ?)",
      ),
      getCommand: prepare("SELECT * FROM commands WHERE id = ?"),
      updateCommand: prepare(
        "UPDATE commands SET status = ?, deadline_at = ?, finished_at = ?, error = ? WHERE id = ?",
      ),
      recentCommands: prepare("SELECT * FROM commands ORDER BY created_at DESC LIMIT ?"),
    };
  }

  createPairing(now: number): { readonly code: string; readonly expiresAt: number } {
    const code = randomPairingCode();
    const expiresAt = now + PAIRING_TTL_MS;
    this.statements.insertGrant.run(newId(), sha256(code), now, expiresAt);
    return { code, expiresAt };
  }

  redeemPairing(
    code: string,
    device: DeviceInfo,
    scopes: ReadonlyArray<Scope>,
    now: number,
  ): { readonly deviceId: DeviceId; readonly token: string; readonly expiresAt: number } | "invalid" | "expired" | "used" {
    const grant = this.statements.findGrant.get(sha256(code)) as
      | { readonly id: string; readonly expires_at: number; readonly consumed_at: number | null }
      | null;
    if (grant === null) return "invalid";
    if (grant.consumed_at !== null) return "used";
    if (grant.expires_at < now) return "expired";
    const deviceId = makeDeviceId(newId());
    const token = randomToken();
    const expiresAt = now + SESSION_TTL_MS;
    const committed = this.db.transaction(() => {
      this.statements.insertDevice.run(
        deviceId,
        device.name,
        device.platform,
        device.model,
        device.appVersion,
        JSON.stringify(scopes),
        now,
      );
      if (this.statements.consumeGrant.run(now, deviceId, grant.id).changes !== 1) {
        throw new Error("grant already consumed");
      }
      this.statements.insertSession.run(newId(), deviceId, sha256(token), now, expiresAt);
      return true;
    });
    try {
      committed();
    } catch {
      return "used";
    }
    return { deviceId, token, expiresAt };
  }

  findSession(token: string, now: number): SessionMatch | null {
    const row = this.statements.findSession.get(sha256(token)) as
      | (DeviceRow & { readonly session_id: string; readonly expires_at: number })
      | null;
    if (row === null || row.expires_at < now) return null;
    this.statements.touchSession.run(now, now + SESSION_TTL_MS, row.session_id);
    this.statements.touchDevice.run(now, row.id);
    return { sessionId: row.session_id, device: toDevice(row) };
  }

  devices(): ReadonlyArray<Omit<Device, "connected">> {
    return (this.statements.listDevices.all() as ReadonlyArray<DeviceRow>).map(toDevice);
  }

  device(id: string): Omit<Device, "connected"> | null {
    const row = this.statements.getDevice.get(id) as DeviceRow | null;
    return row === null ? null : toDevice(row);
  }

  revokeDevice(id: string, now: number): boolean {
    return this.db.transaction(() => {
      this.statements.revokeSessions.run(now, id);
      return this.statements.revokeDevice.run(now, id).changes === 1;
    })();
  }

  setScopes(id: string, scopes: ReadonlyArray<Scope>): boolean {
    const unique = [...new Set<Scope>(["read", ...scopes])];
    return this.statements.setScopes.run(JSON.stringify(unique), id).changes === 1;
  }

  registerPush(deviceId: string, token: string, now: number): void {
    this.statements.upsertPush.run(deviceId, token, now);
  }

  pushTokens(): ReadonlyArray<{ readonly deviceId: string; readonly token: string }> {
    return (this.statements.listPush.all() as ReadonlyArray<{ device_id: string; token: string }>).map((row) => ({
      deviceId: row.device_id,
      token: row.token,
    }));
  }

  insertCommand(id: string, deviceId: string, kind: string, args: unknown, now: number): CommandReceipt | null {
    const existing = this.statements.getCommand.get(id) as CommandRow | null;
    if (existing !== null) return toReceipt(existing);
    this.statements.insertCommand.run(id, deviceId, kind, JSON.stringify(args), now);
    return null;
  }

  updateCommand(receipt: CommandReceipt): void {
    this.statements.updateCommand.run(receipt.status, receipt.deadlineAt, receipt.finishedAt, receipt.error, receipt.id);
  }

  command(id: string): CommandReceipt | null {
    const row = this.statements.getCommand.get(id) as CommandRow | null;
    return row === null ? null : toReceipt(row);
  }

  recentCommands(limit: number): ReadonlyArray<CommandReceipt> {
    return (this.statements.recentCommands.all(limit) as ReadonlyArray<CommandRow>).map(toReceipt);
  }

}
