# SNAP RELAP5 Plug-in User Manual — Exhaustive Extraction for STREAM.jl GUI Design

Source: `/tmp/snap_docs.txt` — *RELAP5 Plug-in Users Manual*, Symbolic Nuclear Analysis Package (SNAP), Version 6.5.1, August 02, 2021. Applied Programming Technology, Inc. Authors: Ken Jones, Bill Dunsford, John Rothe, Don Ulshafer, Dustin Vogt.

This document captures the entire content of the SNAP RELAP5 Plug-in User Manual as a research input for the STREAM.jl GUI. Sections 1–7 describe SNAP as documented; Section 8 maps each feature to STREAM.jl applicability; Section 9 identifies STREAM.jl–specific gaps not covered by SNAP.

---

## 1. COMPLETE FEATURE INVENTORY

### 1.1 SNAP framework context (Chapter 1)
- SNAP = Symbolic Nuclear Analysis Package; suite of integrated apps for thermal-hydraulic analysis.
- Modular plug-in architecture: each plug-in tailors functionality to a specific analysis code. RELAP5 is one such plug-in.
- Two RELAP plug-in versions:
  - RELAP5 MOD3.3 (CAMP-SUG members)
  - RELAP5 MOD3.3 + RELAP5-3D (SNAP users group / SUG members)
- Code name "ModelEditor" is the primary GUI application. SNAP also has a separate "Pre-processor plug-in" referenced for 3D viewing.
- Companion documents: "RELAP5 User's Manual" and "SNAP User's Manual."

### 1.2 Model creation (Chapter 2)
Three entry points to a RELAP5 model:
1. **Import existing ASCII file** — File → Import → RELAP5 ASCII. The MOD3.3+3D plug-in lets the user pick a target code version at import; the MOD3.3 plug-in fixes version. A version-mismatch confirmation dialog appears if file metadata disagrees with selection.
2. **Create new model** — File → New, pick "RELAP" from the New Model Dialog plug-in list. Opens an empty model with one open 2D view.
3. **Open existing `.MED` save file** — File → Open. `.MED` is the SNAP native save format. Forward-compatible (older saves open in newer plug-ins) but not backward-compatible.

Import handling rules:
- Comment lines (other than `*d:` description, `*c:` component comment, `*m:` metadata) are stripped.
- `*m:` line records SNAP version + RELAP code version.
- Duplicate cards: last one wins.
- Undefined cards → routed into "Extra Deck Data" property of Model Options.
- Input after the first RELAP case → "After Case Data" (not processed by plug-in).
- Non-ASCII characters → ignored.
- Unix substitution variables (`$VAR1`) → imported as user-defined constants (initial value 0). Supported for real values and a specific set of integer fields:
  - Model Options: `201 W4` Control Option in Timestep Data
  - Hydraulic Volumes: `CCC9101-9 W1` Volume Control Option
  - Reactor Kinetics: `3000003 W11..W15` (Thermal Scattering Iterations, Outer Iterations, Outer Computation Iterations, Max Order Chebyshev Fission, Transient Timestep Outer Iterations); `3000010 W3, W4` (Max Iterations, Intervals).

### 1.3 Editing UI primitives (Chapter 2.4)
- **Property View** — generic inline editors per attribute. Edits propagate immediately to ASCII view + push undo entry.
  - Generic logical editor (TRUE/FALSE).
- **Custom editors** — used for complex multi-field attributes; many are tabular.
- **Tabular editors** — multi-row editing, column-header tooltips, custom cell editors. Pop-up menu options:
  - Copy / Paste (interoperates with spreadsheets and other tabular editors)
  - Plot — pick one independent + one or more dependent variables; renders via APTPlot plug-in.
- Some tabular editors require explicit OK to commit (no live ASCII update / undo until OK).

### 1.4 Model editing entry points (Chapter 3)
- Add components via Navigator (right-click → New) or via "insert tool" in 2D view.
- Edit components via Property View or via 2D view.
- Disconnect/reconnect via Property View or 2D view.

### 1.5 Model Properties / Model Options (3.1)
- **Code** — selects RELAP5 analysis code variant (MOD3.3 or RELAP5-3D versions). Changing it morphs the rest of the model's available properties.
- **Developmental Options** — toggles internal options that alter properties elsewhere (e.g. Henry-Fauske critical flow model toggles which discharge coefficients appear on Branch junctions).
- **Input Units** — SI or British. Changes units of every real in the model.
- **HD Systems** (Hydraulic Systems) — list of hydraulic systems. Each system has fluid type + property file dependency at run time.
- **Timestep Data** — tabular editor with composite "Control Option" pop-up that uses checkboxes + an option to enter a user-defined numeric.
- **Noncondensible Gas Species** — mass fractions, must sum to 1.0. Default if none set: Nitrogen. Activating these enables noncondensible inputs throughout the model. Fixed export order; restart cases must match this order.
- **Initial Conditions** (managed via the IC editor — see 1.21).
- **Extra Deck Data** — bucket for unrecognized cards.
- **After Case Data** — content after the first RELAP case.
- **Attribute Level Ownership** toggle.

### 1.6 Hydraulic Components (3.2) — common features
- **Show ASCII** — right-click pop-up menu item; opens live-updating ASCII view of selected component.
- **Add to View** — right-click; adds component (or category) to selected 2D View.
- **Reference Docs** — right-click; opens the corresponding RELAP input manual section in default PDF viewer.
- **Copy / Cut / Paste** — across models open in same ModelEditor instance.
- **Description** + **Comments** per component, exported as `*d:` / `*c:` tagged comment lines.

### 1.7 The 1D hydraulic component catalog (3.2.1–3.2.22)
Complete list of components and their distinguishing inputs:

| Component | Key features |
|---|---|
| Single Volume | One hydraulic volume; uses pipe editors. |
| Time Dependent Volume (TDV) | Boundary fluid source/sink; pipe-style geometry; IC editor with T-flag combo, B-flag (boron concentration column), N-flag (noncondensible columns; gated by T-flag + Model Options noncondensibles). Multiple search variable sets allowed (unlike per-volume IC elsewhere). |
| Single Junction | One junction connecting two volumes; pipe-style geometry/IC/friction. |
| Time Dependent Junction (TDJ) | Phasic velocities or mass flow as function of time/quantity. **Control Word** property: Mass Flows vs Velocities (default: Flow Velocities). Tabular search variable / flow rate editor (Add/Remove + OK). |
| Single Flexible Wall | Like single junction but no flow — only wall movement. Has flexible wall area + table of volume displacement vs stiffness. |
| Pipe | Series of cells + interior junctions. Completion dialog at creation (cells, length, etc.). Cell+junction count immutable post-creation (use renodalization). Subordinate editors: Geometry, Initial Conditions, Friction Data. |
| Annulus | Identical to pipe, but must be vertical; different annular-mist regime treatment. |
| Pressurizer | Pipe + a Surge line Junction property. Surge line set by selecting an existing connection on inlet volume / inlet cross-flow faces. |
| CANDU Channel (CANCHAN) | RELAP5-only (not RELAP5-3D); identical to a horizontal pipe. |
| Branch | Single volume + up to 9 external junctions stored on the branch. External Junctions editor with From Face (inlet/outlet/cross-flow 3-6), Target component, Cell, and Reverse flag. |
| Separator (SEPARATR) | Branch with 3 junctions: vapor/gas outlet (1), liquid fall back (2), two-phase inlet (3). Separator Model property: Simple, GE dryer, GE 2-stage, GE 3-stage. Number of Components for stage 2/3. |
| Jet Mixer (JETMIXER) | Branch with exactly 3 junctions: drive (1), suction (2), discharge (3). Strict input ordering enforced (CCC1101/CCC1201 = drive; CCC2101/CCC2201 = suction; CCC3101/CCC3201 = discharge). Drive+suction TO=mixer inlet; discharge FROM=mixer outlet. |
| Turbine | 1–2 junctions: primary steam inlet (mandatory, junction 1), steam extraction bleed (optional, junction 2). Shaft connection via selection editor; Discon. Trip; Shaft Velocity, Inertia, Friction attributes. |
| ECC Mixer (ECCMIX) | Branch with 3 junctions: ECC inlet (1), normal inlet (2), discharge outlet (3). Adds an ECC junction angle (ECC Jun. Angle). |
| Valve | Junction-class component; flow area as function of time and/or hydrodynamic state. Properties depend heavily on Valve Type. |
| Pump | One volume + suction junction + discharge junction. Pipe-style geometry/IC/friction editors. |
| Compressor | RELAP5-3D 2.4 only. One volume + at least one inlet junction; optional outlet junction. Same Shaft + Trip Disconnect connection as Turbine. |
| Multiple Junction | Many single-junction equivalents. Connection editor with Add/Remove/Edit; From/To component selectors; From Cell/To Cell drop-downs. "Zipper" utility (Set button) for batch connections with starting cell, ending cell, increment, inlet face. |
| Multiple Flexible Wall | Same connection editor as Multi-Junction; geometry editor: flexible wall area + displacement vs volume/stiffness table. |
| Accumulator | Lumped tank + tank wall + surge line + outlet check valve junction; auto-resets to single-volume when liquid empties. Pipe-style sub-editors plus extra accumulator properties. |
| Multi-Dimensional (MULTID) | RELAP5-3D only. 1/2/3D array of volumes + internal junctions. Geometries: Partial Cylinder, Full Cylinder (azimuthal=360°), Cartesian. Has dedicated 3D geometry editor with rotate/translate/zoom and 2D Top-Down + axial Side View editors. Connections tab summarizes external connections and detail rows (Local Side / Remote Side). 2D drop-zone connection workflow with completion dialog. |
| Feedwater Heater | RELAP5-3D only. Specialized horizontal branch; 2 or 3 junctions; pipe-style sub-editors. |

