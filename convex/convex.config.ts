import { defineApp } from 'convex/server'
import rateLimiter from '@convex-dev/rate-limiter/convex.config'

/// The rate-limiter component keeps its own internal storage, so we can use it
/// without adding a host-app schema. This stays a schema-less, table-less live
/// proxy to GitHub — the component is the only persistent state in the backend.
const app = defineApp()
app.use(rateLimiter)
export default app
