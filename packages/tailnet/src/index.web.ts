export interface TailnetState {
  readonly backend: string;
  readonly loginUrl: string | null;
}

export const tailnetSupported = false;

export const startTailnet = async (_hostname: string): Promise<void> => {};

export const tailnetState = async (): Promise<TailnetState> => ({ backend: "Unsupported", loginUrl: null });

export const loginTailnet = async (): Promise<void> => {};

export const tailnetNetworkChanged = async (): Promise<void> => {};

export const forwardTo = async (_target: string): Promise<number> => 0;

export const stopTailnet = async (): Promise<void> => {};

export const signOutTailnet = async (): Promise<void> => {};
