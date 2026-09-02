// Browser tests for the web admin, against the LOCAL Supabase stack.
//
// The page is static, so the "web server" is Python's http.server on the
// folder above. config.js picks the local stack for any localhost origin.
// Prerequisites, same as the XCUITests: `supabase start && supabase db reset`.
import { defineConfig } from "@playwright/test";

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
