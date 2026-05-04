# Migration Plan: app_proj_locmap.jsp → React + .NET

## Context

Adds a **Section 14 — Migration Instructions** to the existing spec at `spec/spec_app_proj_locmap.md`. This plan maps every piece of the legacy JSP to its concrete React 19 / .NET 8 equivalent so a developer can generate the migration directly.

**Current state of target projects:**
- **React** (`frontend/pwa-wells-permit-web/`): React 19, React Router DOM v7, Context API. Only Step 1 (`/applicant-info`) is implemented. No map library installed.
- **.NET** (`backend/PWA.WellsPermit.WebApi/`): Minimal .NET 8 Web API, one real endpoint (`GET /api/ref/states`), no EF Core, no session.

---

## Migration Instructions

### A. Project Setup

#### A.1 React: Install Map Library

```bash
# from frontend/pwa-wells-permit-web/
npm install @react-google-maps/api
```

Use `@react-google-maps/api` (not `@googlemaps/js-api-loader`). It provides React-idiomatic hooks (`useJsApiLoader`) and typed wrappers (`GoogleMap`, `Marker`, `InfoWindow`, `StandaloneSearchBox`) that eliminate the global `window.google` DOM manipulation the JSP relies on.

#### A.2 React: Environment Variable for API Key

Create `frontend/pwa-wells-permit-web/.env.local` (gitignored — contains real key):
```
REACT_APP_GOOGLE_MAPS_API_KEY=your_key_here
REACT_APP_API_URL=http://localhost:5012
```

Create `frontend/pwa-wells-permit-web/.env.example` (committed — placeholder only):
```
REACT_APP_GOOGLE_MAPS_API_KEY=
REACT_APP_API_URL=http://localhost:5012
```

Reference in code as `process.env.REACT_APP_GOOGLE_MAPS_API_KEY`.

**TODO:** Obtain a Maps JavaScript API key from Google Cloud Console with **Maps JavaScript API** and **Places API** enabled. Do not reuse the JBoss server key (`PropertiesList.getMapApiKey()`) without confirming its domain restrictions allow `localhost:3000`.

#### A.3 .NET: No NuGet Packages Required

City-code lookup is in-memory (same pattern as `ReferenceController._states`). No EF Core needed for this migration step.

---

### B. State Management

#### B.1 Legacy → React Context Mapping

The Java `ApplicationBean` session fields map to the `project` slice of `ApplicationContext`:

| Legacy Field (`BeanApp`) | React `application.project` field | Type change |
|---|---|---|
| `SiteLat` (String) | `siteLat` | `string → number \| null` |
| `SiteLong` (String) | `siteLong` | `string → number \| null` |
| `SiteLocation` (String) | `siteLocation` | `string` (unchanged) |
| `SiteCityName` (String) | `siteCityName` | `string` (unchanged) |
| `SiteCityCode` (String) | `siteCityCode` | `string` (unchanged) |

#### B.2 Update `ApplicationContext.js`

**File:** `frontend/pwa-wells-permit-web/src/context/ApplicationContext.js`

Add these fields to `INITIAL_APPLICATION.project` (currently `{}`):

```js
project: {
  siteLat: null,        // number | null — null = no location set yet
  siteLong: null,       // number | null
  siteLocation: '',     // string
  siteCityName: '',     // string
  siteCityCode: '',     // string — populated by API response on save
},
```

Use `null` (not `""`) as the sentinel for "not yet set". This eliminates the legacy Java `==` string reference bug. The returning-user check becomes: `application.project.siteLat !== null`.

The existing `updateProject` function already does a full replace — no additional context methods needed.

---

### C. Routing

#### C.1 Update `App.js`

**File:** `frontend/pwa-wells-permit-web/src/App.js`

Add the `/location-map` route:

```jsx
import LocationMap from './components/LocationMap/LocationMap';

<Routes>
  <Route path="/applicant-info" element={<ApplicantInfoForm />} />
  <Route path="/location-map"   element={<LocationMap />} />
  {/* Future routes added here as each JSP is migrated */}
  <Route path="/" element={<Navigate to="/applicant-info" replace />} />
</Routes>
```

Also update the `ApplicantInfoForm` submit handler to navigate to `'/location-map'` after saving (Step 1 → Step 2).

---

### D. React Component Structure

#### D.1 File Layout

Create these files under `frontend/pwa-wells-permit-web/src/components/LocationMap/`:

