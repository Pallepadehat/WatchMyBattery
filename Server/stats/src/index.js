// WatchMyBattery's opt-in install count: a Cloudflare Worker with a D1 database, on Cloudflare's free plan.
//
//   POST   /v1/ping            {"id": "<uuid>", "version": "0.4.2", "macOS": "15.1"}   → 204
//   DELETE /v1/installs/<uuid>                                                        → 204
//   GET    /v1/stats           Authorization: Bearer <STATS_TOKEN>                    → JSON
//
// The app sends a ping at most once a day, and only after the person turned "Count This Mac" on. Only what the
// ping says is stored, with the day it was first and last seen: no IP address, no headers, no location. The Worker
// logs nothing (observability is off in wrangler.toml).
//
// The address is in every copy of the app, so anyone can call it. What keeps that from doing harm:
// - Each IP gets a few requests a minute (the LIMITER binding). The limiter is keyed by a hash of the IP, held only in
//   Cloudflare's rate limiter for its window, never in the database.
// - At most MAX_NEW_PER_DAY new Macs a day are added, so a flood of made-up IDs can't fill the database; Macs already
//   counted keep being updated.
// - Pings must look like the app's: a UUID, and version numbers in the app's own format, in a small JSON body.
// - Deleting needs the random ID, which only that Mac knows. The stats need the token, compared in constant time.
// - "returning" counts Macs seen on two different days or more, which a one-off burst of fake pings doesn't reach.
// On the free plan, going past Cloudflare's daily limits makes requests fail rather than cost anything.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const APP_VERSION = /^\d{1,3}\.\d{1,3}(\.\d{1,3})?$/;
const MACOS_VERSION = /^\d{2}\.\d{1,2}$/;
const MAX_BODY = 256;
const MAX_NEW_PER_DAY = 2000;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "");
    try {
      if (!(await allowed(request, env))) return new Response("Too many requests", { status: 429, headers: { "Retry-After": "60" } });
      if (request.method === "POST" && path === "/v1/ping") return await ping(request, env);
      if (request.method === "DELETE" && path.startsWith("/v1/installs/")) return await forget(path.slice("/v1/installs/".length), env);
      if (request.method === "GET" && path === "/v1/stats") return await stats(request, env);
      return new Response("Not found", { status: 404 });
    } catch {
      return new Response("Something went wrong", { status: 500 });
    }
  },
};

/** A few requests a minute per IP. The IP is hashed before it reaches the limiter, and never stored. */
async function allowed(request, env) {
  if (!env.LIMITER) return true;
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`watchmybattery:${ip}`));
  const key = [...new Uint8Array(digest).slice(0, 16)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const { success } = await env.LIMITER.limit({ key });
  return success;
}

async function ping(request, env) {
  if (!(request.headers.get("content-type") ?? "").startsWith("application/json")) return new Response("Expected JSON", { status: 415 });
  const text = await request.text();
  if (text.length > MAX_BODY) return new Response("Too large", { status: 413 });
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }
  const { id, version, macOS } = body ?? {};
  if (typeof id !== "string" || !UUID.test(id) || typeof version !== "string" || !APP_VERSION.test(version)
    || typeof macOS !== "string" || !MACOS_VERSION.test(macOS)) {
    return new Response("Bad ping", { status: 400 });
  }
  const today = new Date().toISOString().slice(0, 10);

  // A Mac already counted is updated. A new one only while today's new Macs are under the cap.
  const updated = await env.DB.prepare("UPDATE installs SET last_seen = ?2, version = ?3, macos = ?4 WHERE id = ?1")
    .bind(id, today, version, macOS).run();
  if (updated.meta.changes === 0) {
    const { n } = await env.DB.prepare("SELECT COUNT(*) AS n FROM installs WHERE first_seen = ?1").bind(today).first();
    if (n >= MAX_NEW_PER_DAY) return new Response("Try again tomorrow", { status: 503, headers: { "Retry-After": "86400" } });
    await env.DB.prepare("INSERT OR IGNORE INTO installs (id, first_seen, last_seen, version, macos) VALUES (?1, ?2, ?2, ?3, ?4)")
      .bind(id, today, version, macOS).run();
  }
  return new Response(null, { status: 204 });
}

async function forget(id, env) {
  if (!UUID.test(id)) return new Response("Bad ID", { status: 400 });
  await env.DB.prepare("DELETE FROM installs WHERE id = ?1").bind(id).run();
  return new Response(null, { status: 204 });
}

/** Compares two strings in time that doesn't depend on where they differ. */
async function sameSecret(a, b) {
  const encoder = new TextEncoder();
  const [x, y] = await Promise.all([a, b].map((s) => crypto.subtle.digest("SHA-256", encoder.encode(s))));
  const ax = new Uint8Array(x);
  const ay = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < ax.length; i++) diff |= ax[i] ^ ay[i];
  return diff === 0;
}

async function stats(request, env) {
  const token = env.STATS_TOKEN;
  if (!token || !(await sameSecret(request.headers.get("authorization") ?? "", `Bearer ${token}`))) {
    return new Response("Unauthorized", { status: 401 });
  }
  const day = (daysAgo) => new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);
  const [totals, versions, macOS, firstSeen] = await env.DB.batch([
    env.DB.prepare(
      `SELECT COUNT(*) AS installs,
              SUM(last_seen > first_seen) AS returning_macs,
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
    returning: t.returning_macs ?? 0,
    activeToday: t.active1 ?? 0,
    activeLast7Days: t.active7 ?? 0,
    activeLast30Days: t.active30 ?? 0,
    versions: versions.results,
    macOS: macOS.results,
    newPerDay: firstSeen.results,
  });
}
