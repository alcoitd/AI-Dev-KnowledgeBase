# Migration Plan: app_proj_locmap.jsp → React + .NET

## Context

`app_proj_locmap.jsp` is Step 2 of the Wells Permit application — the Project Location Map page. It allows applicants to drop a marker on a Google Map (by clicking or by address search), reverse-geocode to a formatted address and city, validate that the city falls within Alameda County jurisdiction, and save latitude, longitude, location description, and city name before proceeding to the Project Info step. This plan covers every React component, context field, CSS class, .NET endpoint, and DTO needed to replicate that behavior in the modern stack, and documents fixes for all bugs identified in the spec.

**Source spec:** `spec/spec_app_proj_locmap.md`
**Legacy JSP:** `wellspermit-ecomm-web-jboss/src/main/webapp/app_proj_locmap.jsp`

**Current state of target projects:**

- **React** (`frontend/pwa-wells-permit-web/`): One route exists (`/applicant-info` → `ApplicantInfoForm`). `ApplicationContext.js` has five slices (`project`, `works`, `applicant`, `hazard`, `payment`) with `updateProject` already wired. No `apiClient.js` exists yet — `ApplicantInfoForm.js` imports `../../api/apiClient` but the file must still be created. No map-related packages are installed. No `LocationMap` component exists.
- **.NET** (`backend/PWA.WellsPermit.WebApi/`): One real controller exists (`ReferenceController` at `api/ref`). No location or city-code endpoints exist. Only NuGet package is `Swashbuckle.AspNetCore 6.6.2`. No EF Core is wired yet — reference data is served from in-memory static lists.

---

## A. Project Setup

### A.1 npm Packages to Install

`@react-google-maps/api` is not in `package.json`. Install it:

```bash
# Run from: frontend/pwa-wells-permit-web/
npm install @react-google-maps/api
```

This package wraps the Google Maps JavaScript API (including Places and Geocoder) in React-friendly hooks and components. It supports `useJsApiLoader`, `GoogleMap`, `Marker`, `InfoWindow`, and `StandaloneSearchBox` — all needed here.

No other new packages are required. The existing `react-router-dom ^7.14.2` covers navigation.

### A.2 Environment Variables

Add the Google Maps API key to both env files. The key must have the Maps JavaScript API, Places API, and Geocoding API enabled in the Google Cloud Console.

**File: `frontend/pwa-wells-permit-web/.env.local`** (create if absent)
```
REACT_APP_GOOGLE_MAPS_API_KEY=<your_dev_api_key_here>
```

**File: `frontend/pwa-wells-permit-web/.env.example`** (create if absent — commit this, not .env.local)
```
# Google Maps JavaScript API key (requires Maps JS, Places, Geocoding APIs enabled)
REACT_APP_GOOGLE_MAPS_API_KEY=
```

The key is consumed in `LocationMap.js` as `process.env.REACT_APP_GOOGLE_MAPS_API_KEY`.

### A.3 .NET NuGet Packages

No new NuGet packages are required for this page. The city-code lookup is served from an in-memory static dictionary (matching the existing `ReferenceController` pattern) until EF Core is wired.

---

## B. State Management

### B.1 Legacy → React Context Mapping

| Legacy Field (`BeanApp`) | Context slice | React field name | Type | Default |
|---|---|---|---|---|
| `SiteLat` | `project` | `siteLat` | `number \| null` | `null` |
| `SiteLong` | `project` | `siteLng` | `number \| null` | `null` |
| `SiteLocation` | `project` | `siteLocation` | `string` | `''` |
| `SiteCityName` | `project` | `siteCityName` | `string` | `''` |
| `SiteCityCode` | `project` | `siteCityCode` | `string` | `''` |

**Type rationale:** The legacy JSP stores lat/lng as strings (Java `String`), but the React layer should hold them as `number | null` for direct use with the Google Maps API. The .NET endpoint receives them as `number` from the request body and converts to string for any persistence layer. `null` means "not yet set" (distinguishes from the legacy sentinel `""`), fixing the `locset` string-comparison bug.

### B.2 Update `ApplicationContext.js`

