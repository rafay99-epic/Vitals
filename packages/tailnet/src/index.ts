import { requireOptionalNativeModule } from "expo";

interface NativeTailnet {
  start(hostname: string): Promise<void>;
  state(): Promise<string>;
  forward(target: string): Promise<number>;
  stop(): Promise<void>;
}

export interface TailnetState {
  readonly backend: string;
  readonly loginUrl: string | null;
}

const native = requireOptionalNativeModule<NativeTailnet>("VitalsTailnet");

export const tailnetSupported = native !== null;

const unavailable = (): never => {
  throw new Error("Built-in Tailscale is not in this build");
};

export const startTailnet = async (hostname: string): Promise<void> => (native === null ? unavailable() : native.start(hostname));

export const tailnetState = async (): Promise<TailnetState> => {
  if (native === null) return { backend: "Unsupported", loginUrl: null };
  const [backend = "NoState", url = ""] = (await native.state()).split("|");
  return { backend, loginUrl: url.length > 0 ? url : null };
};

export const forwardTo = async (target: string): Promise<number> => (native === null ? unavailable() : native.forward(target));

export const stopTailnet = async (): Promise<void> => {
  await native?.stop();
};
