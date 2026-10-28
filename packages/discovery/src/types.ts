export interface FoundMac {
  readonly name: string;
  readonly host: string;
  readonly port: number;
  readonly txt: Readonly<Record<string, string>>;
}

export type DiscoveryEvent =
  | { readonly _tag: "Found"; readonly mac: FoundMac }
  | { readonly _tag: "Lost"; readonly name: string }
  | { readonly _tag: "Failed"; readonly reason: string };

export type LocalNetworkPermission = "granted" | "denied" | "unsupported";
