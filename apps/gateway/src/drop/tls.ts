import { createHash, X509Certificate } from "node:crypto";
import { chmodSync, existsSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";

export interface TlsIdentity {
  readonly cert: string;
  readonly key: string;
  readonly pin: string;
}

const OPENSSL = "/usr/bin/openssl";

export const spkiPin = (certificate: string | Buffer): string =>
  createHash("sha256")
    .update(new X509Certificate(certificate).publicKey.export({ type: "spki", format: "der" }))
    .digest("base64");

const create = (keyPath: string, certPath: string): string | null => {
  const made = Bun.spawnSync(
    [
      OPENSSL,
      "req",
      "-x509",
      "-newkey",
      "ec",
      "-pkeyopt",
      "ec_paramgen_curve:prime256v1",
      "-pkeyopt",
      "ec_param_enc:named_curve",
      "-nodes",
      "-keyout",
      keyPath,
      "-out",
      certPath,
      "-days",
      "3650",
      "-subj",
      "/CN=Vitals Drop",
    ],
    { stdout: "ignore", stderr: "pipe" },
  );
  if (made.exitCode === 0) return null;
  rmSync(keyPath, { force: true });
  rmSync(certPath, { force: true });
  return made.stderr.toString().trim().slice(0, 300) || `openssl exited ${String(made.exitCode)}`;
};

export const loadTlsIdentity = (dataDir: string): TlsIdentity | { readonly error: string } => {
  const keyPath = join(dataDir, "drop-tls.key");
  const certPath = join(dataDir, "drop-tls.crt");
  try {
    if (!existsSync(keyPath) || !existsSync(certPath)) {
      const error = create(keyPath, certPath);
      if (error !== null) return { error };
    }
    chmodSync(keyPath, 0o600);
    chmodSync(certPath, 0o600);
    const cert = readFileSync(certPath, "utf8");
    return { cert, key: readFileSync(keyPath, "utf8"), pin: spkiPin(cert) };
  } catch (error) {
    return { error: String(error).slice(0, 300) };
  }
};
