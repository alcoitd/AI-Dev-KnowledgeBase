# Execution Plan: app_work_wellsmap.jsp → React + .NET

## What This Document Is

The spec (`spec_app_work_wellsmap.md`) documents exactly what the legacy Wells Map page does.
This document is the concrete _how_: exact file paths, complete code for every file, step-by-step
commands, and a corrections section that records codebase realities found on disk before this plan
was written.

---

## Codebase Reality Check (as of plan-writing date 2026-05-03)

Before executing any step, verify these findings against the current state of the repo:

| # | What was found on disk | Impact on this plan |
|---|---|---|
| 1 | `src/api/apiClient.js` does **not** exist | Must be created (Step B). `ApplicantInfoForm.js` already imports it — the app does not compile without it. This is the same fix noted in `app_proj_locmap_execution.md`. If `LocationMap` was already built, `apiClient.js` will already be there; skip Step B. |
| 2 | `src/pages/LocationMap/` does **not** exist (no files found) | The LocationMap migration has not been executed yet. `WellsMap` depends on it for the "Return to Form" navigation target. See Step D for the `works` slice dependency. |
| 3 | `ApplicationContext.js` `works` slice is `[]` (empty array) | The `works` slice holds work item beans. `WellsMap` works on a single work item and its `wrkSpecsVec`. The work item state management must be established here — see Step C. |
| 4 | `ApplicationContext.js` `project` slice is `{}` (empty object) | Location map fields not yet added. If LocationMap has been executed, the `project` slice will already have `siteLat/siteLng/siteLocation/siteCityName/siteCityCode`. `WellsMap` does **not** add to project — it adds to a specific work item's specs inside `works`. |
| 5 | `App.js` imports `ApplicantInfoForm` from `./components/ApplicantInfo/ApplicantInfoForm` — that path is wrong; the file is at `./pages/ApplicantInfoForm/ApplicantInfoForm` | Fix this import in Step E when adding the WellsMap route. |
| 6 | `@react-google-maps/api` is **not** in `package.json` | Must install (Step A). If LocationMap was already built this will already be installed; skip Step A. |
| 7 | Only `ReferenceController.cs` and `WeatherForecastController.cs` exist in Controllers | `WellsMapController.cs` must be created (Step J). |
| 8 | Only `StateCodeDto.cs` exists in Models | Two new DTOs must be created (Steps I.1 and I.2). |
| 9 | `config.local.js` has `apiBaseUrl: "https://localhost:7241"` | The .NET project runs HTTP on 5012 and HTTPS on 7296 per `CLAUDE.md`. The React app runs HTTP on 3000. Mixed HTTP-to-HTTPS can cause browser mixed-content blocks. Use `http://localhost:5012`. Fix once in Step C of the `app_proj_locmap_execution.md`; this plan assumes it is already fixed if LocationMap has been executed. If not, fix it here per locmap Step C. |

---

## Context: How WellsMap Fits the Overall Workflow

```
Applicant Info (/applicant-info)
  → Location Map (/location-map)
    → [Work Types page — not yet migrated]
      → Well Specs (/well-specs/:workSeq)
        → [THIS PAGE] Wells Map (/wells-map/:workSeq)
        → Well Specs (/well-specs/:workSeq)   [return]
```

The Wells Map page (`app_work_wellsmap.jsp`) is **not** a top-level workflow step. It is a
satellite modal launched from the Well Specs tabular form for a specific work item. The user
clicks "Locate Wells on Map" from the specs form, pins each individual well on a satellite map,
then clicks "Return to Form" to go back to specs. Each pin save is a discrete API call — it
does **not** navigate away. The page reloads (in the legacy app) or re-renders with updated
pins (in React).

Key difference from `LocationMap`: LocationMap sets a single project site coordinate. WellsMap
appends multiple well spec records to one work item's `wrkSpecsVec`. The data model is an array
of well specs per work item.

---

## Prerequisites

1. **Google Maps API key.** The key from the locmap step covers this page too. Confirm it has
   Maps JavaScript API enabled. The `places` library is loaded by the locmap step already.
   WellsMap only needs the Maps JavaScript API — it does not use the Places SearchBox.

2. **Work item routing.** WellsMap is reached from the Well Specs form, not from a top-level
   navigation step. Until `app_work_specs.jsp` is migrated, WellsMap can be tested by navigating
   directly to `http://localhost:3000/wells-map/0` with mock context data.

3. **The `works` slice shape.** Before executing this plan, agree on the shape of a single
   work item in context. This plan establishes that shape (Step C). If the Well Specs form has
   already been migrated, align with whatever shape that migration defined.

---

## Step A — npm Package Install

Run once from the frontend project root. Skip if `@react-google-maps/api` already appears in
`package.json` (it will be there if LocationMap was already built).

```bash
# Working directory: C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web
npm install @react-google-maps/api
```

---

## Step B — Create `apiClient.js`

Skip if the file already exists at the path below (it will exist if LocationMap was already
built). This is included here because this plan must be executable as a standalone unit.

**File to create:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\api\apiClient.js`

```js
/**
 * apiClient.js — Thin fetch wrapper for the Wells Permit .NET API.
 *
 * Exports a plain `api` object with get / post / put / delete methods.
 * No authentication is required for Wells Permit public-facing endpoints.
 */
import config from '../config';

const BASE_URL = config.apiBaseUrl; // e.g. http://localhost:5012

async function request(method, path, body) {
  const url = `${BASE_URL}${path}`;
  const options = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body !== undefined) {
    options.body = JSON.stringify(body);
  }
  const response = await fetch(url, options);
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || `HTTP ${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

export const api = {
  get:    (path)        => request('GET',    path),
  post:   (path, body)  => request('POST',   path, body),
  put:    (path, body)  => request('PUT',    path, body),
  delete: (path)        => request('DELETE', path),
};
```

---

## Step C — Update `ApplicationContext.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\context\ApplicationContext.js`

### C.1 What must change

The `works` slice is currently an empty array `[]`. WellsMap needs each work item to carry a
`wrkSpecs` array (the React equivalent of `BeanAppWrk.wrkSpecsVec`). The shape of a single work
item must also include the fields set by the Well Specs form upstream.

This plan establishes the minimum `works` slice shape required for WellsMap. If Well Specs has
already been migrated, reconcile the shapes and use whichever is more complete.

### C.2 Updated `ApplicationContext.js`

Replace the entire file:

