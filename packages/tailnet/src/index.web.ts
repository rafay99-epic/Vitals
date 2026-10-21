export interface TailnetState {
  readonly backend: string;
  readonly loginUrl: string | null;
}

export const tailnetSupported = false;

export const startTailnet = async (_hostname: string): Promise<void> => {};

export const tailnetState = async (): Promise<TailnetState> => ({ backend: "Unsupported", loginUrl: null });

export const forwardTo = async (_target: string): Promise<number> => 0;

export const stopTailnet = async (): Promise<void> => {};