**File:** `frontend/pwa-wells-permit-web/src/context/ApplicationContext.js`

Expand the `project` slice initial value:

```js
const INITIAL_APPLICATION = {
  project: {
    siteLat: null,       // number | null — null means no marker placed yet
    siteLng: null,       // number | null
    siteLocation: '',    // formatted address / description (max 200 chars)
    siteCityName: '',    // extracted locality name from geocoder
    siteCityCode: '',    // city code returned by .NET lookup
  },
  works: [],
  applicant: {},
  hazard: null,
  payment: null,
  siteHazardRequired: false,
};
```

The existing `updateProject(data)` updater (`setApplication(prev => ({ ...prev, project: data }))`) is sufficient — no new updater methods are needed. The component will spread the incoming save payload over the existing project slice.

---

## C. Routing

### C.1 Update `App.js`

**File:** `frontend/pwa-wells-permit-web/src/App.js`

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

**Navigation wiring:** `ApplicantInfoForm`'s submit handler currently navigates to `/hazard-info` or `/payment-info`. Once the workflow is fully mapped, its `handleSubmit` should instead navigate to `/location-map` (Step 2). That change belongs in `ApplicantInfoForm.js` — update the `navigate` call:

```js
// In ApplicantInfoForm.js handleSubmit, replace the conditional navigate with:
navigate('/location-map');
```

---

## D. React Component Structure

### D.1 File Layout

```
frontend/pwa-wells-permit-web/src/pages/LocationMap/
  LocationMap.js          ← Page root: loads API, owns map state, handles submit/navigation
  LocationMap.css         ← All lm* CSS classes
  LocationInfoWindow.js   ← InfoWindow content: address textarea, city input, action buttons
  LocationOutOfBounds.js  ← InfoWindow content: out-of-jurisdiction warning message
  LocationHelpModal.js    ← Help overlay modal
```

Sub-components are justified because:
- `LocationInfoWindow` and `LocationOutOfBounds` are distinct InfoWindow bodies (mutually exclusive); extracting them keeps `LocationMap.js` under 300 lines and makes each InfoWindow independently testable.
- `LocationHelpModal` is a full overlay with its own open/close state that the parent must toggle — cleanly isolated.

### D.2 CSS Convention

All classes use the `lm` prefix. Pattern mirrors `ApplicantInfoForm.css`:

| Class | Purpose |
|---|---|
| `lmPage` | Full-page wrapper, `max-width: 960px`, centered |
| `lmPageTitle` | Dark-blue title bar (match `#336699`) |
| `lmStepTitle` | White bold title text |
| `lmInstructionBar` | Flex row above map: instruction text left, buttons right |
| `lmInstruction` | Instruction text, `font-size: 13px` |
| `lmReturnBtn` | "Return to Form" button — only rendered when `locset` is true |
| `lmHelpBtn` | Circular dark-green help button |
| `lmSearchBox` | Wrapper for the Google Places input |
| `lmSearchInput` | `width: 400px`, Roboto font, border, padding |
| `lmMapContainer` | `width: 100%`, `height: 520px` |
| `lmInfoWindowForm` | Form inside InfoWindow: flex column layout |
| `lmInfoLabel` | Bold label inside InfoWindow |
| `lmInfoTextarea` | Address/description textarea, `width: 320px`, `height: 80px` |
| `lmInfoInput` | City text input, `width: 320px` |
| `lmInfoActions` | Flex row for Remove/Save buttons |
| `lmInfoBtn` | Base button style inside InfoWindow |
| `lmInfoBtnSave` | Green accent for "SAVE AND CONTINUE" |
| `lmWarningBox` | Out-of-jurisdiction warning InfoWindow content |
| `lmWarningIcon` | Warning icon span |
| `lmWarningText` | Warning message text |
| `lmWarningLink` | Link to acpwa.org |
| `lmModal` | Full-screen semi-transparent overlay |
| `lmModalBox` | Centered white modal content box |
| `lmModalTitle` | Modal heading |
| `lmModalBody` | Modal instruction content |
| `lmModalClose` | Close button |
| `lmButtonBar` | Bottom button bar (matches `aiButtonBar` background `#c0cfe0`) |
| `lmBtn` | Standard button (matches `aiBtn` style) |
| `lmErrors` | Error block (matches `aiErrors` style) |
| `lmErrorNote` | Error text (matches `aiErrorNote` style) |