```
LocationMap/
  LocationMap.js          ← Page container: state, API call, navigation
  LocationMap.css         ← All lm* CSS classes
  MapContainer.js         ← <GoogleMap> with boundary lock and click handler
  SearchBox.js            ← <StandaloneSearchBox> wrapper
  LocationInfoWindow.js   ← InfoWindow content: textarea + city + buttons
  JurisdictionWarning.js  ← InfoWindow content for out-of-jurisdiction pins
  HelpModal.js            ← Instructions overlay modal
```

#### D.2 CSS Convention

All classes in `LocationMap.css` use the `lm` prefix (e.g., `lmPage`, `lmInstructionBar`, `lmMap`, `lmSearchInput`, `lmFormRow`, `lmHelpBtn`, `lmModal`, `lmErrorBanner`). Follow the `ai*` pattern from `ApplicantInfoForm.css`.

#### D.3 Component Responsibilities

| Component | What it does |
|---|---|
| `LocationMap` | Holds all state (`markerPos`, `locDesc`, `locCity`, `isInJurisdiction`, `showModal`, `saveError`). Calls `useJsApiLoader`. Renders instruction bar, `SearchBox`, `MapContainer`, `HelpModal`. Handles save + API call. |
| `MapContainer` | Renders `<GoogleMap>` + `<Marker>` + `<InfoWindow>` (either `LocationInfoWindow` or `JurisdictionWarning`). Receives `center`, `markerPos`, `onMapClick`, `onMarkerRemove`, `onSaveClick` as props. |
| `SearchBox` | Renders `<StandaloneSearchBox>`. Calls `onPlacesChanged` prop with results array. |
| `LocationInfoWindow` | Receives `locDesc`, `locCity`, `onChange`, `onRemoveMarker`, `onSave` as props. Renders textarea + city input. |
| `JurisdictionWarning` | Receives `formattedAddress` as prop. Renders warning text + acpwa.org link. |
| `HelpModal` | Receives `isOpen` + `onClose` as props. Renders the instruction overlay. Drop the IE Compatibility View instructions — not relevant to a modern PWA. |

**Note:** The legacy JSP uses `element.cloneNode(true)` to put DOM nodes inside the Maps InfoWindow. With `@react-google-maps/api`, `<InfoWindow>` accepts JSX children directly — do not replicate the cloneNode pattern.

---

### E. Google Maps Integration

#### E.1 Legacy → React Mapping

| Legacy (`initMap` global callback) | React equivalent |
|---|---|
| `<script async defer src="...&callback=initMap">` | `useJsApiLoader` hook in `LocationMap.js` |
| `new google.maps.Map(div, options)` | `<GoogleMap mapContainerClassName="lmMap" options={MAP_OPTIONS}>` |
| Global `var map` | `mapRef = useRef()` populated via `<GoogleMap onLoad={map => mapRef.current = map}>` |

#### E.2 Loader Pattern in `LocationMap.js`

```js
// MUST be outside the component — a new array ref on each render causes repeated script loads
const LIBRARIES = ['places'];

export default function LocationMap() {
  const { isLoaded, loadError } = useJsApiLoader({
    googleMapsApiKey: process.env.REACT_APP_GOOGLE_MAPS_API_KEY,
    libraries: LIBRARIES,
  });

  if (loadError) return <div className="lmLoadError">Failed to load Google Maps.</div>;
  if (!isLoaded) return <div className="lmLoading">Loading map…</div>;
  return <LocationMapLoaded />;
}
```

#### E.3 Map Options

```js
const DEFAULT_CENTER = { lat: 37.79, lng: -122.26 };
const MAP_OPTIONS = { mapTypeId: 'hybrid', zoom: 16 };
```

---

### F. Click-to-Pin and Reverse Geocoding

#### F.1 Legacy → React Mapping

| Legacy | React |
|---|---|
| `google.maps.event.addListener(map, 'click', fn)` | `<GoogleMap onClick={handleMapClick}>` |
| Global `var geocoder = new google.maps.Geocoder()` | `new window.google.maps.Geocoder()` inside handler |
| `for (k = 0; k < ...; k++)` loop (global `k`) | `result.address_components.find(c => c.types[0] === 'locality')` |

#### F.2 Handler in `LocationMap.js`

```js
function handleMapClick(event) {
  const latLng = { lat: event.latLng.lat(), lng: event.latLng.lng() };
  setMarkerPos(latLng);
  setLocDesc('');
  setLocCity('');
  setIsInJurisdiction(null);

  new window.google.maps.Geocoder().geocode({ location: latLng }, (results, status) => {
    if (status !== 'OK' || !results?.length) { setIsInJurisdiction(false); return; }
    const locality = results[0].address_components.find(c => c.types[0] === 'locality');
    const city = locality?.long_name ?? '';
    setLocDesc(results[0].formatted_address);
    setLocCity(city);
    setIsInJurisdiction(APPROVED_CITIES.has(city));
  });
}
```

