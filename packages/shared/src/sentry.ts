export type SentryApp = "gateway" | "remote";
export type SentryChannel = "stable" | "nightly" | "dev";

const PROJECTS: Record<SentryApp, { readonly prod: string; readonly nightly: string }> = {
  gateway: {
    prod: "https://6d258fdca2210b1a67d0f102a7c5a0cc@o4512219615920128.ingest.us.sentry.io/4512333741359104",
    nightly: "https://21b5c2457a8d58b6745a80642e50506f@o4512219615920128.ingest.us.sentry.io/4512333983383552",
  },
  remote: {
    prod: "https://5be678c5d702791317b48ef1ba197a04@o4512219615920128.ingest.us.sentry.io/4512333352861696",
    nightly: "https://1f83005752755c77e49b385091138d40@o4512219615920128.ingest.us.sentry.io/4512333983055872",
  },
};

export const sentryDsn = (app: SentryApp, channel: SentryChannel): string => (channel === "stable" ? PROJECTS[app].prod : PROJECTS[app].nightly);
