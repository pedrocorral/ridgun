-- case: expand type adds variants; a second fn :: declaration merges its clauses ahead of the first one's catch-all
-- source: FR-COMP-005 §2-§3 and AC-2, AC-3 (format_err example, verbatim)
-- expect-output:
--   IO: disk
--   Timeout: 5ms
--   Auth denied: bob
--   DB [3]: down

type Error = IoError String | Timeout Int
expand type Error = AuthError String | DbError Int String

fn :: format err Error         => String
      format err (IoError msg) =  "IO: {msg}"
      format err (Timeout ms)  =  "Timeout: {ms}ms"
      format err _             =  "Unknown error"

fn :: format err Error                => String
      format err (AuthError user)     =  "Auth denied: {user}"
      format err (DbError   code msg) =  "DB [{code}]: {msg}"

fn :: main => ()
      main =
        echo (format err (IoError "disk"))
        echo (format err (Timeout 5))
        echo (format err (AuthError "bob"))
        echo (format err (DbError 3 "down"))
