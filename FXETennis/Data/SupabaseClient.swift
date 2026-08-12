//
//  SupabaseClient.swift
//  FXETennis
//
//  The single Supabase client for the app. Mirrors Volee's setup on the same
//  SDK version (supabase-swift 2.41.1). The publishable key is safe to ship in
//  a client binary — it only grants what RLS allows, which for a player is
//  their own rows and the public views. Every real permission lives in Postgres.
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://amnaxvznkadkgzdxzegw.supabase.co")!,
    supabaseKey: "sb_publishable_J-UBIJSqeljvVuyb4P27Jg_jLngLuBW"
)
