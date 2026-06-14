/// Minimal `process.env` typing for Convex's runtime — the convex tsconfig has
/// no @types/node, and `env` isn't generated in this Convex version. Convex
/// exposes deployment environment variables (set in the dashboard) via
/// `process.env`.
declare const process: { env: Record<string, string | undefined> }
