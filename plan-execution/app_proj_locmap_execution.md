# Execution Plan: app_proj_locmap.jsp → React + .NET

## What This Document Is

The migration plan (`app_proj_locmap_migration.md`) describes _what_ to build and _why_.
This document is the concrete _how_: exact file paths, complete code for every file, step-by-step
commands, and a corrections section that documents where the migration plan diverged from the
actual codebase found on disk.

---

## Codebase Reality Corrections

The migration plan was written before several project files existed in their final form. The
following discrepancies must be handled during execution — do not follow the migration plan on
these points, follow this document instead.

| # | Migration Plan Said | Actual Codebase | Correction Applied |
|---|---|---|---|
| 1 | `ApplicantInfoForm` lives at `src/pages/ApplicantInfoForm/ApplicantInfoForm.js` | File is at `src/pages/ApplicantInfoForm/ApplicantInfoForm.js` — correct path | But `App.js` **imports** it from `./components/ApplicantInfo/ApplicantInfoForm` — that path is wrong and the app currently cannot compile. Fix the import in Step C.1. |
| 2 | `LocationMap` goes in `src/pages/LocationMap/` | Convention is `src/pages/<PageName>/` (matching `ApplicantInfoForm`) | Confirmed: use `src/pages/LocationMap/` |
| 3 | `api.get`/`api.post` from `src/api/apiClient.js` | `apiClient.js` does not exist. `ApplicantInfoForm.js` imports it (`../../api/apiClient`) — broken. The only API file is `src/api/apnApi.js` which uses `axios` via `useApiClient` hook with auth. | Create `src/api/apiClient.js` as Step B.1 — this unblocks both the existing broken import and the new component simultaneously. |
| 4 | Config `apiBaseUrl` is `http://localhost:5012` | `config.local.js` has `apiBaseUrl: "https://localhost:7241"` | The .NET project listens on HTTP 5012 / HTTPS 7296 (per CLAUDE.md). The CORS policy in `Program.cs` allows `http://localhost:3000`. Because the React app runs HTTP, calling an HTTPS backend from HTTP causes a mixed-content issue in some browsers. Use `http://localhost:5012` in `config.local.js`. |
| 5 | `LocationMap` component folder described as `src/pages/LocationMap/` | Consistent with actual conventions | Confirmed — file layout is correct in the plan. |
| 6 | `ApplicationContext.js` `project` slice shown with sample fields | Actual `project` slice is `{}` (empty object) | All five fields must be explicitly added to `INITIAL_APPLICATION.project`. |
| 7 | Plan shows `@react-google-maps/api` not installed | `package.json` has no map library | Confirmed — must install. |

---

## Prerequisites

Before executing any step:

1. Obtain a Google Maps API key from the Alameda County Google Cloud Console project. The key
   must have three APIs enabled: **Maps JavaScript API**, **Places API**, and **Geocoding API**.
   Without a key the map will not load and the page cannot be tested end-to-end.

2. Confirm the actual city code values from the `city_codes` table in the EEAOWN schema (or read
   `BeanCodesCity.java` in the legacy source). The placeholder codes (`HAY`, `ALA`, `OAK`, etc.)
   in the controller are guesses and must be replaced before any integration test.

3. Confirm the correct .NET dev port. CLAUDE.md documents port 5012 (HTTP). Use that value
   unless `launchSettings.json` overrides it.

---

## Step A — npm Package Install

Run once from the frontend project root.

```bash
# Working directory: frontend/pwa-wells-permit-web/
npm install @react-google-maps/api
```

After install, `package.json` will gain `"@react-google-maps/api": "^2.x.x"` in `dependencies`.
No other new packages are needed — `react-router-dom ^7.14.2` already covers navigation.

---

## Step B — Create `apiClient.js`

This file is imported by the already-existing `ApplicantInfoForm.js` but does not exist on disk.
Creating it is the highest-priority step because it unblocks both the current broken build and
the new `LocationMap` component.

