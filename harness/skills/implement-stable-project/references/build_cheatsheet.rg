-- ============================================================
-- harness/skills/implement-stable-project/references/build_cheatsheet.rg
-- Canonical `build.rg` Reference for `stable` (Executables, Libraries, Tasks & Plugins)
-- Verify with: ./bin/ridgunc check harness/skills/implement-stable-project/references/build_cheatsheet.rg
-- ============================================================

-- 1. Core Project Metadata
fn :: project name => String
      project name =  "my_web_app"

fn :: project version => String
      project version =  "0.2.0"

-- "exe" (executables), "lib" (.rglib + ELF64 .so library), or "both"
fn :: project kind => String
      project kind =  "both"

-- 2. Directory & Entrypoint Layout
fn :: main entry => String
      main entry =  "src/main/ridgun/my_web_app/main.rg"

fn :: source dir => String
      source dir =  "src/main/ridgun"

fn :: test dir => String
      test dir =  "src/test/ridgun"

fn :: target dir => String
      target dir =  "target"

-- 3. Dependencies & Plugins (`stable deps`, `stable plugins`)
fn :: dependencies => [String]
      dependencies =  []

fn :: plugins => [String]
      plugins =  ["plugins/web_router.rg"]

-- 4. Custom Single-Word & Multi-Word Tasks (`stable tasks`, `stable <task>`)
fn :: task serve => String
      task serve =  "./bin/ridgunc run src/main/ridgun/my_web_app/main.rg"

fn :: task db migrate => String
      task db migrate =  "./bin/ridgunc run src/main/ridgun/db/migrate.rg"

fn :: task build release => String
      task build release =  "./bin/stable built && ./bin/stable built lib"