Refer to `ApplicantInfoForm.css` for exact spacing, color tokens, and font values to maintain visual consistency across steps.

### D.3 Component Responsibilities

| Component | State it owns | Props it receives | What it renders |
|---|---|---|---|
| `LocationMap` | `marker` (google.maps.Marker ref), `infoWindowPos`, `infoWindowContent ('form'\|'warning'\|null)`, `locDesc` (string), `locCity` (string), `helpOpen` (bool), `errors` (string[]), `submitting` (bool) | none — reads context via `useApplication()` | Page title, instruction bar, search box, `GoogleMap`, `LocationHelpModal`, bottom button bar |
| `LocationInfoWindow` | none | `locDesc`, `locCity`, `onDescChange`, `onCityChange`, `onRemove`, `onSave` | Textarea, city input, Remove and Save buttons |
| `LocationOutOfBounds` | none | none | Warning text and link |
| `LocationHelpModal` | none | `open` (bool), `onClose` | Full-screen help overlay |

---

## E. Map Integration

### E.1 Loading the Google Maps API

**Legacy:** The JSP injects `<script src="https://maps.googleapis.com/maps/api/js?key=...&libraries=places&callback=initMap">` at the bottom of the page, which calls the global `initMap()` on load.

**React:** Use `useJsApiLoader` from `@react-google-maps/api`. This hook handles async script loading and provides an `isLoaded` boolean. The map and search box are only rendered once `isLoaded` is true, eliminating the race condition inherent in the legacy callback pattern.

```jsx
import { useJsApiLoader, GoogleMap, Marker, InfoWindow, StandaloneSearchBox } from '@react-google-maps/api';

const LIBRARIES = ['places']; // defined outside component to keep reference stable

export default function LocationMap() {
  const { isLoaded, loadError } = useJsApiLoader({
    googleMapsApiKey: process.env.REACT_APP_GOOGLE_MAPS_API_KEY,
    libraries: LIBRARIES,
  });

  if (loadError) return <div className="lmErrors"><p className="lmErrorNote">Failed to load Google Maps.</p></div>;
  if (!isLoaded) return <div className="lmPage"><p style={{ padding: 20 }}>Loading map...</p></div>;

  return <LocationMapInner />;
}
```

Split into an outer loader component and `LocationMapInner` to keep hook usage clean (hooks cannot be called conditionally). `LocationMapInner` contains all the map logic and is only mounted when the API is ready.

### E.2 Map Initialization and Returning-User Mode

**Legacy:** `initMap()` reads Java-rendered JSP variables (`var locset = <%= locset %>`). If `locset=true`, it places a marker, zooms to 20, pre-populates fields, and opens the InfoWindow.

**React:** On mount of `LocationMapInner`, read `application.project` from context. If `siteLat !== null`, the user has a saved location — initialize local state with those values and open the InfoWindow immediately:

```jsx
const { application, updateProject } = useApplication();
const { siteLat, siteLng, siteLocation, siteCityName } = application.project;
const locset = siteLat !== null; // fixes the Java == "" string reference bug

const defaultCenter = { lat: 37.79, lng: -122.26 }; // Oakland area
const [center] = useState(locset ? { lat: siteLat, lng: siteLng } : defaultCenter);
const [zoom] = useState(locset ? 20 : 16);
const [markerPos, setMarkerPos] = useState(locset ? { lat: siteLat, lng: siteLng } : null);
const [infoWindowContent, setInfoWindowContent] = useState(locset ? 'form' : null);
const [locDesc, setLocDesc] = useState(siteLocation);
const [locCity, setLocCity] = useState(siteCityName);
```

### E.3 Bay Area Bounding Box Enforcement

**Legacy:** Inside the `idle` map listener, if `map.getCenter()` is outside the bounding box, `map.setCenter(lastValidCenter)`.

