-- @tests TS-COMP-025
-- case: another module cannot read a field of an opaque record
-- source: FR-COMP-025 §2.4 (AC4)
-- expect-build-error: field 'ss_user' of opaque type 'Session' is private to module 'store'

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

fn :: main => ()
      main =
        s = open session "ana" (sign in "acme")
        echo (ss_user s)