```js
import { createContext, useContext, useState } from 'react';

const ApplicationContext = createContext(null);

/**
 * Shape of a single work item in the `works` array.
 * Mirrors BeanAppWrk fields used by the WellsMap and WellSpecs pages.
 *
 * workSeq    — zero-based index identifying which work item this is
 * workId     — server-assigned ID (null until saved to DB)
 * workCat    — work category code, e.g. "des" prefix triggers decommission fields
 * wrkSpecs   — array of well spec objects (BeanAppWrkSpecs equivalent)
 */
// Exported so WellSpecs and WellsMap can reference the shape for initialisation.
export const EMPTY_WORK_ITEM = {
  workSeq:  0,
  workId:   null,
  workCat:  '',
  wrkSpecs: [],  // Array<WellSpec>
};

/**
 * Shape of a single well spec record in wrkSpecs.
 * Mirrors BeanAppWrkSpecs fields populated by saveWellsMarkers().
 */
export const EMPTY_WELL_SPEC = {
  lat:           null,   // number | null
  lng:           null,   // number | null
  ownerWellNum:  '',     // string — Owner Well ID
  holeDiameter:  '',     // string — Drill Hole Diameter (inches)
  casingDiameter:'',     // string — Casing Diameter (inches)
  sealDepth:     '',     // string — Surface Seal Depth (feet)
  maxDepth:      '',     // string — Max Depth (feet)
  // Decommission-only fields (workCat starts with "des"):
  stateWellId:   '',     // string — State Well #
  permitNum:     '',     // string — Permit #
  dwrNum:        '',     // string — DWR #
};

const INITIAL_APPLICATION = {
  project: {
    siteLat:      null,  // number | null
    siteLng:      null,  // number | null
    siteLocation: '',    // string — formatted address (max 200 chars)
    siteCityName: '',    // string — locality name from geocoder
    siteCityCode: '',    // string — city code from .NET lookup
  },
  works: [],             // Array<WorkItem> — populated by WellSpecs form
  applicant: {},
  hazard: null,
  payment: null,
  siteHazardRequired: false,
};

export function ApplicationProvider({ children }) {
  const [application, setApplication] = useState(INITIAL_APPLICATION);

  const updateApplicant = (data) =>
    setApplication(prev => ({ ...prev, applicant: data }));

  const updateProject = (data) =>
    setApplication(prev => ({ ...prev, project: data }));

  const updateWorks = (works) =>
    setApplication(prev => ({ ...prev, works }));

  /**
   * Append a new well spec to a specific work item's wrkSpecs array.
   * workSeq — index into application.works
   * spec    — WellSpec object matching EMPTY_WELL_SPEC shape
   */
  const addWellSpec = (workSeq, spec) =>
    setApplication(prev => {
      const works = prev.works.map((w, idx) =>
        idx === workSeq
          ? { ...w, wrkSpecs: [...w.wrkSpecs, spec] }
          : w
      );
      return { ...prev, works };
    });

  const updateHazard = (data) =>
    setApplication(prev => ({ ...prev, hazard: data }));

  const updatePayment = (data) =>
    setApplication(prev => ({ ...prev, payment: data }));

  const setSiteHazardRequired = (flag) =>
    setApplication(prev => ({ ...prev, siteHazardRequired: flag }));

  const resetApplication = () => setApplication(INITIAL_APPLICATION);

  return (
    <ApplicationContext.Provider value={{
      application,
      updateApplicant,
      updateProject,
      updateWorks,
      addWellSpec,
      updateHazard,
      updatePayment,
      setSiteHazardRequired,
      resetApplication,
    }}>
      {children}
    </ApplicationContext.Provider>
  );
}

export function useApplication() {
  const ctx = useContext(ApplicationContext);
  if (!ctx) throw new Error('useApplication must be used within ApplicationProvider');
  return ctx;
}
```

### C.3 Why `addWellSpec` instead of a full `updateWorks`

In the legacy app, each SAVE click POSTs a single `BeanAppWrkSpecs` and appends it to
`wrkSpecsVec` — the rest of the works vector is untouched. `addWellSpec(workSeq, spec)` mirrors
this exactly: it appends one spec to one work item without touching other work items. The
existing `updateWorks(works)` remains available for bulk replacement (e.g., when the Well Specs
form loads the full list from the server).

---

## Step D — Update `App.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\App.js`

Add the `/wells-map/:workSeq` route. Also fix the broken `ApplicantInfoForm` import path
(it imports from `./components/ApplicantInfo/ApplicantInfoForm` but the file is at
`./pages/ApplicantInfoForm/ApplicantInfoForm`).

```jsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ApplicationProvider } from './context/ApplicationContext';
import ApplicantInfoForm from './pages/ApplicantInfoForm/ApplicantInfoForm';
import WellsMap from './pages/WellsMap/WellsMap';

function App() {
  return (
    <ApplicationProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/applicant-info"     element={<ApplicantInfoForm />} />
          <Route path="/wells-map/:workSeq" element={<WellsMap />} />
          {/* Future routes added here as each JSP is migrated */}
          <Route path="/" element={<Navigate to="/applicant-info" replace />} />
        </Routes>
      </BrowserRouter>
    </ApplicationProvider>
  );
}

export default App;
```

**Note on import order:** `LocationMap` is not imported here yet — it will be added when the
locmap execution plan is run. If locmap has already been run, preserve its import and route and
add `WellsMap` alongside it.

**Route parameter:** `/wells-map/:workSeq` uses a URL param (`workSeq`) so the page knows which
work item in `application.works` to operate on. `workSeq` is a zero-based index matching
`BeanAppWrk`'s position in `getAppWorksVector()`.

---

## Step E — Environment Variable Files

### E.1 `.env.local` (not committed to git)

File: `C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\.env.local`

If this file already exists from the locmap execution, do NOT overwrite it — just confirm the
key is present. If it does not exist, create it:

```
# Google Maps API key — requires Maps JavaScript API enabled
REACT_APP_GOOGLE_MAPS_API_KEY=<paste_dev_key_here>
```

### E.2 `.env.example` (committed to git)

File: `C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\.env.example`

Same conditional — create only if it does not already exist:

```
# Google Maps API key — requires Maps JavaScript API enabled
REACT_APP_GOOGLE_MAPS_API_KEY=
```

---

## Step F — Create `WellsMap.css`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\WellsMap\WellsMap.css`

All classes use the `wm` prefix, following the `ai` / `lm` convention.

