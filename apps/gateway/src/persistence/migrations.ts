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
  {
    id: 3,
    sql: `
      CREATE TABLE clips (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        at INTEGER NOT NULL,
        device_id TEXT,
        source TEXT,
        text TEXT,
        truncated INTEGER NOT NULL DEFAULT 0,
        name TEXT,
        mime TEXT,
        bytes INTEGER NOT NULL DEFAULT 0,
        files INTEGER,
        thumb TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        stored TEXT,
        origin TEXT,
        sha256 TEXT
      );
      CREATE INDEX clips_at ON clips(at);
    `,
  },
  {
    id: 4,
    sql: `
      UPDATE devices SET scopes = json_insert(scopes, '$[#]', 'files')
      WHERE EXISTS (SELECT 1 FROM json_each(devices.scopes) WHERE value = 'operate')
        AND NOT EXISTS (SELECT 1 FROM json_each(devices.scopes) WHERE value = 'files');
    `,
  },
  {
    id: 5,
    sql: "ALTER TABLE clips ADD COLUMN pushed INTEGER NOT NULL DEFAULT 0;",
  },
  {
    id: 6,
    sql: `
      CREATE TABLE drops (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        incoming INTEGER NOT NULL,
        from_json TEXT NOT NULL,
        to_json TEXT NOT NULL,
        state TEXT NOT NULL,
        route TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        started_at INTEGER,
        error TEXT
      );
      CREATE TABLE drop_files (
        drop_id TEXT NOT NULL REFERENCES drops(id) ON DELETE CASCADE,
        id TEXT NOT NULL,
        ord INTEGER NOT NULL,
        name TEXT NOT NULL,
        path TEXT,
        size INTEGER NOT NULL,
        mime TEXT,
        sha256 TEXT,
        done INTEGER NOT NULL DEFAULT 0,
        complete INTEGER NOT NULL DEFAULT 0,
        parts BLOB,
        origin TEXT,
        PRIMARY KEY (drop_id, id)
      );
      CREATE TABLE drop_tickets (
        hash BLOB PRIMARY KEY,
        drop_id TEXT NOT NULL REFERENCES drops(id) ON DELETE CASCADE,
        device_id TEXT NOT NULL,
        expires_at INTEGER NOT NULL
      );
      CREATE INDEX drop_tickets_drop ON drop_tickets(drop_id, expires_at);
    `,
  },
  {
    id: 7,
    sql: `
      ALTER TABLE drops ADD COLUMN dest TEXT;
      UPDATE devices SET scopes = json_insert(scopes, '$[#]', 'fsRead')
      WHERE platform != 'web'
        AND EXISTS (SELECT 1 FROM json_each(devices.scopes) WHERE value = 'files')
        AND NOT EXISTS (SELECT 1 FROM json_each(devices.scopes) WHERE value = 'fsRead');
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