**File to create:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\api\apiClient.js`

```js
/**
 * apiClient.js — Thin fetch wrapper for the Wells Permit .NET API.
 *
 * Exports a plain `api` object with get / post / put methods.
 * No authentication is required for the Wells Permit public-facing endpoints.
 * For authenticated internal endpoints, use src/components/utils/http.js instead.
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
  get:  (path)       => request('GET',  path),
  post: (path, body) => request('POST', path, body),
  put:  (path, body) => request('PUT',  path, body),
};
```

**Why this pattern:** matches the `api.get('/api/ref/states')` and `api.post(...)` calls already
written in `ApplicantInfoForm.js`. The existing `src/components/utils/http.js` uses `axios` +
auth tokens and is meant for the authenticated internal APN API — not appropriate for the public
permit application flow.

---

## Step C — Fix `config.local.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\config\config.local.js`

Change `apiBaseUrl` from `https://localhost:7241` to `http://localhost:5012`:

```js
// Before:
apiBaseUrl: "https://localhost:7241",

// After:
apiBaseUrl: "http://localhost:5012",
```

The CORS policy in `Program.cs` allows `http://localhost:3000`. Matching HTTP-to-HTTP avoids
mixed-content browser blocking during local development. If HTTPS is required (e.g., the .NET
dev cert is trusted), use `https://localhost:7296` instead — but confirm with the team first.

---

## Step D — Update `ApplicationContext.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\context\ApplicationContext.js`

The current `project` slice is `{}`. Replace it with the five location fields:

```js
// Current (line 6-12):
const INITIAL_APPLICATION = {
  project: {},
  works: [],
  applicant: {},
  hazard: null,
  payment: null,
  siteHazardRequired: false,
};

// Replace with:
const INITIAL_APPLICATION = {
  project: {
    siteLat:      null,  // number | null  — null means no marker placed yet
    siteLng:      null,  // number | null
    siteLocation: '',    // string — formatted address / description (max 200 chars)
    siteCityName: '',    // string — locality name from geocoder
    siteCityCode: '',    // string — city code returned by .NET lookup
  },
  works: [],
  applicant: {},
  hazard: null,
  payment: null,
  siteHazardRequired: false,
};
```

No new updater methods are needed. The existing `updateProject(data)` on line 20-21 performs a
full slice replace (`setApplication(prev => ({ ...prev, project: data }))`), which is the correct
pattern for the location save flow.

---

## Step E — Fix `App.js` Import and Add Route

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\App.js`

The current `App.js` imports `ApplicantInfoForm` from `./components/ApplicantInfo/ApplicantInfoForm`
which does not exist — the file is at `./pages/ApplicantInfoForm/ApplicantInfoForm`. Fix the import
path and add the `LocationMap` route at the same time:

```jsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ApplicationProvider } from './context/ApplicationContext';
import ApplicantInfoForm from './pages/ApplicantInfoForm/ApplicantInfoForm';
import LocationMap from './pages/LocationMap/LocationMap';

function App() {
  return (
    <ApplicationProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/applicant-info" element={<ApplicantInfoForm />} />
          <Route path="/location-map"   element={<LocationMap />} />
          {/* Future routes added here as each JSP is migrated */}
          <Route path="/" element={<Navigate to="/applicant-info" replace />} />
        </Routes>
      </BrowserRouter>
    </ApplicationProvider>
  );
}

export default App;
```

---

## Step F — Update `ApplicantInfoForm.js` Navigation Target

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\ApplicantInfoForm\ApplicantInfoForm.js`

In the current `handleSubmit` (lines 99-115), after saving applicant data the code navigates to
`/hazard-info` or `/payment-info` based on `siteHazardRequired`. According to the workflow spec,
Step 1 (Applicant Info) feeds into Step 2 (Location Map), so change the navigation target:

```js
// Current (line 109):
const nextRoute = application.siteHazardRequired ? '/hazard-info' : '/payment-info';
navigate(nextRoute);

// Replace with:
navigate('/location-map');
```

This wires the workflow: Applicant Info → Location Map → (Work Types, once migrated).

---

## Step G — Environment Variable Files

### G.1 `.env.local` (not committed to git)

Create at:
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\.env.local`

```
# Google Maps API key — requires Maps JavaScript API, Places API, Geocoding API enabled
REACT_APP_GOOGLE_MAPS_API_KEY=<paste_dev_key_here>
```

### G.2 `.env.example` (committed to git)

Create at:
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\.env.example`

```
# Google Maps API key — requires Maps JavaScript API, Places API, Geocoding API enabled
REACT_APP_GOOGLE_MAPS_API_KEY=
```

The key is consumed in `LocationMap.js` as `process.env.REACT_APP_GOOGLE_MAPS_API_KEY`. React's
build pipeline (Create React App 5) injects all `REACT_APP_*` variables at build time.

---

## Step H — Create `LocationMap.css`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\LocationMap\LocationMap.css`

All classes use the `lm` prefix, matching the `ai` prefix pattern in `ApplicantInfoForm.css`.
Colors, fonts, spacing, and button styles are taken directly from the existing CSS to ensure
visual consistency across steps.