**React:** Attach a `onIdle` prop to `<GoogleMap>`. The handler checks bounds and snaps back:

```js
const SW = { lat: 37.453764, lng: -122.369047 };
const NE = { lat: 37.922153, lng: -121.638478 };

function handleMapIdle() {
  if (!mapRef.current) return;
  const center = mapRef.current.getCenter();
  const lat = center.lat();
  const lng = center.lng();
  if (lat < SW.lat || lat > NE.lat || lng < SW.lng || lng > NE.lng) {
    mapRef.current.setCenter(lastValidCenterRef.current);
  } else {
    lastValidCenterRef.current = { lat, lng };
  }
}
```

`mapRef` is populated via `<GoogleMap onLoad={map => { mapRef.current = map; }}>`. `lastValidCenterRef` starts at the initial center.

### E.4 Click-to-Pin Behavior

**Legacy:** Map `click` listener clears markers, reverse-geocodes, populates fields, checks jurisdiction.

**React:** Attach `onClick` to `<GoogleMap>`. The handler:
1. Sets `markerPos` to the clicked `LatLng`.
2. Calls the Google Geocoder directly in the browser (no server round-trip needed):

```js
const geocoder = new window.google.maps.Geocoder();

function handleMapClick(event) {
  const latLng = { lat: event.latLng.lat(), lng: event.latLng.lng() };
  setMarkerPos(latLng);
  setLocDesc('');
  setLocCity('');
  setInfoWindowContent(null);

  geocoder.geocode({ location: latLng }, (results, status) => {
    if (status !== 'OK' || !results?.[0]) return;
    const address = results[0].formatted_address;
    setLocDesc(address);
    const cityComponent = results[0].address_components
      .find(c => c.types[0] === 'locality');
    const city = cityComponent?.long_name ?? '';
    setLocCity(city);
    setInfoWindowContent(isInJurisdiction(city) ? 'form' : 'warning');
  });
}
```

### E.5 Search Box Behavior

**Legacy:** `SearchBox` `places_changed` listener iterates results, builds `locdesc`, checks jurisdiction, fits bounds.

**React:** Use `StandaloneSearchBox` from `@react-google-maps/api`. Attach `onLoad` and `onPlacesChanged`:

```jsx
const searchBoxRef = useRef(null);

function handlePlacesChanged() {
  const places = searchBoxRef.current.getPlaces();
  if (!places?.length) return;

  const place = places[0]; // use first result
  const latLng = {
    lat: place.geometry.location.lat(),
    lng: place.geometry.location.lng(),
  };
  setMarkerPos(latLng);

  // Build locdesc: if place name starts with same char as formatted address, use address only
  const addr = place.formatted_address ?? '';
  const name = place.name ?? '';
  const desc = addr[0]?.toLowerCase() === name[0]?.toLowerCase()
    ? addr
    : `${addr}\n${name}`;
  setLocDesc(desc);

  // Extract city from address_components or fall back to geocoder
  const cityComp = place.address_components?.find(c => c.types[0] === 'locality');
  if (cityComp) {
    const city = cityComp.long_name;
    setLocCity(city);
    setInfoWindowContent(isInJurisdiction(city) ? 'form' : 'warning');
  } else {
    // Geocoder fallback
    const geocoder = new window.google.maps.Geocoder();
    geocoder.geocode({ location: latLng }, (results, status) => {
      if (status !== 'OK' || !results?.[0]) return;
      const fallbackCity = results[0].address_components
        ?.find(c => c.types[0] === 'locality')?.long_name ?? '';
      setLocCity(fallbackCity);
      setInfoWindowContent(isInJurisdiction(fallbackCity) ? 'form' : 'warning');
    });
  }

  // Fit map to results
  if (mapRef.current) {
    const bounds = new window.google.maps.LatLngBounds();
    places.forEach(p => {
      if (p.geometry.viewport) bounds.union(p.geometry.viewport);
      else bounds.extend(p.geometry.location);
    });
    mapRef.current.fitBounds(bounds);
  }
}
```

### E.6 Jurisdiction Validation (client-side)

**Legacy:** Inline JS array check inside map event handlers.