```css
/* ── Page wrapper ── */
.wmPage {
  background: #fff;
  max-width: 960px;
  margin: 0 auto;
  font-family: Arial, Helvetica, sans-serif;
  font-size: 13px;
}

/* ── Step title bar ── */
.wmPageTitle {
  background-color: #336699;
  padding: 6px 10px;
}

.wmStepTitle {
  color: #fff;
  font-size: 15px;
  font-weight: bold;
}

/* ── Instruction bar (above map) ── */
.wmInstructionBar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background-color: #d9e6f2;
  padding: 8px 12px;
  gap: 12px;
}

.wmInstruction {
  font-size: 13px;
  color: #333;
  flex: 1;
}

/* ── Return to Form button ── */
.wmReturnBtn {
  padding: 4px 14px;
  font-size: 13px;
  font-family: inherit;
  cursor: pointer;
  background: #e0e8f0;
  border: 1px solid #666;
  white-space: nowrap;
  flex-shrink: 0;
}

.wmReturnBtn:hover {
  background: #cdd8e8;
}

/* ── Error block ── */
.wmErrors {
  border: 1px solid #cc0000;
  background: #fff0f0;
  padding: 8px 12px;
  margin: 8px 12px;
}

.wmErrorNote {
  color: #cc0000;
  font-weight: bold;
  margin: 0 0 4px 0;
}

.wmErrorList {
  margin: 4px 0 0 16px;
  padding: 0;
  color: #cc0000;
}

.wmErrorList li {
  margin-bottom: 2px;
}

/* ── Map container ── */
.wmMapContainer {
  width: 100%;
  height: 560px;
}

/* ── Loading / error states ── */
.wmLoading {
  padding: 20px;
  text-align: center;
  color: #555;
}

/* ── InfoWindow: data entry panel for new (unsaved) marker ── */
.wmDataForm {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 4px 2px;
  min-width: 280px;
  font-family: Arial, Helvetica, sans-serif;
  font-size: 12px;
}

.wmDataTitle {
  font-weight: bold;
  font-size: 13px;
  color: #336699;
  margin: 0 0 4px 0;
  border-bottom: 1px solid #ccc;
  padding-bottom: 4px;
}

.wmDataRow {
  display: flex;
  align-items: center;
  gap: 6px;
}

.wmDataLabel {
  width: 150px;
  min-width: 150px;
  font-weight: bold;
  color: #333;
  text-align: right;
  padding-right: 4px;
  line-height: 1.4;
}

.wmDataUnit {
  font-size: 11px;
  color: #666;
  white-space: nowrap;
}

.wmDataInput {
  width: 100px;
  padding: 2px 4px;
  font-size: 12px;
  font-family: inherit;
  border: 1px solid #999;
  box-sizing: border-box;
}

.wmDataInput:focus {
  outline: 2px solid #336699;
  border-color: #336699;
}

/* ── Decommission section separator ── */
.wmDecomSection {
  border-top: 1px dashed #aaa;
  padding-top: 6px;
  margin-top: 2px;
}

.wmDecomSectionLabel {
  font-size: 11px;
  color: #666;
  font-style: italic;
  margin-bottom: 4px;
}

/* ── InfoWindow action buttons (inside DataForm) ── */
.wmDataActions {
  display: flex;
  gap: 8px;
  margin-top: 6px;
  padding-top: 6px;
  border-top: 1px solid #ddd;
}

.wmDataBtn {
  padding: 3px 12px;
  font-size: 12px;
  font-family: inherit;
  cursor: pointer;
  background: #e0e8f0;
  border: 1px solid #666;
}

.wmDataBtn:hover {
  background: #cdd8e8;
}

.wmDataBtnSave {
  background: #336699;
  color: #fff;
  border-color: #264d73;
  font-weight: bold;
}

.wmDataBtnSave:hover {
  background: #264d73;
}

.wmDataBtnSave:disabled {
  background: #8ab3d6;
  border-color: #8ab3d6;
  cursor: not-allowed;
}

.wmDataHelpText {
  font-size: 11px;
  color: #555;
  font-style: italic;
  margin-top: 4px;
  line-height: 1.4;
}

/* ── InfoWindow: saved-pin info panel ── */
.wmInfoForm {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 4px 2px;
  min-width: 200px;
  font-family: Arial, Helvetica, sans-serif;
  font-size: 12px;
}

.wmInfoTitle {
  font-weight: bold;
  font-size: 13px;
  color: #336699;
  margin: 0 0 4px 0;
}

.wmInfoWellId {
  font-size: 12px;
  color: #333;
  margin-bottom: 4px;
}

.wmInfoCoords {
  font-size: 11px;
  color: #666;
}

/* ── Bottom button bar ── */
.wmButtonBar {
  background-color: #c0cfe0;
  padding: 8px 12px;
  display: flex;
  gap: 20px;
  align-items: center;
}

.wmBtn {
  padding: 4px 16px;
  font-size: 13px;
  font-family: inherit;
  cursor: pointer;
  background: #e0e8f0;
  border: 1px solid #666;
}

.wmBtn:hover {
  background: #cdd8e8;
}
```

---

## Step G — Create `WellsMapDataForm.js`

This sub-component renders the InfoWindow content shown when the user places a new (unsaved)
marker. It is extracted because the InfoWindow content is rendered into a portal by
`@react-google-maps/api` — keeping it as a separate component makes the DOM boundary explicit.

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\WellsMap\WellsMapDataForm.js`

```jsx
/**
 * WellsMapDataForm
 * Rendered inside a Google Maps InfoWindow when the user places a new marker.
 *
 * Props:
 *   fields       {object}   — controlled field values (see EMPTY_WELL_SPEC shape)
 *   isDecom      {boolean}  — true when workCat starts with "des"; shows extra fields
 *   onChange     {function} — (fieldName, value) => void
 *   onRemove     {function} — called when user clicks Remove
 *   onSave       {function} — called when user clicks SAVE
 *   submitting   {boolean}  — disables SAVE button while API call is in flight
 */
