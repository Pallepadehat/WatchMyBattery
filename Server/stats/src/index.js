// WatchMyBattery's opt-in install count: a Cloudflare Worker with a D1 database, on Cloudflare's free plan.
//
//   POST   /v1/ping            {"id": "<uuid>", "version": "0.4.2", "macOS": "15.1"}   → 204
//   DELETE /v1/installs/<uuid>                                                        → 204
//   GET    /v1/stats           Authorization: Bearer <STATS_TOKEN>                    → JSON
//
// The app sends a ping at most once a day, and only after the person turned "Count This Mac" on. Only what the
// ping says is stored, with the day it was first and last seen: no IP address, no headers, no location. The Worker
// logs nothing (observability is off in wrangler.toml).

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const VERSION = /^[0-9A-Za-z.+-]{1,32}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "");
    try {
      if (request.method === "POST" && path === "/v1/ping") return await ping(request, env);
      if (request.method === "DELETE" && path.startsWith("/v1/installs/")) return await forget(path.slice("/v1/installs/".length), env);
      if (request.method === "GET" && path === "/v1/stats") return await stats(request, env);
      return new Response("Not found", { status: 404 });
    } catch {
      return new Response("Something went wrong", { status: 500 });
    }
  },
};

async function ping(request, env) {
  if (Number(request.headers.get("content-length") ?? 0) > 1024) return new Response("Too large", { status: 413 });
  let body;
  try {
    body = await request.json();
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }
  const { id, version, macOS } = body ?? {};
  if (typeof id !== "string" || !UUID.test(id) || typeof version !== "string" || !VERSION.test(version)
    || typeof macOS !== "string" || !VERSION.test(macOS)) {
    return new Response("Bad ping", { status: 400 });
  }
  const today = new Date().toISOString().slice(0, 10);
  await env.DB.prepare(
    `INSERT INTO installs (id, first_seen, last_seen, version, macos) VALUES (?1, ?2, ?2, ?3, ?4)
     ON CONFLICT (id) DO UPDATE SET last_seen = ?2, version = ?3, macos = ?4`,
  ).bind(id, today, version, macOS).run();
  return new Response(null, { status: 204 });
}

async function forget(id, env) {
  if (!UUID.test(id)) return new Response("Bad ID", { status: 400 });
  await env.DB.prepare("DELETE FROM installs WHERE id = ?1").bind(id).run();
  return new Response(null, { status: 204 });
}

async function stats(request, env) {
  const token = env.STATS_TOKEN;
  if (!token || request.headers.get("authorization") !== `Bearer ${token}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  const day = (daysAgo) => new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);
  const [totals, versions, macOS, firstSeen] = await env.DB.batch([
    env.DB.prepare(
      `SELECT COUNT(*) AS installs,
              SUM(last_seen >= ?1) AS active1,
              SUM(last_seen >= ?2) AS active7,
              SUM(last_seen >= ?3) AS active30
       FROM installs`,
    ).bind(day(1), day(7), day(30)),
    // Versions and macOS of the Macs seen in the last 30 days.
    env.DB.prepare("SELECT version, COUNT(*) AS count FROM installs WHERE last_seen >= ?1 GROUP BY version ORDER BY count DESC").bind(day(30)),
    env.DB.prepare("SELECT macos, COUNT(*) AS count FROM installs WHERE last_seen >= ?1 GROUP BY macos ORDER BY count DESC").bind(day(30)),
    // New Macs a day, over the last 30 days.
    env.DB.prepare("SELECT first_seen AS day, COUNT(*) AS count FROM installs WHERE first_seen >= ?1 GROUP BY first_seen ORDER BY first_seen").bind(day(30)),
  ]);
  const t = totals.results[0];
  return Response.json({
    installs: t.installs,
    activeToday: t.active1 ?? 0,
    activeLast7Days: t.active7 ?? 0,
    activeLast30Days: t.active30 ?? 0,
    versions: versions.results,
    macOS: macOS.results,
    newPerDay: firstSeen.results,
  });
}
