import {
  type CommandReceipt,
  type CommandRunInput,
  type Device,
  CommandRejected,
  TERMINAL_STATUSES,
  Unavailable,
} from "@vitals/contracts";
import * as Context from "effect/Context";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { EventLog } from "../events/EventLog.ts";
import { Store } from "../persistence/Store.ts";

const RECEIPT_TIMEOUT = "5 seconds";
const LOG_REPLAY = 50;
/** How long past its deadline a countdown may stay open before a restart closes it. */
const OVERDUE_GRACE_MS = 10_000;

type Caller = Pick<Device, "id" | "name">;

export class CommandService extends Context.Service<
  CommandService,
  {
    readonly run: (caller: Caller, input: CommandRunInput) => Effect.Effect<CommandReceipt, Unavailable>;
    readonly cancel: (caller: Caller, id: CommandReceipt["id"]) => Effect.Effect<CommandReceipt, CommandRejected>;
    readonly log: Stream.Stream<CommandReceipt>;
  }
>()("@vitals/gateway/CommandService") {}

export const layer = Layer.effect(
  CommandService,
  Effect.gen(function* () {
    const bridge = yield* Bridge;
    const store = yield* Store;
    const events = yield* EventLog;
    const activity = yield* ActivityLog;
    const hub = yield* PubSub.unbounded<CommandReceipt>();
    const waiters = new Map<string, Array<Deferred.Deferred<CommandReceipt>>>();
    const serviceScope = yield* Effect.scope;

    const settle = (receipt: CommandReceipt) =>
      Effect.gen(function* () {
        store.updateCommand(receipt);
        const waiting = waiters.get(receipt.id) ?? [];
        waiters.delete(receipt.id);
        for (const waiter of waiting) yield* Deferred.succeed(waiter, receipt);
        yield* PubSub.publish(hub, receipt);
        yield* events.append({ _tag: "CommandUpdated", at: Date.now(), receipt });
      });

    yield* bridge.messages.pipe(
      Stream.runForEach((message) => (message.t === "receipt" ? settle(message.receipt) : Effect.void)),
      Effect.forkScoped,
    );

    // A shut down or restart takes this gateway down with the Mac, often before its final receipt
    // is written. Close those countdowns, or every phone replays them as "Shutting down in 0 s".
    const startedAt = Date.now();
    for (const receipt of store.overdueCommands(startedAt - OVERDUE_GRACE_MS)) {
      yield* settle({ ...receipt, status: "failed", finishedAt: startedAt, error: "Not confirmed: Vitals restarted after the countdown" });
    }

    const awaitReceipt = <E>(id: string, onTimeout: Effect.Effect<CommandReceipt, E>) =>
      Effect.gen(function* () {
        const waiter = yield* Deferred.make<CommandReceipt>();
        waiters.set(id, [...(waiters.get(id) ?? []), waiter]);
        const settled = Deferred.await(waiter).pipe(
          Effect.timeoutOrElse({
            duration: RECEIPT_TIMEOUT,
            orElse: () =>
              Effect.suspend(() => {
                const rest = (waiters.get(id) ?? []).filter((item) => item !== waiter);
                if (rest.length === 0) waiters.delete(id);
                else waiters.set(id, rest);
                return onTimeout;
              }),
          }),
        );
        return yield* Effect.forkIn(settled, serviceScope);
      });

    const run = (caller: Caller, input: CommandRunInput) =>
      Effect.gen(function* () {
        yield* bridge.identity;
        const now = Date.now();
        const existing = store.insertCommand(input.commandId, caller.id, input.command._tag, input.command, now);
        if (existing !== null) return existing;
        activity.record({
          at: now,
          source: "gateway",
          level: "info",
          kind: "command.requested",
          deviceId: caller.id,
          commandId: input.commandId,
          data: { kind: input.command._tag },
        });
        const pending = yield* awaitReceipt(
          input.commandId,
          Effect.suspend(() => {
            const failed: CommandReceipt = {
              id: input.commandId,
              kind: input.command._tag,
              deviceId: caller.id,
              status: "failed",
              createdAt: now,
              deadlineAt: null,
              finishedAt: Date.now(),
              error: "Vitals did not acknowledge the command",
            };
            return Effect.as(settle(failed), failed);
          }),
        );
        yield* bridge.send({
          t: "cmd",
          id: input.commandId,
          deviceId: caller.id,
          deviceName: caller.name,
          command: input.command,
        });
        return yield* Fiber.join(pending);
      });

    const cancel = (caller: Caller, id: CommandReceipt["id"]) =>
      Effect.gen(function* () {
        const current = store.command(id);
        if (current === null) return yield* Effect.fail(new CommandRejected({ message: "Unknown command" }));
        if (TERMINAL_STATUSES.has(current.status)) return current;
        activity.record({
          at: Date.now(),
          source: "gateway",
          level: "info",
          kind: "command.cancelRequested",
          deviceId: caller.id,
          commandId: id,
          data: {},
        });
        const pending = yield* awaitReceipt(id, Effect.fail(new CommandRejected({ message: "Vitals did not confirm the cancel" })));
        yield* bridge.send({ t: "cancel", id });
        return yield* Fiber.join(pending);
      });

    const log = Stream.unwrap(
      Effect.gen(function* () {
        const subscription = yield* PubSub.subscribe(hub);
        const recent = store.recentCommands(LOG_REPLAY).toReversed();
        return Stream.concat(Stream.fromIterable(recent), Stream.fromSubscription(subscription));
      }),
    );

    return CommandService.of({ run, cancel, log });
  }),
);