### 1.8 Pipe sub-editors in detail (3.2.6)
These editors are reused by Single Volume, TDV, Single Junction, Single Flex Wall, Branch, Pressurizer, CANCHAN, Separator, Jet Mixer, Turbine, ECC Mixer, Valve, Pump, Compressor, Multi-Junction, Multi-Flex Wall, Accumulator, Feedwater Heater.

**Pipe Completion Dialog** — initial cell count, length, etc. Remembered for reuse if completion dialogs are disabled. New pipes get evenly-divided cell volumes.

**Pipe Geometry dialog** — graphical pipe at top + tabbed tables at bottom:
- **Cells tab** — volume, length, area per cell. Calculation type either single (component-wide radio buttons) or "By-Cell" (Calculate column per row). Y/Z crossflow length+area checkboxes per cell.
- **Orientation tab** — vertical/horizontal radio buttons or angle per cell; resulting elevation change shown. "Elevations" combo box switches between angle-mode and DZ-mode.
- **DZ tab** — direct elevation-change entry (when DZ mode chosen).
- **Junctions tab** — hydraulic diameter, flow area, CCFL model, choking model, area change option, momentum flux option, energy-equation modified PV term toggle, single-velocity (homogeneous) vs two-velocity (non-homogeneous) momentum equations toggle.
- Selections in tables and graphical view are bidirectionally linked. Greyed cells = not currently editable.

**Pipe Initial Conditions dialog** — used by all 1D hydraulic components:
- **Cell Fluid panel** — Condition (t-flag) per cell; columns become available based on t-flag value. Pop-up help button describes each t-flag and its column set. **Fluid (e-flag)** is read-only; defined by component's hydraulic system. On import, non-zero e-flag mismatches with system fluid are reconciled or a new hydraulic system is created with reference elevation 0.0.
- **Junction Flow panel** — flow velocity OR mass flow per fluid phase per junction.
- **Noncondensibles table** — per-noncondensible mass fraction overrides.

**Pipe Friction Data dialog** — used by all 1D hydraulic components:
- **Cell Options** — thermal front tracking model, mixture level tracking model, vertical stratification model. (More info in column tooltips.)
- **Wall Friction** — hydraulic diameter, wall roughness, shape, viscosity per axis. Axis Specification combo selects x/y/z (y/z only enabled if cell geometry enabled them).
- **Junction Friction** — forward + reverse loss coefficients; Reynolds-dependent loss coefficients.

**User-Defined Numerics** — most real-valued cells support User Values via right-click pop-up; pull from list of model-wide user-defined numerics.

### 1.9 Control Systems (3.3)
- Composed of: signal variables, control blocks, interactive variables, trips.

#### 1.9.1 Signal Variables (3.3.1)
Sources: General, Component, Volumetric, Junction, Heat, Power.

**Signal Variable Creation Dialog**
- Category list (left) + Type table (right). Selecting a category prunes the type list. Selecting "All" shows all types.
- **Creation Criteria** property view — per-type attributes the user must fill.
- **Signal Variables to be Created** preview list — auto-updates from Creation Criteria. Shows `{exists in model}` annotation if a candidate already exists.
- **Range creation** for Volumetric / Junction / Heat: start + end editors (3D constrained to single direction); one variable per element in range.
- **Filter** input — prunes type column. Categories show "matches" tags. "Include Description" checkbox extends filter to descriptions. Last 5 filters remembered in dropdown.

**Signal Variable Type Edit dialog**
- Mirror of creation dialog but for changing an existing variable's type across its usages.
- Usages table at bottom; user picks which usages to update.
- If the new type+properties match an existing variable, it is reused; otherwise a new one is created.

**Signal variable subtypes:**
- *General* — global system data (CPU time, current timestep, mass error estimate, etc.).
- *Component* — turbine efficiency, pump torque, valve area ratio, etc. Requires component reference but no location.
- *Volumetric* — value from a hydraulic cell. Requires component + Parameter (location). "S" button opens hydraulic component selection dialog.
- *Junction* — junction value within a component. Component + junction.
- *Heat* — heat structure value. Component + Surface + Parameter.
- *Power* — reactor kinetics power-related. Some types (e.g. RKOCRPSN) require Control Rod Group.

#### 1.9.2 Control Blocks (3.3.2)
- Manipulate input data; output a float.
- Inputs connected via 2D View "connect tool" — connect output of source (signal variable / other control block) to input of control block.

#### 1.9.3 Trips (3.3.3)
- **Variable Trips** — Relationship: =, ≠, >, ≥, ≤, <.
- **Logical Trips** — Operator: AND, OR, XOR.
- Two numbering formats:
  - Original: cards 401–799 → 199 variable + 199 logical.
  - Expanded: 20600010–20620000 → 1000 variable + 1000 logical.
- Format switchable if existing trip count fits new format; numbers are renumbered automatically.

#### 1.9.4 General Tables (3.3.4)
- Independent/dependent variable tables for heat structures, valves, reactor kinetics, control systems.
- Examples of relations: Temperature vs Time, Heat Transfer vs Time, Reactivity vs Time, Heat Transfer vs Temperature.
- Editor: Add / Remove rows; Sort by independent variable.
- **Foreground-color validation**:
  - Independent value < preceding → red.
  - Duplicate independent → red.
- Table contents may be replaced by a **Table Variable reference** with column mapping. Errors reported if rows out-of-order or column mapping invalid.
- Model report flags: non-ascending or duplicate independent values.

#### 1.9.5 Interactive Variables (3.3.5)
- Inputs that can change during interactive run-time. Card input = name + initial value.
- Usable in trips, control variable statements, table search arguments, minor edits, plots.
- Operator-style interactions: open/close/reposition valves, set new operating points.
- Connected via 2D view connection tool, or via editors that accept Interactive controls.

### 1.10 Heat Structures (3.4)
- Geometries: flat slab, cylindrical, spherical.
- **Heatstructure Completion Dialog** — geometry choice + axial+radial nodalization at creation.
- No 2D drawn glyph — connections only via editing dialogs.
- **Axial Cells/BCs editor** — table of axial cells; selecting cells shows their properties in a property view below; multi-select shows union of attributes (`< Different Values >` for non-shared values).
- **Left/Right Surface Boundary Conditions** — drop-downs for Additional Boundary Data Format per side; activation checkboxes force output even with no hydraulic connection. Boundary types include "symmetric" (no connection) and others.
- **Heat Connections dialog** (E button on Cell property) — connect ranges of hydraulic cells to selected heat cells (Hydraulic Component + Starting/Ending Cell).
- **Axial Power/Heating dialog** — power factor + heating multipliers per cell. Only enabled when at least one cell has source data. Replaceable by Table Variable reference (with column mapping validation).
- **Heatstructure Radial Geometry editor**:
  - Radial mesh thicknesses OR radial positions (only end position needed in second mode).
  - Optional: import radial geometry from another heat structure via Node Location property.
  - Split / Merge buttons for radial renodalization.
  - User-defined numerics allowed for any value.

### 1.11 Radiation Enclosure (3.5)
- Group of heat structures communicating via radiation/conduction.
- Heatstructures grouping editor — Add/Remove. Selecting a member surfaces its property view.
- View Factors editor — table; column tooltips identify surface being edited.

### 1.12 Materials (3.6)
- Pre-defined: carbon steel, stainless steel, zircaloy, etc.
- Add via Navigator → Materials → New, then choose **Material Type**.
- User-defined materials: pick "Table/Function" Material Type for tabular/functional properties.

### 1.13 Reactor Kinetics (3.7)
- Point Kinetics (RELAP5 + RELAP5-3D) and Nodal Kinetics (RELAP5-3D only).
- Enable: Reactor Kinetics navigator node → set Enable=True. Fires completion dialog.
- Disable: Enable=False. Clear: right-click Clear (removes data entirely).
- Greyed-out options indicate inapplicability for the chosen kinetics/feedback type.

#### 1.13.1 Point Kinetics editors
- **Table Data Editor** — spreadsheet-like; Add/Remove/Copy/Paste; Sort by independent variable.
- **Volumes/Heat Weighting Factors editor** — top table of Hydraulic / Heatstructure components providing feedback; bottom table of weighting factors + temperature coefficients per node of the upper-table selection. Replaceable by Table Variable reference; export reflects the mapped table.
- **Detector Editor** — Add/Remove detectors top table; source terms + weighting + attenuation in bottom table.