```css
/* ── Page wrapper ── */
.lmPage {
  background: #fff;
  max-width: 960px;
  margin: 0 auto;
  font-family: Arial, Helvetica, sans-serif;
  font-size: 13px;
}

/* ── Step title bar ── */
.lmPageTitle {
  background-color: #336699;
  padding: 6px 10px;
}

.lmStepTitle {
  color: #fff;
  font-size: 15px;
  font-weight: bold;
}

/* ── Instruction bar (above map) ── */
.lmInstructionBar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background-color: #d9e6f2;
  padding: 8px 12px;
  gap: 12px;
}

.lmInstruction {
  font-size: 13px;
  color: #333;
  flex: 1;
}

.lmInstructionActions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}

/* ── Return to Form button ── */
.lmReturnBtn {
  padding: 4px 14px;
  font-size: 13px;
  font-family: inherit;
  cursor: pointer;
  background: #e0e8f0;
  border: 1px solid #666;
}

.lmReturnBtn:hover {
  background: #cdd8e8;
}

/* ── Help button ── */
.lmHelpBtn {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background-color: #336633;
  color: #fff;
  font-weight: bold;
  font-size: 15px;
  border: none;
  cursor: pointer;
  line-height: 28px;
  text-align: center;
  padding: 0;
  font-family: inherit;
}

.lmHelpBtn:hover {
  background-color: #254d25;
}

/* ── Search box ── */
.lmSearchBox {
  background-color: #f0f4f8;
  padding: 6px 12px;
  border-bottom: 1px solid #ccc;
}

.lmSearchInput {
  width: 400px;
  padding: 4px 8px;
  font-size: 13px;
  font-family: 'Roboto', Arial, sans-serif;
  border: 1px solid #999;
  box-sizing: border-box;
}

.lmSearchInput:focus {
  outline: 2px solid #336699;
  border-color: #336699;
}

/* ── Map container ── */
.lmMapContainer {
  width: 100%;
  height: 520px;
}

/* ── InfoWindow form ── */
.lmInfoWindowForm {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 4px;
  min-width: 300px;
}

.lmInfoLabel {
  font-weight: bold;
  font-size: 12px;
  color: #333;
  margin-bottom: 2px;
}

.lmInfoTextarea {
  width: 320px;
  height: 80px;
  padding: 4px;
  font-size: 12px;
  font-family: inherit;
  border: 1px solid #999;
  resize: vertical;
  box-sizing: border-box;
}

.lmInfoInput {
  width: 320px;
  padding: 4px;
  font-size: 12px;
  font-family: inherit;
  border: 1px solid #999;
  box-sizing: border-box;
}

.lmInfoActions {
  display: flex;
  gap: 8px;
  margin-top: 4px;
}

.lmInfoBtn {
  padding: 4px 12px;
  font-size: 12px;
  font-family: inherit;
  cursor: pointer;
  background: #e0e8f0;
  border: 1px solid #666;
}

.lmInfoBtn:hover {
  background: #cdd8e8;
}

.lmInfoBtnSave {
  background: #2e7d32;
  color: #fff;
  border-color: #1b5e20;
  font-weight: bold;
}

.lmInfoBtnSave:hover {
  background: #1b5e20;
}

.lmInfoBtnSave:disabled {
  background: #a5d6a7;
  border-color: #a5d6a7;
  cursor: not-allowed;
}

/* ── Out-of-jurisdiction warning InfoWindow ── */
.lmWarningBox {
  padding: 8px;
  max-width: 300px;
}

.lmWarningIcon {
  font-size: 18px;
  margin-right: 4px;
}

.lmWarningText {
  font-size: 12px;
  color: #b71c1c;
  margin: 6px 0;
  line-height: 1.5;
}

.lmWarningLink {
  font-size: 12px;
  color: #336699;
}

/* ── Help modal overlay ── */
.lmModal {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  z-index: 1000;
  display: flex;
  align-items: center;
  justify-content: center;
}

.lmModalBox {
  background: #fff;
  border: 1px solid #666;
  padding: 20px 24px;
  max-width: 540px;
  width: 90%;
  font-size: 13px;
  font-family: Arial, Helvetica, sans-serif;
}

.lmModalTitle {
  font-size: 15px;
  font-weight: bold;
  color: #336699;
  margin: 0 0 12px 0;
}

.lmModalBody {
  color: #333;
  line-height: 1.6;
}

.lmModalBody p {
  margin: 0 0 8px 0;
}

.lmModalBody ul {
  margin: 0 0 8px 16px;
  padding: 0;
}

.lmModalBody li {
  margin-bottom: 4px;
}

.lmModalClose {
  display: block;
  margin-top: 16px;
  padding: 4px 20px;
  font-size: 13px;
  font-family: inherit;
  cursor: pointer;
  background: #e0e8f0;
  border: 1px solid #666;
}

.lmModalClose:hover {
  background: #cdd8e8;
}

/* ── Error block ── */
.lmErrors {
  border: 1px solid #cc0000;
  background: #fff0f0;
  padding: 8px 12px;
  margin: 8px 12px;
}

.lmErrorNote {
  color: #cc0000;
  font-weight: bold;
  margin: 0 0 4px 0;
}

.lmErrorList {
  margin: 4px 0 0 16px;
  padding: 0;
  color: #cc0000;
}

.lmErrorList li {
  margin-bottom: 2px;
}

/* ── Bottom button bar ── */
.lmButtonBar {
  background-color: #c0cfe0;
  padding: 8px 12px;
  display: flex;
  gap: 20px;
  align-items: center;
}

.lmBtn {
  padding: 4px 16px;
  font-size: 13px;
  font-family: inherit;
  cursor: pointer;
  background: #e0e8f0;
  border: 1px solid #666;
}

.lmBtn:hover {
  background: #cdd8e8;
}

/* ── Loading state ── */
.lmLoading {
  padding: 20px;
  text-align: center;
  color: #555;
}
```

---

## Step I — Create `LocationHelpModal.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\LocationMap\LocationHelpModal.js`

```jsx
/**
 * LocationHelpModal — Full-screen overlay with map usage instructions.
 * Props:
 *   open   {boolean} — whether to render the modal
 *   onClose {function} — called when user clicks Close
 */
export default function LocationHelpModal({ open, onClose }) {
  if (!open) return null;

  return (
    <div className="lmModal" role="dialog" aria-modal="true" aria-labelledby="lmModalTitle">
      <div className="lmModalBox">
        <h2 id="lmModalTitle" className="lmModalTitle">
          Project Location Map — Help
        </h2>
        <div className="lmModalBody">
          <p><strong>How to set your project location:</strong></p>
          <ul>
            <li>
              <strong>Click on the map</strong> to drop a marker at your project site.
              The address will be filled in automatically from the clicked coordinates.
            </li>
            <li>
              <strong>Use the Search Address box</strong> above the map to search by
              address or location name. The map will zoom to the result and place a marker.
            </li>
            <li>
              After placing a marker, you may <strong>edit the Location Description</strong>
              in the text field — for example, to add a suite number or landmark detail.
              The field is limited to 200 characters.
            </li>
            <li>
              The <strong>Location City</strong> field is filled automatically. If it appears
              incorrect, remove the marker and re-pin the correct location.
            </li>
            <li>
              If the selected location is <strong>outside Alameda County Public Works
              jurisdiction</strong>, a warning message will appear. Click elsewhere on
              the map to choose a different location.
            </li>
            <li>
              Click <strong>SAVE AND CONTINUE</strong> to save the location and proceed
              to the next step. Click <strong>Remove marker</strong> to start over.
            </li>
          </ul>
          <p>
            <strong>Note:</strong> The map is restricted to the Bay Area. Panning outside
            this area will snap the map back to the valid region.
          </p>
        </div>
        <button className="lmModalClose" onClick={onClose}>
          Close
        </button>
      </div>
    </div>
  );
}
```

