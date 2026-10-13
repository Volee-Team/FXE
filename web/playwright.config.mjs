// Browser tests for the web admin, against the LOCAL Supabase stack.
//
// The page is static, so the "web server" is Python's http.server on the
// folder above. config.js picks the local stack for any localhost origin.
// Prerequisites, same as the XCUITests: `supabase start && supabase db reset`.
import { defineConfig } from "@playwright/test";
import { existsSync, readFileSync } from "node:fs";

// A UI test run (scripts/run-ui-tests.sh) owns the local database while it
// holds its lock, and these tests sign in and write rows. tests/run-probes.sh
// has refused to start in that window since 2026-10-01; the browser suite did
// not, and on 2026-10-12 a review-link test wrote into the database mid-run.
// Same check: the lock directory exists and its process is alive. Never in CI.
if (!process.env.CI && existsSync("/tmp/fxe-ui-tests.lock")) {
  let alive = false;
  try { process.kill(Number(readFileSync("/tmp/fxe-ui-tests.lock/pid", "utf8").trim()), 0); alive = true; } catch {}
  if (alive) throw new Error("A UI test run holds the local database (/tmp/fxe-ui-tests.lock). Wait for it to finish.");
}

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  retries: 0,
  workers: 1,               // the tests share one database; keep them ordered
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://localhost:8790",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "python3 -m http.server 8790",
    url: "http://localhost:8790/index.html",
    reuseExistingServer: true,
    timeout: 10_000,
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