#### 1.13.2 Nodal Kinetics (RELAP5-3D only)
- **Geometry**: Hexagonal (full / 1/3 / 1/6 core) or Cartesian (full / 1/2 / 1/4 core).
- **Mesh Length editor** — X / Y / Z radio buttons; per-axis node lengths. Conventions documented:
  - Z starts bottom, proceeds upward (mesh #1 is bottom).
  - X starts at left (looking down), proceeds right.
  - Y starts at top (looking down), proceeds downward.
- **Composition/Zone Figure editor** — assigns figures to axial mesh intervals (mesh #1 = lowest). Add/Remove figures; figure-to-interval mapping.
- **Zones / Compositions / Control Rods editor (Planar Top-Down view)** — Cartesian or Hexagonal. Left-click selects single node; click+drag selects contiguous region; node selection editor (bottom-right) edits multi-node.
- **Initial Power Fraction editor** — initial guess for prompt fission distribution per node. Layout left→right, top→bottom; (1,1) = top-left. Per-axial-level optional; "Initialize Values" checkbox to enable; Axial Mesh Interval combo to switch level.
- **Volume/Heat Region Feedback editor** — upper table = data-entry counts per zone; selecting updates lower table. Feedback property toggles between volume / heatstructure feedback. Component selectors with min/max cell constraints.
- **Composition Cross Section editor** — list of cross sections + property view. **XS Data** sub-editor for each cross-section type; tooltips describe scattering pattern; type-specific extra properties.

### 1.14 Restart Cases (Chapter 4)
- Restart deck = subset of original input + fully resupplied components for any modified component.
- Created via Cases node → right-click → New.
- Edit modes: ASCII or Graphical (via Editing Mode property; press Edit on Restart Model property).
- **Graphical restart editing** — opens case as "Virtual Model" in Navigator. Restart panel above Navigator with Save/Close buttons. Modified components colored red.
- Save/Close commit/discard the restart input deck.
- Some properties locked during restart editing.
- Right-click on Case node provides Show ASCII, Import Case, Export Case.
- Noncondensible ordering caveat — must be adjusted via ASCII view of Model Options before graphical edits if order differs.

### 1.15 ASCII I/O (Chapter 5)
- **Input deck** — full RELAP5 ASCII; import via File → Import → RELAP5 ASCII; supports code+version selection and Unix substitution variables (imported as user-defined numerics).
- **Restart deck** — handled via Restart Cases (above).
- **Export options** in model right-click → Export sub-menu and File → Export.

### 1.16 Model Validation Tests (Chapter 6)
- Run on: ASCII export, calculation server submission, manual Check Model button press.
- Includes a "loop test" plus standard component validation for invalid data.

### 1.17 3D Visualization (Chapter 7)
- Provided by SNAP **Pre-processor plug-in for RELAP5** (separate plug-in).
- 1D components don't natively have 3D coords — generated via "Generate 3D Coordinates" tool.

#### 1.17.1 3D Coordinate Generation (7.1)
- Right-click on model → Generate 3D Coordinates.
- User picks a component for each hydraulic loop + an X/Y offset for that component.
- Geometry placer uses breadth-first walk through component connections.
- Components placed in approximately flat planes; bends inserted only for tee side-pipes, vessel connections, parallel plenum connections.

#### 1.17.2 3D Model Viewer (7.2)
- Open via right-click model → View Model in 3D.
- **Camera Controls**:
  - Mouse: left-drag rotate, right-drag translate, middle-drag zoom.
  - Camera control buttons on left side; reset buttons.
- **Selection modes**: Selection (CTRL+click toggles), Lasso Select (rectangular region; full-containment).
- Selected components → yellow.
- **Transforming Components**:
  - **Pivot** — pick a junction + flow direction; rotation pivots about the cell center opposite the flow. Slider ±180° about Z. Live preview; Apply / Finish to commit.
  - **Shift** — X+Y sliders. Live preview; Apply / OK to commit.
- **3D View Preferences (Properties button)**:
  - Show Arrows (junctions + external connections shown as arrows)
  - Use Wire frame
  - Show Axis Lines (axis at origin)
  - Center On Highlighted
  - Zoom Factor / Rotation Factor / Pan Factor (scaling factors)
  - Rotation Point — origin or selection center
  - Shading Type — optimization control; recommended "Nicest"
  - Lighting Attenuation coefficients
  - Cell Scale slider — render percentage of full cell volume (60% example illustrated).

### 1.18 Renodalization (Chapter 8)
- All renodalization is undo/redo-safe.

#### 1.18.1 1D Hydraulic (8.1)
- Multi-cell 1D components only.
- Right-click → Renodalize (in Navigator or 2D view).
- **Renodalization dialog**:
  - 2D view (top) + table (bottom) of axial node lengths (Nodes tab) or total elevation (Elevation tab).
  - Selecting cells in either pane reflects in the other.
  - Buttons: **Split**, **Split Uniform**, **Merge**.
  - Forward/back buttons for undo/redo within the dialog.
  - OK applies all changes; nothing applied until then.
- **Split** dialog (8.1.1) — table of new cells + fraction of original each represents. Normalize button if fractions don't sum to 1.0. Cell volume vs neighbor flow areas → conical-section detection for internal junction areas; same logic determines small-cell volumes.
- **Split Uniform** (8.1.2) — split each selected cell into N evenly-sized cells.
- **Merge** (8.1.3) — join selected cells (≥2) into one.
- **Elevation tab** (8.1.4) — Original DZ, Current DZ, Difference per cell — preview elevation impact.
- **Announce Changes** (8.1.5) — toggles Message Window output of which components were affected by the renodalization.
- **Renodalization Results** (8.1.6) — modified for restart inclusion. Volume/junction signal variables auto-update by closest-axial-position. Hydraulic connections auto-update target cells/junctions (rendering-only impact, no ASCII change).

#### 1.18.2 Heat Structure (8.2)
- **Radial renodalization** — via radial geometry dialog. Internal tables (e.g. fuel rod temperature) interpolated by radial dimension. Heat structure signal variables update by closest radial location.
- **Axial renodalization** — usually triggered by hydraulic component renodalization (compact equivalent-heat-transfer nodalization). Manual via Axial Node / Surface BCs editor with Split / Merge. Axial cells auto-coalesce only when both surfaces' BCs match.

#### 1.18.3 Pipe Split (8.3)
- Split a Pipe or Annulus into two at an internal junction.
- Downstream cells/junctions move to new component; selected interface becomes a single junction joining old outlet to new inlet.
- Cell/junction signal variable references update.
- Connected heat structures that span the split also split; reactor kinetics feedback coefficients and heat structure signal variables are auto-updated.

### 1.19 Attribute Level Ownership (Chapter 9)
- Activation: Model Options → Attribute Level Ownership = On. Newly created/imported models start with no ownership data.
- Display: Properties View → Show Owner checkbox in General attribute group heading.
- Per-attribute fields: owner, last modified time, reviewer, last reviewed time.
- Modifying an attribute → current user becomes owner, last-modified set, reviewer/last-reviewed cleared.
- Disabled attributes' ownership data discarded on save.
- **Review Properties window** — table of all attributes (component, attribute group, owner, reviewer). Toolbar Review button reviews selected; Take Ownership button clears reviewer + sets owner=current.
- **Search parameters**: Property Name, Component, Component Type, Owner, Reviewer, Modified Before/After, Reviewed Before/After. Dates for time fields; wildcard/glob for name fields.

### 1.20 Batch Commands (Chapter 10)
RELAP5 plug-in adds these to the ModelEditor batch interface:

- `RELAP IMPORT [flavor] [version] <RESTART> <LITERAL> <Mn> [filename]`
  - flavor: `MOD3.3`, `R53D`
  - version: 3.3 (MOD3.3); 2.2, 2.3, 2.4, 2.6, 4.0, 4.1, 4.3, 4.4 (RELAP5-3D)
  - `<RESTART>`, `<LITERAL>` (preserve `$VAR` literal names), `<Mn>` (M0–M9 model label).
- `RELAP EXPORT <NOMETA> <LITERAL> <RESTART> <Mn> [filename]`
- `RELAP EXPORT CASE [case name] [filename]`
- `RELAP EXPORT METRICS_SPEC [filename]` — Test Suite Analyzer (TSA) model spec.
- `RELAP EXPORT METRICS <Mn> [filename]` — TSA plug-in metrics data.
- `RELAP EXPORT NOTEBOOK_ODT <Mn> [filename]` — Model Notebook as ODF.
- `RELAP EXPORT NOTEBOOK_DOCX <Mn> [filename]` — Model Notebook as DOCX.
- `RELAP CREATE_VIEW <Mn> [category name]` — new view containing all components in a Navigator category.

### 1.21 Importing Initial Conditions (Chapter 11)
- Right-click model → Retrieve Initial Conditions.
- **Select IC Receiving Components** dialog — checkbox per category; cell-click opens additional dialog to fine-tune which components in that category are updated.
- A specific job must be loaded via the load action (arrow icon) before its ICs can be imported.
- **Retrieve Initial Conditions dialog** — restart cycling arrows; restart number + restart time displayed; option to import heat structure internal mesh temperatures from the closest Major Edit.
- OK starts import; errors → Message Window.

#### 1.21.1 Manage Initial Conditions (11.1)
- Editor accessible from model right-click pop-up or Model Options → Initial Conditions property.
- Buttons: Retrieve, Store (snapshot current model ICs), Load (restore a stored set), Remove (delete a stored set).
- Stored sets get a name + label.
- Sets persist in the model save and survive without the original run.

### 1.22 Model Notebooks (Chapter 12)
- Single annotated document containing calculations, export data, model status, attribute descriptions, etc.
- Export via File menu or model node → Export → Model Notebook → opens **Export Model Notebook dialog**. Tabs: General, Sub-Systems, Tables. Export button at bottom.

#### 1.22.1 General tab
- **Title Page** — references a model note. Buttons: Select, Edit, Preview (exports note as ODF and opens in default viewer).
- **Front Matter** — model notes before/after table of contents; reorderable (Up/Down arrows around an implicit ToC row).
- **Classification, Header, Footer** — fields for header/footer text; Classification appears in large type top + bottom.
- **Page Styles** — alternating left/right pages (book printing) vs single pages (electronic).
- **Misc**:
  - Mathcad Output Format (when Mathcad-function user-numerics are present).
  - Dollar Variable Display Format (Names / Values).
  - Include Input Listing — appends ASCII per component.
  - Include Owner/Reviewer Listing.
  - Open Exported Notebook (auto-open in viewer).
  - Include Component Images (non-trivial 2D View graphics).
  - Include Control System Sub-sections — toggle nesting (5.1 Logical Trips, 5.2 Variable Trips, 5.3 Control Blocks…) vs single combined section.

#### 1.22.2 Sub-Systems tab
- Lists top-level + their direct child sub-systems (children indented). Third-level and deeper folded into second-level parents.
- **Nest** flag — whether a sub-system gets its own document section or folds into parent.
- Non-nested top-level systems and orphans → implicit model-wide section.
- **View** column — set a 2D view used as the sub-system header image (disabled for non-nested).

#### 1.22.3 Tables tab
- Default: include all Table Variable data. Tables tab lets the user exclude. Choice persists with the model.

### 1.23 Resource File Import/Export (Chapter 13)
- Export ASCII model + associated resources (views, numerics, model notes) for round-trip text-editing.
- Numerics map at top of file maps original numeric names to UNIX substitution-format names.
- Trigger via "Include Resource Map" option in ASCII Export menu.
- Plug-in prompts to save `.MED` if not yet saved (resource info pulled from the saved `.MED`).
- Re-import via normal RELAP import. Plug-in detects resource model + opens **Resource Model Import** dialog (locate `.MED`) then **Resource Options** dialog (pick which resources to include).
- Import creates a new model retaining text-editor changes + selected resources.

---

## 2. COMPONENT EDITOR PATTERNS

This section catalogs the parameter set, organization, validation, and defaults for each editable component.

### 2.1 Pipe (canonical, reused by ~17 component types)
**Top-level Property View fields** (Figure 3.10): name, description, comments, hydraulic system membership, plus access buttons to sub-editors (Geometry, Initial Conditions, Friction Data).

**Geometry sub-editor** — graphical pipe + tabs:

| Tab | Fields | Validation |
|---|---|---|
| Cells | volume, length, area; per-cell calculation type via "By-Cell" + Calculate column; Y/Z crossflow length+area checkboxes. | Greyed if not currently editable; auto-recalculation enforced by chosen calc type. |
| Orientation | per-cell vertical/horizontal/angle; resulting elevation displayed read-only. | Elevations combo selects angle vs DZ mode. |
| DZ | direct elevation change per cell. | Only enabled in DZ mode. |
| Junctions | hydraulic diameter, flow area, CCFL model, choking model, area change option, momentum flux option, energy-equation modified PV term, single-velocity vs two-velocity momentum equations. | Cell+junction count immutable post-creation (use renodalization). |

**Initial Conditions sub-editor** — tabs:
- Cell Fluid: Condition (t-flag) per cell; Fluid (e-flag) read-only (set by hydraulic system). Pop-up help inside Condition editor describes each t-flag.
- Junction Flow: per-phase velocity or mass flow per junction.
- Noncondensibles: per-noncondensible mass fraction overrides.

**Friction Data sub-editor** — tabs:
- Cell Options: thermal front tracking, mixture level tracking, vertical stratification model (descriptions in column tooltips).
- Wall Friction: hydraulic diameter, wall roughness, shape, viscosity per axis (Axis Specification combo selects x/y/z; y/z gated on cell crossflow checkboxes).
- Junction Friction: forward + reverse loss coefficients, Reynolds-dependent loss coefficients.

**Defaults** — newly created pipe distributes cell volumes evenly along total length. Last completion-dialog values remembered if completion is disabled.

### 2.2 Time Dependent Volume
- Pipe-style geometry editor.
- Custom IC dialog: **T Flag Input** combo controls visible columns; **B Flag** checkbox adds Boron Concentration column; **N Flag** enabled only when T Flag and Model Options noncondensibles align. Add/Remove rows for arbitrary search variable sets.

### 2.3 Time Dependent Junction
- **Control Word** — Flow Velocities (default) vs Mass Flows; switches search variable association.
- TDJ Flow Rate Editor — Add/Remove + OK to commit.

### 2.4 Single Flexible Wall / Multiple Flexible Wall
- Adds flexible wall area + a table of volume displacement vs wall stiffness.
- Multi-Flex uses the Multi-Junction connection editor.

### 2.5 Branch
- External Junctions editor (table of stored junctions): From Face (inlet/outlet/cross-flow 3-6), Target component, Cell (target), Reverse (flag).

### 2.6 Pressurizer
- Surge line Junction property: dropdown limited to connections on inlet volume / inlet cross-flow faces.

### 2.7 Separator
- Separator Model: Simple / GE dryer / GE 2-stage / GE 3-stage. Stage 2/3 enables Number of Components.

### 2.8 Jet Mixer / ECC Mixer
- Junction count fixed at 3; labels enforced (drive/suction/discharge or ECC inlet/normal inlet/discharge outlet). ECC Mixer adds **ECC Jun. Angle**.
- Strict TO/FROM connection rules; input-error message printed if violated.

### 2.9 Turbine / Compressor
- Completion dialog for **Number of Junctions** (1 or 2).
- Shaft selection editor + Discon. Trip controller selector.
- Turbine Property View also has Shaft Velocity, Shaft Inertia, Shaft Friction.

### 2.10 Valve
- Properties depend on **Valve Type** (form factor changes editor).

### 2.11 Pump
- Standard pipe-style sub-editors. (Manual states "general properties" but defers to pipe for specifics.)

### 2.12 Multiple Junction
- Connection Editor: Add/Remove/Edit; From/To components; From/To Cell drop-downs (auto-update on component selection).
- **Set / Zipper utility**: two component selectors; Starting Cell, Ending Cell spinners (constrained); Increment; Inlet Face. Auto-creates batches of connections.

### 2.13 Multi-Dimensional (MULTID)
- Completion dialog branches on geometry: Partial Cylinder, Full Cylinder (azimuth=360°), Cartesian.
- Geometry editor: 3D view (rotate/translate/zoom); Display Actual Positions checkbox; Select Axis combo (Axial / Radial / Azimuthal selection modes).
- Connections tab: external components summary + detailed Local Side / Remote Side rows.
- 2D editing: Top Down View + axial Side View; cell selection in either pane mirrors in the table; junctions selected via the dotted line in Side View; drop-down combos at top of editor select which property is being edited; junction faces selectable.
- Connection workflow: standard 2D drop-zone connection → completion dialog determines exact target.

### 2.14 Heat Structure
- Completion dialog: geometry (flat slab / cylindrical / spherical), axial+radial nodalization.
- Axial Cells/BCs editor: top table of axial cells; property view below shows union of attributes for selected rows; `< Different Values >` for non-shared values across multi-select.
- Left/Right Surface BC: Boundary Type drop-down (with "symmetric" disabling hydraulic connections); per-surface Additional Boundary Data Format combo; per-surface activation checkbox.
- Heat Connections dialog: Hydraulic Component + Starting Cell + Ending Cell to connect ranges.
- Axial Power/Heating dialog: power factor + heating multipliers per cell; Table Variable reference replaces table.
- Radial Geometry editor: mesh thicknesses OR end-mesh radial position; optional Node Location property to inherit another HS's radial geometry; Split / Merge buttons.

### 2.15 Radiation Enclosure
- Heat structure grouping list: Add/Remove. Selecting a row reveals its property view.
- View Factors editor: tooltips describe surface per column.

### 2.16 Materials
- Material Type drop-down: pre-defined types or "Table/Function" for user-defined tabular/functional.

### 2.17 Reactor Kinetics — Point
- Table Data Editor: Add/Remove/Copy/Paste/Sort.
- Volumes/Heat Weighting Factors editor: top table of feedback components; bottom table of weighting factors+temperature coefficients per node. Table Variable reference replaces entire bottom table.
- Detector Editor: top table of detectors; bottom table of source terms+weighting+attenuation per detector.

### 2.18 Reactor Kinetics — Nodal
- Mesh Length editor: X/Y/Z radio buttons; documented axis conventions (Z bottom-up, X looking-down left-to-right, Y looking-down top-to-bottom).
- Composition/Zone Figure editor + figure assignment dialog (Add/Remove).
- Planar Top-Down editor (Cartesian or Hexagonal): single click + click-drag region selection; per-region or per-node editor.
- Initial Power Fraction editor: optional per-axial-level (Initialize Values checkbox); Axial Mesh Interval combo.
- Region Feedback editor: zone-keyed; Volume/Heatstructure feedback toggle; component selectors with min/max constraints.
- Composition Cross Section editor: list + property view; XS Data sub-editor varies by cross-section type; type tooltips for scattering pattern.

---

## 3. MODEL BUILDING WORKFLOW

### 3.1 Sequence
1. **Start the model** — File → New → choose RELAP plug-in (or File → Import → RELAP5 ASCII; or File → Open `.MED`).
2. **Configure Model Options** — pick Code variant + version, Input Units (SI/British), enable Developmental Options, set up HD Systems, Timestep Data, Noncondensible Gas Species.
3. **Add hydraulic components** — Navigator right-click → New (or 2D view insert tool); fill in completion dialogs (cell counts immutable post-creation for pipes — plan accordingly).
4. **Connect components** — 2D view connection tool (drag from one connection point to a drop zone), or edit via Property View / dedicated connection editors (Branch External Junctions; Multi-Junction Connection Editor; Heat Connections dialog).
5. **Add heat structures** — Navigator → Heatstructure → New → completion dialog; connect via Axial Cells/BCs editor.
6. **Add materials** — Navigator → Materials → New → choose Material Type.
7. **Add control systems** — Signal Variables (creation dialog), Control Blocks (connect via 2D view), Trips (Variable / Logical), Interactive Variables, General Tables.
8. **Add reactor kinetics** — Reactor Kinetics navigator node → Enable=True → completion dialog; fill kinetics-specific editors.
9. **(Optional)** Add radiation enclosures, advanced components (Multi-Dim, Accumulator, Pressurizer, etc.).
10. **(Optional)** Generate 3D Coordinates → arrange via 3D viewer pivots/shifts.
11. **Validate** — Check Model button or auto-checks at export/submit.
12. **Export** — File → Export → Input Deck (or via right-click model → Export sub-menu) or Restart Deck (via Restart Cases).
13. **(Optional)** Build a Model Notebook + manage initial-conditions sets.

### 3.2 Canvas / workspace
- **Navigator** (tree on the side) — hierarchical model browser with categories: Model Options, Hydraulic Components, Control Systems (Signal Variables, Control Blocks, Trips, General Tables, Interactive Variables), Heatstructures, Radiation Enclosures, Materials, Reactor Kinetics, Cases.
- **2D View(s)** — drawn representation; multiple views per model. Canvas where components are inserted, connected, and visually arranged.
- **3D View** — separate 3D viewer (Pre-processor plug-in); rotate/translate/zoom + pivot/shift transforms.
- **Property View** — context-dependent panel showing properties of the selected component.
- **ASCII View** — live ASCII representation of selected component or model.
- **Message Window** — emits validation, renodalization announcements, IC import errors, etc.

### 3.3 Connections
- Drag-connect in 2D view: select connection point → select drop zone on target.
- Branch / Multi-Junction / Heatstructure use dedicated dialogs.
- Multi-Dim drop-zone connection ends with a completion dialog choosing exact target.

---

## 4. DATA IMPORT/EXPORT

### 4.1 File formats
- `.MED` — SNAP native model save (binary; preserves component, view, numeric info).
- **ASCII input deck** — RELAP5-compliant text deck (the canonical RELAP input format).
- **ASCII restart deck** — subset of input deck with resupplied modified components.
- **Resource-augmented ASCII** — ASCII deck + resource map header (numerics renamed in UNIX-substitution format) + companion `.MED` file lookup.
- **Model Notebook** — ODF (`.odt`) or DOCX export.
- **Test Suite Analyzer (TSA)** — METRICS_SPEC + METRICS files.

### 4.2 ASCII deck structure (as documented)
- Comment lines ignored except special prefixes:
  - `*d:` — component description
  - `*c:` — component comment
  - `*m:` — meta data (e.g. `*m: CODE:RELAP5 3D Version 2.4`)
- Cards numbered using RELAP5 conventions (e.g. `3200000`, `3200001`, `CCC1101`, `CCC1201`, `20600010-20620000`, `401-799`, etc.).
- Components are blocks of cards keyed by component number CCC.
- Junction cards inside components follow strict ordering for Jet Mixer / Turbine / Compressor.
- Trip numbering: original (401-799) vs expanded (20600010-20620000).
- Unix substitution variables: `$VAR1` style; integer-supported only for specific fields (see 1.2).
- "After Case Data" — anything after the first RELAP case is preserved verbatim.
- "Extra Deck Data" — unrecognized cards captured as a Model Options property.

### 4.3 Import workflow
- File → Import → RELAP5 ASCII → file selector → code+version selector + LITERAL substitution-variable option.
- Version-mismatch dialog if `*m:` disagrees with selection.
- Resource model auto-detected → Resource Model Import dialog → Resource Options dialog.
- Restart deck import: right-click Case → Import Case (treats incoming file as a restart layered onto current case).
- Initial Conditions import is separate (Chapter 11): right-click model → Retrieve Initial Conditions.

### 4.4 Export workflow
- File → Export → RELAP5 input deck (via model right-click → Export sub-menu).
- Export Restart Deck — produced from a Restart Case.
- Export Resource-augmented ASCII — "Include Resource Map" option in ASCII Export menu (requires saved `.MED`).
- Export Model Notebook — File → Export → Model Notebook → dialog (General/Sub-Systems/Tables tabs).
- Batch commands: `RELAP IMPORT`, `RELAP EXPORT`, `RELAP EXPORT CASE`, `RELAP EXPORT METRICS_SPEC`, `RELAP EXPORT METRICS`, `RELAP EXPORT NOTEBOOK_ODT`, `RELAP EXPORT NOTEBOOK_DOCX`, `RELAP CREATE_VIEW`.

---

## 5. VISUALIZATION FEATURES

### 5.1 2D Views
- Multiple 2D views per model. Components added via right-click "Add to View" or via Insert tool.
- Bidirectional selection sync with table editors (e.g. Pipe Geometry tab table ↔ pipe diagram).
- Connection tool for drag-to-connect interactions. Disconnect/reconnect supported.
- Used as the source for sub-system header images in Model Notebook.

### 5.2 3D View (Pre-processor plug-in)
- Camera: orbit (LMB), pan (RMB), zoom (MMB) + dedicated camera buttons + reset.
- Selection: Selection mode (CTRL+click toggle) or Lasso Select (rectangle, full containment). Selected = yellow.
- Transforms: Pivot (junction + flow direction → ±180° about Z) and Shift (X/Y sliders) — both with live preview + Apply / Finish.
- Toggles: Show Arrows (junctions/connections as arrows), Use Wireframe, Show Axis Lines, Center on Highlighted, Rotation Point (origin/center).
- Optimization: Shading Type, Lighting Attenuation coefficients, Cell Scale slider (0–100%).
- 3D coordinate generation: breadth-first walk; bends inserted only for tee side-pipes, vessel and parallel-plenum connections.

### 5.3 Component-specific 3D
- Multi-Dim component has its own 3D geometry editor (rotate/translate/zoom), separate from the main 3D viewer. Includes:
  - Cell highlight on table selection
  - Cell thickness vs Actual Positions display toggle
  - Axial / Radial / Azimuthal selection modes

### 5.4 Plotting
- Tabular editor right-click → Plot — pick one independent + one or more dependents → uses APTPlot plug-in.
- Interactive Variables, signal variables, etc. are plottable.

### 5.5 Live ASCII view
- Show ASCII (right-click on component or model) — opens a live-updating ASCII representation that mirrors edits.

---

## 6. ADVANCED FEATURES

### 6.1 Renodalization
See 1.18. Tools to change cell counts while preserving geometry, hydraulic connections, signal variables, heat structure interpolation, and reactor kinetics feedback. Works for 1D hydraulic, heat structure (radial+axial), and Pipe Split. Undo/redo safe at every step. Internal dialog has its own undo stack with forward/back buttons; commits only on OK.

### 6.2 Batch Commands
See 1.20. Scriptable interface for import, export, restart cases, metrics, model notebooks, and view creation. Supports model labels M0-M9 for managing multiple models in a batch.

### 6.3 Importing Initial Conditions
See 1.21. Pull ICs from a finished job's restart at a specific restart number; selectively apply per category and per component. Optionally import heat-structure internal mesh temperatures from the closest Major Edit. Stored sets can be named, persisted with the model, and loaded later without the original run.

### 6.4 Model Notebooks
See 1.22. Annotated, model-wide ODF/DOCX report generator with title page selection, front matter, classification headers, page styles, sub-system organization, table inclusion control, optional ASCII listings, owner/reviewer listings, control-system sub-sectioning, component images, and Mathcad/Dollar variable formatting.

### 6.5 Resource File Import/Export
See 1.23. Round-trip ASCII editing while keeping non-ASCII resources (views, numerics, model notes). Numerics map renames model numerics to UNIX-substitution names + records the mapping at the top of the deck.

### 6.6 Validation Tests
See 1.16. Auto-run on export / submission / Check Model. RELAP5-specific loop test + standard component-attribute validations. Errors emit to Message Window and model report.

### 6.7 Attribute Level Ownership
See 1.19. Per-attribute owner/reviewer/timestamps. Activated per model (off by default; new/imported models have none). Review window with toolbar + glob/wildcard search across name fields and date ranges for time fields.

### 6.8 Restart Cases
See 1.14. First-class case objects in the Cases navigator node, supporting graphical or ASCII editing modes. "Virtual Model" mode shows modifications in red; Save/Close commit or discard. Some properties locked from edit during restart.

### 6.9 User-Defined Numerics
- Available via right-click → User Values → choose from list. Supported in nearly all real-valued attributes and a specific list of integer fields. Can be Mathcad functions (with Mathcad Output Format option in Model Notebook). Can be exported as Unix substitution variables.

### 6.10 Table Variables
- Replace table contents (e.g. General Table, Axial Power/Heating, Volume Weighting Factors) with a Table Variable reference + column mapping. Mapping validation enforces row order + column types. Exported in place of the original table data.

---

## 7. UX PATTERNS WORTH NOTING

### 7.1 Navigation patterns
- **Navigator tree** — single hierarchical browser of every model construct.
- **Right-click pop-up menus** are the workhorse for: New, Show ASCII, Add to View, Reference Docs, Copy/Cut/Paste, Renodalize, Generate 3D Coordinates, View Model in 3D, Retrieve Initial Conditions, Import/Export Case, etc. Almost every operation lives in one of these pop-ups.

### 7.2 Editor design idioms
- **Property View** is the universal inline editor surface. Edits commit live + push undo.
- **Custom dialogs** for complex multi-tab editing (Pipe Geometry, IC, Friction, Heat Structure axial cells, Multi-Dim geometry, Renodalization, Signal Variable Creation/Type).
- **OK-commit dialogs** for tabular editors that must validate before any change reaches the ASCII / undo stack.
- **Forward/Back undo within dialogs** — Renodalization has its own undo separate from the outer model undo.
- **Greyed (read-only) cells** convey computed-elsewhere or context-disabled state.
- **Tooltip-driven documentation** — column header tooltips routinely supply the only human-readable description of a parameter.
- **Multi-select table editors** show union of attributes; non-shared values display as `< Different Values >` and become read-only.
- **Inline validation by foreground color** — General Table marks errors (out-of-order or duplicate independent values) in red; foreground color is the diagnostic UI.
- **Live preview for transforms** — Pivot/Shift in 3D viewer preview as sliders move; commit only on Apply/Finish/OK.
- **Selection sync** — picks in tables, graphical pipe diagrams, 3D viewer, planar editors all stay in sync bidirectionally.
- **Component selection editor** — invoked via "S" button on signal-variable-style fields; modal dialog listing applicable components.
- **Range editors** — many editors support batch creation by start+end ("Signal Variables to be Created" range, Heat Connections range, Multi-Junction zipper).
- **Filter widgets with history** — Signal Variable Creation/Type filters remember last 5 filters and offer "Include Description" for broadened matching; categories show match counts.
- **Completion dialogs at component creation** — many components launch a one-shot configuration dialog at creation (Pipe, Heatstructure, Turbine, Compressor, Multi-Dim, Reactor Kinetics enable). Last-entered values remembered if completion dialogs disabled.
- **Reference-driven content replacement** — General Tables, Axial Power/Heating, and Point Kinetics weighting factors all support replacement by Table Variable references.
- **Color coding for state** — modified components in restart-edit Virtual Model are red; selected 3D components are yellow.

### 7.3 Workflow integration
- **Live ASCII** — Show ASCII gives a synchronized view; many users use this as a sanity check while editing graphically.
- **Undo stack** — generic editors push entries automatically; OK-style dialogs push only on commit.
- **Reference Docs** — every hydraulic component links to its RELAP input manual section (PDF). Built-in just-in-time documentation.
- **Message Window** — central console for non-modal feedback (validation, renodalization announcements, IC import errors).
- **Copy/Paste interop with spreadsheets** — tabular editors are spreadsheet-clipboard-compatible.

### 7.4 Keyboard / mouse
- 3D viewer: LMB rotate, RMB translate, MMB zoom; CTRL+click toggles selection; lasso-select rectangle.
- Planar Hex/Cartesian editors: left-click single, click-drag for contiguous region.
- Specific keyboard shortcuts (beyond CTRL+click) are not enumerated in this manual.

---

## 8. APPLICABILITY TO STREAM.jl

For each major feature, classification: **APPLY** / **ADAPT** / **SKIP** / **GREY**.

### 8.1 Model creation
| Feature | Verdict | Notes |
|---|---|---|
| File → New → pick plug-in | ADAPT | STREAM has only one "plug-in" — the dialog reduces to a project template picker (loop / cube / custom). |
| File → Import ASCII | SKIP | RELAP-specific deck format. STREAM has no equivalent text input language. (Could ADAPT for `build_loop`-style code-stub import — see Section 9.) |
| File → Open `.MED` | APPLY | Need a project save format that preserves canvas, components, parameter values, user-defined numerics. JSON or HDF5 likely. Forward-compat-only policy is reasonable. |
| Three creation entry points | APPLY | Mirror in STREAM: New from template, Open existing, Import (if implemented). |
| Description + Comments per component (`*d:`/`*c:` round-trip) | APPLY | STREAM should record free-text component descriptions/comments in its save format. Round-trip survives even with code-export workflows. |

### 8.2 Editing primitives
| Feature | Verdict | Notes |
|---|---|---|
| Property View with live edits + auto-undo | APPLY | Core editor pattern. STREAM should mirror — Property View synced with canvas/equation-based view. |
| Generic logical (TRUE/FALSE) editor | ADAPT | STREAM components have far fewer Boolean toggles than RELAP; small handful (e.g. fixed-dP vs fixed-mdot pump mode). Reuse generic Bool editor. |
| Tabular editor with Copy/Paste/Plot pop-up | APPLY | STREAM has tabular use cases: pipe-cell discretization (HeatDiffusion), IC tables, transient boundary tables, time-series boundary conditions. Copy/Paste-with-spreadsheets and embedded plotting are high-value. |
| OK-commit dialogs for complex edits | ADAPT | Use for multi-step component construction (e.g. PipeGeometry constructor) where partial states would confuse downstream symbolic compilation. |
| Live ASCII view | ADAPT | STREAM equivalent: live Julia-code view (auto-generated MTK construction code) for the selected component or whole model. **Very high value** — see Section 9. |
| Reference Docs pop-up | APPLY | STREAM components have docstrings; surface them in a "Help" pop-up. |
| Copy / Cut / Paste components across models | APPLY | Multi-document scenario likely (compare loops, build a library). |

### 8.3 Hydraulic components catalog (RELAP-specific list)
| Feature | Verdict | Notes |
|---|---|---|
| 22 hydraulic component types | ADAPT | STREAM's catalog is much smaller and physics-different (Pump, Channel, ChannelAndContacts, ChannelHeatFlux, HeatExchanger, Resistor, Friction, Gravity, Inertia, HeatDiffusion). The *pattern* of having a Navigator category with one node per component type APPLIES; the *contents* don't. |
| Pipe-style multi-cell completion dialog | ADAPT | STREAM channels have axial discretization (e.g. via `_channel_base_eqs`), so a completion dialog asking for L, Dh, N_cells, etc. is direct. |
| Cell+junction count immutable post-creation | ADAPT | STREAM should likely allow re-discretization (its MTK system can be rebuilt). May be more permissive than SNAP. |
| Pipe Geometry Cells/Orientation/DZ/Junctions tabs | ADAPT | STREAM PipeGeometry struct already has rectangular vs circular factories; add a UI: Cells (length/area/Dh), Orientation (vertical/horizontal/angle/elevation), Junctions (loss coefficients, friction). DZ tab maps directly to Gravity component or per-cell elevation. |
| Pipe Initial Conditions (cell + junction tabs) | ADAPT | STREAM transient solver needs initial conditions (mdot, T, p). Cell-fluid table maps to per-cell initial T/P; junction-flow table maps to mdot guess. |
| Pipe Friction Data (Cell Options + Wall Friction + Junction Friction) | ADAPT | STREAM has correlation closures (HTC + friction). UI surfaces: choice of correlation, wall roughness, hydraulic diameter, loss coefficients. RELAP's per-axis y/z stuff is multi-D-only — SKIP for now. |
| Branch external junctions, Pressurizer surge line, Jet Mixer / ECC Mixer / Turbine ordered junctions | SKIP | RELAP-specific component constraints. |
| Multi-Dimensional component | SKIP | STREAM is currently 1D-axial; HeatDiffusion is 2D solid plate but not a hydraulic 3D volume. If multi-D fluid is added later, revisit. |
| Accumulator | SKIP | Not in STREAM domain currently. |

### 8.4 Control systems
| Feature | Verdict | Notes |
|---|---|---|
| Signal Variables (General/Component/Volumetric/Junction/Heat/Power) | ADAPT | STREAM equivalent: probes / observables. Signal Variable Creation Dialog pattern (category list + type table + creation criteria + preview) APPLIES strongly for designing a "Probe" creation UI. Range creation also useful (probe every cell in a channel). |
| Signal Variable filter with history + match counts | APPLY | Excellent UX pattern for component-pickers in general. |
| Control Blocks (manipulate signals, output float) | ADAPT | STREAM doesn't currently have a built-in control block library, but MTK supports composing equations. A future "Block" category for derived/computed quantities could mirror this. |
| Trips (Variable + Logical) | ADAPT | STREAM transient runs may benefit from event-trigger components (e.g. switching valve state on pressure threshold). DiffEq.jl has a callback system; a UI could expose this. |
| General Tables (independent/dependent table data) | APPLY | STREAM time-dependent boundary conditions, T(t) BCs, mdot(t) sources — all want a General-Table-style editor with red-foreground validation. Sort + Add/Remove + Plot. |
| Interactive Variables | ADAPT | STREAM transient simulations could benefit from "live" inputs while a sim runs (operator-style). Implementation requires a runtime channel into the running ODE — non-trivial but achievable with Julia. GREY with a lean toward ADAPT. |
| Trip numbering formats (original vs expanded) | SKIP | RELAP card-numbering artifact. |

### 8.5 Heat Structures
| Feature | Verdict | Notes |
|---|---|---|
| Flat slab / cylindrical / spherical geometry | ADAPT | STREAM has HeatDiffusion (2D FD plate). UI could expose geometry choice if more types are added; for now a single editor for the existing implementation. |
| Axial Cells/BCs editor with multi-select union view + `< Different Values >` | APPLY | Strong pattern for editing per-cell properties consistently. |
| Left/Right Surface BC with hydraulic-component connection | APPLY | Maps directly to STREAM's ThermalPort connections. UI needs: per-axial-cell ThermalPort connection editor with range fill. |
| Heat Connections range dialog | APPLY | Mirror as a "connect every axial face to channel cells N..M" tool. |
| Axial Power/Heating dialog | APPLY | STREAM ChannelHeatFlux + HeatDiffusion need per-cell power factors; this maps directly. Table Variable reference for time-varying power. |
| Radial Geometry editor | ADAPT | HeatDiffusion has 2D mesh; UI could expose mesh thicknesses with Split/Merge. |
| Heat structure has no 2D drawn glyph (dialog-only connections) | SKIP | STREAM should give heat structures a graphical representation — better UX. |

### 8.6 Radiation Enclosure / Materials
| Feature | Verdict | Notes |
|---|---|---|
| Radiation Enclosure with View Factors editor | SKIP | STREAM does not currently model radiation. (Revisit if added.) |
| Materials with pre-defined types + Table/Function user-defined | APPLY | STREAM has water property functions (rho, cp, mu, k); future "Materials" category could expose pre-defined fluids and user-defined Table/Function fluids. Provides a clean extensibility path for `src/fluids/`. |

### 8.7 Reactor Kinetics
| Feature | Verdict | Notes |
|---|---|---|
| Point Kinetics editors (table editor, V/H weighting, detector) | ADAPT | STREAM does not currently have point kinetics. CLAUDE.md mentions `point_kinetics.jl` as a possible new component file. If implemented, the Volume/Heat Weighting Factor editor pattern + Table Variable replacement is directly reusable. |
| Nodal Kinetics (Cartesian/Hexagonal mesh, planar editors, cross sections, region feedback) | SKIP | Out of scope for STREAM. |

### 8.8 Restart Cases
| Feature | Verdict | Notes |
|---|---|---|
| Cases as first-class navigator objects | ADAPT | STREAM has `solve_steady` + `solve_transient`. A "Cases" concept = parametric variations / restart-from-snapshot. Useful for batch-of-runs UX. |
| Graphical Virtual Model edit with red-coloring of modified components | APPLY | Excellent diff-visualization pattern. |
| Some properties locked during restart edit | ADAPT | Translate to "structural changes prohibited after solve snapshot" if STREAM adopts snapshot-restart. |

### 8.9 ASCII I/O
| Feature | Verdict | Notes |
|---|---|---|
| Input deck import/export | SKIP | RELAP-specific. STREAM analog = Julia-code import/export — see Section 9. |
| Resource Map round-trip | ADAPT | STREAM equivalent: emit a Julia source file with auto-generated parameter names (substitution-variable analog) and re-import the user-edited file while preserving canvas/views/numerics from a sidecar save. **High value** for users who prefer to tweak in code. |

### 8.10 Validation
| Feature | Verdict | Notes |
|---|---|---|
| Check Model button + auto-checks at export/submit | APPLY | STREAM should validate before solving: undefined parameters, inconsistent units, dangling FlowPort/ThermalPort connections, geometry sanity, etc. |
| Loop test | ADAPT | STREAM's mass-conservation / pressure-loop closure check on hydraulic loops. |
| Foreground-color in-place validation | APPLY | Use red foreground in tabular editors for invalid rows. |
| Message Window | APPLY | Central feedback console. |

### 8.11 3D Visualization
| Feature | Verdict | Notes |
|---|---|---|
| 3D coordinate generation from elevation data | GREY | STREAM models are typically a small graph of components — 3D may be overkill v0; but a 2D "auto-layout" using BFS from a chosen anchor is directly applicable. |
| 3D Model Viewer with camera + selection + Pivot/Shift transforms | GREY | Useful only if STREAM grows into multi-loop spatial models. For early GUI, prefer 2D-only. |
| Show Arrows / Wireframe / Axis Lines / Cell Scale | GREY | Same — depends on whether 3D is in scope. |
| Live preview during slider transforms | APPLY | Pattern transcends 3D — applies to any parametric drag (e.g. resizing a channel, scrubbing time on a transient plot). |

### 8.12 Renodalization
| Feature | Verdict | Notes |
|---|---|---|
| 1D split / split-uniform / merge with previewed Original/Current/Difference DZ | APPLY | STREAM channels have N_cells; users will want to refine/coarsen post-hoc. Renodalization dialog with internal forward/back undo is an excellent pattern. |
| Conical-section detection for split-cell flow areas | ADAPT | STREAM's PipeGeometry could expose a similar interpolation policy; conical detection is a useful default. |
| Heat structure radial+axial renodalization (auto-coalescing on equal BCs) | APPLY | HeatDiffusion mesh refinement UI follows the same pattern. |
| Pipe Split | ADAPT | STREAM channel split — useful for inserting a tee or component mid-channel. |
| Auto-update of signal variables / hydraulic connections post-renodalization | APPLY | STREAM probe references must update on re-discretization; nearest-axial-position policy applies. |
| Announce Changes | APPLY | Emit a Message Window log of what changed. |

### 8.13 Attribute Level Ownership
| Feature | Verdict | Notes |
|---|---|---|
| Per-attribute owner/reviewer/timestamps | GREY | Useful for regulated nuclear analyses with QA processes. STREAM is open-source / academic; not a v0 priority. Possibly later for institutional users. |
| Review Properties window with glob search | GREY | Same — depends on user base. |

### 8.14 Batch Commands
| Feature | Verdict | Notes |
|---|---|---|
| Scriptable IMPORT/EXPORT/CASE/METRICS/NOTEBOOK/CREATE_VIEW | ADAPT | STREAM is already a Julia library — its "batch interface" is just Julia scripting. The GUI should expose a way to dump/replay Julia code for any sequence of GUI operations (record-and-replay). |

### 8.15 Importing Initial Conditions
| Feature | Verdict | Notes |
|---|---|---|
| Retrieve Initial Conditions from a previous run, with category-level + component-level selection | APPLY | STREAM transient runs benefit massively from steady-state warm-starts. The category+component selection dialog pattern is directly reusable. `steady_state_guess` already exists — UI for "load ICs from solve_steady result" is a clear win. |
| Cycle through restart numbers + restart times | ADAPT | STREAM solutions have many time points; a slider/picker selecting time t=t* to seed transient ICs is the equivalent. |
| Heat structure internal mesh temperatures from Major Edit | ADAPT | HeatDiffusion needs temperature seeding; pull from previous solve. |
| Manage Initial Conditions (Store/Load/Remove named sets) | APPLY | Named IC snapshots persisting with the model — extremely useful for parameter sweeps and what-ifs. |

### 8.16 Model Notebooks
| Feature | Verdict | Notes |
|---|---|---|
| ODF/DOCX export with title page, front matter, headers, classification | ADAPT | STREAM analog = generate a Markdown / Quarto / Pluto notebook of the model. Markdown easier than DOCX in Julia; Pluto.jl is the natural target. |
| Sub-system organization with Nest flag and View image per section | APPLY | STREAM models will grow into sub-systems (primary loop, secondary loop, etc.); a notebook with sub-system sections + a 2D-view image per section is high value. |
| Tables tab to control which tables are inlined | APPLY | Necessary for any large-table situation. |
| Owner/Reviewer listings | SKIP | Tied to attribute ownership. |
| Mathcad output format | SKIP | Mathcad-specific. |
| Component image inclusion | APPLY | STREAM-equivalent: render canvas glyphs into the notebook. |

### 8.17 Resource File Import/Export
| Verdict | Notes |
|---|---|
| ADAPT | STREAM should support: export model to a Julia source file with a sidecar JSON of GUI-only data (positions, views, numerics, notes); re-import the edited Julia file while reattaching the sidecar. Numerics map → Julia constants/parameters. **One of the most valuable patterns in SNAP for STREAM**, given STREAM's code-first heritage. |

### 8.18 General UX patterns
| Feature | Verdict | Notes |
|---|---|---|
| Navigator tree as primary org structure | APPLY | Standard, expected. |
| Right-click pop-up menus everywhere | APPLY | Discoverability + scope-localized actions. |
| Pop-up menus include New / Show ASCII / Show Code / Add to View / Reference Docs / Copy/Cut/Paste / Renodalize | APPLY (with renaming) | Show ASCII → Show Julia Code; everything else maps directly. |
| Tooltip-driven docs on column headers | APPLY | High info density for low UI cost. |
| Multi-select with `< Different Values >` | APPLY | Standard for multi-row attribute editing. |
| Filter widgets with history | APPLY | Component pickers, signal-variable creators, etc. |
| Live preview for parametric sliders | APPLY | Universal good pattern. |
| Selection sync (canvas ↔ tables ↔ viewers) | APPLY | Critical UX for spatial models. |
| Color coding (red=modified, yellow=selected, red foreground=invalid) | APPLY | Cheap, effective state communication. |
| Range-creation utilities (zipper, batch connections, signal-variable ranges) | APPLY | STREAM's `plate`, `symmetric_plate`, `compose_systems` already have this composition philosophy — surfacing it in UI makes sense. |

---

## 9. THINGS MISSING FROM SNAP THAT STREAM.jl MIGHT NEED

These are GUI features driven by STREAM.jl's distinguishing characteristics — equation-based acausal modeling via ModelingToolkit.jl, Julia-language integration, MTK symbolic IR + `mtkcompile`, Sundials/OrdinaryDiffEq solvers — that SNAP either doesn't have or can't have because RELAP5 is causal and procedural.

### 9.1 Show Julia Code (live, bidirectional)
Analog of "Show ASCII" but for Julia code. Two views, both live:
- **Component Julia code** — auto-generated `@named ch = Channel(L=..., Dh=..., ...)` for the selected component.
- **Whole-model Julia code** — fully reconstructible script (imports, component constructions, `compose_systems`, `mtkcompile`, solver call). Re-runnable verbatim. This is the natural STREAM analog of the RELAP ASCII deck.
- *Bidirectional* edits: typing in the code view should round-trip back into the canvas (parser-driven). At minimum, it should be the export/import format (resource-map style).

### 9.2 Equation view
Surface the actual symbolic equations of the selected component (post-`mtkcompile` if helpful, or pre-compile for understanding). Shows:
- Pre-compile system: full DAE
- Post-compile system: index-reduced ODE
- Observed equations
- Variables / unknowns / observed split

SNAP has no analog; RELAP5 doesn't expose equations.

### 9.3 Connector visualization (FlowPort / ThermalPort)
SNAP's connections are scalar; STREAM's `FlowPort` carries (mdot, p) and `ThermalPort` carries (Q, T). The GUI should:
- Show each port's variable list when hovering / selecting
- Color-code FlowPort vs ThermalPort connections
- Detect type mismatches at connection time (cannot connect FlowPort to ThermalPort)
- Show acausal nature explicitly (no "from"/"to" — just a shared algebraic equation)

### 9.4 Solve dialog and monitoring
- **Solve mode picker**: solve_steady, steady_state_guess, solve_transient.
- **Solver selection**: Sundials IDA, Rodas5, FBDF, etc. with tooltips on suitability.
- **Solver options**: tolerances, dtmax, maxiters.
- **Run monitor**: progress bar (transients), convergence indicators (steady), abort button.
- SNAP has only a "submit to calculation server" pattern (RELAP5 is an external executable). STREAM solves in-process — UX can be tighter (live progress, partial results, abort).

### 9.5 Plot viewer integrated with solution
- Auto-discover plottable variables (every unknown, every observed) without an explicit "signal variable" creation step. STREAM doesn't need to declare probes upfront because MTK keeps everything.
- Time-series plot for transients; scalar-vs-parameter for steady sweeps.
- Spatial plot along channel cells.
- Side-by-side compare across stored solutions / cases.

### 9.6 Parametric study / sweep
- First-class "Sweep" object: pick parameters + ranges, run N solves, browse results.
- SNAP's restart cases approximate this for restarts; STREAM should make it explicit.

### 9.7 Symbolic-vs-numeric parameter distinction
- MTK supports symbolic parameters (`@parameters`). The GUI should let a user mark a parameter as symbolic (kept in the ODE problem and tunable post-compile without rebuilding) vs numeric (baked at compile time).
- No SNAP analog (RELAP5 is purely numeric).

### 9.8 Unit handling
- Julia + MTK has Unitful.jl integration. The GUI could expose explicit unit fields per parameter and validate dimensional consistency before `mtkcompile`.
- SNAP only has SI / British global toggles.

### 9.9 Compose / Plate / Helper-driven construction
- STREAM's composition helpers (`plate`, `symmetric_plate`, `one_sided_connection`, `compose_systems`, `port`) are first-class workflow tools. The GUI should expose these as "macro" operations — e.g. "Symmetric plate from these N channels with these contacts" → one click instead of N drag-connects.
- Closest SNAP analog is the Multi-Junction zipper utility — generalize that.

### 9.10 MTK compile diagnostics
- `mtkcompile` errors (DAE index too high, structural singularity, missing equations) need a dedicated diagnostic panel that highlights the offending component / equation in the canvas.
- SNAP's RELAP errors are surfaced as ASCII messages; STREAM can do better with structural insight.

### 9.11 Live REPL embedding (optional but high-leverage)
- Many Julia users prefer to drop into a REPL; the GUI could embed (or attach to) a Julia REPL where the loaded model is already in scope as `model`. SNAP has no equivalent because RELAP5 isn't interactive.

### 9.12 Revise.jl integration
- Per CLAUDE.md, STREAM dev workflow is built on Revise. The GUI should detect source-file changes to component types and offer to reconstruct affected components.

### 9.13 Case-based parameter sweep persistence
- SNAP has named stored Initial Conditions sets; STREAM should have named stored solutions (steady solutions, transient endpoints) usable as warm-starts and as plot baselines.

### 9.14 Notebook export targets specific to STREAM
- Pluto.jl notebook export (reactive + Julia-native) — natural fit; SNAP has nothing equivalent.
- Quarto / Markdown export for static reports.
- Each component section embeds (a) an MTK equation rendering, (b) the Julia construction code, (c) a parameter table, (d) a plot of the relevant solution variables.

### 9.15 No "deck" — graph is the source of truth
- SNAP's "deck = source of truth" with `.MED` as superset is a legacy of RELAP5. STREAM can flip this: the *Julia graph + parameter set* is the source of truth, and any sidecar (canvas positions, comments, views) is layered on top.
- Implication for save format: a `.stream` file = JSON/HDF5 with {component graph, parameters, canvas layout, comments, stored solutions, named IC sets, sweep definitions} — single source, directly loadable into Julia.

### 9.16 Component constructor argument introspection
- Julia introspection (`methods`, `Base.kwarg_decl`, docstrings) lets the GUI auto-generate property panels from the component's constructor signature. SNAP hard-codes these editors; STREAM can generate them.
- This is a very large UX win and reduces maintenance burden as new components are added (e.g. new physical_models/correlations).

### 9.17 Correlation-closure picker
- STREAM's `physical_models/correlations.jl` exposes HTC + friction correlations. GUI should let the user pick a correlation per component (with previewable `Re`/`Nu`/`htc` curves). SNAP has fixed RELAP5 closures; STREAM is more flexible.

### 9.18 Multi-physics coupling indicators
- Visual cue showing which components are thermally coupled (via ThermalPort) vs hydraulically coupled (via FlowPort). SNAP only has hydraulic + heat-structure-surface bridges; STREAM has fluid–solid coupling baked into the connector layer and should make it visually obvious.

### 9.19 Symbolic parameter linking
- Two parameters that should always equal each other (e.g. inlet temperature of channel A = boundary T of HeatExchanger B) can be linked via MTK constraint equations. GUI should support a "Link" gesture between two property fields.

### 9.20 Ahead-of-time compile cache visibility
- `mtkcompile` is slow on first call. The GUI should show the compile-cache status of the current model and let users pre-warm or invalidate.

---

## Notes / Ambiguities

- The manual frequently references figures (e.g. "Figure 3.10. Pipe General Properties") without reproducing the figure content beyond the surrounding paragraph. The exact full set of "general properties" of, e.g., a Pipe is not enumerated in the text — only the structural editors (Geometry / IC / Friction) are described in detail. Specific named fields visible in figures cannot be extracted from text alone.
- The exact list of pipe "general properties" (Property View top-level fields) is not enumerated in the text; same for Pump (manual just says "uses pipe editors" plus "general properties").
- "Reference Docs" — points to RELAP input manual sections, not described content.
- Specific keyboard shortcuts beyond CTRL+click (selection toggle) are not documented.
- The set of t-flag values, e-flag values, T Flag combo entries, and B Flag/N Flag specifics are documented as existing but not enumerated. Same for valve types, control block types, and the full signal-variable type catalog.
- No version-by-version changelog of editors is provided.
- Materials section says "set of pre-defined materials such as carbon steel, stainless steel, zircaloy, etc." — the full list is not given.
- The set of trip relationships (=, ≠, >, ≥, ≤, <) is given for variable trips and (AND, OR, XOR) for logical trips. No nesting / parenthesization documented.
- The Multi-Dim 2D editing dialog's drop-down property list is not enumerated.
- The Compressor's RELAP5-3D 2.4-only constraint comes from the manual; later versions are not discussed.
- The 3D viewer is part of "the SNAP Pre-processor plug-in for RELAP5" — separate from the ModelEditor proper. Whether the integration is in-process or via a launched window is not specified.
- Sub-System hierarchy depth is implicitly 2 (third-level folded into second). Whether sub-systems are user-defined groupings or come from another mechanism is not detailed in this manual.
- "Test Suite Analyzer (TSA)" is referenced for the METRICS_SPEC / METRICS exports but not described.