---

## Step J — Create `LocationInfoWindow.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\LocationMap\LocationInfoWindow.js`

```jsx
/**
 * LocationInfoWindow — Content rendered inside the Google Maps InfoWindow
 * when a marker is placed within Alameda County jurisdiction.
 *
 * Props:
 *   locDesc      {string}   — current value of the location description textarea
 *   locCity      {string}   — current value of the city input
 *   onDescChange {function} — called with new locDesc string on textarea change
 *   onCityChange {function} — called with new locCity string on input change
 *   onRemove     {function} — called when user clicks "Remove marker"
 *   onSave       {function} — called when user clicks "SAVE AND CONTINUE"
 *   submitting   {boolean}  — disables Save button while API call is in flight
 */
export default function LocationInfoWindow({
  locDesc,
  locCity,
  onDescChange,
  onCityChange,
  onRemove,
  onSave,
  submitting,
}) {
  return (
    <div className="lmInfoWindowForm">
      <div>
        <label className="lmInfoLabel" htmlFor="lmLocDesc">
          Location Address / Description
        </label>
        <textarea
          id="lmLocDesc"
          className="lmInfoTextarea"
          maxLength={200}
          value={locDesc}
          onChange={e => onDescChange(e.target.value)}
        />
      </div>
      <div>
        <label className="lmInfoLabel" htmlFor="lmLocCity">
          Location City
        </label>
        <input
          id="lmLocCity"
          type="text"
          className="lmInfoInput"
          maxLength={200}
          value={locCity}
          onChange={e => onCityChange(e.target.value)}
        />
      </div>
      <div className="lmInfoActions">
        <button
          type="button"
          className="lmInfoBtn"
          onClick={onRemove}
          disabled={submitting}
        >
          Remove marker
        </button>
        <button
          type="button"
          className="lmInfoBtn lmInfoBtnSave"
          onClick={onSave}
          disabled={submitting}
        >
          {submitting ? 'Saving...' : 'SAVE AND CONTINUE'}
        </button>
      </div>
    </div>
  );
}
```

---

## Step K — Create `LocationOutOfBounds.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\LocationMap\LocationOutOfBounds.js`

```jsx
/**
 * LocationOutOfBounds — Content rendered inside the Google Maps InfoWindow
 * when a marker is placed outside Alameda County jurisdiction.
 * No props — this component is purely presentational.
 */
export default function LocationOutOfBounds() {
  return (
    <div className="lmWarningBox">
      <span className="lmWarningIcon" aria-hidden="true">&#9888;</span>
      <p className="lmWarningText">
        Location is not within Alameda County Public Works Jurisdiction, or the
        address returned is not sufficient. Click on the map area to retry.
      </p>
      <a
        href="https://www.acpwa.org/drilling-and-wells-permit"
        target="_blank"
        rel="noopener noreferrer"
        className="lmWarningLink"
      >
        Visit acpwa.org for jurisdiction information
      </a>
    </div>
  );
}
```

---

## Step L — Create `LocationMap.js`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages\LocationMap\LocationMap.js`

This is the main page component. It is split into two parts:
- `LocationMap` (outer): handles API loading state only
- `LocationMapInner` (inner): all map logic; only mounted once `isLoaded` is true