**Bug fixed:** Legacy uses `for` loop with implicit global `k`. React uses `Array.find()` with `const`.

---

### G. Search Box

#### G.1 `SearchBox.js`

```jsx
import { StandaloneSearchBox } from '@react-google-maps/api';

export default function SearchBox({ onPlacesChanged }) {
  const [searchBox, setSearchBox] = useState(null);
  return (
    <StandaloneSearchBox onLoad={setSearchBox}
      onPlacesChanged={() => searchBox && onPlacesChanged(searchBox.getPlaces())}>
      <input type="text" className="lmSearchInput" placeholder="Search Address" />
    </StandaloneSearchBox>
  );
}
```

#### G.2 Handler in `LocationMap.js`

```js
function handlePlacesChanged(places) {
  const place = places[0];
  if (!place?.geometry) return;

  const latLng = { lat: place.geometry.location.lat(), lng: place.geometry.location.lng() };
  setMarkerPos(latLng);

  // Populate locdesc — same logic as JSP, with null guard on place.name
  const desc = place.name && place.name[0] !== place.formatted_address[0]
    ? `${place.formatted_address}\n${place.name}`
    : place.formatted_address;
  setLocDesc(desc);

  // Extract city — with geocoder fallback if address_components absent
  if (place.address_components) {
    const locality = place.address_components.find(c => c.types[0] === 'locality');
    const city = locality?.long_name ?? '';
    setLocCity(city);
    setIsInJurisdiction(APPROVED_CITIES.has(city));
  } else {
    new window.google.maps.Geocoder().geocode({ location: latLng }, (results, status) => {
      if (status === 'OK' && results?.[0]) {
        const locality = results[0].address_components.find(c => c.types[0] === 'locality');
        const city = locality?.long_name ?? '';
        setLocCity(city);
        setIsInJurisdiction(APPROVED_CITIES.has(city));
      } else {
        setIsInJurisdiction(false);
      }
    });
  }

  // Fit bounds
  if (mapRef.current) {
    const bounds = new window.google.maps.LatLngBounds();
    if (place.geometry.viewport) bounds.union(place.geometry.viewport);
    else bounds.extend(place.geometry.location);
    mapRef.current.fitBounds(bounds);
  }
}
```

**Bug fixed:** `place.name &&` guard prevents crash when `place.name` is undefined.

---

### H. Jurisdiction Validation

#### H.1 Client-Side Constant in `LocationMap.js`

```js
// Module level — not inside the component
const APPROVED_CITIES = new Set([
  'Hayward', 'Alameda', 'Oakland', 'Castro Valley',
  'Emeryville', 'Albany', 'Piedmont', 'San Lorenzo', 'San Leandro',
]);
```

A `Set` replaces the three duplicated `if` chains in the JSP. All code paths call `APPROVED_CITIES.has(city)` — single source of truth.

#### H.2 Also Validate Server-Side

The `.NET SaveLocation` endpoint (Section K) rejects saves with an unapproved city and returns `400 Bad Request`. This prevents bypass by DOM manipulation.

**TODO:** Confirm with the county team that the Google Geocoder consistently returns the exact city strings above for Castro Valley, San Lorenzo, and unincorporated areas before go-live.

---

### I. Map Boundary Lock

#### I.1 Legacy → React Mapping

| Legacy | React |
|---|---|
| `google.maps.event.addListener(map, 'dragend', fn)` | `<GoogleMap onDragEnd={handleDragEnd}>` |
| `map.setCenter(new LatLng(...))` | `mapRef.current.panTo({ lat, lng })` |

#### I.2 Handler in `MapContainer.js`

```js
const BOUNDARY = {
  sw: { lat: 37.453764, lng: -122.369047 },
  ne: { lat: 37.922153, lng: -121.638478 },
};

function handleDragEnd() {
  if (!mapRef.current) return;
  const c = mapRef.current.getCenter();
  let lat = c.lat(), lng = c.lng(), clamped = false;
  if (lat < BOUNDARY.sw.lat) { lat = BOUNDARY.sw.lat; clamped = true; }
  if (lat > BOUNDARY.ne.lat) { lat = BOUNDARY.ne.lat; clamped = true; }
  if (lng < BOUNDARY.sw.lng) { lng = BOUNDARY.sw.lng; clamped = true; }
  if (lng > BOUNDARY.ne.lng) { lng = BOUNDARY.ne.lng; clamped = true; }
  if (clamped) mapRef.current.panTo({ lat, lng });
}
```