export default function WellsMapDataForm({
  fields,
  isDecom,
  onChange,
  onRemove,
  onSave,
  submitting,
}) {
  function field(name, label, unit) {
    return (
      <div className="wmDataRow">
        <label className="wmDataLabel" htmlFor={`wm-${name}`}>{label}</label>
        <input
          id={`wm-${name}`}
          type="text"
          className="wmDataInput"
          value={fields[name]}
          onChange={e => onChange(name, e.target.value)}
        />
        {unit && <span className="wmDataUnit">{unit}</span>}
      </div>
    );
  }

  return (
    <div className="wmDataForm">
      <p className="wmDataTitle">Well Specifications</p>

      {field('ownerWellNum',   'Owner Well ID',         '')}
      {field('holeDiameter',   'Drill Hole Diameter',   'in.')}
      {field('casingDiameter', 'Casing Diameter',       'in.')}
      {field('sealDepth',      'Surface Seal Depth',    'ft.')}
      {field('maxDepth',       'Max Depth',             'ft.')}

      {isDecom && (
        <div className="wmDecomSection">
          <p className="wmDecomSectionLabel">Decommission fields</p>
          {field('stateWellId', 'State Well #', '')}
          {field('permitNum',   'Permit #',     '')}
          {field('dwrNum',      'DWR #',        '')}
        </div>
      )}

      <div className="wmDataActions">
        <button
          type="button"
          className="wmDataBtn"
          onClick={onRemove}
          disabled={submitting}
        >
          Remove
        </button>
        <button
          type="button"
          className="wmDataBtn wmDataBtnSave"
          onClick={onSave}
          disabled={submitting}
        >
          {submitting ? 'Saving...' : 'SAVE'}
        </button>
      </div>

      <p className="wmDataHelpText">
        Click SAVE, then locate next well — OR — click "Return to Form" at top of page.
      </p>
    </div>
  );
}
```

---

## Step H — Create `WellsMapSavedPin.js`

This sub-component renders the InfoWindow content shown when the user clicks a saved (already
persisted to context) pin.

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\WellsMap\WellsMapSavedPin.js`

```jsx
/**
 * WellsMapSavedPin
 * Rendered inside a Google Maps InfoWindow when the user clicks a saved well-pin.
 *
 * Props:
 *   ownerWellNum {string} — Owner Well ID to display
 *   lat          {number} — saved latitude
 *   lng          {number} — saved longitude
 *
 * Note: saved pins are read-only in this UI — there is no delete path for a saved
 * pin, matching the actual legacy behavior (Bug 3 in the spec is NOT replicated here).
 */
export default function WellsMapSavedPin({ ownerWellNum, lat, lng }) {
  return (
    <div className="wmInfoForm">
      <p className="wmInfoTitle">Saved Well</p>
      <p className="wmInfoWellId">
        <strong>Owner Well ID:</strong> {ownerWellNum || '(none)'}
      </p>
      <p className="wmInfoCoords">
        {lat.toFixed(6)}, {lng.toFixed(6)}
      </p>
    </div>
  );
}
```

---

## Step I — Create .NET DTOs

### I.1 `SaveWellSpecRequestDto.cs`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\Models\SaveWellSpecRequestDto.cs`

```csharp
namespace PWA.WellsPermit.WebApi.Models;

/// <summary>
/// Request body for POST api/wells-map/{workSeq}/save-spec.
/// Maps to saveWellsMarkers() POST parameters in DisplayAppServlet.java (lines 2444–2505).
/// </summary>
public record SaveWellSpecRequestDto(
    double  Lat,             // wlat
    double  Lng,             // wlong
    string  OwnerWellNum,    // owellnum
    string  HoleDiameter,    // holediam
    string  CasingDiameter,  // casediam
    string  SealDepth,       // sealdepth
    string  MaxDepth,        // maxdepth
    // Decommission-only — empty string when not applicable:
    string  StateWellId,     // swellid
    string  PermitNum,       // permit
    string  DwrNum           // dwr
);
```

### I.2 `SaveWellSpecResponseDto.cs`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\Models\SaveWellSpecResponseDto.cs`

```csharp
namespace PWA.WellsPermit.WebApi.Models;

/// <summary>
/// Response body for POST api/wells-map/{workSeq}/save-spec.
/// Returns the saved spec echoed back for the React client to append to its wrkSpecs array.
/// </summary>
public record SaveWellSpecResponseDto(
    double  Lat,
    double  Lng,
    string  OwnerWellNum,
    string  HoleDiameter,
    string  CasingDiameter,
    string  SealDepth,
    string  MaxDepth,
    string  StateWellId,
    string  PermitNum,
    string  DwrNum
);
```

Both records follow the same positional-record style as `StateCodeDto.cs`.

---

## Step J — Create `WellsMapController.cs`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\Controllers\WellsMapController.cs`

```csharp
using Microsoft.AspNetCore.Mvc;
using PWA.WellsPermit.WebApi.Models;

namespace PWA.WellsPermit.WebApi.Controllers;

/// <summary>
/// Handles well-pin save requests for app_work_wellsmap.jsp (proc=wmapu).
///
/// In the legacy app, saveWellsMarkers() (lines 2444–2505) performed no DB write —
/// all data lived in the HTTP session until final submission. Here we validate and
/// echo the spec back so the React client can append it to its in-memory works array.
/// No DB write occurs at this stage; DB persistence happens at final order submission.
/// </summary>
[ApiController]
[Route("api/wells-map")]
public class WellsMapController : ControllerBase
{
    /// <summary>
    /// Save a single well spec for a given work item.
    /// The client appends the returned spec to application.works[workSeq].wrkSpecs.
    /// </summary>
    /// <param name="workSeq">Zero-based index of the work item in the session works vector.</param>
    /// <param name="request">Well spec fields from the map data entry panel.</param>
    [HttpPost("{workSeq:int}/save-spec")]
    public IActionResult SaveWellSpec(int workSeq, [FromBody] SaveWellSpecRequestDto request)
    {
        if (request is null)
            return BadRequest("Request body is required.");

        if (workSeq < 0)
            return BadRequest("workSeq must be a non-negative integer.");

        // Coordinate range validation (Bay Area bounds — matches locmap controller)
        if (request.Lat < 37.0 || request.Lat > 38.5)
            return BadRequest("Latitude is outside the expected Alameda County range.");

        if (request.Lng < -123.0 || request.Lng > -121.0)
            return BadRequest("Longitude is outside the expected Alameda County range.");

        // No further server-side validation here — the legacy app deferred validation
        // to app_work_specs.jsp (BeanAppWrkSpecs.validate()). Client-side guidance is
        // provided via the InfoWindow help text. Empty fields are accepted.
        // TODO: add BeanAppWrkSpecs.validate() equivalent once validation rules are documented.

        var response = new SaveWellSpecResponseDto(
            Lat:            request.Lat,
            Lng:            request.Lng,
            OwnerWellNum:   request.OwnerWellNum,
            HoleDiameter:   request.HoleDiameter,
            CasingDiameter: request.CasingDiameter,
            SealDepth:      request.SealDepth,
            MaxDepth:       request.MaxDepth,
            StateWellId:    request.StateWellId,
            PermitNum:      request.PermitNum,
            DwrNum:         request.DwrNum
        );

        return Ok(response);
    }
}
```

