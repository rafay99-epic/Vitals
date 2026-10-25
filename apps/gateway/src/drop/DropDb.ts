import type { Database, Statement } from "bun:sqlite";
import {
  type DeviceId,
  type DropFileId,
  type DropId,
  type DropPeer,
  type DropState,
  DeviceId as DeviceIdSchema,
  DropFileId as DropFileIdSchema,
  DropId as DropIdSchema,
  DropPeer as DropPeerSchema,
  DropState as DropStateSchema,
} from "@vitals/contracts";
import * as Schema from "effect/Schema";

export type DropRoute = "lan" | "tailnet";

export interface DropFileRecord {
  readonly id: DropFileId;
  readonly name: string;
  readonly path: string | null;
  readonly size: number;
  readonly mime: string | null;
  readonly origin: string | null;
  readonly parts: Set<number>;
  sha256: string | null;
  done: number;
  complete: boolean;
  verifying: boolean;
}

export interface DropRecord {
  readonly id: DropId;
  readonly deviceId: DeviceId;
  readonly incoming: boolean;
  readonly from: DropPeer;
  readonly to: DropPeer;
  readonly files: ReadonlyArray<DropFileRecord>;
  readonly byId: ReadonlyMap<string, DropFileRecord>;
  readonly createdAt: number;
  state: DropState;
  route: DropRoute | null;
  updatedAt: number;
  startedAt: number | null;
  error: string | null;
}

export interface TicketGrant {
  readonly dropId: string;
  readonly deviceId: string;
  readonly expiresAt: number;
}

interface DropRow {
  readonly id: string;
  readonly device_id: string;
  readonly incoming: number;
  readonly from_json: string;
  readonly to_json: string;
  readonly state: string;
  readonly route: string | null;
  readonly created_at: number;
  readonly updated_at: number;
  readonly started_at: number | null;
  readonly error: string | null;
}

interface FileRow {
  readonly drop_id: string;
  readonly id: string;
  readonly name: string;
  readonly path: string | null;
  readonly size: number;
  readonly mime: string | null;
  readonly sha256: string | null;
  readonly done: number;
  readonly complete: number;
  readonly parts: Uint8Array | null;
  readonly origin: string | null;
}

interface TicketRow {
  readonly drop_id: string;
  readonly device_id: string;
  readonly expires_at: number;
}

const decodeDropId = Schema.decodeUnknownSync(DropIdSchema);
const decodeFileId = Schema.decodeUnknownSync(DropFileIdSchema);
const decodeDeviceId = Schema.decodeUnknownSync(DeviceIdSchema);
const decodePeer = Schema.decodeUnknownSync(Schema.fromJsonString(DropPeerSchema));
const encodePeer = Schema.encodeSync(Schema.fromJsonString(DropPeerSchema));
const decodeState = Schema.decodeUnknownSync(DropStateSchema);

const toBitmap = (parts: ReadonlySet<number>): Uint8Array => {
  let highest = -1;
  for (const index of parts) highest = Math.max(highest, index);
  const bytes = new Uint8Array(Math.ceil((highest + 1) / 8));
  for (const index of parts) bytes[index >> 3] = (bytes[index >> 3] ?? 0) | (1 << (index & 7));
  return bytes;
};

const fromBitmap = (bytes: Uint8Array | null): Set<number> => {
  const parts = new Set<number>();
  if (bytes === null) return parts;
  bytes.forEach((byte, offset) => {
    for (let bit = 0; bit < 8; bit += 1) if ((byte & (1 << bit)) !== 0) parts.add(offset * 8 + bit);
  });
  return parts;
};

const toRoute = (route: string | null): DropRoute | null => (route === "lan" || route === "tailnet" ? route : null);

const toFile = (row: FileRow): DropFileRecord => ({
  id: decodeFileId(row.id),
  name: row.name,
  path: row.path,
  size: row.size,
  mime: row.mime,
  origin: row.origin,
  parts: fromBitmap(row.parts),
  sha256: row.sha256,
  done: row.done,
  complete: row.complete === 1,
  verifying: false,
});

export const makeDrop = (fields: Omit<DropRecord, "byId">): DropRecord => ({
  ...fields,
  byId: new Map(fields.files.map((file) => [file.id, file])),
});

export class DropDb {
  private readonly db: Database;
  private readonly statements: Record<
    | "insertDrop"
    | "insertFile"
    | "saveDrop"
    | "saveFile"
    | "deleteDrop"
    | "insertTicket"
    | "trimTickets"
    | "findTicket"
    | "pruneTickets",
    Statement
  >;

