//
//  SupabaseClient.swift
//  FXETennis
//
//  The single Supabase client. DEBUG builds talk to the LOCAL stack so the app
//  can be signed into with the seeded test users (Maria, Ken, …) and the whole
//  flow walked on the simulator — this is also what XCUITest drives. RELEASE
//  talks to the hosted project. The publishable key is safe in a client binary;
//  RLS is the real boundary.
//
//  localhost (not 127.0.0.1) so iOS App Transport Security lets the http:// dev
//  connection through without an exception.
//

import Foundation
import Supabase

private enum SupabaseConfig {
    #if DEBUG
    // A Debug build can be pointed at another backend for CI: the UI-test job
    // has no Docker, so it cannot host the local stack, and forwards a
    // throwaway hosted project's URL and publishable key through the launch
    // environment (see FXETennisUITests setUp). Never read in Release, so a
    // shipped build cannot be redirected by an environment variable.
    private static let env = ProcessInfo.processInfo.environment
    static let url = URL(string: env["FXE_SUPABASE_URL"] ?? "http://localhost:54321")!
    static let anonKey = env["FXE_SUPABASE_ANON_KEY"] ?? "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    #else
    static let url = URL(string: "https://amnaxvznkadkgzdxzegw.supabase.co")!
    static let anonKey = "sb_publishable_J-UBIJSqeljvVuyb4P27Jg_jLngLuBW"
    #endif
}

// flowType .implicit, deliberately. "Forgot password?" emails a link that opens
// web/reset.html in a BROWSER, not this app (no Apple account yet, so no
// universal links). With the default PKCE flow the link carries a one-time code
// that only the client which started the flow can redeem, and that client is
// this app, not the browser: the page would fail with "code verifier not found".
// Implicit puts the recovery token in the URL fragment so any page can finish
// it. Password sign-in is unaffected by flow type. (2026-09-01)
let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey,
    options: SupabaseClientOptions(auth: .init(flowType: .implicit))
)