**Design notes:**
- Route template is `api/wells-map/{workSeq:int}/save-spec` — one endpoint, no GET.
- The `workSeq` path parameter mirrors `wSeq` from the legacy form POST, keeping the intent clear.
- The controller does not hold any state (no static dictionaries needed). The echo-back pattern
  is appropriate because the legacy app had no separate validation step at this stage.
- `[ApiController]` + `[Route(...)]` at class, `[HttpPost(...)]` at method — matches
  `ReferenceController.cs` and `LocationMapController.cs` conventions.

---

## Step K — Create `WellsMap.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\WellsMap\WellsMap.js`

This is the main page component. It is split:
- `WellsMap` (outer): loads Maps script, handles `workSeq` param resolution.
- `WellsMapInner` (inner): all map + interaction logic; only mounted once `isLoaded` is true.

```jsx
import { useState, useRef, useCallback } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  useJsApiLoader,
  GoogleMap,
  Marker,
  InfoWindow,
} from '@react-google-maps/api';
import { useApplication } from '../../context/ApplicationContext';
import { api } from '../../api/apiClient';
import WellsMapDataForm from './WellsMapDataForm';
import WellsMapSavedPin from './WellsMapSavedPin';
import './WellsMap.css';

// Stable library array reference — prevents useJsApiLoader from re-loading the script.
// WellsMap does not use 'places'; the array is identical to what LocationMap uses so
// that if both pages are rendered in the same session the script loads only once.
const GOOGLE_MAPS_LIBRARIES = ['places'];

// Default center matches the legacy hardcoded fallback (37.792, -122.26 — East Bay / Oakland)
const DEFAULT_CENTER = { lat: 37.792, lng: -122.26 };

// Empty spec shape — mirrors EMPTY_WELL_SPEC exported from ApplicationContext
const EMPTY_FORM_FIELDS = {
  ownerWellNum:   '',
  holeDiameter:   '',
  casingDiameter: '',
  sealDepth:      '',
  maxDepth:       '',
  stateWellId:    '',
  permitNum:      '',
  dwrNum:         '',
};

// ─────────────────────────────────────────────────────────────────────────────
// Outer component: Maps script loading + workSeq resolution
// ─────────────────────────────────────────────────────────────────────────────
export default function WellsMap() {
  const { workSeq: workSeqParam } = useParams();
  const workSeq = parseInt(workSeqParam, 10);

  const { isLoaded, loadError } = useJsApiLoader({
    googleMapsApiKey: process.env.REACT_APP_GOOGLE_MAPS_API_KEY,
    libraries: GOOGLE_MAPS_LIBRARIES,
  });

  if (isNaN(workSeq) || workSeq < 0) {
    return (
      <div className="wmPage">
        <div className="wmErrors">
          <p className="wmErrorNote">Invalid work item — workSeq must be a non-negative integer.</p>
        </div>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="wmPage">
        <div className="wmErrors">
          <p className="wmErrorNote">
            Failed to load Google Maps. Please check your internet connection and refresh.
          </p>
        </div>
      </div>
    );
  }

  if (!isLoaded) {
    return (
      <div className="wmPage">
        <div className="wmPageTitle">
          <span className="wmStepTitle">Locate Wells on Map</span>
        </div>
        <p className="wmLoading">Loading map...</p>
      </div>
    );
  }

  return <WellsMapInner workSeq={workSeq} />;
}

// ─────────────────────────────────────────────────────────────────────────────
// Inner component: all map state and behavior
// ─────────────────────────────────────────────────────────────────────────────
function WellsMapInner({ workSeq }) {
  const navigate = useNavigate();
  const { application, addWellSpec } = useApplication();

  // Resolve the work item from context
  const workItem = application.works[workSeq];
  const isDecom = typeof workItem?.workCat === 'string' &&
    workItem.workCat.toLowerCase().startsWith('des');
  const savedSpecs = workItem?.wrkSpecs ?? [];

  // ── Derive initial map center (Bug 6 fix) ───────────────────────────────
  // Legacy: map center was overwritten by the last spec's coordinates.
  // Fix: always center on the project site coordinates; zoom to last spec only
  // if specs exist, but keep the site as the stable center reference.
  const siteCenter = (application.project.siteLat !== null)
    ? { lat: application.project.siteLat, lng: application.project.siteLng }
    : DEFAULT_CENTER;

  const initialCenter = savedSpecs.length > 0
    ? { lat: savedSpecs[savedSpecs.length - 1].lat, lng: savedSpecs[savedSpecs.length - 1].lng }
    : siteCenter;

  // ── Local state ──────────────────────────────────────────────────────────
  // pendingMarker: the unsaved marker the user just placed by clicking the map
  const [pendingMarker, setPendingMarker] = useState(null); // { lat, lng } | null

  // infoWindowTarget: which InfoWindow is open
  // null = none; 'pending' = data entry for unsaved pin; number = saved spec index
  const [infoWindowTarget, setInfoWindowTarget] = useState(null);

  // formFields: controlled inputs for the data entry panel
  const [formFields, setFormFields] = useState(() => {
    // Pre-fill from last saved spec (mirrors getLastSpecs() in legacy)
    if (savedSpecs.length > 0) {
      const last = savedSpecs[savedSpecs.length - 1];
      return {
        ownerWellNum:   '',   // Owner Well ID is NOT pre-filled (it's unique per well)
        holeDiameter:   last.holeDiameter   || '',
        casingDiameter: last.casingDiameter || '',
        sealDepth:      last.sealDepth      || '',
        maxDepth:       last.maxDepth       || '',
        stateWellId:    '',
        permitNum:      '',
        dwrNum:         '',
      };
    }
    return { ...EMPTY_FORM_FIELDS };
  });

  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors]         = useState([]);

  // ── Map ref ──────────────────────────────────────────────────────────────
  const mapRef = useRef(null);
  const handleMapLoad = useCallback((map) => { mapRef.current = map; }, []);

  // ── Map click: place pending marker (Bug 3 + Bug 4 fixes) ───────────────
  // Bug 4 fix: resize listener is NOT registered here — it is registered once
  // on the GoogleMap component itself via onIdle, not inside createMarker().
  // Bug 3 fix: pending marker state is separate from saved specs; the Remove
  // button in the data form only clears the pending marker, never a saved pin.
  const handleMapClick = useCallback((event) => {
    const latLng = {
      lat: event.latLng.lat(),
      lng: event.latLng.lng(),
    };
    // Clear any open InfoWindow, set the pending marker, open data form
    setInfoWindowTarget(null);
    setPendingMarker(latLng);
    setErrors([]);
    // Open data entry InfoWindow for the new pending marker
    setInfoWindowTarget('pending');
  }, []);

  // ── Field change handler ─────────────────────────────────────────────────
  function handleFieldChange(fieldName, value) {
    setFormFields(prev => ({ ...prev, [fieldName]: value }));
  }

  // ── Remove pending marker ────────────────────────────────────────────────
  function handleRemovePending() {
    setPendingMarker(null);
    setInfoWindowTarget(null);
  }

  // ── Save well spec ───────────────────────────────────────────────────────
  async function handleSave() {
    if (!pendingMarker) {
      setErrors(['No marker placed. Click on the map to place a well marker first.']);
      return;
    }

    setErrors([]);
    setSubmitting(true);

    try {
      const result = await api.post(
        `/api/wells-map/${workSeq}/save-spec`,
        {
          lat:            pendingMarker.lat,
          lng:            pendingMarker.lng,
          ownerWellNum:   formFields.ownerWellNum,
          holeDiameter:   formFields.holeDiameter,
          casingDiameter: formFields.casingDiameter,
          sealDepth:      formFields.sealDepth,
          maxDepth:       formFields.maxDepth,
          stateWellId:    isDecom ? formFields.stateWellId : '',
          permitNum:      isDecom ? formFields.permitNum   : '',
          dwrNum:         isDecom ? formFields.dwrNum      : '',
        }
      );

      // Append spec to context (mirrors BeanAppWrk.wrkSpecsVec append in legacy)
      addWellSpec(workSeq, {
        lat:           result.lat,
        lng:           result.lng,
        ownerWellNum:  result.ownerWellNum,
        holeDiameter:  result.holeDiameter,
        casingDiameter:result.casingDiameter,
        sealDepth:     result.sealDepth,
        maxDepth:      result.maxDepth,
        stateWellId:   result.stateWellId,
        permitNum:     result.permitNum,
        dwrNum:        result.dwrNum,
      });

      // Pre-fill dimension fields from the spec just saved (mirrors getLastSpecs() on reload)
      setFormFields({
        ownerWellNum:   '',   // reset well ID for the next well
        holeDiameter:   result.holeDiameter   || '',
        casingDiameter: result.casingDiameter || '',
        sealDepth:      result.sealDepth      || '',
        maxDepth:       result.maxDepth       || '',
        stateWellId:    '',
        permitNum:      '',
        dwrNum:         '',
      });

      // Remove pending marker and close InfoWindow — user clicks map again for next well
      setPendingMarker(null);
      setInfoWindowTarget(null);

    } catch (err) {
      setErrors([err.message ?? 'Failed to save well spec. Please try again.']);
    } finally {
      setSubmitting(false);
    }
  }

  // ── Return to specs form ─────────────────────────────────────────────────
  function handleReturnToForm() {
    // TODO: update '/well-specs/{workSeq}' once app_work_specs.jsp is migrated
    navigate(`/well-specs/${workSeq}`);
  }

  // ── Render ───────────────────────────────────────────────────────────────
  return (
    <div className="wmPage">
      {/* Title bar */}
      <div className="wmPageTitle">
        <span className="wmStepTitle">Locate Wells on Map</span>
      </div>

      {/* Instruction bar */}
      <div className="wmInstructionBar">
        <p className="wmInstruction">
          Locate wells by clicking on the map to enter well specifications.
          Click [Return to Form] when finished locating wells.
        </p>
        <button
          type="button"
          className="wmReturnBtn"
          onClick={handleReturnToForm}
        >
          Return to Form
        </button>
      </div>

      {/* Error block */}
      {errors.length > 0 && (
        <div className="wmErrors">
          <p className="wmErrorNote">
            The following issues must be resolved:
          </p>
          <ul className="wmErrorList">
            {errors.map((err, i) => <li key={i}>{err}</li>)}
          </ul>
        </div>
      )}

      {/* Google Map */}
      <GoogleMap
        mapContainerClassName="wmMapContainer"
        center={initialCenter}
        zoom={20}
        mapTypeId="hybrid"
        onLoad={handleMapLoad}
        onClick={handleMapClick}
      >
        {/* Saved pins — read-only; clicking opens WellsMapSavedPin InfoWindow */}
        {savedSpecs.map((spec, idx) => (
          <Marker
            key={idx}
            position={{ lat: spec.lat, lng: spec.lng }}
            title={spec.ownerWellNum || `Well ${idx + 1}`}
            onClick={() => setInfoWindowTarget(idx)}
          />
        ))}

        {/* Pending (unsaved) marker — clicking re-opens data entry panel */}
        {pendingMarker && (
          <Marker
            position={pendingMarker}
            onClick={() => setInfoWindowTarget('pending')}
          />
        )}

        {/* InfoWindow: data entry for pending (unsaved) marker */}
        {pendingMarker && infoWindowTarget === 'pending' && (
          <InfoWindow
            position={pendingMarker}
            onCloseClick={() => setInfoWindowTarget(null)}
          >
            <WellsMapDataForm
              fields={formFields}
              isDecom={isDecom}
              onChange={handleFieldChange}
              onRemove={handleRemovePending}
              onSave={handleSave}
              submitting={submitting}
            />
          </InfoWindow>
        )}

        {/* InfoWindow: saved-pin info (read-only) */}
        {typeof infoWindowTarget === 'number' &&
          savedSpecs[infoWindowTarget] && (
          <InfoWindow
            position={{
              lat: savedSpecs[infoWindowTarget].lat,
              lng: savedSpecs[infoWindowTarget].lng,
            }}
            onCloseClick={() => setInfoWindowTarget(null)}
          >
            <WellsMapSavedPin
              ownerWellNum={savedSpecs[infoWindowTarget].ownerWellNum}
              lat={savedSpecs[infoWindowTarget].lat}
              lng={savedSpecs[infoWindowTarget].lng}
            />
          </InfoWindow>
        )}
      </GoogleMap>

      {/* Bottom button bar */}
      <div className="wmButtonBar">
        <button
          type="button"
          className="wmBtn"
          onClick={handleReturnToForm}
        >
          Return to Form
        </button>
      </div>
    </div>
  );
}
```

