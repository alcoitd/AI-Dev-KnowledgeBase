# Specification: app_proj_locmap.jsp — Project Location Map Page

## Context

This specification was reverse-engineered from the production legacy Java/JBoss application at:
`wellspermit-ecomm-web-jboss/src/main/webapp/app_proj_locmap.jsp`

The goal is to document exactly what this page does so it can be understood, maintained, or replicated in the new React/PWA frontend.

---

## 1. What the Page Does

`app_proj_locmap.jsp` is **Step 2 of the Wells Permit application workflow** — the **Project Location Map** page. Its job is to let the permit applicant identify the geographic location of their well project on a Google Map and save the result (latitude, longitude, address, and city) back to the application session.

The applicant can:
- Click anywhere on the map to drop a location marker
- Search for an address using a Google Places search box
- Edit the auto-populated location description
- Save the location and continue to the next step (Project Info)
- Return to the previous form without saving (if a location was already set)

---

## 2. Page Position in Workflow

```
Project Info (proj) → [THIS PAGE] Location Map (lmap/lmapu) → Work Types (wrktp)
```

| Process Code | Action |
|---|---|
| `lmap` | `DisplayAppServlet.displayLocationMap()` forwards to this JSP |
| `lmapu` | `DisplayAppServlet.saveLocationMarker()` processes the form POST |
| `proj` | `DisplayAppServlet.displayProjInfo()` — where "Return to Form" goes |

---

## 3. Page URL / Entry Point

- **Triggered by:** POST to `/pwapermitsecomm_app/DisplayAppServlet` with `proc=lmap`
- **Rendered by:** `DisplayAppServlet.displayLocationMap()` (lines 459–487)
- **Saves via:** POST to `/pwapermitsecomm_app/DisplayAppServlet` with `proc=lmapu`

---

## 4. Session / State Inputs

On page load, the JSP reads these values from the `ApplicationBean` session object:

| Session Field | Java Getter | Default | Use |
|---|---|---|---|
| `SiteLat` | `aBean.getBeanApp().getSiteLat()` | `"37.79"` (Oakland area) | Map center latitude |
| `SiteLong` | `aBean.getBeanApp().getSiteLong()` | `"-122.26"` | Map center longitude |
| `SiteLocation` | `aBean.getBeanApp().getSiteLocation()` | `""` | Pre-fill location description textarea |
| `SiteCityName` | `aBean.getBeanApp().getSiteCityName()` | `""` | Pre-fill city input |

If `SiteLat` is non-empty, `locset = true`, which activates **returning-user mode** (see §7).

---

## 5. UI Layout

### 5.1 Page Header
- County header via SSI import (`ssi/header2.htm`)
- Department header via `pwaecomm_header.jsp`
- Page title: `"Public Works Water Resources-Wells Permit Application-Location Map"`

### 5.2 Instruction Bar (above map)
- Label text: *"Identify project location on map; Click on map or enter address/location in 'Search Address' box to position map."*
- **"Return to Form" button** — visible only if `locset=true` (a location was previously saved). Submits the `returnToProj` form (proc=proj), discarding any changes.
- **"help" button** — circular dark-green button, top-right. Opens instructions modal.

### 5.3 Search Box
- Google Places `SearchBox` bound to `<input id="pac-input">` with placeholder "Search Address"
- Width: 400px, styled with Roboto font

### 5.4 Google Map
- `<div id="map">` — full width, height fills container
- Map type: `hybrid` (satellite + road labels)
- Initial zoom: 16
- Centered on saved lat/lng (or default 37.79, -122.26 if not set)

### 5.5 Location Form (shown in map InfoWindow)
- **Location Address/Description** textarea (`id="locdesc"`, max 200 chars) — auto-populated from geocoding
- **Location City** text input (`id="loccity"`, max 200 chars) — auto-populated from address components
- **"Remove marker" button** — calls `removeMarker()`, removes the map marker (does not clear text fields)
- **"SAVE AND CONTINUE" button** — calls `saveData()`, validates and submits

### 5.6 Help Modal
- Overlay with instructions for:
  - IE browser Compatibility View fix
  - How to click-to-pin a location
  - How to use the Search Address box
  - Character limit note (200 chars)
  - Save/Cancel guidance

### 5.7 Page Footer
- County footer via SSI import (`ssi/footer2.htm`)
- Department footer via `pwaecomm_footer.jsp`

---

## 6. Map Behavior — Detailed Logic

### 6.1 Map Initialization (`initMap()`)
1. Centers map on saved lat/lng (or default Oakland coordinates)
2. If `locset=true` (returning user with saved location):
   - Drops a marker at the saved coordinates
   - Sets zoom to 20
   - Pre-populates `locdesc` textarea with saved location lines (split on `\r\n`)
   - Pre-populates `loccity` with saved city name
   - Opens InfoWindow (containing the location form) on the marker
3. Restricts map panning to **Bay Area bounding box**: SW (37.453764, -122.369047) → NE (37.922153, -121.638478). If user drags outside bounds, map auto-snaps back.

### 6.2 Click-to-Pin (`map 'click' listener`)
1. Clears existing markers
2. Clears `locdesc` and `loccity` fields
3. Drops new marker at clicked coordinates
4. Calls Google Geocoder (reverse geocode) on clicked lat/lng
5. Populates `locdesc` with `result[0].formatted_address`
6. Extracts city from address components (`types[0] == "locality"`)
7. **Jurisdiction check** (see §8) — if city is in approved list: opens InfoWindow with location form on marker. Otherwise: opens InfoWindow with warning message.

