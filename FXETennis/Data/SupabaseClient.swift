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
    static let url = URL(string: "http://localhost:54321")!
    static let anonKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    #else
    static let url = URL(string: "https://amnaxvznkadkgzdxzegw.supabase.co")!
    static let anonKey = "sb_publishable_J-UBIJSqeljvVuyb4P27Jg_jLngLuBW"
    #endif
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
