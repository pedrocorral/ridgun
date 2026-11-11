-- @tests TS-COMP-025
-- case: another module cannot match a constructor of an opaque type
-- source: FR-COMP-025 §2.3 (AC3)
-- expect-build-error: constructor 'UnsafeTenantScope' of opaque type 'TenantScope' is private to module 'store' (used in function 'tenant of')

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

fn :: tenant of TenantScope => String
      tenant of (UnsafeTenantScope t) =  t
      tenant of _                     =  ""

fn :: main => ()
      main =  echo (tenant of (sign in "acme"))
