# Specification: app_work_wellsmap.jsp — Wells Map (Per-Work Item)

## Context

This specification was reverse-engineered from the production legacy Java/JBoss application at:
`wellspermit-ecomm-web-jboss/src/main/webapp/app_work_wellsmap.jsp`

The goal is to document exactly what this page does so it can be understood, maintained, or replicated in the new React/PWA frontend.

---

## 1. What the Page Does

This page presents an interactive Google Maps interface that allows applicants to drop pin markers on a satellite/hybrid map to record the physical location of each well associated with a specific work item on their permit application. For each pin placed, the applicant enters well specification details (dimensions and identifiers) into a data entry form embedded in a map info-window. Each completed well entry is saved back to the session's `BeanAppWrk.wrkSpecsVec` and the map re-renders with all previously saved pins upon each reload.

The applicant can:
- Click anywhere on the map to drop a new, unsaved marker
- Fill in well dimension and identifier fields in the pop-up data entry panel
- Click SAVE to POST a single well record to the server (page reloads with the new pin rendered)
- Repeat the click-fill-save cycle for each individual well in the work item
- Click "Return to Form" to go back to the well specifications tabular form (`proc=specs`) when finished

---

## 2. Page Position in Workflow

```
Well Specs Form (specs) -> [THIS PAGE] Well Map (wmap / wmapu) -> Well Specs Form (specs)
```

| Process Code | Action |
|---|---|
| `wmap` | `DisplayAppServlet.displayWellsMap()` (lines 488–522) forwards to this JSP |
| `wmapu` | `DisplayAppServlet.saveWellsMarkers()` (lines 2444–2505) processes the form POST, then re-calls `displayWellsMap()` |
| `specs` | `DisplayAppServlet.displayWellSpecs()` — destination of the "Return to Form" button |

---

## 3. Page URL / Entry Point

- **Triggered by:** POST to `/pwapermitsecomm_app/DisplayAppServlet` with `proc=wmap`
- **Rendered by:** `DisplayAppServlet.displayWellsMap()` (lines 488–522)
- **Saves via:** POST to `/pwapermitsecomm_app/DisplayAppServlet` with `proc=wmapu`
- **Entry from:** The "Locate Wells on Map" button on `app_work_specs.jsp`, which POSTs `proc=wmap`

---

## 4. Session / State Inputs

| Session/Request Field | Java Getter | Default | Use |
|---|---|---|---|
| `BeanAppWrk` (request attribute) | `request.getAttribute("BeanAppWrk")` | None — null causes JS redirect | Work item being mapped; provides `workId`, `appId`, `workCat`, existing `wrkSpecsVec` |
| `ApplicationBean` (session) | `request.getSession().getAttribute("ApplicationBean")` | Redirect if null | Parent session bean; provides site coordinates |
| `aBean.getBeanApp().getSiteLat()` | `BeanApp.getSiteLat()` | `"37.792"` (hardcoded Oakland-area default) | Initial map center latitude |
| `aBean.getBeanApp().getSiteLong()` | `BeanApp.getSiteLong()` | `"-122.26"` (hardcoded Oakland-area default) | Initial map center longitude |
| `wBean.getWrkSpecsVec()` | `BeanAppWrk.getWrkSpecsVec()` | Empty `Vector` | Existing saved well pins to render on map load |
| `wBean.getWorkCat()` | `BeanAppWrk.getWorkCat()` | `""` | Controls conditional display of Decommission-mode fields |

Conditional logic:
- If `wBean.getWrkSpecsVec().size() > 0`, existing specs are iterated server-side to build the JavaScript `arr[]` array for rendering saved pins.
- If `wBean.getWorkCat()` starts with `"des"` (case-insensitive), three additional input fields appear: State Well #, Permit #, and DWR #.
- The map center variable (`lat`/`lng`) is initialized from the project site coordinates, then overwritten by the last spec in `specsVec` if any specs exist. The hidden `mp` form fields (`mlat`/`mlng`) therefore hold the last well's coordinates rather than the site's coordinates when specs exist (see Bug 6).

---

## 5. UI Layout