```jsx
import { useState, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  useJsApiLoader,
  GoogleMap,
  Marker,
  InfoWindow,
  StandaloneSearchBox,
} from '@react-google-maps/api';
import { useApplication } from '../../context/ApplicationContext';
import { api } from '../../api/apiClient';
import LocationInfoWindow from './LocationInfoWindow';
import LocationOutOfBounds from './LocationOutOfBounds';
import LocationHelpModal from './LocationHelpModal';
import './LocationMap.css';

// Defined outside the component so the array reference is stable across renders.
// Changing this reference causes useJsApiLoader to reload the entire Maps script.
const GOOGLE_MAPS_LIBRARIES = ['places'];

// Alameda County approved cities (must match _cityCodes keys in LocationMapController.cs)
const APPROVED_CITIES = new Set([
  'Hayward',
  'Alameda',
  'Oakland',
  'Castro Valley',
  'Emeryville',
  'Albany',
  'Piedmont',
  'San Lorenzo',
  'San Leandro',
]);

function isInJurisdiction(city) {
  return APPROVED_CITIES.has(city);
}

// Bay Area bounding box: SW corner → NE corner
const BOUNDS_SW = { lat: 37.453764, lng: -122.369047 };
const BOUNDS_NE = { lat: 37.922153, lng: -121.638478 };

// Default center when no saved location exists
const DEFAULT_CENTER = { lat: 37.79, lng: -122.26 };

// ─────────────────────────────────────────────────────────────────────────────
// Outer component: only responsible for loading the Maps script
// ─────────────────────────────────────────────────────────────────────────────
export default function LocationMap() {
  const { isLoaded, loadError } = useJsApiLoader({
    googleMapsApiKey: process.env.REACT_APP_GOOGLE_MAPS_API_KEY,
    libraries: GOOGLE_MAPS_LIBRARIES,
  });

  if (loadError) {
    return (
      <div className="lmPage">
        <div className="lmErrors">
          <p className="lmErrorNote">
            Failed to load Google Maps. Please check your internet connection and refresh.
          </p>
        </div>
      </div>
    );
  }

  if (!isLoaded) {
    return (
      <div className="lmPage">
        <div className="lmPageTitle">
          <span className="lmStepTitle">Project Location Map</span>
        </div>
        <p className="lmLoading">Loading map...</p>
      </div>
    );
  }

  return <LocationMapInner />;
}

// ─────────────────────────────────────────────────────────────────────────────
// Inner component: all map state and behavior
// ─────────────────────────────────────────────────────────────────────────────
function LocationMapInner() {
  const navigate = useNavigate();
  const { application, updateProject } = useApplication();
  const { siteLat, siteLng, siteLocation, siteCityName } = application.project;

  // locset: true when the user has a previously saved location
  const locset = siteLat !== null;

  // ── Local state ──────────────────────────────────────────────────────────
  const [markerPos, setMarkerPos]               = useState(
    locset ? { lat: siteLat, lng: siteLng } : null
  );
  const [infoWindowContent, setInfoWindowContent] = useState(
    locset ? 'form' : null   // 'form' | 'warning' | null
  );
  const [locDesc, setLocDesc]   = useState(siteLocation);
  const [locCity, setLocCity]   = useState(siteCityName);
  const [helpOpen, setHelpOpen] = useState(false);
  const [errors, setErrors]     = useState([]);
  const [submitting, setSubmitting] = useState(false);

  // ── Map refs ─────────────────────────────────────────────────────────────
  const mapRef              = useRef(null);
  const searchBoxRef        = useRef(null);
  const lastValidCenterRef  = useRef(
    locset ? { lat: siteLat, lng: siteLng } : DEFAULT_CENTER
  );

  const initialCenter = locset ? { lat: siteLat, lng: siteLng } : DEFAULT_CENTER;
  const initialZoom   = locset ? 20 : 16;

  // ── Geocoder (created once the Maps script is loaded) ─────────────────────
  const geocoderRef = useRef(null);
  function getGeocoder() {
    if (!geocoderRef.current) {
      geocoderRef.current = new window.google.maps.Geocoder();
    }
    return geocoderRef.current;
  }

  // ── Map load callback ─────────────────────────────────────────────────────
  const handleMapLoad = useCallback((map) => {
    mapRef.current = map;
  }, []);

  // ── Bounds enforcement on idle ────────────────────────────────────────────
  const handleMapIdle = useCallback(() => {
    if (!mapRef.current) return;
    const center = mapRef.current.getCenter();
    const lat = center.lat();
    const lng = center.lng();
    const outOfBounds =
      lat < BOUNDS_SW.lat || lat > BOUNDS_NE.lat ||
      lng < BOUNDS_SW.lng || lng > BOUNDS_NE.lng;
    if (outOfBounds) {
      mapRef.current.setCenter(lastValidCenterRef.current);
    } else {
      lastValidCenterRef.current = { lat, lng };
    }
  }, []);

  // ── Click-to-pin ──────────────────────────────────────────────────────────
  const handleMapClick = useCallback((event) => {
    const latLng = { lat: event.latLng.lat(), lng: event.latLng.lng() };
    setMarkerPos(latLng);
    setLocDesc('');
    setLocCity('');
    setInfoWindowContent(null);
    setErrors([]);

    getGeocoder().geocode({ location: latLng }, (results, status) => {
      if (status !== 'OK' || !results?.[0]) return;
      const address = results[0].formatted_address;
      setLocDesc(address);
      const cityComp = results[0].address_components
        .find(c => c.types[0] === 'locality');
      const city = cityComp?.long_name ?? '';
      setLocCity(city);
      setInfoWindowContent(isInJurisdiction(city) ? 'form' : 'warning');
    });
  }, []);

  // ── Search box: places changed ────────────────────────────────────────────
  const handlePlacesChanged = useCallback(() => {
    if (!searchBoxRef.current) return;
    const places = searchBoxRef.current.getPlaces();
    if (!places?.length) return;

    const place = places[0];
    const latLng = {
      lat: place.geometry.location.lat(),
      lng: place.geometry.location.lng(),
    };
    setMarkerPos(latLng);
    setErrors([]);

    // Build description: if place name starts with same char as address, use address only
    const addr = place.formatted_address ?? '';
    const name = place.name ?? '';
    const desc =
      addr[0]?.toLowerCase() === name[0]?.toLowerCase()
        ? addr
        : `${addr}\n${name}`;
    setLocDesc(desc);

    // Extract city from address_components, or fall back to geocoder
    const cityComp = place.address_components?.find(c => c.types[0] === 'locality');
    if (cityComp) {
      const city = cityComp.long_name;
      setLocCity(city);
      setInfoWindowContent(isInJurisdiction(city) ? 'form' : 'warning');
    } else {
      getGeocoder().geocode({ location: latLng }, (results, status) => {
        if (status !== 'OK' || !results?.[0]) return;
        const fallbackCity = results[0].address_components
          ?.find(c => c.types[0] === 'locality')?.long_name ?? '';
        setLocCity(fallbackCity);
        setInfoWindowContent(isInJurisdiction(fallbackCity) ? 'form' : 'warning');
      });
    }

    // Fit map bounds to all results
    if (mapRef.current) {
      const bounds = new window.google.maps.LatLngBounds();
      places.forEach(p => {
        if (p.geometry.viewport) bounds.union(p.geometry.viewport);
        else bounds.extend(p.geometry.location);
      });
      mapRef.current.fitBounds(bounds);
    }
  }, []);

  // ── Remove marker ─────────────────────────────────────────────────────────
  function handleRemoveMarker() {
    setMarkerPos(null);
    setInfoWindowContent(null);
    // locDesc and locCity are intentionally NOT cleared — matches legacy behavior
  }

  // ── Submit / Save and Continue ────────────────────────────────────────────
  async function handleSubmit() {
    const validationErrors = [];
    if (!markerPos) {
      validationErrors.push(
        'Please click on the map or search for an address to set a project location.'
      );
    }
    if (!locDesc.trim()) {
      validationErrors.push('Location description is required.');
    }
    if (!locCity.trim()) {
      validationErrors.push(
        'Location city could not be determined. Please remove the marker and re-pin your location.'
      );
    }
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    setErrors([]);
    setSubmitting(true);

    try {
      const result = await api.post('/api/location-map/save', {
        lat:     markerPos.lat,
        lng:     markerPos.lng,
        projLoc: locDesc.trim(),
        locCity: locCity.trim(),
      });

      updateProject({
        ...application.project,
        siteLat:      result.siteLat,
        siteLng:      result.siteLng,
        siteLocation: result.siteLocation,
        siteCityName: result.siteCityName,
        siteCityCode: result.cityCode,
      });

      // TODO: update '/work-types' once app_wrktp.jsp is migrated
      navigate('/work-types');
    } catch (err) {
      setErrors([err.message ?? 'Failed to save location. Please try again.']);
    } finally {
      setSubmitting(false);
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <div className="lmPage">
      {/* Title bar */}
      <div className="lmPageTitle">
        <span className="lmStepTitle">Project Location Map</span>
      </div>

      {/* Instruction bar */}
      <div className="lmInstructionBar">
        <p className="lmInstruction">
          Identify project location on map. Click on the map or enter an address
          in the Search Address box to position the marker.
        </p>
        <div className="lmInstructionActions">
          {locset && (
            <button
              type="button"
              className="lmReturnBtn"
              onClick={() => navigate('/applicant-info')}
              // TODO: change to '/project-info' once app_proj_info.jsp is migrated
            >
              Return to Form
            </button>
          )}
          <button
            type="button"
            className="lmHelpBtn"
            aria-label="Help"
            onClick={() => setHelpOpen(true)}
          >
            ?
          </button>
        </div>
      </div>

      {/* Error block */}
      {errors.length > 0 && (
        <div className="lmErrors">
          <p className="lmErrorNote">
            The following issues must be resolved before saving:
          </p>
          <ul className="lmErrorList">
            {errors.map((err, i) => <li key={i}>{err}</li>)}
          </ul>
        </div>
      )}

      {/* Search box — rendered outside GoogleMap so it appears above the map */}
      <div className="lmSearchBox">
        <StandaloneSearchBox
          onLoad={ref => { searchBoxRef.current = ref; }}
          onPlacesChanged={handlePlacesChanged}
        >
          <input
            type="text"
            placeholder="Search Address"
            className="lmSearchInput"
          />
        </StandaloneSearchBox>
      </div>

      {/* Google Map */}
      <GoogleMap
        mapContainerClassName="lmMapContainer"
        center={initialCenter}
        zoom={initialZoom}
        mapTypeId="hybrid"
        onLoad={handleMapLoad}
        onIdle={handleMapIdle}
        onClick={handleMapClick}
      >
        {/* Marker */}
        {markerPos && (
          <Marker
            position={markerPos}
            onClick={() => {
              if (locCity) {
                setInfoWindowContent(isInJurisdiction(locCity) ? 'form' : 'warning');
              }
            }}
          />
        )}

        {/* InfoWindow — shown only when a marker is placed and content is set */}
        {markerPos && infoWindowContent && (
          <InfoWindow
            position={markerPos}
            onCloseClick={() => setInfoWindowContent(null)}
          >
            {infoWindowContent === 'form' ? (
              <LocationInfoWindow
                locDesc={locDesc}
                locCity={locCity}
                onDescChange={setLocDesc}
                onCityChange={setLocCity}
                onRemove={handleRemoveMarker}
                onSave={handleSubmit}
                submitting={submitting}
              />
            ) : (
              <LocationOutOfBounds />
            )}
          </InfoWindow>
        )}
      </GoogleMap>

      {/* Help modal */}
      <LocationHelpModal
        open={helpOpen}
        onClose={() => setHelpOpen(false)}
      />

      {/* Bottom button bar */}
      <div className="lmButtonBar">
        <button
          type="button"
          className="lmBtn"
          onClick={() => navigate('/applicant-info')}
          // TODO: change to '/project-info' once app_proj_info.jsp is migrated
        >
          Back
        </button>
      </div>
    </div>
  );
}
```