---

### J. Returning-User Mode

#### J.1 Legacy → React Mapping

| Legacy (`locset=true`) | React equivalent |
|---|---|
| `!(getSiteLat() == "")` (buggy ref-equality) | `application.project.siteLat !== null` |
| Server-rendered JS loop splitting `\r\n` | `useState(savedProject.siteLocation ?? '')` |
| `map.zoom = 20` | Pass `zoom: 20` in map options when `hasExistingLocation` |
| `infowindow.open(map, marker)` on load | `<InfoWindow>` renders when `markerPos !== null && isInJurisdiction` |
| "Return to Form" (proc=proj) | `navigate('/applicant-info')` |

#### J.2 Pattern in `LocationMap.js`

```js
const { application, updateProject } = useApplication();
const saved = application.project;
const hasExistingLocation = saved.siteLat !== null;

const [markerPos, setMarkerPos] = useState(
  hasExistingLocation ? { lat: saved.siteLat, lng: saved.siteLong } : null
);
const [locDesc,  setLocDesc]  = useState(saved.siteLocation ?? '');
const [locCity,  setLocCity]  = useState(saved.siteCityName ?? '');
const [isInJurisdiction, setIsInJurisdiction] = useState(
  hasExistingLocation ? true : null
);
```

**TODO:** When the Project Info page is migrated (likely `/project-info`), update `navigate('/applicant-info')` in `handleReturnToForm` to point to the correct route.

---

### K. .NET API Endpoint

#### K.1 New Controller

**File:** `backend/PWA.WellsPermit.WebApi/PWA.WellsPermit.WebApi/Controllers/ProjectLocationController.cs`

```csharp
[ApiController]
[Route("api/project-location")]
public class ProjectLocationController : ControllerBase
{
    private static readonly Dictionary<string, string> _cityCodes =
        new(StringComparer.OrdinalIgnoreCase)
    {
        { "Hayward",       "HAY" },   // TODO: verify actual codes from legacy DB
        { "Alameda",       "ALA" },
        { "Oakland",       "OAK" },
        { "Castro Valley", "CAS" },
        { "Emeryville",    "EME" },
        { "Albany",        "ALB" },
        { "Piedmont",      "PIE" },
        { "San Lorenzo",   "SLO" },
        { "San Leandro",   "SLE" },
    };

    [HttpPost("save")]
    public IActionResult SaveLocation([FromBody] SaveLocationRequest request)
    {
        if (!_cityCodes.TryGetValue(request.SiteCityName, out var cityCode))
            return BadRequest(new { error =
                $"'{request.SiteCityName}' is not within Alameda County Public Works jurisdiction." });

        return Ok(new SaveLocationResponse(
            request.Lat, request.Lng,
            request.SiteLocation, request.SiteCityName, cityCode));
    }
}
```

`StringComparer.OrdinalIgnoreCase` ensures minor geocoder casing variations don't break the lookup.

**TODO:** Retrieve actual city code values from the legacy DB's `city_codes` table (query `BeanCodesCity` or run a SQL lookup). The 3-letter codes above are placeholders.

#### K.2 New DTOs

**File:** `backend/.../Models/SaveLocationRequest.cs`
```csharp
namespace PWA.WellsPermit.WebApi.Models;
public record SaveLocationRequest(double Lat, double Lng, string SiteLocation, string SiteCityName);
```

**File:** `backend/.../Models/SaveLocationResponse.cs`
```csharp
namespace PWA.WellsPermit.WebApi.Models;
public record SaveLocationResponse(double Lat, double Lng, string SiteLocation, string SiteCityName, string SiteCityCode);
```

#### K.3 React Save Handler in `LocationMap.js`

```js
async function handleSave() {
  if (!markerPos) {
    setSaveError('Please pin a location on the map before saving.');
    return;
  }
  if (!isInJurisdiction) {
    setSaveError('Location is not within Alameda County Public Works jurisdiction.');
    return;
  }
  try {
    const result = await api.post('/api/project-location/save', {
      lat: markerPos.lat, lng: markerPos.lng,
      siteLocation: locDesc, siteCityName: locCity,
    });
    updateProject({ ...application.project, ...result });
    navigate('/work-types');
  } catch (err) {
    setSaveError(err.message);
  }
}
```

---

### L. Known Bugs Fixed in Migration