**React:** Pure function defined in the component file (or extracted to a utility module if shared):

```js
const APPROVED_CITIES = new Set([
  'Hayward', 'Alameda', 'Oakland', 'Castro Valley',
  'Emeryville', 'Albany', 'Piedmont', 'San Lorenzo', 'San Leandro',
]);

function isInJurisdiction(city) {
  return APPROVED_CITIES.has(city);
}
```

This drives the `infoWindowContent` state: `'form'` → show `LocationInfoWindow`, `'warning'` → show `LocationOutOfBounds`.

### E.7 InfoWindow Rendering

**Legacy:** A single `google.maps.InfoWindow` whose content is swapped between two HTML strings.

**React:** Conditional rendering using `@react-google-maps/api`'s `<InfoWindow>` component, placed at `markerPos`:

```jsx
{markerPos && infoWindowContent && (
  <InfoWindow
    position={markerPos}
    onCloseClick={() => setInfoWindowContent(null)}
  >
    {infoWindowContent === 'form'
      ? <LocationInfoWindow
          locDesc={locDesc}
          locCity={locCity}
          onDescChange={setLocDesc}
          onCityChange={setLocCity}
          onRemove={handleRemoveMarker}
          onSave={handleSubmit}
        />
      : <LocationOutOfBounds />
    }
  </InfoWindow>
)}
```

### E.8 Remove Marker

**Legacy:** `removeMarker()` calls `marker.setMap(null)`.

**React:** Set `markerPos` to `null` and `infoWindowContent` to `null`:

```js
function handleRemoveMarker() {
  setMarkerPos(null);
  setInfoWindowContent(null);
  // Note: locDesc and locCity are intentionally NOT cleared,
  // matching legacy behavior (only the map marker is removed).
}
```

### E.9 Help Modal

**Legacy:** `<div id="helpBlock">` toggled via `openHelp()` / `closeHelp()` JavaScript functions that show/hide a fixed overlay.

**React:** `LocationHelpModal` is conditionally rendered based on `helpOpen` boolean state in the parent:

```jsx
// In LocationMap.js:
const [helpOpen, setHelpOpen] = useState(false);

// In JSX:
<button className="lmHelpBtn" onClick={() => setHelpOpen(true)}>?</button>
<LocationHelpModal open={helpOpen} onClose={() => setHelpOpen(false)} />
```

The modal itself uses a simple CSS overlay (`position: fixed`, `z-index: 1000`, semi-transparent background) — no third-party modal library needed.

### E.10 Return to Form Button

**Legacy:** Visible only when `locset=true`. Submits a separate form (`returnToProj`) with `proc=proj` to go back to Project Info.

**React:** Visible only when `locset` is true (i.e., `application.project.siteLat !== null`). Calls `navigate('/applicant-info')` or the appropriate previous route without saving:

```jsx
{locset && (
  <button
    type="button"
    className="lmReturnBtn"
    onClick={() => navigate('/applicant-info')}
  >
    Return to Form
  </button>
)}
```

Update the target route when the Project Info page (`app_proj_info.jsp`) is migrated — at that point, change `'/applicant-info'` to `'/project-info'`.

---

## F. Form Submission

### F.1 Submit Handler in `LocationMap.js`

```js
async function handleSubmit() {
  // 1. Client-side validation (fixes legacy no-validation bug)
  const validationErrors = [];
  if (!markerPos) {
    validationErrors.push('Please click on the map or search for an address to set a project location.');
  }
  if (!locDesc.trim()) {
    validationErrors.push('Location description is required.');
  }
  if (!locCity.trim()) {
    validationErrors.push('Location city could not be determined. Please re-pin your location.');
  }
  if (validationErrors.length > 0) {
    setErrors(validationErrors);
    return;
  }
  setErrors([]);
  setSubmitting(true);

  // 2. Build request payload
  const payload = {
    lat: markerPos.lat,
    lng: markerPos.lng,
    projLoc: locDesc.trim(),
    locCity: locCity.trim(),
  };

  try {
    // 3. POST to .NET endpoint
    const result = await api.post('/api/location-map/save', payload);

    // 4. Update context with saved data (including cityCode returned from server)
    updateProject({
      ...application.project,
      siteLat: markerPos.lat,
      siteLng: markerPos.lng,
      siteLocation: locDesc.trim(),
      siteCityName: locCity.trim(),
      siteCityCode: result.cityCode ?? '',
    });

    // 5. Navigate to next step
    navigate('/work-types'); // update when WorkTypes page is migrated
  } catch (err) {
    setErrors([err.message ?? 'Failed to save location. Please try again.']);
  } finally {
    setSubmitting(false);
  }
}
```

