import { requireOptionalNativeModule } from "expo";

interface NativeTailnet {
  start(hostname: string): Promise<void>;
  state(): Promise<string>;
  login(): Promise<void>;
  networkChanged(): Promise<void>;
  forward(target: string): Promise<number>;
  stop(): Promise<void>;
  signOut(): Promise<void>;
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

/** Asks for a new sign-in URL when a saved node lost its login (key expired, node removed). */
export const loginTailnet = async (): Promise<void> => (native === null ? unavailable() : native.login());

/** Tells the node the phone switched networks; the native side reads the new default interface. */
export const tailnetNetworkChanged = async (): Promise<void> => {
  await native?.networkChanged();
};

export const forwardTo = async (target: string): Promise<number> => (native === null ? unavailable() : native.forward(target));

export const stopTailnet = async (): Promise<void> => {
  await native?.stop();
};

/** Logs out, stops the node and deletes its saved login, so the next start signs in fresh. */
export const signOutTailnet = async (): Promise<void> => {
  await native?.signOut();
};
