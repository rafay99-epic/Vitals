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
  readonly lan_key: string | null;
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

export interface NewSession {
  readonly deviceId: DeviceId;
  readonly token: string;
  readonly expiresAt: number;
}

export interface SessionMatch {
  readonly sessionId: string;
  readonly device: Omit<Device, "connected">;
  readonly expiresAt: number;
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
    | "findDeviceSession"
    | "findLanDevice"
    | "setLanKey"
    | "touchSession"
    | "touchDevice"
    | "listDevices"
    | "getDevice"
    | "revokeDevice"
    | "revokeSessions"
    | "setScopes"
    | "insertCommand"
    | "getCommand"
    | "updateCommand"
    | "recentCommands"
    | "overdueCommands",
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
        "INSERT INTO devices (id, name, platform, model, app_version, scopes, created_at, lan_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      ),
      insertSession: prepare(
        "INSERT INTO sessions (id, device_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
      ),
      findSession: prepare(
        `SELECT s.id AS session_id, s.expires_at, d.* FROM sessions s JOIN devices d ON d.id = s.device_id
         WHERE s.token_hash = ? AND s.revoked_at IS NULL AND d.revoked_at IS NULL`,
      ),
      findDeviceSession: prepare(
        `SELECT s.id AS session_id, s.expires_at, d.* FROM sessions s JOIN devices d ON d.id = s.device_id
         WHERE d.id = ? AND s.revoked_at IS NULL AND d.revoked_at IS NULL ORDER BY s.expires_at DESC LIMIT 1`,
      ),
      findLanDevice: prepare("SELECT * FROM devices WHERE lan_key = ? AND revoked_at IS NULL"),
      setLanKey: prepare("UPDATE devices SET lan_key = ? WHERE id = ? AND revoked_at IS NULL"),
      touchSession: prepare("UPDATE sessions SET last_used_at = ?, expires_at = ? WHERE id = ?"),
      touchDevice: prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?"),
      listDevices: prepare("SELECT * FROM devices WHERE revoked_at IS NULL ORDER BY created_at"),
      getDevice: prepare("SELECT * FROM devices WHERE id = ?"),
      revokeDevice: prepare("UPDATE devices SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL"),
      revokeSessions: prepare("UPDATE sessions SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL"),
      setScopes: prepare("UPDATE devices SET scopes = ? WHERE id = ?"),
      insertCommand: prepare(
        "INSERT INTO commands (id, device_id, kind, args_json, status, created_at) VALUES (?, ?, ?, ?, 'pending', ?)",
      ),
      getCommand: prepare("SELECT * FROM commands WHERE id = ?"),
      updateCommand: prepare(
        "UPDATE commands SET status = ?, deadline_at = ?, finished_at = ?, error = ? WHERE id = ?",
      ),
      recentCommands: prepare("SELECT * FROM commands ORDER BY created_at DESC LIMIT ?"),
      overdueCommands: prepare(
        "SELECT * FROM commands WHERE status IN ('pending', 'running') AND deadline_at IS NOT NULL AND deadline_at < ? ORDER BY created_at",
      ),
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
    lanKey: string | null = null,
  ): NewSession | "invalid" | "expired" | "used" {
    const grant = this.statements.findGrant.get(sha256(code)) as
      | { readonly id: string; readonly expires_at: number; readonly consumed_at: number | null }
      | null;
    if (grant === null) return "invalid";
    if (grant.consumed_at !== null) return "used";
    if (grant.expires_at < now) return "expired";
    const created = this.newSession(now);
    const committed = this.db.transaction(() => {
      this.retireLanKey(lanKey, now);
      this.insertDevice(created, device, scopes, now, lanKey);
      if (this.statements.consumeGrant.run(now, created.deviceId, grant.id).changes !== 1) {
        throw new Error("grant already consumed");
      }
      this.statements.insertSession.run(newId(), created.deviceId, sha256(created.token), now, created.expiresAt);
      return true;
    });
    try {
      committed();
    } catch {
      return "used";
    }
    return created;
  }

  createLanDevice(device: DeviceInfo, scopes: ReadonlyArray<Scope>, lanKey: string, now: number): NewSession {
    const created = this.newSession(now);
    this.db.transaction(() => {
      this.retireLanKey(lanKey, now);
      this.insertDevice(created, device, scopes, now, lanKey);
      this.statements.insertSession.run(newId(), created.deviceId, sha256(created.token), now, created.expiresAt);
    })();
    return created;
  }

  bindLanKey(deviceId: string, lanKey: string, now: number): boolean {
    return this.db.transaction(() => {
      for (const row of this.statements.findLanDevice.all(lanKey) as ReadonlyArray<DeviceRow>) {
        if (row.id === deviceId) return true;
        this.statements.revokeSessions.run(now, row.id);
        this.statements.revokeDevice.run(now, row.id);
      }
      return this.statements.setLanKey.run(lanKey, deviceId).changes === 1;
    })();
  }

  lanDevice(lanKey: string): Omit<Device, "connected"> | null {
    const row = this.statements.findLanDevice.get(lanKey) as DeviceRow | null;
    return row === null ? null : toDevice(row);
  }

  findDeviceSession(deviceId: string, now: number): SessionMatch | null {
    const row = this.statements.findDeviceSession.get(deviceId) as
      | (DeviceRow & { readonly session_id: string; readonly expires_at: number })
      | null;
    return row === null ? null : this.touch(row, now);
  }

  private newSession(now: number): NewSession {
    return { deviceId: makeDeviceId(newId()), token: randomToken(), expiresAt: now + SESSION_TTL_MS };
  }

  private insertDevice(created: NewSession, device: DeviceInfo, scopes: ReadonlyArray<Scope>, now: number, lanKey: string | null): void {
    this.statements.insertDevice.run(
      created.deviceId,
      device.name,
      device.platform,
      device.model,
      device.appVersion,
      JSON.stringify(scopes),
      now,
      lanKey,
    );
  }

  private retireLanKey(lanKey: string | null, now: number): void {
    if (lanKey === null) return;
    for (const row of this.statements.findLanDevice.all(lanKey) as ReadonlyArray<DeviceRow>) {
      this.statements.revokeSessions.run(now, row.id);
      this.statements.revokeDevice.run(now, row.id);
    }
  }

  private touch(row: DeviceRow & { readonly session_id: string; readonly expires_at: number }, now: number): SessionMatch | null {
    if (row.expires_at < now) return null;
    const expiresAt = now + SESSION_TTL_MS;
    this.statements.touchSession.run(now, expiresAt, row.session_id);
    this.statements.touchDevice.run(now, row.id);
    return { sessionId: row.session_id, device: toDevice(row), expiresAt };
  }

  findSession(token: string, now: number): SessionMatch | null {
    const row = this.statements.findSession.get(sha256(token)) as
      | (DeviceRow & { readonly session_id: string; readonly expires_at: number })
      | null;
    return row === null ? null : this.touch(row, now);
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

  /** Countdowns (shut down, restart, log out) still open whose deadline passed before `before`. */
  overdueCommands(before: number): ReadonlyArray<CommandReceipt> {
    return (this.statements.overdueCommands.all(before) as ReadonlyArray<CommandRow>).map(toReceipt);
  }

}