**Key differences from legacy:**
- Validates that a marker exists before submitting (fixes the NullPointerException risk in spec §13).
- Validates that `locDesc` and `locCity` are non-empty.
- The "Location saved" InfoWindow feedback from the legacy JSP is omitted — React's navigation to the next step provides sufficient feedback.

### F.2 `api` client pattern

The `ApplicantInfoForm.js` already imports `api` from `../../api/apiClient`. That module must be created as part of this migration (it is missing from the codebase). Define it as a thin wrapper over `fetch` or `axios` matching what `ApplicantInfoForm.js` expects:

**File to create:** `frontend/pwa-wells-permit-web/src/api/apiClient.js`

```js
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
  // Return null for 204 No Content
  if (response.status === 204) return null;
  return response.json();
}

export const api = {
  get:  (path)         => request('GET',  path),
  post: (path, body)   => request('POST', path, body),
  put:  (path, body)   => request('PUT',  path, body),
};
```

This matches the `api.get('/api/ref/states')` call already in `ApplicantInfoForm.js` and the `api.post('/api/location-map/save', payload)` call in the new component.

Note: `config.apiBaseUrl` in `config.local.js` is currently `https://localhost:7241`. The .NET backend runs on port 5012 (HTTP) or 7296 (HTTPS) per CLAUDE.md. Update `config.local.js` accordingly:

```js
// config.local.js — update apiBaseUrl to match .NET dev port
apiBaseUrl: 'http://localhost:5012',
```

---

## G. .NET API Endpoint

### G.1 New Controller

**File:** `backend/PWA.WellsPermit.WebApi/PWA.WellsPermit.WebApi/Controllers/LocationMapController.cs`

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
    private static readonly Dictionary<string, string> _cityCodes = new(StringComparer.OrdinalIgnoreCase)
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
            return BadRequest($"City '{request.LocCity}' is not within Alameda County Public Works jurisdiction.");

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

**Design notes:**
- The endpoint returns the resolved `cityCode` to the frontend so `ApplicationContext` can store it without a second call.
- The jurisdiction check is duplicated server-side (belt-and-suspenders) — the client also validates before calling.
- The `_cityCodes` dictionary keys match the `APPROVED_CITIES` set in the React component exactly. When city codes are confirmed from the DB schema, update both locations in sync.

### G.2 New DTOs

**File:** `backend/PWA.WellsPermit.WebApi/PWA.WellsPermit.WebApi/Models/SaveLocationRequestDto.cs`

```csharp
namespace PWA.WellsPermit.WebApi.Models;

public record SaveLocationRequestDto(
    double Lat,
    double Lng,
    string ProjLoc,
    string LocCity
);
```

**File:** `backend/PWA.WellsPermit.WebApi/PWA.WellsPermit.WebApi/Models/SaveLocationResponseDto.cs`

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

### G.3 In-Memory City Code Data

The `_cityCodes` dictionary above maps city name → city code. The actual code values (`HAY`, `ALA`, etc.) are placeholders — the real codes must be confirmed from the `city_codes` table in the EEAOWN schema via `BeanCodesCity.java`. Add the `// TODO` comment in the controller (already included above).

### G.4 React: Calling the Endpoint

```js
// In LocationMap.js handleSubmit:
const result = await api.post('/api/location-map/save', {
  lat: markerPos.lat,
  lng: markerPos.lng,
  projLoc: locDesc.trim(),
  locCity: locCity.trim(),
});
// result shape: { siteLat, siteLng, siteLocation, siteCityName, cityCode }
updateProject({
  ...application.project,
  siteLat:      result.siteLat,
  siteLng:      result.siteLng,
  siteLocation: result.siteLocation,
  siteCityName: result.siteCityName,
  siteCityCode: result.cityCode,
});
```