| Legacy Bug | Root Cause | Fix Applied |
|---|---|---|
| `!(getSiteLat() == "")` — returning-user mode may never activate | Java `==` compares String references, not values | `siteLat !== null` strict null check |
| `marker.getPosition()` called without null-checking `marker` | No defensive guard on undefined var | `if (!markerPos) return` guard at top of `handleSave` |
| Jurisdiction check duplicated 3× in JSP | Copy-paste, no shared function | Single `APPROVED_CITIES.has(city)` from all code paths |
| `place.name.substring(0,1)` crashes if `place.name` is undefined | No null guard | `place.name &&` guard before comparison |
| `var k` in geocoder callback is implicitly global | ES5 style, no block scoping | `Array.find()` with `const` — no global leakage |
| Warning InfoWindow uses `<img src="/images/Warning.png">` | JSP hardcodes internal server path | Replace with Unicode `⚠` or asset in `public/images/` |
| IE Compatibility View instructions in help modal | Legacy IE targeting | Remove from `HelpModal.js` |

---

### M. Verification / End-to-End Testing

#### M.1 Local Test Sequence

1. `dotnet run` from `backend/PWA.WellsPermit.WebApi/` — confirm Swagger at `http://localhost:5012/swagger`.
2. `npm start` from `frontend/pwa-wells-permit-web/` — confirm app at `http://localhost:3000`.
3. Navigate `/applicant-info` → submit → confirm router goes to `/location-map`.
4. Confirm map loads: hybrid view, Oakland center, zoom 16.
5. Click inside Alameda County (e.g., downtown Oakland) → marker, textarea + city auto-populate, InfoWindow shows location form.
6. Click outside jurisdiction (e.g., San Francisco) → InfoWindow shows warning, no Save button.
7. Search "City Hall, Oakland, CA" → marker moves, fields populate, form shown.
8. Drag map north toward Richmond → confirm map snaps back to boundary.
9. Click "Remove marker" → marker disappears.
10. Place valid pin → "SAVE AND CONTINUE" → `POST /api/project-location/save` returns `200 OK` with `siteCityCode` → context updated → router navigates to `/work-types`.
11. Navigate back to `/location-map` → confirm returning-user mode: saved marker pre-placed, fields pre-filled, InfoWindow open, "Return to Form" button visible.
12. Via Swagger: `POST /api/project-location/save` with `SiteCityName: "Fremont"` → confirm `400 Bad Request`.

#### M.2 React Component Tests (React Testing Library)

- `HelpModal`: renders/hides on `isOpen` prop; calls `onClose` on X click.
- `LocationInfoWindow`: textarea and city values bound correctly; buttons fire correct callbacks.
- `JurisdictionWarning`: warning text + acpwa.org anchor with `target="_blank"` present.
- Jurisdiction unit: `APPROVED_CITIES.has('Oakland')` → `true`; `APPROVED_CITIES.has('Fremont')` → `false`.
- Mock `useJsApiLoader` to return `{ isLoaded: true }` to avoid loading real Maps API in tests.

#### M.3 .NET Unit Tests (xUnit)

- `SaveLocation` with `SiteCityName: "Oakland"` → `200 OK` + `siteCityCode` in response.
- `SaveLocation` with `SiteCityName: "Fremont"` → `400 Bad Request`.
- `SaveLocation` with `SiteCityName: "oakland"` (lowercase) → `200 OK` (OrdinalIgnoreCase).
- `SaveLocation` with empty `SiteLocation` → `200 OK` (no required validation on description).

---

## Critical Files — Implementation Order

| # | File | Change |
|---|---|---|
| 1 | `frontend/.env.local` | Add `REACT_APP_GOOGLE_MAPS_API_KEY` |
| 2 | `frontend/src/context/ApplicationContext.js` | Add 5 fields to `project` slice |
| 3 | `frontend/src/App.js` | Add `/location-map` route |
| 4 | `frontend/src/components/LocationMap/LocationMap.js` | Create page component |
| 5 | `frontend/src/components/LocationMap/LocationMap.css` | Create `lm*` styles |
| 6 | `frontend/src/components/LocationMap/MapContainer.js` | Create map wrapper |
| 7 | `frontend/src/components/LocationMap/SearchBox.js` | Create search input |
| 8 | `frontend/src/components/LocationMap/LocationInfoWindow.js` | Create form InfoWindow |
| 9 | `frontend/src/components/LocationMap/JurisdictionWarning.js` | Create warning InfoWindow |
| 10 | `frontend/src/components/LocationMap/HelpModal.js` | Create help modal |
| 11 | `backend/Controllers/ProjectLocationController.cs` | Create save endpoint |
| 12 | `backend/Models/SaveLocationRequest.cs` | Create request DTO |
| 13 | `backend/Models/SaveLocationResponse.cs` | Create response DTO |
