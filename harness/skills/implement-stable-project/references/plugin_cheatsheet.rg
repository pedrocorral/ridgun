-- ============================================================
-- harness/skills/implement-stable-project/references/plugin_cheatsheet.rg
-- Canonical `stable` Plugin Reference (`plugins/web_router.rg`)
-- Demonstrates:
--   1. Plugin-contributed `fn :: task <words...> => String` commands
--   2. Open ADT command extension (`expand type`) & clause merging
--   3. Executable plugin entrypoint (`fn :: main => ()`)
-- Verify with: ./bin/ridgunc check harness/skills/implement-stable-project/references/plugin_cheatsheet.rg
-- ============================================================

-- 1. Tasks exported automatically to `stable tasks` when this plugin is loaded
fn :: task routes => String
      task routes =  "echo 'GET /health -> 200 OK'"

fn :: task generate controller => String
      task generate controller =  "echo 'Scaffolding controller...'"

-- 2. Extensible Command Pattern (`expand type` + `fn ::` clause merging)
type PluginAction = ActionRoutes | ActionVersion

fn :: run plugin action PluginAction  => String
      run plugin action ActionRoutes  =  "GET /health\nPOST /api/items"
      run plugin action ActionVersion =  "web_router plugin v0.1.0"
      run plugin action _             =  "unknown plugin action"

expand type PluginAction = ActionScaffold String

fn :: run plugin action PluginAction          => String
      run plugin action (ActionScaffold name) =  "scaffolded controller: {name}"

-- 3. Direct Plugin Entrypoint (invoked when running `stable web_router`)
fn :: main => ()
      main =
        echo (run plugin action ActionRoutes)
        echo (run plugin action (ActionScaffold "users"))
