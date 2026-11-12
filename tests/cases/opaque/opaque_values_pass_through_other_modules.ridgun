-- @tests TS-COMP-025
-- case: other modules hold, pass, store and compare opaque values; the defining module builds, matches, reads, updates and expands them
-- source: FR-COMP-025 §1, §4, §5 (AC1, AC6)
-- expect-output:
--   acme acme True False
--   ana bea
--   False True
--   2

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

fn :: same scope TenantScope TenantScope => Bool
      same scope a b =  a == b

fn :: count scopes [TenantScope] => Int
      count scopes []     =  0
      count scopes (_:xs) =  1 + (count scopes xs)

fn :: main => ()
      main =
        a = sign in "acme"
        b = sign in "acme"
        c = sign in "other"
        echo (scope tenant a) (scope tenant b) (same scope a b) (a == c)
        s = open session "ana" a
        t = renamed s "bea"
        echo (session user s) (session user t)
        echo (is everyone a) (is everyone Everyone)
        echo (count scopes [a, c])