---

## Step M — Create .NET DTOs

### M.1 `SaveLocationRequestDto.cs`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\Models\SaveLocationRequestDto.cs`

```csharp
namespace PWA.WellsPermit.WebApi.Models;

public record SaveLocationRequestDto(
    double Lat,
    double Lng,
    string ProjLoc,
    string LocCity
);
```

### M.2 `SaveLocationResponseDto.cs`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\Models\SaveLocationResponseDto.cs`

```csharp
namespace PWA.WellsPermit.WebApi.Models;

public record SaveLocationResponseDto(
    double SiteLat,
    double SiteLng,
    string SiteLocation,
    string SiteCityName,
    string CityCode
);
```

**Pattern note:** Both records follow the exact same style as `StateCodeDto.cs` — positional record,
namespace declaration, no file-scoped attributes beyond the namespace.

---

## Step N — Create `LocationMapController.cs`

**File:**
`C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\Controllers\LocationMapController.cs`

```csharp
using Microsoft.AspNetCore.Mvc;
using PWA.WellsPermit.WebApi.Models;

namespace PWA.WellsPermit.WebApi.Controllers;

[ApiController]
[Route("api/location-map")]
public class LocationMapController : ControllerBase
{
    // Sourced from BeanCodesCity / city_codes table (EEAOWN schema).
    // TODO: replace with EF Core query once DB connection is configured.
    // TODO: confirm actual code values (HAY, ALA, OAK, etc.) from city_codes table
    //       or from BeanCodesCity.java in the legacy source before any integration test.
    private static readonly Dictionary<string, string> _cityCodes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            { "Hayward",       "HAY" },
            { "Alameda",       "ALA" },
            { "Oakland",       "OAK" },
            { "Castro Valley", "CSV" },
            { "Emeryville",    "EME" },
            { "Albany",        "ALB" },
            { "Piedmont",      "PIE" },
            { "San Lorenzo",   "SLO" },
            { "San Leandro",   "SLE" },
        };

    [HttpPost("save")]
    public IActionResult SaveLocation([FromBody] SaveLocationRequestDto request)
    {
        if (request is null)
            return BadRequest("Request body is required.");

        if (string.IsNullOrWhiteSpace(request.ProjLoc))
            return BadRequest("Location description (projLoc) is required.");

        if (string.IsNullOrWhiteSpace(request.LocCity))
            return BadRequest("City (locCity) is required.");

        if (!_cityCodes.TryGetValue(request.LocCity, out var cityCode))
            return BadRequest(
                $"City '{request.LocCity}' is not within Alameda County Public Works jurisdiction."
            );

        var response = new SaveLocationResponseDto(
            SiteLat:      request.Lat,
            SiteLng:      request.Lng,
            SiteLocation: request.ProjLoc,
            SiteCityName: request.LocCity,
            CityCode:     cityCode
        );

        return Ok(response);
    }
}
```