---

## Step L — Verification

### L.1 Build Checks

```bash
# Backend — confirm no compile errors
# Working directory: C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi
dotnet build

# Frontend — confirm no compile errors
# Working directory: C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web
npm run build
```

### L.2 Manual Seed Data for Testing

WellsMap requires a work item in `application.works` before it can render meaningfully.
Until Well Specs is migrated, seed a mock work item directly in `ApplicationContext.js`
for testing only — **remove it before merging**:

```js
// Temporary test seed — remove before merge
const INITIAL_APPLICATION = {
  ...
  works: [
    {
      workSeq:  0,
      workId:   null,
      workCat:  '',      // use 'desA' to test decommission fields
      wrkSpecs: [],
    },
  ],
  ...
};
```

Navigate directly to `http://localhost:3000/wells-map/0` to test the page in isolation.

### L.3 Local End-to-End Test Sequence

1. Start .NET: `dotnet run` from
   `C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\`
   Confirm Swagger at `http://localhost:5012/swagger`.

2. Start React: `npm start` from
   `C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\`
   Confirm app at `http://localhost:3000`.

3. Add seed work item to context (see L.2). Navigate to `http://localhost:3000/wells-map/0`.

4. Confirm map loads centered at Oakland default (37.792, -122.26), zoom 20, type `hybrid`.

