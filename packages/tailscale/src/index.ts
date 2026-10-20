export interface CommandResult {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

export type Runner = (args: ReadonlyArray<string>, timeoutMs: number) => Promise<CommandResult>;

export interface TailscaleStatus {
  readonly running: boolean;
  readonly dnsName: string | null;
  readonly ownerLogin: string | null;
  readonly magicDns: boolean;
}

const CANDIDATES = [
  "/usr/local/bin/tailscale",
  "/opt/homebrew/bin/tailscale",
  "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
] as const;

export const findBinary = async (exists: (path: string) => Promise<boolean>): Promise<string | null> => {
  for (const candidate of CANDIDATES) {
    if (await exists(candidate)) return candidate;
  }
  return null;
};

export const bunRunner =
  (binary: string): Runner =>
  async (args, timeoutMs) => {
    try {
      const child = Bun.spawn([binary, ...args], { stdout: "pipe", stderr: "pipe", stdin: "ignore", timeout: timeoutMs });
      const [stdout, stderr, code] = await Promise.all([
        new Response(child.stdout).text(),
        new Response(child.stderr).text(),
        child.exited,
      ]);
      return { code, stdout, stderr };
    } catch (error) {
      return { code: -1, stdout: "", stderr: String(error) };
    }
  };

interface RawStatus {
  readonly BackendState?: string;
  readonly MagicDNSSuffix?: string;
  readonly CurrentTailnet?: { readonly MagicDNSEnabled?: boolean } | null;
  readonly Self?: { readonly DNSName?: string; readonly UserID?: number } | null;
  readonly User?: Readonly<Record<string, { readonly LoginName?: string }>> | null;
}

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null;

const parseJson = (json: string): unknown => {
  try {
    return JSON.parse(json);
  } catch {
    return null;
  }
};

export const parseStatus = (json: string): TailscaleStatus => {
  const parsed = parseJson(json);
  if (!isRecord(parsed)) return { running: false, dnsName: null, ownerLogin: null, magicDns: false };
  const raw: RawStatus = parsed;
  const dnsName = raw.Self?.DNSName?.replace(/\.$/, "") ?? null;
  const userId = raw.Self?.UserID;
  const ownerLogin = userId === undefined ? null : (raw.User?.[String(userId)]?.LoginName ?? null);
  return {
    running: raw.BackendState === "Running",
    dnsName: dnsName === "" ? null : dnsName,
    ownerLogin,
    magicDns: raw.CurrentTailnet?.MagicDNSEnabled ?? false,
  };
};

export const status = async (run: Runner): Promise<TailscaleStatus> => {
  const result = await run(["status", "--json", "--peers=false"], 3_500);
  if (result.code !== 0) return { running: false, dnsName: null, ownerLogin: null, magicDns: false };
  return parseStatus(result.stdout);
};

export const serveOn = async (run: Runner, httpsPort: number, localPort: number): Promise<CommandResult> =>
  run(["serve", "--bg", `--https=${httpsPort}`, `http://127.0.0.1:${localPort}`], 15_000);

export const parseServeTarget = (json: string, httpsPort: number): string | null => {
  const parsed = parseJson(json);
  if (!isRecord(parsed) || !isRecord(parsed["Web"])) return null;
  for (const [host, site] of Object.entries(parsed["Web"])) {
    if (!host.endsWith(`:${httpsPort}`) || !isRecord(site) || !isRecord(site["Handlers"])) continue;
    const root = site["Handlers"]["/"];
    if (isRecord(root) && typeof root["Proxy"] === "string") return root["Proxy"];
  }
  return null;
};

export const isServing = async (run: Runner, httpsPort: number, localPort: number): Promise<boolean> => {
  const result = await run(["serve", "status", "--json"], 3_500);
  return result.code === 0 && parseServeTarget(result.stdout, httpsPort) === `http://127.0.0.1:${localPort}`;
};

export const serveOff = async (run: Runner, httpsPort: number): Promise<CommandResult> =>
  run(["serve", `--https=${httpsPort}`, "off"], 15_000);

export const httpsUrl = (dnsName: string, httpsPort: number): string =>
  httpsPort === 443 ? `https://${dnsName}` : `https://${dnsName}:${httpsPort}`;