**Design notes matching `ReferenceController.cs` conventions:**
- `[ApiController]` + `[Route(...)]` at class level, `[HttpPost(...)]` at method level
- Static readonly in-memory list with `// TODO: replace with EF Core` comment
- Returns `IActionResult` (`Ok(...)` / `BadRequest(...)`)
- Namespace matches the project: `PWA.WellsPermit.WebApi.Controllers`
- No constructor injection needed at this stage (no services yet)

---

## Step O — Verification

### O.1 Build Checks

```bash
# Backend — confirm no compile errors
cd C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi
dotnet build

# Frontend — confirm no compile errors
cd C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web
npm run build
```

### O.2 Local End-to-End Test Sequence

1. Start .NET: `dotnet run` from
   `C:\Development\PWA-Wells-Permit-WebApp\backend\PWA.WellsPermit.WebApi\PWA.WellsPermit.WebApi\`
   Confirm Swagger at `http://localhost:5012/swagger`.

2. Start React: `npm start` from
   `C:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\`
   Confirm app at `http://localhost:3000`.

3. Navigate to `http://localhost:3000/` — confirm redirect to `/applicant-info`.

4. Fill in required Applicant Info fields and click Continue — confirm redirect to `/location-map`.

5. Confirm map loads centered on Oakland (37.79, -122.26) with zoom 16 and map type `hybrid`.

6. Click a point within the Bay Area on an Oakland address — confirm:
   - Marker appears at clicked point
   - InfoWindow opens with Location Address/Description textarea and Location City input
   - Fields are auto-populated via reverse geocode
   - City reads "Oakland" (or applicable city)

7. Edit the description text — confirm textarea allows edits and respects 200-char limit.

8. Click "SAVE AND CONTINUE" — confirm:
   - POST to `http://localhost:5012/api/location-map/save` (visible in Network tab)
   - 200 response with `{ siteLat, siteLng, siteLocation, siteCityName, cityCode }`
   - `application.project` context is updated (inspect via React DevTools)
   - Navigation to `/work-types` (will show a 404 until that page is built — that is expected)

9. Navigate back to `/location-map` — confirm:
   - Map re-centers on saved lat/lng with zoom 20
   - Marker is pre-placed at saved position
   - InfoWindow opens automatically with saved description and city
   - "Return to Form" button is visible

10. Click "Return to Form" — confirm it navigates to `/applicant-info` without modifying context.

11. Pan the map to San Francisco — confirm it snaps back to the last valid Bay Area position.

12. Click a point in San Francisco (outside jurisdiction) — confirm the warning InfoWindow appears
    with the red warning text and link to `https://www.acpwa.org/drilling-and-wells-permit`.
    Confirm the location form is NOT shown.

13. Type an address in the Search Address box (e.g., "1221 Oak Street, Oakland") — confirm
    autocomplete appears, marker is placed on selection, InfoWindow opens.

14. Click "Remove marker" inside the InfoWindow — confirm marker disappears, InfoWindow closes,
    but address and city text values remain in local state (they do not clear — per legacy behavior).