### 5.1 Page Header
- County shared header via `c_rt:import` from `System.getProperty("alco-inter-http") + "ssi/header2.htm"`
- Application sub-header via `<jsp:include page="pwaecomm_header.jsp" />`

### 5.2 Instruction Bar
- Text label: "Locate wells by clicking on map to enter well specifications. Click [Return to Form] when finished locating wells."
- Blue "Return to Form" button (`.medBtn`): submits the `returnToSpecs` form — POSTs `proc=specs`, `idNum`, `wSeq` to `DisplayAppServlet`.

### 5.3 Google Map
- Full-width `<div id="map">` at 100% height and width.
- Map type `hybrid` (satellite + road labels), initial zoom 20.
- Map click: clears any unsaved pending marker, places a new marker, opens the data entry `datawindow`.
- Saved pins: rendered at stored coordinates with Owner Well ID as title; clicking a saved pin opens an info-window with name and position string.

### 5.4 Data Entry Panel (`<div id="dataform">`, initially hidden)
Displayed in a Google Maps `InfoWindow` attached to a newly placed marker.

For all work categories:

| Label | HTML Input ID | Unit |
|---|---|---|
| Owner Well ID | `name` | — |
| Drill Hole Diameter | `drillDiameter` | in. |
| Casing Diameter | `casingDiameter` | in. |
| Surface Seal Depth | `surfaceDepth` | ft. |
| Max Depth | `maxDepth` | ft. |

For Decommission categories only (`workCat` starts with `"des"`):

| Label | HTML Input ID | Unit |
|---|---|---|
| State Well # | `stateID` | — |
| Permit # | `permit` | — |
| DWR # | `dwr` | — |

Buttons:
- "Remove" (gray `.smBtn`): `removeMarker()` — removes the unsaved pending marker.
- "SAVE" (blue `.medBtn`): `saveData()` — collects fields and submits the `saveMarker` form.

Help text: "Click SAVE; then locate next well OR Click 'Return to Form' button at top of page"

### 5.5 Saved-Pin Info Panel (`<div id="infoform">`, initially hidden)
Shown in an `InfoWindow` when a saved pin is clicked. Displays Owner Well ID label and a "Remove" button. The Remove button here calls `removeMarker()`, which acts on the currently pending unsaved marker — not the saved pin (Bug 3).

### 5.6 Hidden State Form (`<form name="mp">`)
Hidden fields `mlat` and `mlng` hold the lat/long used to center the map in `initMap()`. Values are rendered server-side from the final `lat`/`lng` scriptlet variables.

### 5.7 Page Footer
- Application sub-footer via `<jsp:include page="pwaecomm_footer.jsp" />`
- County shared footer via `c_rt:import` from `System.getProperty("alco-inter-http") + "ssi/footer2.htm"`

---

## 6. Google Maps Integration — Detailed Logic

### 6.1 `initMap()`
1. Server-renders `specsVec.size()` into `arr` variable.
2. If specs exist, calls `getData()` to populate `arr` with `"lat:lng:ownerWellNum"` strings.
3. Centers map at `(mp.mlat, mp.mlng)`.
4. Initializes map: type `hybrid`, zoom 20.
5. Calls `createMarker()` for each existing spec to render saved pins.
6. If specs exist, calls `getLastSpecs()` and pre-fills dimension inputs with the last saved spec's values.
7. Registers a map click listener: clears `notSavedMarkers[]`, places new marker, opens `datawindow`.

### 6.2 `createMarker(point, wname)`
Creates a saved-pin `Marker`. Registers: (a) a click listener to open `infowindow` with name and coordinates; (b) a window resize listener that re-centers and resets zoom — registered once per marker, so N markers means N listeners stacking on every resize (Bug 4).

### 6.3 `getData()`
Server-renders a JavaScript array at JSP parse time. Each element: `"latitude:longitude:ownerWellNum"`.

### 6.4 `getLastSpecs()`
Server-renders a JavaScript loop overwriting `specs[0..3]` on each iteration. Returns the last saved spec's hole diameter, casing diameter, seal depth, and max depth.