### 6.3 Search Box (`searchBox 'places_changed' listener`)
1. Clears existing markers
2. For each result place:
   - Creates marker at `place.geometry.location`
   - Populates `locdesc`:
     - If place name starts with same character as formatted address → use `formatted_address` only
     - Otherwise → `formatted_address + "\n" + place.name`
   - Extracts city from `place.address_components` (`types[0] == "locality"`)
   - If no address_components: falls back to reverse geocoder to extract city
   - **Jurisdiction check** (see §8)
3. Fits map bounds to search results

---

## 7. Returning-User Mode

If the applicant has already set a location (session `SiteLat` is non-empty):
- The map initializes with the saved marker and opens the form InfoWindow automatically
- "Return to Form" button is shown, allowing the user to abandon edits and go back to Project Info
- Location description and city are pre-populated

---

## 8. Jurisdiction Validation

After every marker placement (click or search), the city extracted from geocoding is checked against an **approved city list**:

```
Hayward, Alameda, Oakland, Castro Valley, Emeryville, Albany,
Piedmont, San Lorenzo, San Leandro
```

**If city IS in the list:** InfoWindow shows the location form (address, city, Save button).

**If city is NOT in the list:** InfoWindow shows a warning:
> "Location is not within Alameda County Public Works Jurisdiction or Address returned is not sufficient. Click on map area to retry."
> With a warning icon and link to https://www.acpwa.org/drilling-and-wells-permit

The user cannot save an out-of-jurisdiction location — the form is not presented.

---

## 9. Form Submission (`saveData()`)

1. Reads `locdesc` value (location description)
2. Reads `loccity` value (city name)
3. Calls `marker.getPosition()` to get current lat/lng
4. Populates hidden fields in `saveMarker` form:
   - `projLoc` ← locdesc value
   - `locCity` ← loccity value
   - `lat` ← marker latitude
   - `lng` ← marker longitude
5. Submits `saveMarker` form via POST to `DisplayAppServlet` with `proc=lmapu`
6. Opens "Location saved" message InfoWindow on map (visual feedback before page navigates away)

**Note:** There is no client-side validation of empty fields before submit — validation/defaults handled server-side.

---

## 10. Backend Save Logic (`DisplayAppServlet.saveLocationMarker`, lines 2395–2442)

Receives POST parameters and updates session:

| POST Parameter | Session Field Set | Method |
|---|---|---|
| `projLoc` | `appBean.setSiteLocation(locdesc)` | Stores description |
| `locCity` | `appBean.setSiteCityName(loccity)` | Stores city name |
| `locCity` | `appBean.setSiteCityCode(...)` | Lookup via `BeanCodesCity.retrieveCityCodeByName(conn, loccity)` |
| `lat` | `appBean.setSiteLat(latitude)` | Stores latitude string |
| `lng` | `appBean.setSiteLong(longitude)` | Stores longitude string |

After saving, calls `displayProjInfo()` → forwards to `app_proj_info.jsp` (Project Info page).

---

## 11. External Dependencies

| Dependency | Purpose |
|---|---|
| Google Maps JavaScript API | Map rendering, marker placement |
| Google Places library | Address search box autocomplete |
| Google Geocoder API | Reverse geocoding (click-to-pin and fallback for search) |
| `PropertiesList.getMapApiKey()` | Retrieves API key from server config |
| `/ssi/countypage.js` | Alameda County shared JS |
| `/ssi/deptpage.js` | Department-level shared JS |
| `/ssi/onlineServices.css` | County online services stylesheet |
| `/wells/pwa_wells/pwa.css` | Wells permit custom CSS |
| Bootstrap CSS | UI layout/buttons |
| `pwaecomm_header.jsp` / `pwaecomm_footer.jsp` | Department header/footer |
| `ssi/header2.htm` / `ssi/footer2.htm` | County SSI header/footer |

---

## 12. Key Files

| File | Role |
|---|---|
| `wellspermit-ecomm-web-jboss/src/main/webapp/app_proj_locmap.jsp` | This page (641 lines) |
| `…/app/DisplayAppServlet.java` lines 459–487 | Forwards to this JSP on `proc=lmap` |
| `…/app/DisplayAppServlet.java` lines 2395–2442 | Saves location data on `proc=lmapu` |
| `…/common/ApplicationBean.java` | Session container bean |
| `…/common/BeanApp.java` lines ~2961–3602 | Site location fields (SiteLat, SiteLong, SiteLocation, SiteCityName, SiteCityCode) |
| `…/common/BeanCodesCity.java` | City code lookup by name |
| `…/common/PropertiesList.java` line 611 | Google Maps API key getter |

---

## 13. Known Issues / Notes

- **String comparison bug (line 22):** `!(aBean.getBeanApp().getSiteLat()== "")` uses `==` for string comparison instead of `.equals("")` or `.isEmpty()`. In Java, `==` compares references not values. This may cause `locset` to always be `false` on some JVM implementations, preventing returning-user mode from activating.
- **IE browser compatibility note** in help modal suggests this was developed targeting IE; code also uses deprecated Google Maps API patterns.
- **No client-side empty-field validation** before form submit — a user could theoretically submit with no marker placed, causing a NullPointerException in `saveData()` when `marker.getPosition()` is called on an undefined marker.
- **"locaddr" hidden field** is present in the form but is commented out throughout the JavaScript — it is submitted as empty and unused server-side.
- The `locset` check controls pre-population of fields and marker placement; if the bug on line 22 prevents this, users will always see a fresh map even on return visits.