15. Submit with no marker — confirm error message appears above the map without any API call.

16. Test .NET endpoint directly in Swagger:
    - `POST /api/location-map/save` with `{ "lat": 37.80, "lng": -122.25, "projLoc": "123 Oak St, Oakland, CA", "locCity": "Oakland" }` → 200, `cityCode: "OAK"`
    - Same with `"locCity": "San Francisco"` → 400
    - Same with empty `"projLoc": ""` → 400
    - Same with null body → 400

### O.3 React Component Tests (React Testing Library)

Suggested test file:
`src/pages/LocationMap/LocationMap.test.js`

Key test cases:
- Mock `useJsApiLoader` to return `{ isLoaded: false }` → confirm "Loading map..." text is shown
- Mock `useJsApiLoader` to return `{ loadError: new Error() }` → confirm error message shown
- Mock `useJsApiLoader` to return `{ isLoaded: true }` + mock `useApplication` with `siteLat: null`
  → confirm no "Return to Form" button, no marker
- Same with `siteLat: 37.79`, `siteLng: -122.26` → confirm "Return to Form" is visible
- Test `isInJurisdiction`: each of the 9 approved cities → `true`; `'San Francisco'` → `false`
- Render `LocationInfoWindow` → confirm textarea, city input, Remove and Save buttons present
- Render `LocationOutOfBounds` → confirm warning text and link to `acpwa.org`
- Render `LocationHelpModal` with `open={true}` → confirm overlay renders; click Close → `onClose` called
- Render `LocationHelpModal` with `open={false}` → confirm nothing renders

### O.4 .NET Unit Tests (xUnit)

Suggested test file: `LocationMapControllerTests.cs`

Key test cases:
- Valid Oakland body → 200, `CityCode == "OAK"`
- Each of the 9 cities → 200 with non-null `CityCode`
- `locCity: "San Francisco"` → 400 with jurisdiction message
- `projLoc: ""` → 400
- `locCity: ""` → 400
- `locCity: "hayward"` (lowercase) → 200 (dictionary uses `OrdinalIgnoreCase`)
- Null body → 400

---

## Step P — Implementation Order Summary

Execute steps in this order. Steps A-G may be done in a single dev session; each is a prerequisite
for the one that follows it in terms of making the frontend compile.

| # | File | Action | Dependency |
|---|---|---|---|
| A | (command) | `npm install @react-google-maps/api` | none |
| B | `src/api/apiClient.js` | **Create** — fetch wrapper | none — but unblocks existing broken build |
| C | `src/config/config.local.js` | **Edit** — change `apiBaseUrl` to `http://localhost:5012` | none |
| D | `src/context/ApplicationContext.js` | **Edit** — expand `project` slice with 5 fields | none |
| E | `src/App.js` | **Edit** — fix broken import path + add `/location-map` route | Step B (import LocationMap which imports apiClient) |
| F | `src/pages/ApplicantInfoForm/ApplicantInfoForm.js` | **Edit** — change `navigate` target to `/location-map` | Step E (route must exist) |
| G | `.env.local` | **Create** — add `REACT_APP_GOOGLE_MAPS_API_KEY` | Google API key required |
| G | `.env.example` | **Create** — add key placeholder | none |
| H | `src/pages/LocationMap/LocationMap.css` | **Create** — all `lm*` classes | none |
| I | `src/pages/LocationMap/LocationHelpModal.js` | **Create** | Step H (CSS) |
| J | `src/pages/LocationMap/LocationInfoWindow.js` | **Create** | Step H (CSS) |
| K | `src/pages/LocationMap/LocationOutOfBounds.js` | **Create** | Step H (CSS) |
| L | `src/pages/LocationMap/LocationMap.js` | **Create** | Steps H, I, J, K, B, D |
| M.1 | `backend/Models/SaveLocationRequestDto.cs` | **Create** | none |
| M.2 | `backend/Models/SaveLocationResponseDto.cs` | **Create** | none |
| N | `backend/Controllers/LocationMapController.cs` | **Create** | Steps M.1, M.2 |

Total new files: 10 (5 frontend source + 2 frontend env + 3 backend)
Total edited files: 4 (`apiClient.js` creation, `config.local.js`, `ApplicationContext.js`, `App.js`, `ApplicantInfoForm.js`)

---

## Open TODOs for the Developer

| # | Item | Blocking? |
|---|---|---|
| 1 | Obtain Google Maps API key (Maps JS + Places + Geocoding APIs enabled) and add to `.env.local` | Yes — without it, the map page cannot be tested |
| 2 | Confirm actual city code values from `city_codes` table (EEAOWN schema) or `BeanCodesCity.java` | Yes — placeholder codes (`HAY`, `OAK`, etc.) may be wrong; affects city lookup in controller and integration tests |
| 3 | Update `navigate('/work-types')` in `LocationMap.js` once `app_wrktp.jsp` migration is done | No — page will show a 404 but the save flow still works |
| 4 | Update "Return to Form" and Back button targets from `/applicant-info` to `/project-info` once `app_proj_info.jsp` is migrated | No — current target keeps navigation working within what is built |
| 5 | Replace `_cityCodes` static dictionary in the controller with an EF Core query once DB is configured | No — static data is sufficient for MVP |
| 6 | Confirm .NET dev port (CLAUDE.md says 5012 HTTP / 7296 HTTPS); update `config.local.js` if different | Yes — wrong port causes all API calls to fail |
