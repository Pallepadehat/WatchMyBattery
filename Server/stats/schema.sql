-- One row per Mac that turned on "Count This Mac". The ID is random, made on the Mac when sharing was turned on.
-- Dates are days (YYYY-MM-DD), not times.
CREATE TABLE IF NOT EXISTS installs (
  id TEXT PRIMARY KEY,
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  version TEXT NOT NULL,
  macos TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS installs_last_seen ON installs (last_seen);
CREATE INDEX IF NOT EXISTS installs_first_seen ON installs (first_seen);