---

## H. Known Bugs Fixed in Migration

| Legacy Bug (spec §13) | Root Cause | Fix Applied |
|---|---|---|
| `locset` always false — `!(aBean.getBeanApp().getSiteLat() == "")` uses Java reference equality on a String | Java `==` compares object identity, not value; on most JVMs interned strings differ, so `==` against `""` returns false even when the value is empty | React context stores `siteLat` as `number \| null`; `locset` is `siteLat !== null` — strictly typed, no string comparison involved |
| No client-side validation before submit — `saveData()` calls `marker.getPosition()` on potentially undefined marker, causing NullPointerException | No marker guard in the legacy `saveData()` function | `handleSubmit` checks `if (!markerPos)` and adds a user-facing error before any API call |
| Unused `locaddr` hidden field submitted in every POST, causing confusion | Field commented out in JS but still in the HTML form | Field is simply not present in the React component or DTO |
| IE Compatibility View instructions in help modal | Legacy IE-targeted code | Modal content updated to modern browser guidance; IE-specific instructions removed |

---

## I. Verification / End-to-End Testing

### I.1 Local Test Sequence

1. Start .NET: `dotnet run` from `backend/PWA.WellsPermit.WebApi/PWA.WellsPermit.WebApi/` — confirm Swagger at `http://localhost:5012/swagger`.
2. Start React: `npm start` from `frontend/pwa-wells-permit-web/` — confirm app at `http://localhost:3000`.
3. Navigate to `/applicant-info`, fill required fields, click Continue — confirm redirect to `/location-map`.
4. Confirm map loads centered on default Oakland coordinates (37.79, -122.26) with zoom 16.
5. Click within the Bay Area bounding box on an Oakland location — confirm reverse-geocode populates address textarea and city input, InfoWindow shows the location form.
6. Click "SAVE AND CONTINUE" — confirm POST to `http://localhost:5012/api/location-map/save`, 200 response, context updated, navigation to `/work-types`.
7. Navigate back to `/location-map` — confirm map re-centers on saved location, zoom 20, marker pre-placed, InfoWindow open with saved description and city.
8. Test the "Return to Form" button — confirm it appears only when a location is saved, and navigates back without modifying context.
9. Click outside the Bay Area bounding box — confirm map snaps back to last valid center.
10. Click on a location outside Alameda County jurisdiction (e.g., San Francisco) — confirm out-of-jurisdiction InfoWindow appears with warning text and link, and the location form is NOT shown.
11. Type an address in the Search Address box (e.g., "1221 Oak St, Oakland") — confirm Places autocomplete works, marker placed, InfoWindow opens.
12. Click "Remove marker" — confirm marker disappears, InfoWindow closes, address/city fields retain their values.
13. Test .NET endpoint directly via Swagger: POST `/api/location-map/save` with valid Oakland coordinates and city → 200 with `cityCode`. POST with a non-jurisdiction city → 400.

### I.2 React Component Tests

Using React Testing Library:

- Render `LocationMap` with context where `siteLat: null` — confirm no marker, no InfoWindow, no "Return to Form" button.
- Render with context where `siteLat: 37.79`, `siteLng: -122.26`, `siteLocation: '123 Main St'`, `siteCityName: 'Oakland'` — confirm "Return to Form" button is visible and `locset` is true.
- Mock `useJsApiLoader` to return `{ isLoaded: true }` for all map tests.
- Simulate submit with no marker set — confirm error message "Please click on the map...".
- Simulate submit with marker and valid fields — confirm `api.post` called with correct payload, `updateProject` called with returned data, `navigate('/work-types')` called.
- Render `LocationInfoWindow` with props — confirm textarea and input are bound, Remove and Save buttons present.
- Render `LocationOutOfBounds` — confirm warning text and link to `https://www.acpwa.org/drilling-and-wells-permit`.
- Render `LocationHelpModal` with `open={true}` — confirm overlay and close button visible; click close → `onClose` called.
- Test `isInJurisdiction` with each approved city → `true`; with `'San Francisco'` → `false`.