### 6.5 `saveData()`
1. Reads decommission fields if applicable.
2. Reads all five well dimension/ID fields from DOM.
3. Reads `marker.getPosition()` for pending marker coordinates.
4. Calls `addMarker()` to push `marker` to `markers[]`.
5. Populates all hidden fields of `saveMarker` form.
6. Submits `saveMarker` form (full page POST). No client-side validation is performed.

---

## 7. Form Submission

**Return to Form:**
1. User clicks "Return to Form."
2. `document.returnToSpecs.submit()` fires.
3. POST: `proc=specs`, `idNum`, `wSeq` to `DisplayAppServlet`.
4. Routes to `displayWellSpecs()` → `app_work_specs.jsp`.

**Save a Well:**
1. User clicks map to place marker.
2. User fills data entry panel. No validation occurs client-side.
3. User clicks SAVE — `saveData()` populates and submits `saveMarker` form.
4. POST: `proc=wmapu`, `idNum`, `wSeq`, plus all well spec fields.
5. Server routes to `saveWellsMarkers()`.
6. New `BeanAppWrkSpecs` appended to session's `wrkSpecsVec`. No database write.
7. `displayWellsMap()` called → page re-renders with updated pins.

---

## 8. Backend Save Logic (`DisplayAppServlet.saveWellsMarkers()`, lines 2444–2505)

No database write occurs. All changes are in-session only, persisted to DB at final submission via `ProcessAppServlet.addOrderToDb()`.

| POST Parameter | Session Update | Description |
|---|---|---|
| `wSeq` | Used to locate `BeanAppWrk` in `getAppWorksVector()` | Identifies the work item |
| `swellid` | `spBean.setStateWellId()` | State Well ID (decommission only) |
| `permit` | `spBean.setPermitNum()` | Permit number (decommission only) |
| `dwr` | `spBean.setDwrNum()` | DWR number (decommission only) |
| `owellnum` | `spBean.setOwnerWellNum()` | Owner-assigned well identifier |
| `holediam` | `spBean.setHoleDiameter()` | Drill hole diameter (inches) |
| `casediam` | `spBean.setCasingDiameter()` | Casing diameter (inches) |
| `sealdepth` | `spBean.setSealDepth()` | Surface seal depth (feet) |
| `maxdepth` | `spBean.setMaxDepth()` | Maximum depth (feet) |
| `wlat` | `spBean.setLatitude()` | Latitude from marker position |
| `wlong` | `spBean.setLongitude()` | Longitude from marker position |

`spBean.setSpecsId()`, `spBean.setStatusCode()`, and `spBean.setAddBy()` are NOT set here; they are assigned later in `BeanAppWrk.add()` at submission time.

After appending `spBean`, calls `displayWellsMap()` → re-forwards to this JSP.

---

## 9. External Dependencies

| Dependency | Purpose |
|---|---|
| `https://maps.googleapis.com/maps/api/js?key=<mapApiKey>&libraries=places&callback=initMap` | Google Maps JavaScript API; key from `PropertiesList.getMapApiKey()` (JVM system property) |
| `/ssi/countypage.js` | County shared JavaScript |
| `/ssi/deptpage.js` | Department shared JavaScript |
| `/ssi/onlineServices.css` | County shared stylesheet |
| `/wells/pwa_wells/pwa.css` | Application-specific stylesheet |
| `System.getProperty("alco-inter-http") + ssi/header2.htm` | County shared header HTML fragment |
| `System.getProperty("alco-inter-http") + ssi/footer2.htm` | County shared footer HTML fragment |
| `pwaecomm_header.jsp` | Application sub-header include |
| `pwaecomm_footer.jsp` | Application sub-footer include |
| `org.acgov.utility.PropertiesList` | Internal library — `getMapApiKey()`, `trace()` |
| `org.acgov.utility.Parameter` | Internal library — `getParm()` for safe request param reads |

---

## 10. Key Files

