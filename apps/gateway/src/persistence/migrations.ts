import type { Migration } from "./sqlite.ts";

export const REMOTE_MIGRATIONS: ReadonlyArray<Migration> = [
  {
    id: 1,
    sql: `
      CREATE TABLE devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        platform TEXT NOT NULL,
        model TEXT NOT NULL,
        app_version TEXT NOT NULL,
        scopes TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_seen_at INTEGER,
        revoked_at INTEGER
      );
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        token_hash BLOB NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        last_used_at INTEGER,
        revoked_at INTEGER
      );
      CREATE INDEX sessions_device ON sessions(device_id);
      CREATE TABLE pairing_grants (
        id TEXT PRIMARY KEY,
        code_hash BLOB NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        consumed_at INTEGER,
        device_id TEXT REFERENCES devices(id) ON DELETE SET NULL
      );
      CREATE TABLE commands (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        args_json TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        deadline_at INTEGER,
        finished_at INTEGER,
        error TEXT
      );
      CREATE INDEX commands_created ON commands(created_at);
    `,
  },
  {
    id: 2,
    sql: `
      ALTER TABLE devices ADD COLUMN lan_key TEXT;
      CREATE UNIQUE INDEX devices_lan_key ON devices(lan_key) WHERE lan_key IS NOT NULL AND revoked_at IS NULL;
    `,
  },
];

export const ACTIVITY_MIGRATIONS: ReadonlyArray<Migration> = [
  {
    id: 1,
    sql: `
      CREATE TABLE events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        at INTEGER NOT NULL,
        received_at INTEGER NOT NULL,
        source TEXT NOT NULL,
        level TEXT NOT NULL,
        kind TEXT NOT NULL,
        device_id TEXT,
        connection_id TEXT,
        rpc TEXT,
        command_id TEXT,
        duration_ms REAL,
        data_json TEXT NOT NULL
      );
      CREATE INDEX events_at ON events(at);
      CREATE INDEX events_kind_at ON events(kind, at);
      CREATE INDEX events_device_at ON events(device_id, at);
      CREATE INDEX events_cmd ON events(command_id) WHERE command_id IS NOT NULL;
      CREATE TABLE connections (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        close_reason TEXT,
        ts_login TEXT,
        client_version TEXT,
        msgs_in INTEGER NOT NULL DEFAULT 0,
        msgs_out INTEGER NOT NULL DEFAULT 0,
        bytes_in INTEGER NOT NULL DEFAULT 0,
        bytes_out INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX connections_opened ON connections(opened_at);
      CREATE TABLE frames (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        connection_id TEXT NOT NULL,
        at INTEGER NOT NULL,
        dir TEXT NOT NULL,
        rpc_id TEXT,
        method TEXT,
        tag TEXT NOT NULL,
        bytes INTEGER NOT NULL
      );
      CREATE INDEX frames_conn_seq ON frames(connection_id, seq);
      CREATE INDEX frames_at ON frames(at);
      CREATE TABLE system_events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        at INTEGER NOT NULL,
        event_json TEXT NOT NULL
      );
      CREATE INDEX system_events_at ON system_events(at);
      CREATE TABLE rollups_minute (
        minute INTEGER NOT NULL,
        kind TEXT NOT NULL,
        count INTEGER NOT NULL,
        errors INTEGER NOT NULL,
        PRIMARY KEY (minute, kind)
      );
    `,
  },
];
