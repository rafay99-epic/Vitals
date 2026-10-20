import type { Alert } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { EventLog } from "../events/EventLog.ts";
import { Store } from "../persistence/Store.ts";

const EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send";

export type PushSender = (
  messages: ReadonlyArray<Record<string, unknown>>,
) => Promise<{ readonly ok: boolean; readonly status: number }>;

export const expoSender =
  (accessToken: string | null): PushSender =>
  async (messages) => {
    const response = await fetch(EXPO_PUSH_URL, {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        ...(accessToken === null ? {} : { authorization: `Bearer ${accessToken}` }),
      },
      body: JSON.stringify(messages),
      signal: AbortSignal.timeout(10_000),
    });
    return { ok: response.ok, status: response.status };
  };

const pushMessage = (token: string, alert: Alert) => ({
  to: token,
  title: alert.severity === "critical" ? "Mac under heavy pressure" : "Mac under pressure",
  body: "Tap to review. Calm down is one tap away.",
  data: { alertId: alert.id, kind: "pressure" },
  categoryId: "pressure",
  priority: "high",
  channelId: "pressure",
});

export const layer = (sender: PushSender) =>
  Layer.effectDiscard(
    Effect.gen(function* () {
      const events = yield* EventLog;
      const store = yield* Store;
      const activity = yield* ActivityLog;

      const deliver = (alert: Alert) =>
        Effect.gen(function* () {
          const tokens = store.pushTokens();
          if (tokens.length === 0) return;
          const result = yield* Effect.tryPromise(() => sender(tokens.map(({ token }) => pushMessage(token, alert)))).pipe(
            Effect.match({
              onFailure: (error) => ({ ok: false, status: 0, error: String(error) }),
              onSuccess: (value) => ({ ...value, error: null }),
            }),
          );
          activity.record({
            at: Date.now(),
            source: "gateway",
            level: result.ok ? "info" : "warn",
            kind: result.ok ? "alert.pushed" : "push.failed",
            data: { alertId: alert.id, devices: tokens.length, status: result.status, error: result.error },
          });
        });

      yield* events.published.pipe(
        Stream.runForEach(({ event }) => (event._tag === "AlertRaised" ? deliver(event.alert) : Effect.void)),
        Effect.forkScoped,
      );
    }),
  );
