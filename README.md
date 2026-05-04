## What This Is ?

This repo demonstrates a repeatable, agent-driven workflow for legacy-to-modern migrations. The source of truth is a real production system: an Alameda County wells permit application built on Java servlets and JSP views. The target is a React 19 PWA frontend with a .NET 8 Web API backend.

The AI tooling does the heavy lifting — reverse engineering, spec generation, execution planning, and test writing — while the developer stays in the loop for decisions and verification.

---

## The Core Workflow

```
Legacy JSP
    │
    ▼
[agent: spec writer]
    │  Reads JSP + servlet + bean classes
    │  Outputs: spec/ directory
    ▼
Spec File (.md)
    │  Documents: what page does, data flow, API contracts,
    │  validation rules, workflow position, UI behavior
    │
    ▼
[agent: execution planner]
    │  Reads spec, reads actual codebase on disk
    │  Corrects plan vs. reality discrepancies
    │  Outputs: plan-execution/ directory
    ▼
Execution Plan (.md)
    │  Concrete file paths, complete code, step-by-step commands,
    │  codebase-reality corrections table
    │
    ▼
[agent: migration executor]
    │  Implements React component + .NET controller
    │  Follows Controller → Service → DapperRepository pattern
    │
    ▼
Migrated Page


---

## Agent Roster

| Agent | Job | Input | Output |
|-------|-----|-------|--------|
| `agent-create-spec-from-jsp` | Reverse engineer legacy JSP into structured spec | JSP file path | `spec/spec_<page>.md` |
| `agent-create-execution-migration-from-spec` | Map spec to concrete implementation plan | Spec file | `plan-execution/<page>_execution.md` |
| `migrate-jsp` | Implement React component + .NET endpoint | Spec + execution plan | Source files in `frontend/` and `backend/` |
| `agent-test-migration-from-spec` | Generate Playwright e2e tests | React component + spec | `tests/<page>.spec.ts` |

Supporting agents used inline:

- `cavecrew-investigator` — locate symbols, trace data flow, map file structure (read-only, compressed output)
- `cavecrew-builder` — surgical 1–2 file edits
- `cavecrew-reviewer` — diff review, severity-tagged findings
- `Explore` — broad codebase exploration before writing specs

---

## Artifacts Produced Per Page

```
spec/
  spec_app_proj_locmap.md         ← What the JSP does, fully documented
  spec_app_work_wellsmap.md

plan-execution/
  app_proj_locmap_migration.md    ← What to build + why
  app_proj_locmap_execution.md    ← How to build it (exact files, corrections)
  app_work_wellsmap_execution.md

tests/
  (Playwright e2e per migrated page)
```

---

## Spec File Structure

Each spec captures:

1. **What the page does** — plain-language summary
2. **Workflow position** — where it sits in the multi-step form flow
3. **Data model** — fields read/written, session state
4. **API contracts** — endpoints, request/response shapes
5. **Validation rules** — client + server side
6. **UI behavior** — conditional rendering, map interactions, error states
7. **Navigation** — where the user came from, where they go next
8. **Edge cases** — returning users, pre-populated data, back-navigation

---

## Execution Plan Structure

Each execution plan includes:

1. **Codebase reality corrections** — table of where the migration plan diverged from actual files on disk
2. **Prerequisites** — npm packages to install, config changes needed
3. **Step-by-step implementation** — labeled A/B/C/D with exact file paths and complete code
4. **Verification checklist** — how to confirm the page works end-to-end

The corrections table is the most valuable part — the spec agent writes from the JSP, but the execution agent reads the actual disk. Discrepancies are documented explicitly so nothing gets silently wrong.

---

## Tech Stack (Migration Target)

**Frontend**
- React 19, Create React App 5
- React Router for navigation
- Context API for application state
- `@react-google-maps/api` for map components
- Axios via `useApiClient` hook (with auth)

**Backend**
- .NET 8 minimal ASP.NET Core
- Swagger/OpenAPI via Swashbuckle
- Controller → Service → DapperRepository pattern
- CORS configured for `http://localhost:3000`

**Legacy Source**
- Java/JBoss servlet + JSP architecture
- `ProcessAppServlet.java` — main HTTP handler
- `ApplicationBean`, `BeanApp` — business logic beans
- JSP views named by domain (`app_proj_locmap.jsp`, etc.)

---

## Key Lessons

**Spec first, code second.** The spec agent produces a document that outlives the migration — it becomes the source of truth for what the page was supposed to do, independent of the legacy code.

**Plan vs. reality corrections are essential.** The migration plan is written from the spec. The execution plan is written from the actual codebase. The gap between them — import paths, missing files, wrong config values — is documented in a corrections table in every execution plan. Without this step, broken assumptions silently propagate into the implementation.

**Agents protect main context.** Long migrations generate a lot of code. Delegating spec reading, file location, and diff review to subagents keeps the main conversation context small and focused on decisions, not boilerplate.

**Read the disk before writing code.** Every execution agent starts by reading actual files — not trusting memory, prior specs, or migration plans. File paths, import conventions, and config values are verified before being written into new code.

---

## Running the Project

### Frontend
```bash
cd frontend/pwa-wells-permit-web
npm start          # http://localhost:3000
npm test -- --watchAll=false
```

### Backend
```bash
cd backend/PWA.WellsPermit.WebApi
dotnet run         # HTTP 5012 / HTTPS 7296
# Swagger: http://localhost:5012/swagger
```

### Legacy (read-only reference)
```bash
cd wellspermit-ecomm-web-jboss
mvn -B package
```

---

## Repo Structure

```
PWA-Wells-Permit-WebApp/
├── frontend/pwa-wells-permit-web/     # React 19 PWA
├── backend/PWA.WellsPermit.WebApi/    # .NET 8 Web API
├── wellspermit-ecomm-web-jboss/       # Legacy Java/JBoss (production source)
├── spec/                              # Generated specs per JSP page
├── plan-execution/                    # Generated execution plans per page
└── tests/                             # Playwright e2e tests
```

---
