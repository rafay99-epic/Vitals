import * as Schema from "effect/Schema";

import { DeviceId, EpochMs, NonNegativeInt } from "./ids.ts";

export const TERMINAL_LIMITS = {
  write: 65_536,
  cols: { min: 2, max: 500 },
  rows: { min: 2, max: 300 },
  perDevice: 4,
  total: 8,
  history: 400_000,
} as const;

export const TerminalId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9-]{8,64}$/)).pipe(Schema.brand("TerminalId"));
export type TerminalId = typeof TerminalId.Type;

const Cols = Schema.Int.check(Schema.isBetween({ minimum: TERMINAL_LIMITS.cols.min, maximum: TERMINAL_LIMITS.cols.max }));
const Rows = Schema.Int.check(Schema.isBetween({ minimum: TERMINAL_LIMITS.rows.min, maximum: TERMINAL_LIMITS.rows.max }));

export const TerminalSize = Schema.Struct({ cols: Cols, rows: Rows });
export type TerminalSize = typeof TerminalSize.Type;

export const TerminalInfo = Schema.Struct({
  id: TerminalId,
  title: Schema.String,
  cols: Cols,
  rows: Rows,
  startedAt: EpochMs,
  running: Schema.Boolean,
  exitCode: Schema.NullOr(Schema.Int),
  deviceId: DeviceId,
  deviceName: Schema.String,
});
export type TerminalInfo = typeof TerminalInfo.Type;

export const TerminalEvent = Schema.Union([
  Schema.TaggedStruct("Snapshot", { info: TerminalInfo, history: Schema.String }),
  Schema.TaggedStruct("Output", { data: Schema.String }),
  Schema.TaggedStruct("Exited", { code: Schema.NullOr(Schema.Int) }),
]);
export type TerminalEvent = typeof TerminalEvent.Type;

export const TerminalList = Schema.Struct({ sessions: Schema.Array(TerminalInfo) });
export type TerminalList = typeof TerminalList.Type;

export const TerminalAttachInput = Schema.Struct({ id: TerminalId, cols: Cols, rows: Rows });
export type TerminalAttachInput = typeof TerminalAttachInput.Type;

export const TerminalWriteInput = Schema.Struct({
  id: TerminalId,
  data: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(TERMINAL_LIMITS.write)),
});
export type TerminalWriteInput = typeof TerminalWriteInput.Type;

export const TerminalIdInput = Schema.Struct({ id: TerminalId });
export type TerminalIdInput = typeof TerminalIdInput.Type;

export const MacTerminal = Schema.Struct({
  id: TerminalId,
  title: Schema.String,
  deviceId: DeviceId,
  deviceName: Schema.String,
  startedAt: EpochMs,
  attached: NonNegativeInt,
});
export type MacTerminal = typeof MacTerminal.Type;
