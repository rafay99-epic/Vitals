const host = globalThis.navigator as { userAgent?: string; platform?: string } | undefined;
if (host) {
  host.userAgent ??= "";
  host.platform ??= "";
}