| File | Role |
|---|---|
| `wellspermit-ecomm-web-jboss/src/main/webapp/app_work_wellsmap.jsp` | This page (505 lines) |
| `…/app/DisplayAppServlet.java` lines 488–522 | `displayWellsMap()` — validates session, finds `BeanAppWrk` by `wSeq`, sets request attribute, forwards on `proc=wmap` |
| `…/app/DisplayAppServlet.java` lines 2444–2505 | `saveWellsMarkers()` — reads POST params, builds `BeanAppWrkSpecs`, appends to session vector, re-displays map on `proc=wmapu` |
| `…/common/BeanAppWrk.java` | Work item bean; `getWrkSpecsVec()`, `setWrkSpecsVec()`, `getWorkCat()`, `getAppId()`, `getWorkId()` |
| `…/common/BeanAppWrkSpecs.java` | Well spec bean; all coordinate and dimension fields populated by `saveWellsMarkers()` |
| `…/common/ApplicationBean.java` | Session container; `hasSiteLoc()`, `getAppWorksVector()`, `getBeanApp()` |
| `…/common/BeanApp.java` lines 3591–3602 | `getSiteLat()` / `getSiteLong()` — project site coordinates |
| `…/common/PropertiesList.java` line 611 | `getMapApiKey()` — Google Maps API key from JVM property |
| `…/app/DisplayWellsMapServlet.java` | Unrelated servlet; forwards to `wells_map.jsp`, not this page |
| `…/app/RoutedToWellsMapServlet.java` | Unrelated servlet; redirects to `DisplayWellsMapServlet` |

---

## 11. Known Issues / Notes

**Bug 1 — Missing `return` after `response.sendRedirect()` for null `aBean` (lines 18–22):** The redirect fires but execution continues. Line 26 then dereferences null, throwing `NullPointerException`. Fix: add `return;` immediately after `sendRedirect()`.

**Bug 2 — Missing `return` after JS-only redirect for null `wBean` (lines 45–47):** A JavaScript `window.location` redirect is emitted but server execution continues. Line 196 (`wBean.getWorkCat()`) will throw `NullPointerException`. Fix: use a server-side guard with `return;`.

**Bug 3 — `removeMarker()` in saved-pin info-window removes the wrong marker (lines 410–412):** Clicking Remove from a saved pin's info-window calls `removeMarker()`, which removes the currently pending unsaved marker (held in global `marker`), not the saved pin that was clicked. Saved pins have no functional remove path in this UI.

**Bug 4 — Stacking window resize listeners (lines 378–383 inside `createMarker()`):** One resize listener is registered per `createMarker()` call. With N saved specs, N handlers fire on every window resize event, each re-centering the map to a different well's position. Behavior is unpredictable and performance degrades with spec count. Fix: register the resize listener once outside the marker-creation loop.

**Bug 5 — String reference equality for lat/lng empty check (line 26):** `aBean.getBeanApp().getSiteLat() == ""` uses `==` not `.equals("")`. A non-interned empty String from a database result will not be reference-equal to the `""` literal, so the check incorrectly treats an empty lat as non-empty, passing a blank coordinate to Google Maps (resulting in a `NaN` center). Fix: use `.equals("")` or `.isEmpty()`.

**Bug 6 — Map center overwritten by last well's coordinates (lines 32–40, 215–216):** `lat`/`lng` are initialized from site coordinates, then overwritten by the spec loop. The hidden `mlat`/`mlng` fields receive the last well's coordinates. The map re-centers on the last well rather than the project site on every page reload when any specs exist. Fix: use separate iteration variables so site coordinates survive the loop.

**Note — Unused `places` library loaded:** `&libraries=places` remains in the Google Maps API URL despite the SearchBox feature being fully commented out (lines 266–322). This adds unnecessary network overhead.

**Note — `drillCount` not set in `saveWellsMarkers()`:** `BeanAppWrkSpecs.drillCount` defaults to `"1"`. All pins saved through the map will have drill count 1 with no way to change it from the map UI. The tabular specs form allows direct editing of drill count.

**Note — No client-side validation before save:** All fields can be submitted empty. Server-side validation in `BeanAppWrkSpecs.validate()` runs only later in `app_work_specs.jsp`, giving no in-context feedback on the map page.

**Note — Hardcoded default coordinates:** `lat = "37.792"`, `lng = "-122.26"` (lines 16–17) are hardcoded to an East Bay, California location near Oakland. Not configurable from any external property file.
