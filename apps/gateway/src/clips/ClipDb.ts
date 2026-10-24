import type { Database } from "bun:sqlite";
import { type ClipKind, type ClipStats, Clip, ClipFileName } from "@vitals/contracts";
import * as Schema from "effect/Schema";

/** A clip as stored: the wire `Clip` plus where its bytes live on disk. */
export const ClipRecord = Schema.Struct({
  ...Clip.fields,
  /** File inside `clips/`, once the bytes exist there. */
  stored: Schema.NullOr(ClipFileName),
  /** Mac path of a copied file or folder, materialized into `stored` on first download. */
  origin: Schema.NullOr(Schema.String),
  /** Hex sha256 of `stored`, when hashed. Used to spot repeat copies of the same image. */
  sha256: Schema.NullOr(Schema.String),
  pushed: Schema.Boolean,
});
export type ClipRecord = typeof ClipRecord.Type;

interface ClipRow {
  readonly id: string;
  readonly kind: string;
  readonly at: number;
  readonly device_id: string | null;
  readonly source: string | null;
  readonly text: string | null;
  readonly truncated: number;
  readonly name: string | null;
  readonly mime: string | null;
  readonly bytes: number;
  readonly files: number | null;
  readonly thumb: string | null;
  readonly pinned: number;
  readonly stored: string | null;
  readonly origin: string | null;
  readonly sha256: string | null;
  readonly pushed: number;
}

const decodeRecord = Schema.decodeUnknownSync(ClipRecord);

const toRecord = (row: ClipRow): ClipRecord =>
  decodeRecord({
    id: row.id,
    kind: row.kind,
    at: row.at,
    deviceId: row.device_id,
    source: row.source,
    text: row.text,
    truncated: row.truncated === 1,
    name: row.name,
    mime: row.mime,
    bytes: row.bytes,
    files: row.files,
    thumb: row.thumb,
    pinned: row.pinned === 1,
    stored: row.stored,
    origin: row.origin,
    sha256: row.sha256,
    pushed: row.pushed === 1,
  });

/** Synchronous SQL for the `clips` table in remote.db. Knows nothing about files or events. */
export class ClipDb {
  private readonly db: Database;

  constructor(db: Database) {
    this.db = db;
  }

  get(id: string): ClipRecord | null {
    const row = this.db.query<ClipRow, [string]>("SELECT * FROM clips WHERE id = ?").get(id);
    return row === null ? null : toRecord(row);
  }

  /** Newest first. With `includeMac` false, only clips phones sent and clips the Mac pushed. */
  recent(limit: number, includeMac: boolean): ReadonlyArray<ClipRecord> {
    const sql = includeMac
      ? "SELECT * FROM clips ORDER BY at DESC, id DESC LIMIT ?"
      : "SELECT * FROM clips WHERE device_id IS NOT NULL OR pushed = 1 ORDER BY at DESC, id DESC LIMIT ?";
    return this.db.query<ClipRow, [number]>(sql).all(limit).map(toRecord);
  }

  /** An earlier clip with the same content, by the strongest key the new clip has. */
  findDuplicate(clip: Pick<ClipRecord, "kind" | "text" | "truncated" | "origin" | "sha256">): ClipRecord | null {
    const find = (sql: string, ...params: Array<string>) => {
      const row = this.db.query<ClipRow, Array<string>>(sql).get(...params);
      return row === null ? null : toRecord(row);
    };
    if (clip.sha256 !== null) return find("SELECT * FROM clips WHERE sha256 = ? AND kind = ?", clip.sha256, clip.kind);
    if (clip.origin !== null) return find("SELECT * FROM clips WHERE origin = ? AND kind = ?", clip.origin, clip.kind);
    if (clip.text !== null && !clip.truncated && isTextKind(clip.kind)) {
      return find("SELECT * FROM clips WHERE text = ? AND kind = ? AND truncated = 0", clip.text, clip.kind);
    }
    return null;
  }

  insert(clip: ClipRecord): void {
    this.db.run(
      `INSERT INTO clips (id, kind, at, device_id, source, text, truncated, name, mime, bytes, files, thumb, pinned, stored, origin, sha256, pushed)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        clip.id,
        clip.kind,
        clip.at,
        clip.deviceId,
        clip.source,
        clip.text,
        clip.truncated ? 1 : 0,
        clip.name,
        clip.mime,
        clip.bytes,
        clip.files,
        clip.thumb,
        clip.pinned ? 1 : 0,
        clip.stored,
        clip.origin,
        clip.sha256,
        clip.pushed ? 1 : 0,
      ],
    );
  }

  /** Writes back the fields that change after insert. */
  update(clip: ClipRecord): void {
    this.db.run("UPDATE clips SET at = ?, pinned = ?, pushed = ?, stored = ?, bytes = ?, files = ?, thumb = ?, name = ? WHERE id = ?", [
      clip.at,
      clip.pinned ? 1 : 0,
      clip.pushed ? 1 : 0,
      clip.stored,
      clip.bytes,
      clip.files,
      clip.thumb,
      clip.name,
      clip.id,
    ]);
  }

  delete(ids: ReadonlyArray<string>): void {
    const remove = this.db.prepare("DELETE FROM clips WHERE id = ?");
    this.db.transaction(() => {
      for (const id of ids) remove.run(id);
    })();
  }

  unpinnedOldestFirst(): ReadonlyArray<ClipRecord> {
    return this.db.query<ClipRow, []>("SELECT * FROM clips WHERE pinned = 0 ORDER BY at, id").all().map(toRecord);
  }

  storedNames(): ReadonlySet<string> {
    const rows = this.db.query<{ stored: string }, []>("SELECT stored FROM clips WHERE stored IS NOT NULL").all();
    return new Set(rows.map((row) => row.stored));
  }

  stats(): ClipStats {
    const row = this.db
      .query<{ clips: number; pinned: number | null; bytes: number | null }, []>(
        "SELECT count(*) AS clips, sum(pinned) AS pinned, sum(CASE WHEN stored IS NULL THEN 0 ELSE bytes END) AS bytes FROM clips",
      )
      .get();
    return { clips: row?.clips ?? 0, pinned: row?.pinned ?? 0, bytes: row?.bytes ?? 0 };
  }
}

export const isTextKind = (kind: ClipKind): kind is "text" | "link" => kind === "text" || kind === "link";

const RETENTION = { rows: 500, bytes: 2 * 1024 ** 3 } as const;

/**
 * Which unpinned clips to drop, oldest first: anything older than `cutoff`, then enough to get
 * under the row cap, then enough stored files to get under the byte cap. Pinned clips are never
 * dropped: they aren't in `unpinned`, though they do count toward the totals.
 */
export const expired = (
  unpinned: ReadonlyArray<ClipRecord>,
  totals: ClipStats,
  cutoff: number | null,
): ReadonlyArray<ClipRecord> => {
  const doomed = new Set(unpinned.filter((clip) => cutoff !== null && clip.at < cutoff));
  const size = (clip: ClipRecord) => (clip.stored === null ? 0 : clip.bytes);
  let rows = totals.clips - doomed.size;
  let bytes = totals.bytes - [...doomed].reduce((sum, clip) => sum + size(clip), 0);
  for (const clip of unpinned) {
    if (rows <= RETENTION.rows) break;
    if (doomed.has(clip)) continue;
    doomed.add(clip);
    rows -= 1;
    bytes -= size(clip);
  }
  for (const clip of unpinned) {
    if (bytes <= RETENTION.bytes) break;
    if (doomed.has(clip) || size(clip) === 0) continue;
    doomed.add(clip);
    bytes -= size(clip);
  }
  return [...doomed];
};
