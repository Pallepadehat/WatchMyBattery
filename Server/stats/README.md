# Install count

How many Macs run WatchMyBattery, from the people who turned on **Count This Mac** (in the welcome tour, or Settings › General › Privacy). It's off until they do, and nothing is sent before that.

A [Cloudflare Worker](https://developers.cloudflare.com/workers/) with a [D1](https://developers.cloudflare.com/d1/) database, both on Cloudflare's free plan (100,000 requests and 5 million D1 row reads a day, far more than a ping a day per Mac needs).

## What's sent, and kept

Once a day, the app posts:

```json
{ "id": "6f1c…-…", "version": "0.4.2", "macOS": "15.1" }
```

- `id` is a random UUID, made on the Mac when sharing is turned on. It isn't tied to anything else.
- The Worker stores that, plus the **day** it was first and last seen. No IP address, no headers, no location, and request logs are off.
- Turning sharing off sends `DELETE /v1/installs/<id>`, which deletes the row, and the app forgets the ID.

## Misuse

The Worker's address is inside every copy of the app, so anyone can call it. What keeps that harmless:

- **Rate limit.** Each IP gets 10 requests a minute; past that, `429`. The limiter is keyed by a hash of the IP and only holds it for its one-minute window. Nothing about the IP reaches the database.
- **A daily cap on new Macs** (2,000), so a flood of made-up IDs can't fill the database. Macs already counted keep updating.
- **Strict pings.** A version 4 UUID, an app version like `0.4.2`, a macOS version like `15.1`, as JSON of at most 256 bytes. Anything else is `400`.
- **Deleting** needs the Mac's random ID, which only that Mac knows. **The stats** need the token, compared in constant time.
- **`returning`** counts Macs seen on two different days or more. A burst of fake pings doesn't reach it, so it's the number to trust if the total ever looks inflated.
- **No bill.** On Cloudflare's free plan, going past the daily limits makes requests fail rather than cost money.

Someone determined could still add a few fake Macs a day from many IPs: an open-source app can't prove a ping is real. The cap and `returning` keep that from mattering.

## Setting it up

You need a free Cloudflare account. Where it's deployed stays out of git: `wrangler.toml` (with the database ID) and Wrangler's `.wrangler/` folder are git-ignored, the Worker's host lives in the git-ignored `Config/Local.xcconfig`, and the stats token in your Keychain. From this folder:

```sh
npx wrangler login
npx wrangler d1 create watchmybattery-stats          # prints its database_id
cp wrangler.example.toml wrangler.toml               # and paste the database_id in
npx wrangler d1 execute watchmybattery-stats --remote --file schema.sql
TOKEN=$(openssl rand -hex 32)
security add-generic-password -U -s watchmybattery-stats -a STATS_TOKEN -w "$TOKEN"
echo "$TOKEN" | npx wrangler secret put STATS_TOKEN
npx wrangler deploy                                  # prints https://watchmybattery-stats.<you>.workers.dev
```

Then add the host to `Config/Local.xcconfig`, without `https://` (in an xcconfig, `//` starts a comment):

```
WMB_USAGE_STATS_HOST = watchmybattery-stats.<you>.workers.dev
```

Info.plist turns it into `WMBUsageStatsURL`. A build without it, like anyone else's, sends nothing. If the `wrangler.toml` goes missing, `npx wrangler d1 list` shows the database ID again.

Debug builds don't send pings unless they're launched with `--send-usage-stats`, so working on the app doesn't count.

## Reading the numbers

```sh
curl -s -H "Authorization: Bearer $(security find-generic-password -s watchmybattery-stats -a STATS_TOKEN -w)" \
  https://watchmybattery-stats.<you>.workers.dev/v1/stats
```

```json
{
  "installs": 42,
  "returning": 35,
  "activeToday": 18,
  "activeLast7Days": 31,
  "activeLast30Days": 38,
  "versions": [{ "version": "0.4.2", "count": 30 }],
  "macOS": [{ "macos": "15.1", "count": 21 }],
  "newPerDay": [{ "day": "2026-11-20", "count": 3 }]
}
```

`installs` is every Mac that has opted in and not opted out since; `returning` is those seen on two different days or more. The `active…` counts are Macs that pinged in that window. `versions` and `macOS` cover the last 30 days.

Or query D1 yourself: `npx wrangler d1 execute watchmybattery-stats --remote --command "SELECT COUNT(*) FROM installs"`.