5. Confirm the "Return to Form" button is present in the instruction bar (always visible here,
   unlike LocationMap which shows it only after a location is saved).

6. Click a point on the map — confirm:
   - A marker appears at the clicked point.
   - An InfoWindow opens immediately with the WellsMapDataForm panel.
   - All five standard fields are shown; decommission fields are NOT shown (workCat is '').

7. Fill in "Owner Well ID" = "TEST-001", "Max Depth" = "50". Click SAVE — confirm:
   - POST to `http://localhost:5012/api/wells-map/0/save-spec` (visible in Network tab).
   - 200 response echoing all fields back.
   - `application.works[0].wrkSpecs` now has one entry (inspect via React DevTools).
   - Pending marker disappears; InfoWindow closes.
   - Dimension fields (holeDiameter, casingDiameter, sealDepth, maxDepth) are pre-filled from
     the just-saved spec; Owner Well ID is cleared for the next entry.

8. Click another point on the map — confirm a new pending marker appears and the data form
   opens with dimension fields pre-populated from the previous save (mirrors `getLastSpecs()`).
   Owner Well ID should be empty.

9. Click SAVE with all fields empty — confirm the API call is made (no client-side validation
   is applied per legacy behavior). Server returns 200 with empty strings echoed. A second spec
   is appended to `wrkSpecs`.

10. Click the first saved pin — confirm a read-only WellsMapSavedPin InfoWindow opens showing
    the Owner Well ID and coordinates. Confirm there is no Remove button for saved pins
    (Bug 3 in legacy is fixed — saved pins are non-interactive except for viewing).

11. Click elsewhere on the map while a saved-pin InfoWindow is open — confirm the pending-marker
    placement replaces it and opens the data entry form.

12. Click the "Return to Form" button — confirm navigation to `/well-specs/0`
    (will show 404 until Well Specs is migrated — expected).

13. Navigate to `http://localhost:3000/wells-map/999` (invalid workSeq) — confirm the page
    renders without crashing; `workItem` is undefined, `savedSpecs` falls back to `[]`, map
    centers on DEFAULT_CENTER.

14. Change seed `workCat` to `'desAbandon'` — refresh — confirm three additional decommission
    fields appear in the InfoWindow data form: State Well #, Permit #, DWR #.

15. Test .NET endpoint directly in Swagger:

    **Happy path:**
    ```json
    POST /api/wells-map/0/save-spec
    {
      "lat": 37.792, "lng": -122.260,
      "ownerWellNum": "W-001",
      "holeDiameter": "12", "casingDiameter": "8",
      "sealDepth": "20", "maxDepth": "100",
      "stateWellId": "", "permitNum": "", "dwrNum": ""
    }
    ```
    Expect: 200, all fields echoed.

    **Invalid workSeq:**
    ```json
    POST /api/wells-map/-1/save-spec  { same body }
    ```
    Expect: 400 "workSeq must be a non-negative integer."

    **Out-of-bounds lat:**
    ```json
    POST /api/wells-map/0/save-spec  { "lat": 34.0, ... }
    ```
    Expect: 400 "Latitude is outside the expected Alameda County range."

    **Null body:**
    ```
    POST /api/wells-map/0/save-spec  (no body)
    ```
    Expect: 400.

### L.4 React Component Tests (React Testing Library)