### I.3 .NET Unit Tests (xUnit)

- `POST /api/location-map/save` with valid body `{ lat: 37.8, lng: -122.2, projLoc: "123 Oak St, Oakland, CA", locCity: "Oakland" }` → 200 with `cityCode: "OAK"`.
- `POST /api/location-map/save` with `locCity: "San Francisco"` → 400 with jurisdiction error message.
- `POST /api/location-map/save` with empty `projLoc` → 400.
- `POST /api/location-map/save` with empty `locCity` → 400.
- `POST /api/location-map/save` with null body → 400.
- Test each city in `_cityCodes` — confirm all return 200 with a non-null `cityCode`.

---

## J. Implementation Order

| # | File | Change |
|---|---|---|
| 1 | `frontend/src/context/ApplicationContext.js` | Add 5 fields to `project` slice: `siteLat`, `siteLng`, `siteLocation`, `siteCityName`, `siteCityCode` |
| 2 | `frontend/src/api/apiClient.js` | Create — thin `fetch` wrapper exporting `api.get`, `api.post`, `api.put` (also required by existing `ApplicantInfoForm.js`) |
| 3 | `frontend/src/config/config.local.js` | Update `apiBaseUrl` to `http://localhost:5012` (currently points to 7241) |
| 4 | `frontend/src/App.js` | Add `import LocationMap` and `<Route path="/location-map" element={<LocationMap />} />` |
| 5 | `frontend/src/pages/ApplicantInfoForm/ApplicantInfoForm.js` | Update `handleSubmit` to `navigate('/location-map')` after saving applicant info |
| 6 | `frontend/src/pages/LocationMap/LocationMap.css` | Create all `lm*` CSS classes |
| 7 | `frontend/src/pages/LocationMap/LocationHelpModal.js` | Create help overlay component |
| 8 | `frontend/src/pages/LocationMap/LocationInfoWindow.js` | Create in-map form component |
| 9 | `frontend/src/pages/LocationMap/LocationOutOfBounds.js` | Create out-of-jurisdiction warning component |
| 10 | `frontend/src/pages/LocationMap/LocationMap.js` | Create main page component (outer loader + inner map) |
| 11 | `frontend/.env.local` | Add `REACT_APP_GOOGLE_MAPS_API_KEY=<dev_key>` |
| 12 | `frontend/.env.example` | Add `REACT_APP_GOOGLE_MAPS_API_KEY=` with comment |
| 13 | `backend/Controllers/LocationMapController.cs` | Create controller with `POST api/location-map/save` |
| 14 | `backend/Models/SaveLocationRequestDto.cs` | Create request DTO |
| 15 | `backend/Models/SaveLocationResponseDto.cs` | Create response DTO |

**Open TODOs before implementation:**

1. **Google Maps API key** — A key with Maps JavaScript API, Places API, and Geocoding API enabled must be obtained from Google Cloud Console and placed in `.env.local`. Confirm whether a dev key already exists in the Alameda County Google Cloud project.
2. **City codes** — The city code values in `_cityCodes` (e.g., `"HAY"`, `"OAK"`) are placeholders. Confirm actual code values from the `city_codes` table in the EEAOWN schema (or from `BeanCodesCity.java` in the legacy source).
3. **Next route after save** — `handleSubmit` navigates to `'/work-types'` as a placeholder. Update this once the Work Types page (`app_wrktp.jsp`) migration is planned and its route is known.
4. **"Return to Form" back route** — Currently navigates to `'/applicant-info'`. Update to `'/project-info'` once `app_proj_info.jsp` is migrated.
5. **`apiClient.js`** — This file is referenced by `ApplicantInfoForm.js` but does not exist in the codebase. Creating it in step 2 above unblocks both the existing Applicant Info page and the new Location Map page simultaneously.
6. **`config.local.js` port** — Current value (`7241`) does not match the documented .NET port (5012 HTTP). Confirm the correct dev port before wiring the API client.
