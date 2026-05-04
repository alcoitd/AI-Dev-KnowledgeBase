---
description: Set or restore active project scope to limit file searches to one sub-project. No args = restore persisted scope. Args: frontend | backend | legacy | migration | clear
---

Set the active work scope based on: $ARGUMENTS

## No-Arg Behavior (session restore)

If `$ARGUMENTS` is empty or blank:
1. Read `.claude/scope.json`
2. If file missing or empty: tell user no scope set, list available scopes, stop
3. If scope found: output current scope name + root path, apply behavioral rules below for this session, confirm scope restored. Do NOT re-generate manifest unless user asks.

## Scope Map

| Arg | Root Path | Focus |
|-----|-----------|-------|
| frontend | frontend/pwa-wells-permit-web/ | React 19 PWA — src/pages, src/components, src/hooks |
| backend | backend/PWA.WellsPermit.WebApi/ | .NET 8 — Controllers, Services, Repositories |
| legacy | wellspermit-ecomm-web-jboss/ | JSPs, Servlets (ProcessAppServlet), Beans |
| migration | spec/ + plan-execution/ | Specs, execution plans, JSP sources for migration work |
| clear | (all) | Remove scope restriction |

## Steps

1. Parse argument: `$ARGUMENTS`

2. If `clear`: delete `.claude/scope.json` if it exists, tell user scope cleared. Stop.

3. Identify root path from map above.

4. Generate compact manifest using Bash — use `find` with max depth 3, output only relative paths:
   - **frontend**: `find frontend/pwa-wells-permit-web/src -maxdepth 3 -type f \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) | sort`
   - **backend**: `find backend/PWA.WellsPermit.WebApi -maxdepth 4 -type f \( -name "*.cs" -o -name "*.json" \) | sort`
   - **legacy**: `find wellspermit-ecomm-web-jboss/src -maxdepth 6 -type f \( -name "*.jsp" -o -name "*.java" \) | sort`
   - **migration**: `find spec plan-execution -maxdepth 2 -type f | sort`

5. Save scope to `.claude/scope.json`:
```json
{
  "scope": "<arg>",
  "root": "<root-path>",
  "set_at": "<ISO timestamp>"
}
```

6. Output compact manifest in this format:
```
SCOPE: <arg> → <root-path>
Files (<count>):
<relative paths, one per line>
```

7. Remind user: from now on, constrain Glob/Grep/Read to this scope unless they explicitly ask to cross scope. Say scope active.

## Behavioral Rules (apply immediately after scope set)

- All Glob `pattern` calls: prefix path with scoped root unless user explicitly asks to search outside
- All Grep calls: set `path` to scoped root unless user specifies otherwise
- All Read calls: warn inline if reading outside scope (but still read if user requested it)
- Do NOT preemptively explore other sub-project directories
- Scope persists for the entire session unless user runs `/scope clear` or `/scope <other>`
