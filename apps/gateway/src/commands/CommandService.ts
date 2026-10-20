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
import * as Layer from "effect/Layer";
import * as PubSub from "effect/PubSub";
import * as Stream from "effect/Stream";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Bridge } from "../bridge/Bridge.ts";
import { EventLog } from "../events/EventLog.ts";
import { Store } from "../persistence/Store.ts";

const RECEIPT_TIMEOUT = "5 seconds";
const LOG_REPLAY = 50;

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
    const waiters = new Map<string, Deferred.Deferred<CommandReceipt>>();

    const settle = (receipt: CommandReceipt) =>
      Effect.gen(function* () {
        store.updateCommand(receipt);
        const waiter = waiters.get(receipt.id);
        if (waiter !== undefined) {
          waiters.delete(receipt.id);
          yield* Deferred.succeed(waiter, receipt);
        }
        yield* PubSub.publish(hub, receipt);
        yield* events.append({ _tag: "CommandUpdated", at: Date.now(), receipt });
      });

    yield* bridge.messages.pipe(
      Stream.runForEach((message) => (message.t === "receipt" ? settle(message.receipt) : Effect.void)),
      Effect.forkScoped,
    );

    const awaitReceipt = (id: string, onTimeout: () => CommandReceipt) =>
      Effect.gen(function* () {
        const waiter = yield* Deferred.make<CommandReceipt>();
        waiters.set(id, waiter);
        return waiter;
      }).pipe(
        Effect.flatMap((waiter) =>
          Deferred.await(waiter).pipe(
            Effect.timeoutOrElse({
              duration: RECEIPT_TIMEOUT,
              orElse: () =>
                Effect.gen(function* () {
                  waiters.delete(id);
                  const failed = onTimeout();
                  yield* settle(failed);
                  return failed;
                }),
            }),
          ),
        ),
      );

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
        const pending = awaitReceipt(input.commandId, () => ({
          id: input.commandId,
          kind: input.command._tag,
          deviceId: caller.id,
          status: "failed",
          createdAt: now,
          deadlineAt: null,
          finishedAt: Date.now(),
          error: "Vitals did not acknowledge the command",
        }));
        yield* bridge.send({
          t: "cmd",
          id: input.commandId,
          deviceId: caller.id,
          deviceName: caller.name,
          command: input.command,
        });
        return yield* pending;
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
        const pending = awaitReceipt(id, () => current);
        yield* bridge.send({ t: "cancel", id });
        return yield* pending;
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