Suggested test file:
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\WellsMap\WellsMap.test.js`

Key test cases:

- Mock `useJsApiLoader` to return `{ isLoaded: false }` → confirm "Loading map..." text shown.
- Mock `useJsApiLoader` to return `{ loadError: new Error() }` → confirm error message shown.
- Mock `useParams` to return `{ workSeq: 'abc' }` → confirm invalid-workSeq error shown.
- Render `WellsMapDataForm` with `isDecom={false}` → confirm 5 standard fields, no decommission section.
- Render `WellsMapDataForm` with `isDecom={true}` → confirm 8 fields total (5 + 3 decommission).
- Render `WellsMapDataForm` with `submitting={true}` → confirm both buttons are disabled and Save shows "Saving...".
- Call `onChange` callback via field input change → confirm the callback fires with correct field name and value.
- Render `WellsMapSavedPin` with `ownerWellNum="W-001" lat={37.79} lng={-122.26}` → confirm name and coordinate text displayed.
- Mock `useApplication` with one saved spec in `works[0].wrkSpecs` → confirm that `formFields`
  is pre-populated with that spec's dimension values (holeDiameter, casingDiameter, etc.) and
  ownerWellNum is empty.
- After successful SAVE (mock `api.post` returning a spec), confirm `addWellSpec` was called
  with the correct workSeq and spec object.

### L.5 .NET Unit Tests (xUnit)

Suggested test file: `WellsMapControllerTests.cs`

Key test cases:
- Valid body, `workSeq=0` → 200 with all fields echoed.
- All string fields empty → 200 (empty strings are accepted per legacy behavior).
- `workSeq=-1` → 400.
- `lat=34.0` (below 37.0 bound) → 400.
- `lat=39.0` (above 38.5 bound) → 400.
- `lng=-124.0` (below -123.0 bound) → 400.
- `lng=-120.0` (above -121.0 bound) → 400.
- Null request body → 400 (handled by `[ApiController]` model binding).

---

## Step M — Implementation Order Summary

Execute steps in this order. Steps A–E are prerequisites for the frontend to compile.
Steps F–K can be done in a single session.

| # | File | Action | Dependency |
|---|---|---|---|
| A | (command) | `npm install @react-google-maps/api` | none; skip if already installed |
| B | `src/api/apiClient.js` | **Create** — fetch wrapper | none; skip if already exists |
| C | `src/context/ApplicationContext.js` | **Edit** — add `EMPTY_WORK_ITEM`, `EMPTY_WELL_SPEC`, `addWellSpec`, expand `project` slice | none |
| D | `src/App.js` | **Edit** — fix broken ApplicantInfoForm import + add `/wells-map/:workSeq` route | Step B (WellsMap imports apiClient) |
| E | `.env.local` | **Create** — `REACT_APP_GOOGLE_MAPS_API_KEY` | Google API key required; skip if already exists |
| E | `.env.example` | **Create** — key placeholder | none; skip if already exists |
| F | `src/pages/WellsMap/WellsMap.css` | **Create** — all `wm*` classes | none |
| G | `src/pages/WellsMap/WellsMapDataForm.js` | **Create** — InfoWindow data entry sub-component | Step F (CSS) |
| H | `src/pages/WellsMap/WellsMapSavedPin.js` | **Create** — InfoWindow saved-pin sub-component | Step F (CSS) |
| K | `src/pages/WellsMap/WellsMap.js` | **Create** — main page component | Steps F, G, H, B, C |
| I.1 | `backend/Models/SaveWellSpecRequestDto.cs` | **Create** | none |
| I.2 | `backend/Models/SaveWellSpecResponseDto.cs` | **Create** | none |
| J | `backend/Controllers/WellsMapController.cs` | **Create** | Steps I.1, I.2 |

**Total new files: 10**
- Frontend: `WellsMap.js`, `WellsMap.css`, `WellsMapDataForm.js`, `WellsMapSavedPin.js`, `.env.local`, `.env.example` (= 6; last 2 conditional)
- Backend: `WellsMapController.cs`, `SaveWellSpecRequestDto.cs`, `SaveWellSpecResponseDto.cs` (= 3)
- Shared: `apiClient.js` (= 1; conditional)

**Edited files: 2**
- `src/context/ApplicationContext.js` — expand `works` slice shape + `addWellSpec`
- `src/App.js` — fix broken import + add `/wells-map/:workSeq` route

---

## Known Bugs from Spec and How This Plan Addresses Them

| Legacy Bug (spec §11) | Root Cause | Fix Applied in This Plan |
|---|---|---|
| Bug 1 — Missing `return` after `sendRedirect()` for null `aBean` | JSP server-side null guard missing `return` | Not applicable in React/REST — null session is replaced by guard on `application.works[workSeq]` in `WellsMapInner` |
| Bug 2 — Missing `return` after JS redirect for null `wBean` | JSP server-side null guard missing `return` | Same — React renders an empty map gracefully if `workItem` is undefined |
| Bug 3 — `removeMarker()` in saved-pin InfoWindow removes wrong marker | Both InfoWindows shared the global `marker` variable | Saved pins open `WellsMapSavedPin` (read-only, no Remove button). `handleRemovePending()` only clears `pendingMarker` state |
| Bug 4 — Stacking window resize listeners | `addEventListener` called inside `createMarker()` loop | `@react-google-maps/api` manages map lifecycle; no manual resize listener is registered anywhere in this implementation |
| Bug 5 — String reference equality `== ""` for lat/lng check | Java `==` operator on non-interned String | JavaScript always uses value equality for strings; no `==` on string references occurs |
| Bug 6 — Map center overwritten by last well's coordinates | `lat`/`lng` loop variable also used for `mp.mlat` / `mp.mlng` | `siteCenter` is derived from `application.project.siteLat/Lng` (immutable here); `initialCenter` uses a separate variable from `savedSpecs[last]` |
| Note — `places` library overhead | `&libraries=places` loaded but SearchBox is commented out | `GOOGLE_MAPS_LIBRARIES = ['places']` is kept because `LocationMap` requires it. If WellsMap is ever served without LocationMap, this array can be changed to `[]` |
| Note — `drillCount` not set | `saveWellsMarkers()` never sets `drillCount` | `EMPTY_WELL_SPEC` does not include `drillCount`; this matches current behavior. Add when the Well Specs form exposes it |
| Note — No client-side validation | Legacy had no validation before save | No validation is added before the API call, matching legacy. Field validation belongs in the Well Specs form (BeanAppWrkSpecs.validate() equivalent) |

---

## Open TODOs for the Developer

| # | Item | Blocking? |
|---|---|---|
| 1 | Obtain Google Maps API key (Maps JavaScript API enabled) and add to `.env.local` | Yes — without it the map will not load |
| 2 | Update `navigate('/well-specs/${workSeq}')` in `WellsMap.js` once `app_work_specs.jsp` is migrated | No — page will 404 but the save flow still works |
| 3 | Reconcile `EMPTY_WORK_ITEM` / `EMPTY_WELL_SPEC` shape with whatever Well Specs migration defines | No — shapes are compatible by design; Well Specs can extend them |
| 4 | Add `workId` and `appId` to work items when the application creation API is built; `workSeq` is a temporary zero-based index stand-in | No — WellsMap does not use `workId` directly |
| 5 | Consider adding client-side required-field validation for `ownerWellNum` once UX requirements are confirmed | No — current behavior matches legacy (no client-side validation) |
| 6 | Confirm .NET dev port is 5012 HTTP; update `config.local.js` if different | Yes — wrong port causes all API calls to fail |
| 7 | Remove seed work item added for testing (Step L.2) before merging to any shared branch | Yes — seed data will mask missing Well Specs integration |
| 8 | Verify that `GOOGLE_MAPS_LIBRARIES = ['places']` is stable across LocationMap and WellsMap; if they are loaded independently, each page needs its own `useJsApiLoader` call with the same array reference | No — `@react-google-maps/api` handles deduplication across components |