  constructor(db: Database) {
    this.db = db;
    const prepare = (sql: string) => db.prepare(sql);
    this.statements = {
      insertDrop: prepare(
        `INSERT INTO drops (id, device_id, incoming, from_json, to_json, state, route, created_at, updated_at, started_at, error)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ),
      insertFile: prepare(
        `INSERT INTO drop_files (drop_id, id, ord, name, path, size, mime, sha256, done, complete, parts, origin)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ),
      saveDrop: prepare("UPDATE drops SET state = ?, route = ?, updated_at = ?, started_at = ?, error = ? WHERE id = ?"),
      saveFile: prepare("UPDATE drop_files SET sha256 = ?, done = ?, complete = ?, parts = ? WHERE drop_id = ? AND id = ?"),
      deleteDrop: prepare("DELETE FROM drops WHERE id = ?"),
      insertTicket: prepare("INSERT INTO drop_tickets (hash, drop_id, device_id, expires_at) VALUES (?, ?, ?, ?)"),
      trimTickets: prepare(
        `DELETE FROM drop_tickets WHERE drop_id = ? AND hash NOT IN
         (SELECT hash FROM drop_tickets WHERE drop_id = ? ORDER BY expires_at DESC LIMIT ?)`,
      ),
      findTicket: prepare("SELECT drop_id, device_id, expires_at FROM drop_tickets WHERE hash = ?"),
      pruneTickets: prepare("DELETE FROM drop_tickets WHERE expires_at < ?"),
    };
  }

  insert(drop: DropRecord): void {
    this.db.transaction(() => {
      this.statements.insertDrop.run(
        drop.id,
        drop.deviceId,
        drop.incoming ? 1 : 0,
        encodePeer(drop.from),
        encodePeer(drop.to),
        drop.state,
        drop.route,
        drop.createdAt,
        drop.updatedAt,
        drop.startedAt,
        drop.error,
      );
      drop.files.forEach((file, order) => {
        this.statements.insertFile.run(
          drop.id,
          file.id,
          order,
          file.name,
          file.path,
          file.size,
          file.mime,
          file.sha256,
          file.done,
          file.complete ? 1 : 0,
          toBitmap(file.parts),
          file.origin,
        );
      });
    })();
  }

  saveDrop(drop: DropRecord): void {
    this.statements.saveDrop.run(drop.state, drop.route, drop.updatedAt, drop.startedAt, drop.error, drop.id);
  }

  saveFile(dropId: string, file: DropFileRecord): void {
    this.statements.saveFile.run(file.sha256, file.done, file.complete ? 1 : 0, toBitmap(file.parts), dropId, file.id);
  }

  delete(id: string): void {
    this.statements.deleteDrop.run(id);
  }

  loadAll(): Array<DropRecord> {
    const files = new Map<string, Array<DropFileRecord>>();
    for (const row of this.db.query<FileRow, []>("SELECT * FROM drop_files ORDER BY drop_id, ord").all()) {
      const list = files.get(row.drop_id) ?? [];
      list.push(toFile(row));
      files.set(row.drop_id, list);
    }
    return this.db
      .query<DropRow, []>("SELECT * FROM drops ORDER BY created_at")
      .all()
      .map((row) =>
        makeDrop({
          id: decodeDropId(row.id),
          deviceId: decodeDeviceId(row.device_id),
          incoming: row.incoming === 1,
          from: decodePeer(row.from_json),
          to: decodePeer(row.to_json),
          files: files.get(row.id) ?? [],
          createdAt: row.created_at,
          state: decodeState(row.state),
          route: toRoute(row.route),
          updatedAt: row.updated_at,
          startedAt: row.started_at,
          error: row.error,
        }),
      );
  }

  insertTicket(hash: Uint8Array, grant: TicketGrant, keep: number): void {
    this.db.transaction(() => {
      this.statements.insertTicket.run(hash, grant.dropId, grant.deviceId, grant.expiresAt);
      this.statements.trimTickets.run(grant.dropId, grant.dropId, keep);
    })();
  }

  ticket(hash: Uint8Array): TicketGrant | null {
    const row = this.statements.findTicket.get(hash) as TicketRow | null;
    return row === null ? null : { dropId: row.drop_id, deviceId: row.device_id, expiresAt: row.expires_at };
  }

  pruneTickets(now: number): void {
    this.statements.pruneTickets.run(now);
  }
}
