-- @tests TS-COMP-025
-- case: another module cannot expand an opaque type
-- source: FR-COMP-025 §3 (AC5)
-- expect-build-error: 'expand type' on opaque type 'TenantScope' is private to module 'store'

module :: store

opaque type TenantScope = UnsafeTenantScope String
opaque type Session     = ss_user: String, ss_scope: TenantScope

fn :: sign in String => TenantScope
      sign in t =  UnsafeTenantScope t

fn :: scope tenant TenantScope => String
      scope tenant (UnsafeTenantScope t) =  t

fn :: open session String TenantScope => Session
      open session u scope =  Session u scope

fn :: session user Session => String
      session user s =  ss_user s

fn :: renamed Session String => Session
      renamed s u =  s with ss_user = u

expand type TenantScope = Everyone

fn :: is everyone TenantScope => Bool
      is everyone Everyone =  True
      is everyone _        =  False

module :: main

import store

expand type TenantScope = Forged String

fn :: main => ()
      main =  echo (scope tenant (sign in "acme"))
