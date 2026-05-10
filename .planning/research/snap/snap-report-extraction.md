# SNAP CAFEAN Main Report — Structured Extraction for STREAM.jl GUI Design

**Source:** NUREG/CR-6974, Vol. 1 — *Symbolic Nuclear Analysis Package (SNAP) Common Application Framework for Engineering Analysis (CAFEAN) Preprocessor Plug-in Application Programming Interface, Main Report* (June 2009). Authors: K. Jones, J. Rothe, W. Dunsford (Applied Programming Technology, Inc.).

This extraction is based on the *Main Report* only (Sections 1–4 plus front matter). Appendix A (the JavaDoc) is referenced throughout but is not part of the read source.

---

## 1. SNAP ARCHITECTURE OVERVIEW

### What is CAFEAN?
CAFEAN (Common Application Framework for Engineering Analysis) is the Java-based **application framework / API layer** that underlies SNAP. SNAP is the end-user product (a graphical user interface for creating, editing, and visualizing input for nuclear analytic codes); CAFEAN is the **reusable framework** on which SNAP is built and which third-party developers extend via plug-ins.

The relationship described in the Foreword and Section 1:
- **SNAP** = the application (the "ModelEditor" plus runtime and post-processor).
- **CAFEAN** = the standardized API used to build SNAP and to create modular plug-ins.
- The "Preprocessor" portion of SNAP (covered by this document) is one of three sub-applications: **Preprocessor**, **Runtime**, **Post-processor**. Plug-in JARs typically contain extensions for all three (e.g., the TRACE manifest declares `Plugin-Class`, `ClientPlugin-Class`, and `MEPluginData-Class`).

### Structural overview (per Section 1, "Introduction")
- SNAP runs on Windows XP/Vista, Linux, and Mac OS X (Java).
- The architecture is **plug-in based**. The SNAP/CAFEAN core provides:
  - The 2D and 3D visual editing canvas ("Multi-View" architecture).
  - A primary-foreign key relational mapping for component interconnections.
  - Multi-step undo/redo, component duplication, cut-&-paste between models.
  - A Python scripting interpreter exposed at the preprocessor level.
- Domain-specific behavior (e.g., RELAP5, TRACE, CONTAIN) lives in plug-ins.

### SNAP core ↔ plug-in relationship
The core (Section 2.1) provides abstract base classes; a plug-in **extends** them:

| Layer | Core abstract class | Plug-in extension example |
|---|---|---|
| Plug-in identity / loader | `MEPluginData` | `RelapPluginData`, `TracePluginData` |
| Plug-in entry point | `MEPlugin` | (analysis-specific subclass) |
| Code plug-in (introduces a code & its components) | `MECodePlugin` | `RelapPlugin` (Figure 1) |
| Feature plug-in (manipulates existing models) | `MEFeaturePlugin` | (e.g., a postprocess feature) |
| Model | `AbstractModel` | `ExampleModel`, TRACE model, RELAP5 model |
| Component | `AbstractComponent` / `AbstractBeanComponent` | TRACE Pipe, Tee, Vessel, etc. |
| Connection | `Connection` / `ConnectionBean` | `HydroConnection`, `ControlConnection`, `HeatConnection` (Figure 2) |
| Generic identifiable object | `GenericObject` | Cells inside thermal-hydraulic components |

### Layers / subsystems mentioned
- **MainFrame** — the application's central window. Holds the menu bar, the registered-dialog list, the message window, the undo manager, the current-model registry, and the plug-in registry.
- **ModelEditor** — the editing environment within MainFrame; hosts AbstractModels.
- **Navigator** — a tree view of model contents organized by Category.
- **DrawnView** (canvas) — 2D editor; contains a `ZoomablePanel` containing a `BeanBox` containing `DrawnComponent`s.
- **Property View** — JavaBeans-based property editing panel using Java Introspection.
- **Message Window** — error/warning/info channel.
- **Calculation Server** — remote (or local) job-running back end that executes the analysis code.
- **Python interpreter** — scripting subsystem exposed via a `MACRO` batch command and at runtime.

### Two plug-in kinds (Section 1, "What Kind of Plug-in")
- **Code plug-in** — introduces new components and supports a new analysis code.
- **Feature plug-in** — manipulates existing components/models without owning them.

---

## 2. PLUGIN / EXTENSIBILITY ARCHITECTURE

### Plug-in loading sequence (Section 2.1)
1. Plug-in JARs sit in SNAP's plug-in directory.
2. The JAR manifest must include `MEPluginData-Class:` pointing to the plug-in's `MEPluginData` extension class. (A JAR may also include `Plugin-Class:` for runtime, `ClientPlugin-Class:` for post-processor.)
3. The plug-in manager loads `MEPluginData` first to obtain static metadata: **plugin-id, plug-in class, version, plug-in prerequisites, class prerequisites**.
4. `MEPluginData.loadPlugin()` then loads the actual `MEPlugin` instance.

### `MEPluginData` static metadata (Section 2.1)
- **plugin-id** — short reference name.
- **plugin class** — fully qualified Java class name.
- **version** — string.
- **plug-in prerequisites** — `["pluginId:version", ...]` indicating dependencies on other plug-ins (version optional).
- **class prerequisites** — Java class packages required to be installed.

### `MEPlugin` lifecycle methods
- `init()` — initialization.
- `getPluginId()`, `getVersion()`, `getPluginPrereqs()`, `getPluginInfo()` — wrappers over `MEPluginData` accessors.
- `loadMainMenuItems()` — register menu items into the MainFrame menus.
- `loadViewMenuItems(view: DrawnView)` — register menu items / toolbars / mouse handlers per view.
- `loadSettings(config: Configurator)` / `saveSettings(config: Configurator)` — persist plug-in preferences (XML).
- `processCommand(cmdVect: Vector)` — receive batch commands prefixed with the plugin-id.
- `getPluginPreferences()` — return a JavaBean describing user-editable preferences (rendered automatically by the Preferences dialog).

### Code plug-in interface (`MECodePlugin`)
- `createNewModel(): AbstractModel` — invoked when the user creates a new model of this plugin's type.
- `Open(File): AbstractModel` — open an MED file authored by this plug-in.
- `getSamPackage(): String` — file-type package identifier (matched against the PIB header's File Type Identifier to dispatch open).
- `submitModel(model: AbstractModel)` — send the model to the Calculation Server.

### Feature plug-in interface (`MEFeaturePlugin`)
- `load(model, file: PibFile)` — read feature-specific PibBlocks from another plug-in's MED file.
- `save(model, file: PibFile)` — write feature-specific PibBlocks into another plug-in's MED file.
- `modelAdded(model)` / `modelRemoved(model)` — observe model lifecycle.
- `isAssociated(model): boolean` — declare whether this feature has data tied to a particular model.

### Menu / toolbar registration (Section 2.2.2)
- `MainFrame.addMenuItem(item: JMenuItem, name: String)` — `name` ∈ {File, Edit, View, Window, Tools, Help}.
- `MainFrame.addImportMenuItem(...)` and `addCurrentExportItems(...)` — separate import/export item handling. If multiple imports exist, prefer adding a single `JMenu` (named after plugin-id) containing all the import operations.
- `DrawnView.addMenuItem(...)` — appends to a per-view "Tools" menu.
- `DrawnView.addToolbar(...)` — recommended to be called from `loadViewMenuItems`.
- Standard toolbars always present (Section 2.14.1): **Main** (Select, Pan, Zoom, Connect, Insert), **Clipboard** (Cut/Copy/Paste/Paste Special/Find), **Annotation** (Ellipse, Image, Line, Polygon, Rectangle, Text), **Numerics** (User-Defined Variables/Constants).
- One toolbar is auto-generated per visual parent Category from the model's `getCategories()`.

### Batch command processing (Section 2.2.1)
- Commands are parsed by whitespace into a vector.
- If the first token equals a plugin-id, that token is stripped and the remainder is forwarded to `MEPlugin.processCommand(Vector)`.
- A built-in `MACRO` batch command runs Python scripts.

### Job submission (Section 2.2.3)
- `MECodePlugin.submitModel(model)` is the responsibility of the plug-in.
- `LocalSubmitDialog` is the documented helper.

### Preferences (Section 2.2.4)
- Each plug-in has its own `Configurator` "module" (keyed by plugin-id) — prevents key collisions across plug-ins.
- Settings file is XML, but typed convenience accessors exist (fonts, colors).
- Editable preferences are exposed as a JavaBean via `getPluginPreferences()`.

---

## 3. DATA MODEL

### Model = `AbstractModel`
A model is the central container (Section 2.4). Holdings:
- `connectionList: ComponentList`
- `views: ComponentList`
- One `ComponentList` per component category (or one shared list for small models).
- A reference to the `Navigator`.
- A `getModelOptions()` JavaBean (extends `AbstractBeanComponent`) for global properties (name, description, comments) — appears as the first sub-node under the model in the Navigator.
- "Root components" — singletons that appear directly in the Navigator (Section 2.4.5).
- Component number groups (Section 2.4.6) — define numeric ranges per Category for auto-numbering, validation, and renumbering.

### Component identity
Three keys per component (Section 2.2.5, "Essential Core Classes"):
- **ident** — primary unique identifier within the model (the foreign-key target).
- **cc number** (component number) — the user-facing number, often unique only within Category.
- **dbid** — secondary temporary key (transient).

### `AbstractComponent` and `AbstractBeanComponent`
- All visible/persistent objects extend `AbstractComponent`. Bean-based plug-ins must extend `AbstractBeanComponent` to access modern editors and undo.
- Required component methods: `label()`, `getCategory()`, `clone()`, `storeState(state)` / `restoreState(state)`.
- Optional: `complete()`, `isOkayForExport(prompt)`, `getCustomPopupItems()`, `getCustomPopupActions()`, `removeVerify()`, `getOrder()` / `setOrder()`, `toString()`.
- Listener interface: components fire `componentChanged`, `componentDeleted`, `componentConnected`, `componentDisconnected` to all `ComponentListener` subscribers (the Property View, the undo system, ASCII viewers, drawn components).

### `GenericObject`
Anything inside a model that isn't a Component but needs a global primary key. Stored in a single `ElementList` on `AbstractModel`. Used (for instance) for cells inside thermal-hydraulic components — keeps them addressable via primary-foreign key references rather than direct pointers (which is what enables renodalization without breaking references, per Section 2.2.5).

### Categories (Section 2.4.1)
- Hierarchical taxonomy: each `Category` may have one parent and many children. A Category that represents an actual component **cannot** have children (leaves only).
- Each Category contains: navigator icon, toolbox image URL, name, and a flag indicating whether it represents visual components.
- Categories drive: Navigator tree structure, toolbox button generation, foreign-key search scoping, component creation dispatch (`createComponent(category)`), iteration (`getComponentIterator(category)`).
- Special predefined Categories on `AbstractModel`: `CATVIEW` (views) and `CATCONNECTION` (connections); also `CATNUMERICS` for user-defined numerics.
- Comparison must use `isSubset`/`isSuperset`/`equals` — **never** reference equality.

### Connections (Sections 2.6, 2.9)
- A `Connection` extends `ConnectionBean` (which extends `AbstractComponent`) — connections are themselves components.
- A connection is essentially two ident foreign keys plus a `ConnectionData` per side describing what each end attaches to.
- Stored in `connectionList` on `AbstractModel`, and a list of foreign-key references is also kept in each connected `AbstractComponent` (its `ConnectionList`).
- Subclasses in TRACE example (Figure 2): `HydroConnection` (with `toFace`, `toAngle`, `fromEdge`, `fromFace`), `ControlConnection` (with `targetPoint`, `sourcePoint`), `HeatConnection`.
- `ConnectionData` (Section 2.2.5) is transient location data (e.g., for `HydroConnectionData`: cell index, face number on target, edge index, face number on source).
- `SpecialConnectionData` is used when a `ConnectingPt` represents multiple internal locations and the user must choose at connection time.
- Foreign-key NULL = ident value `0`. Non-zero ident does not guarantee the referenced component exists.

### Two-way reference resolution
- All component-to-component links are foreign keys; on load, `reconnectIdentReferences(...)` walks the model and resolves them.
- This indirection is what makes undo/redo, copy-paste between models, and renodalization tractable.

### Serialization: ModelEditor Document (MED) / PIB format (Section 2.7)
- Recommended format: **PIB (Platform-Independent Binary)** — XDR-encoded.
- File layout:
  - **Header:** three 80-character XDR-encoded strings: File Type Identifier (= the `PibFile` class name with package), Version Identifier, Description.
  - **Body:** sequence of named `PibBlock` records. Each PibBlock begins with a Data Block Header: 24-char Block Type Identifier, 4-byte Block Size (including header), Block Compression Flag (int), Block Version (int).
- Plug-in components implement `PibBlock` directly when possible; otherwise a `store()` method returns a configured `PibBlock` instance.
- File type dispatch: on open, the File Type Identifier is matched against each `MECodePlugin.getSamPackage()`; the first match owns the file.
- Core MED block types provided by CAFEAN: `UserConstantRec`, `UserVariableRec`, `UserFunctionRec`, `ViewCompRec`, `DrawnComponentRec`, `DrawnAnnotationRec`, `DrawnImageAnnotationRec`, `DrawnNumericRec`. These are loaded via `MEDReader.loadVisualComponents(drawingBlocks, viewBlocks, model)`.
- An auxiliary `writePackageHeader("com.example", "ExampleFile", LABEL)` separates the plug-in section from core blocks, allowing core blocks to be appended even on machines that don't have the plug-in (Section 2.7.5).

### Save/load procedure (Sections 2.7.2 / 2.7.3)
**Loading:**
1. Create new model.
2. Loop `getNextBlock(name, params)`; for each block, dispatch on block name.
3. Call `model.addComponent(comp, false)` (false = don't auto-assign ident).
4. Call `model.validateAllComponents()`.
5. Call `MEDReader.loadVisualComponents(drawingBlocks, viewBlocks, model)`.
6. Call `model.reconnectIdentReferences(false, false)` to wire foreign keys.
7. Call `model.clearDbIds()`.

**Saving:**
1. Create `PibFile`, open file.
2. Write package header.
3. Write model options PibBlock.
4. Iterate categories; for each non-VIEW non-NUMERICS category, write components (directly if `instanceof PibBlock`, else via custom code).
5. Write the core "ModelEditor" package header.
6. Write view components via `ViewComponent.store(file)`.
7. Write user-defined numerics via `MEDReader.storeUserFunction/Constant/Variable(...)`.

---

## 4. CANVAS / DIAGRAM ENGINE

### Containment hierarchy (Section 2.2.5, "DrawnView Class")
```
DrawnView (dialog)
  └─ ZoomablePanel (zoom/pan)
       └─ BeanBox (selection management, hosts beans)
            └─ DrawnComponent[] (one per AbstractComponent in this view)
                 └─ ConnectingPt[] (connection anchor points)
                      └─ ConnectionData / Pad
            └─ DrawnConnection[] (renders Connections as lines)
```

### Multi-View architecture (Section 2.3)
- Multiple views can show the same components simultaneously; all views update automatically when the underlying component data changes (because views are `ComponentListener`s).
- A view is itself a component (in `AbstractModel.CATVIEW`) — meaning views are stored, serialized, and undoable just like model components.
- Views may be 2D, 3D, ASCII (the `AsciiViewer` rendering of `Writeable` components), or editor dialogs.
- 2D views may be **embedded** within other 2D views — this is the "Drill-Down" capability.

### `DrawnComponent` (Section 2.2.5)
- One `DrawnComponent` per renderable `AbstractComponent`, produced by `AbstractComponent.createDrawnComponent()`.
- Owns `ConnectingPt`s — the visual anchor points where connections originate or terminate.
- Each `ConnectingPt` has:
  - A `ConnectionData` describing what location the point represents on the parent component (cell number, face index, edge, etc.).
  - A `Pad` defining position and orientation of any line exiting the component at that point.

### Connection drawing (Section 2.6.2)
- A `DrawnConnection` is created by the connection's `createDrawnComponent()`.
- The drawing engine matches each `ConnectionData` (left/right) against `ConnectingPt`s on each end-component using `ConnectionData.equals(Object)`. The first matching `ConnectingPt` is used as the line endpoint.
- `getConnectionColor()` and `getConnectionStroke()` allow per-connection styling; defaults come from a global "Connection Color" preference.
- `isVisual()` controls whether a `DrawnConnection` is created at all.

### Interaction model
- **Standard tools** (Section 2.14.1): Select, Pan, Zoom, Connect, Insert (the "Main" toolbar).
- **Connect Tool** (Section 2.9.1): on hover, calls `canConnectTo(target)` on each candidate to enable/disable drop zones.
- **Insert Tool**: places a single component instance at click position.
- **Insertion Handlers** (Section 2.14.2): for elements requiring more interaction:
  - `RectangularInsertHandler` — drag a rectangle (used by Rectangle Annotation, Display Beans).
  - `AbstractPathHandler` — click a series of points (used by Line Annotation, Polygon).
- Insertable elements implement the `Insertable` interface and return their handler from `getNewInsertHandler()`.
- **Custom MouseHandlers** (Section 2.14.3): subclass `MouseHandler`; override `activate()`, `deactivate()`, `getCurrentCursor()`, mouse listener methods. Add via `ZoomablePanel.addMouseHandler(...)` in `loadViewMenuItems`.
- Components may also implement `MouseListener`/`MouseMotionListener` directly for fine-grained control without a new tool.

### Layout
- `AbstractModel.layoutComponents(...)` — plugin-specific method to assign x,y locations to a set of `DrawnComponent`s in a view (used after import or auto-layout).
- The document does not specify a coordinate-space convention (zoom/pan-based; details would be in `ZoomablePanel`'s JavaDoc).

### Selection
- `BeanBox` exposes selection events via `BoxSelectionListener` (`addBoxSelectionListener`/`removeBoxSelectionListener`).

---

## 5. EDITOR FRAMEWORK

### Property View (Section 2.12)
- Bean-based: uses Java's `Introspector` + plug-in–supplied `BeanInfo` to enumerate properties.
- Auto-refresh: Property View is itself a `ComponentListener` and re-renders when the active `ComponentElement` fires `componentChanged`.
- Two checkboxes: **show Optional**, **show Disabled**.
- Three orthogonal property states determined by the bean's optional `PropertyController` interface:
  - `isPropertyEnabled(name)` — disabled vs. enabled.
  - `isPropertyRequired(name)` — required vs. optional.
  - `isRestartEditable(name)` — editable while editing a restart.
  - `isResizable(name)` / `isRestartResizable(name)` — for tables/arrays that may not be resizable in some modes.
- **Attribute ordering** (Section 2.12.1.3): `getAttributeIndex(name): int` — returns relative ordering index (default ~999 for unspecified). Goes beyond JavaBeans' "Preferred" attribute.
- **Attribute Groups** (Section 2.12.2): static methods `getAttributeGroups(): String[]`, `getAttributeGroup(name): String`, `getAttributesForGroup(name): String[]`. Each group is rendered as a collapsible table; editors are not instantiated for collapsed groups (perf optimization). The implicit "General" group holds anything not assigned a group.

### Bean editors provided by CAFEAN (Section 2.15.2)
- **`ComponentSelectionEditor`** ("IdentEditor") — edits an integer foreign key. Implements `ModelDependent`. Typically subclassed to scope selection by Category.
- **`RealBeanEditor`** — edits a `Real` value (handles unit display).
- **`RealArrayEditor`** — array of Reals, supports resize semantics.
- **`NamedIntEditor`** ("Enumeration Editor") — integer with named values (e.g., 0=Off, 1=On). Always subclassed.
- **Namelist editors** — for Fortran-style namelists where each value has an active flag:
  - `NamelistEditor` (interface; expects `setPropertyActive`).
  - `NamelistIntEditor`, `NamelistBooleanEditor`, `NamelistRealEditor`, `NamelistNamedIntEditor`.

### Editor-component binding
- Editors are registered globally via `PropertyEditorManager.registerEditor(targetClass, editorClass)` (Section 2.10.2 example: `Energy.class → RealBeanEditor.class`). This is done per-Real-subclass typically in a `static { ... }` initializer.
- For sub-components, implement `ComponentElement` (which extends `ModelElement`) so the editor architecture can find the parent component for state/undo operations.
- Editors needing the model use the `ModelDependent` interface (a `getModel()` accessor).

### Custom editing dialogs
- `AbstractComponent.popupDataDialog(parent, modal)` — default creates a Mini-Navigator + Property View (acts identically to the main Navigator + Property View). Override to provide a custom dialog.
- The custom popup menu can be tailored via `getCustomPopupItems()` and `getCustomPopupActions()`. Default popup includes: Show ASCII (for `Writeable`s), Reference Docs menu, Special menu (built from `getCustomPopupActions`), Properties (opens Mini-Navigator).

### Validation framework (Section 2.11)
- Two layers:
  1. `AbstractModel.checkModel()` — model-level validity. Calls `AbstractComponent.isOkayForExport(prompt)` per component; emits errors/warnings to the Message Window via `MainFrame.addMessage(...)`.
  2. `ValidationTest` — pluggable, configurable, JavaBean-based test units.
- A `ValidationTest` overrides:
  - `getName()` — unique short name (used as storage key).
  - `getDisplayName()` — human-readable.
  - `getShortDescription()` — popup help (HTML-ish).
  - `runValidation(printErrors)` — actual test; returns false on failure. When `printErrors=false`, run silently for pre-export check.
- `AbstractModel` overrides:
  - `getValidationTests(): ValidationTest[]` — full set (enabled + disabled).
  - `getValidationOptions(): ValidationOptions` — name/value config bag, can be extended for MED-file persistence.
- The default `checkModel()` runs all enabled tests automatically.

### Registered Dialogs (Section 2.13)
- Any dialog can register with the MainFrame via `MainFrame.addRegisteredDialog(dialog, model)`. Effects:
  - Appears under the Windows menu.
  - Auto-cascaded by `setWindowLocation` to avoid hiding peers.
  - Auto-closed when its associated model closes.
  - If it implements `RefreshableDialog`, gets `unitsChanged()` (from `MainFrame.resetAllUnits`) and `refresh()` (after undo/redo) called automatically.
- `getRegisteredDialogs(model)` retrieves them; `removeRegisteredDialog(dialog, model)` deregisters.

### Units (Section 2.10)
- All numeric quantities are subclasses of `Real` carrying SI ↔ British conversion factors.
- A unit class implements:
  - `getConversionFactor()` — multiplier to go SI → British (reverse divides).
  - `getSIUnits()` — e.g., `K`, `m`, `m^2`, `m^3`.
  - `getENGUnits()` — e.g., `F`, `ft`, `ft^2`, `ft^3`.
  - `getUnitName()` (default: class name) and `getDisplayName()` (human-readable).
- Each unit registers its bean editor in a static block.
- The model owns plug-in unit registration via `getUnitsDisplay`, `findReal(siString)`, `getRealByIndex(index)`, `getUnitIndex(realOrString)`, `getDimensionless()`, and optionally `getExportUnits()` (for codes that accept only one unit set).
- All values stored internally in SI; conversion is on display only.

### Undo/Redo (Section 2.8)
- Single application-wide undo stack on the MainFrame's `UndoManager`.
- Single edit:
  ```java
  StateEdit edit = new StateEdit(component, "Single Modification");
  // mutate component
  edit.end();
  MainFrame.instance.getUndoManager().undoableEditHappened(
      new UndoableEditEvent(this, edit));
  ```
- Compound edits use `CompoundEdit` aggregating multiple `StateEdit`s (each `.end()`'d before adding).
- All edited objects must be `StateEditable` with proper `storeState(state)` / `restoreState(state)`.

---

## 6. PROJECT / FILE MANAGEMENT

### File-on-disk model
- One model = one **MED file** (ModelEditor Document) using the PIB format (Section 2.7.1). Recommended but not enforced.
- The MED file contains:
  1. Plug-in package header.
  2. Plug-in's global model options PibBlock.
  3. Plug-in-specific component PibBlocks.
  4. Core ModelEditor package header.
  5. Core blocks: views (`ViewCompRec`), drawn components (`DrawnComponentRec`, `DrawnAnnotationRec`, `DrawnImageAnnotationRec`, `DrawnNumericRec`), user-defined numerics (`UserConstantRec`, `UserVariableRec`, `UserFunctionRec`).
- A `MEFeaturePlugin` may also write blocks into another plug-in's MED — co-tenanted persistence (Section 2.1, "MEFeaturePlugin").

### "Project" concept
- The document does **not** describe a multi-file "project" container. The unit of file management is the model (one MED file), plus per-user settings (XML, segmented by plugin-id via Configurator), plus restart data fetched from the Calculation Server.
- The Mainframe concurrently holds **multiple open models** (`getModel(label)`, `getCurrentModel()` for menu actions, the Navigator shows them all).

### Versioning / history
- No external version control concept. The only "history" is the in-memory undo/redo stack (Section 2.8), which is **not persisted** across sessions (as far as the document describes).
- Plug-in version numbers and prerequisite versions are tracked via `MEPluginData` so that loading a model from a newer plug-in version on an older install can fail gracefully.

### User preferences
- Stored in an XML settings file (Section 2.2.4). Each plug-in's preferences are stored under a Configurator module keyed by plugin-id (avoids collisions).

### Restart data
- `loadRestartData()` on `AbstractModel` fetches initial conditions from the Calculation Server for restart submission (Section 2.4.3).

---

## 7. SOLVER INTEGRATION

### Solve workflow
- `MECodePlugin.submitModel(model)` is the integration point (Section 2.2.3).
- The submission target is described as the **Calculation Server**, with `LocalSubmitDialog` as a documented helper for local execution.
- The document doesn't specify the wire protocol. It does describe restart fetching: `loadRestartData()` retrieves restart data **from** the Calculation Server.

### Result loading / display (post-processor)
- The Main Report covers only the Preprocessor plug-in API. The Runtime and Post-processor are referenced as separate JAR-mate plug-ins (`Plugin-Class`, `ClientPlugin-Class` manifest entries — Section 3) but not described in detail here.
- The Multi-View architecture supports overlaying analysis results onto the same `DrawnComponent`s that built the input — the document calls views "displays of the analysis code ASCII input" and notes that views update automatically as data changes (Section 1).

### Pre-submission validation
- `checkModel()` is called before submission (the validation tests' silent `runValidation(false)` invocations exist for exactly this purpose — Section 2.11.1).

---

## 8. APPLICABILITY TO STREAM.jl GUI

For each architectural concept above, the recommendation for a STREAM.jl GUI follows.

### Plug-in architecture (Section 2.1, MEPlugin/MECodePlugin/MEFeaturePlugin)
- **GREY → ADAPT.** STREAM.jl is a single library (one "domain") with no obvious need to support multiple analysis codes. A SNAP-style code-plug-in boundary is overkill. **However**, the plug-in idea reduces nicely to a **component registry**: any STREAM.jl component (Pump, Channel, …) registers a renderer + editor + ports descriptor. Adopt the registration concept; drop the cross-language plug-in JAR machinery. A "feature plug-in" analog (e.g., a plotting overlay, a results viewer) could remain separate from the core editor.

### Two-tier `MEPluginData` / `MEPlugin` split
- **SKIP.** The split exists to allow loading static metadata before the plug-in code itself is loaded. With Julia + Revise, there's no equivalent need.

### `MainFrame` as singleton with menu/dialog/undo registries
- **APPLY (in spirit).** A central UI shell that owns: the active model registry, the undo manager, the message channel, the registered-dialog list. The Julia-side equivalent is a single GUI state object (a struct) pinned at the application root.

### `AbstractModel` + categories + foreign-key relational mapping
- **APPLY.** Foreign-key indirection is the single most important architectural insight in the report. STREAM.jl components are MTK systems that are ultimately plugged into a composite system. A GUI-side "model" object should:
  - Assign each component a stable **ident** (UUID or integer) on creation.
  - Reference components by ident, never by direct Julia handle.
  - Resolve idents lazily at MTK-build time.
  - This gives STREAM.jl undo/redo, copy-paste between models, and renaming-without-breakage almost for free.

### `ident` / `cc number` / `dbid` triple
- **ADAPT.** STREAM.jl does not need a separate "component number" for the analysis code (since MTK names are already symbolic). One stable ID (the equivalent of `ident`) is enough. A user-editable display label can replace the cc-number role.

### `Category` as primary organizing axis
- **APPLY.** STREAM.jl's natural categories are: Fluids, Pumps, Channels, Resistors (Friction/Gravity/Resistor), Heat Exchangers, Heat Diffusion, Inertia. These can drive a Navigator tree, toolbox layout, and component creation dispatch. The hierarchy (e.g., `Resistors → {Friction, Gravity, Resistor}`) maps directly.

### `Connection` as a first-class component (with foreign keys)
- **APPLY.** STREAM.jl has two connector kinds: `FlowPort` and `ThermalPort`. These map exactly onto SNAP's typed-connection pattern (`HydroConnection`, `HeatConnection`). A connection between two ports is itself a model object stored alongside components.

### `ConnectionData` + `ConnectingPt` + `Pad`
- **APPLY.** The pattern of "anchor point on the icon + descriptive data per anchor" is the right abstraction. For STREAM.jl, connection data is simple (just port name); the value is the explicit anchor model with position and orientation, which simplifies line routing.

### `DrawnComponent` + `BeanBox` + `ZoomablePanel` + `DrawnView`
- **APPLY (with modern equivalents).** The 4-layer canvas (dialog / pan-zoom / selection-host / drawn-items) is sound. In any modern toolkit (web SVG/Canvas, Makie, GTK, Qt) this maps cleanly.

### Multi-View with auto-sync via ComponentListener
- **APPLY.** The reactive update pattern is correct. Implement as: components fire change events; views subscribe and re-render. The Property View as a `ComponentListener` is the canonical example.

### 2D-view-embedded-in-2D-view (Drill-Down)
- **GREY.** STREAM.jl's hierarchy is shallow today (loops contain components). If sub-system encapsulation (e.g., a `compose_systems` block treated as a single icon at the parent level, drillable to inner detail) is desired, the SNAP approach is the right precedent.

### PIB binary serialization
- **SKIP.** Use a human-readable, diffable format (JSON, TOML, or YAML). Julia ecosystem favors these. PIB only made sense in 2008 for Java cross-platform binary; it has no advantage today.

### `MEFeaturePlugin` writing blocks into another plug-in's file
- **SKIP.** This was needed to let auxiliary plug-ins persist alongside a single MED file without owning it. With JSON/TOML and a single-domain library, a model file can simply have an `extensions: {}` section.

### Model options as a JavaBean shown as a Navigator child
- **APPLY.** A "Model Options" node (loop name, fluid choice, gravity vector, default solver settings) is exactly the right place to put project-level metadata. It should appear as a child of the model in the navigator and edit through the same property view as components.

### Root components (singleton components in Navigator)
- **APPLY (sparingly).** Useful for one-of-a-kind objects (e.g., a default fluid record, a global solver config object).

### Component number groups (auto-numbering, validation, renumbering)
- **ADAPT.** STREAM.jl uses Julia symbols for component names, not numbers. A "name groups" analog (auto-name like `pump1`, `pump2`, …) is useful. Renumber-on-demand maps to "rename-on-demand".

### `AbstractBeanComponent` + `BeanInfo` + `Introspector`
- **ADAPT.** The Java-specific bean introspection mechanism doesn't exist in Julia. The equivalent is to define a struct-like description per component (a list of `(field_name, type, units, default, doc)` tuples). This becomes the source of truth for the property editor, the validator, and the serializer.

### `clone()` for component duplication
- **APPLY.** Required for copy-paste. In Julia, this is `deepcopy` plus a "give the copy a new ident" pass.

### `storeState` / `restoreState` (for `StateEditable`)
- **APPLY.** Snapshot the property bag before mutation; restore on undo. Trivial to implement on a struct-of-fields component.

### `complete()` post-creation hook
- **APPLY.** Useful for filling defaults from geometry (e.g., when a Channel is created, compute initial guesses for L, Dh).

### `removeVerify()`
- **APPLY.** Ask the user before deleting a component referenced by others.

### `Writeable` interface + AsciiViewer
- **ADAPT.** STREAM.jl's "ASCII representation" is the generated MTK equations. A "Show MTK Source" view (live-updated as the user edits) is high-value: it gives expert users transparency into what the GUI is producing.

### Property View design (PropertyController, attribute ordering, attribute groups, optional/disabled toggles)
- **APPLY in full.** This is one of the strongest parts of the SNAP design. Specifically:
  - Optional/Required state per field.
  - Enabled/Disabled state per field (e.g., disable "wall thickness" when "use thin-wall approximation" is on).
  - Explicit ordering (don't rely on field declaration order).
  - Collapsible groups; defer editor instantiation for collapsed groups.

### Bean editors (RealBeanEditor, ComponentSelectionEditor, NamedIntEditor, NamelistEditor)
- **APPLY.**
  - **RealBeanEditor analog**: a numeric field with a unit selector and SI/imperial toggle (display-only conversion).
  - **ComponentSelectionEditor analog**: a foreign-key picker — when a Channel needs to reference a `PipeGeometry`, present a dropdown of all geometry instances in the model.
  - **NamedIntEditor analog**: enum dropdowns (e.g., friction correlation: laminar / turbulent / blended).
  - **NamelistEditor**: less relevant. STREAM.jl doesn't have Fortran namelists. The "value + active flag" pair is occasionally useful (e.g., optional gravity term) but can be modeled as a normal optional field.

### Units (`Real`, SI/British, registration)
- **ADAPT.** STREAM.jl already uses SI internally. Reuse the SNAP design: store SI, convert on display, let the user toggle display units globally and per-field. Use `Unitful.jl` as the underlying mechanism. Each numeric field carries a unit type.

### Validation framework (`checkModel` + `ValidationTest`)
- **APPLY.** Two-tier validation is the right pattern:
  - Per-component `is_valid_for_solve()` returning errors/warnings.
  - Pluggable model-level `ValidationTest`s that the user can enable/disable individually and configure (e.g., "warn if any flow path has Re < 100", "error if any heated channel has q'' but no fluid contact").
- Validation runs silently before solve and verbosely on user request.

### Registered Dialogs + RefreshableDialog
- **APPLY.** Useful for:
  - Plot windows tied to a model that should close when the model closes.
  - A "Solver Output" dialog.
  - Avoiding overlapping placement.
  - Refreshing dialogs after units change or undo.

### Insertion handlers (`Insertable`, `RectangularInsertHandler`, `AbstractPathHandler`)
- **APPLY in spirit.** Most STREAM.jl components are point-insertions, but a multi-segment pipe (`Channel` with custom geometry path) might want a path handler. The interface concept generalizes well.

### Custom MouseHandlers + tool architecture
- **APPLY.** A small set of canvas tools (Select, Pan, Zoom, Connect, Insert) plus per-component custom tools is the right division.

### Standard toolbars (Main / Clipboard / Annotation / Numerics)
- **APPLY.** Annotations (rectangles, ellipses, text) for diagram documentation are a feature users expect.

### Single application-wide Undo stack with `StateEdit` / `CompoundEdit`
- **APPLY.** This is the right model.

### Python scripting via `MACRO` batch + `findComponent(catName, number)`
- **APPLY.** STREAM.jl already exists in Julia, so users get a free REPL. The GUI should expose the same APIs the REPL would: `find_component(model, category, name)`, batch macros, scripting. Bonus: STREAM.jl is Julia-native, so scripts ARE first-class — no foreign-language interpreter needed. The right form is a Julia REPL pane embedded in the GUI with the active `model` pre-bound.

### `getCustomPopupItems` / `getCustomPopupActions` (per-component context menus)
- **APPLY.** Right-click extensibility is essential.

### Reference Document Links (per-component help)
- **APPLY.** Each STREAM.jl component should expose a docstring URL or rendered docstring in its context menu.

### Save/load procedure (`reconnectIdentReferences`, `clearDbIds`, `validateAllComponents`)
- **APPLY.** The order of operations on load is exactly right: deserialize all → validate → resolve foreign keys → clear transients.

### MEDReader.loadVisualComponents pattern (separating drawn metadata from semantic blocks)
- **APPLY.** Layout/visual data and semantic data should be separable in the file format. This makes diffing and merging much cleaner: a layout-only edit doesn't touch the simulation-relevant section.

### Restart data fetched from Calculation Server
- **GREY.** STREAM.jl already has `solve_steady` that produces a steady state guess used by `solve_transient`. The "restart" concept maps directly. The GUI workflow is: run steady → use as IC for transient. Whether this needs a server backend or just an in-process solve depends on scale.

### `getSamPackage` / file-type-based plug-in dispatch
- **SKIP.** Only one library; one file type.

### `addOrder` / `setOrder` / `getOrderComparator`
- **SKIP.** Used in SNAP to preserve the relative order of components in imported text decks — STREAM.jl has no text-deck import.

### `MEDReader` core block types (UserConstant, UserVariable, UserFunction)
- **APPLY (analog).** Users need scratch-pad parameters (e.g., "let me define `Q_total = 100kW` once and reference it from three components"). Map to: parameter expressions, named constants, lookup tables. Store these as model-level objects in the same file.

### TableSorter / OptionPane / GUI utilities
- **SKIP.** Toolkit-specific.

---

## 9. ARCHITECTURAL PATTERNS WORTH ADOPTING

These are the SNAP/CAFEAN design decisions that are worth importing wholesale into STREAM.jl's GUI design.

1. **Foreign-key relational model with `ident`s.** Never let one component hold a direct pointer to another. Always resolve via the model's lookup table at the moment of use. This is the foundation that enables every other useful feature: undo, copy-paste between models, renaming, renodalization, partial loads, version-tolerant deserialization.

2. **Connections are first-class components.** A connection has its own ident, its own storage, its own listeners, its own renderer, its own connection-data describing what it attaches to on each side. This is far cleaner than treating connections as adjacency lists owned by components.

3. **Connection-data + connecting-point separation.** The visual anchor on the icon (`ConnectingPt`) is decoupled from the data describing what that anchor means (`ConnectionData`). The drawing engine resolves the line by `ConnectionData.equals(...)`. This makes layout robust to component-shape changes — connections find their anchors by meaning, not by pixel coordinates.

4. **Multi-view architecture with `ComponentListener`s.** All views (2D diagram, property editor, ASCII/MTK source, per-component editing dialogs) listen to the same component change events and refresh independently. This eliminates the "I edited a value but the property panel didn't update" class of bugs.

5. **Embedded-view drill-down.** A view is itself a component. Composite components can have their own views embedded in the parent view. This is the right way to scale to large reactor models without losing local context.

6. **Property View driven by `PropertyController` + Attribute Groups.** A few orthogonal flags on the underlying bean (`isPropertyEnabled`, `isPropertyRequired`, `isResizable`) plus group/order metadata gives a rich, dynamic property panel without ad-hoc UI code per component. Group collapse defers editor instantiation — important for large components.

7. **Two-tier validation: per-component + pluggable model tests.** Component-level `isOkayForExport` for invariants the component owns; model-level `ValidationTest` for cross-component checks that are user-configurable.

8. **Categories driving Navigator + toolbox + creation dispatch.** A single hierarchical category tree provides three different UI artifacts and the type system for creation/iteration. Reuse beats redundancy.

9. **Layout / visual / drawing data is separable from semantic data in the file format.** SNAP loads `Drawn*` blocks separately from semantic component blocks via `loadVisualComponents`. This makes layout-only edits non-invasive in version control.

10. **Single application-wide undo stack with `StateEdit` + `CompoundEdit`.** Compound edits are essential for any operation that mutates more than one component (e.g., "delete component and its three connections").

11. **Registered Dialog pattern with `RefreshableDialog`.** Auto-cascade, auto-close-with-model, auto-refresh-on-units-change. A small infrastructural pattern that avoids many small bugs.

12. **Plug-in/feature/code distinction (concept, not impl).** Even though STREAM.jl needn't support multi-domain plug-ins, the *split* between core editor capabilities and feature add-ons (a postprocess plot, a results overlay, an export tool) is worth preserving. It encourages clean boundaries.

13. **Reactive scripting parity.** Whatever the GUI can do, the user must be able to do from a script (and vice versa). SNAP uses Python; STREAM.jl already uses Julia, so the GUI should be a thin shell around a fully-scriptable model object — not the only entry point.

14. **Units are first-class on every numeric field.** SI internally, display conversion only. Per-field unit type registration. A global SI/imperial toggle. This is non-negotiable for engineering software.

---

## 10. WHAT SNAP GETS WRONG (or what STREAM.jl can do better)

1. **Two-tier plug-in metadata (`MEPluginData` + `MEPlugin`)** is a Java class-loading workaround. It existed because Java needed to enumerate available plug-ins without paying the cost of fully loading them. Modern languages (and Julia in particular) don't need this. Skip.

2. **Binary, opaque PIB serialization** is hostile to: version control (no diff), peer review (no read-aloud), interop (need a custom parser), and recovery (a single corrupt block can break a whole model). Use JSON or TOML. Cost is negligible; benefit is enormous.

3. **JavaBean reflection-based property panels** require every component to have a hand-written `BeanInfo`, plus a discovery dance via `Introspector`. Modern alternatives (a single component-spec table interpreted by a single editor renderer) are simpler and more uniform.

4. **Three component identifiers (`ident`, `cc number`, `dbid`)** are confusing. The `cc number` exists because TRACE/RELAP5 input formats demand integer component IDs. STREAM.jl has no such legacy. One stable ID per component is enough.

5. **`Configurator` settings file segmented by plugin-id with no schema** invites per-plug-in inconsistency. A single typed settings document is preferable.

6. **Save logic split across the model and the file class** (Section 2.7.4 / 2.7.5) — save flow weaves between `ExampleModel.saveModel`, `ExampleMedFile.prepareStore`, manual block iteration, header-writing protocols, and core-block helpers. The lack of a single declarative format spec means every plug-in re-implements substantial save/load logic. **STREAM.jl should have a single declarative serialization layer** (e.g., StructTypes/JSON3, or a custom serializer that walks a uniform component schema).

7. **`reconnectIdentReferences(...)` requires plug-in authors to remember to override it for every new ComponentList** (Section 2.4.3). This is a footgun — forget it and foreign keys silently break on load. A type-driven serializer that knows about ident references avoids this.

8. **No project / multi-file structure.** A real reactor model often spans multiple sub-systems, scenarios, restart points, sensitivity studies. SNAP treats each as a separate MED file with no first-class container. STREAM.jl could define a project (a directory with a manifest) holding multiple model files plus shared geometry/fluid libraries.

9. **No mention of merge/diff/collaboration.** Binary blob format makes git collaboration painful. Engineers do collaborate on reactor models. Build for diffability from day one.

10. **No mention of automated layout.** `layoutComponents` is a plug-in-implemented hook; SNAP provides nothing. STREAM.jl could ship a built-in graph-layout algorithm (Sugiyama, force-directed, or domain-specific "loop" layouts) — important for first-time users staring at an empty canvas.

11. **`Connection` extends `Component`, but a connection is conceptually different.** SNAP shoehorns connections into the component lifecycle to inherit ident/listeners/persistence. This works but creates oddities (e.g., should a connection appear in the Navigator? In counts? In iterators?). STREAM.jl could keep connections out of the component category tree while still giving them idents and persistence — a parallel "edge list" alongside the "node list".

12. **Undo state captured via `storeState`/`restoreState` on each bean** — every component author must implement this correctly, and bugs are hard to diagnose (Section 2.5.1 explicitly warns about this). A centralized snapshot mechanism (deep-copy-the-model on each edit, or a structurally-shared persistent data structure) is more reliable.

13. **`ConnectionData.equals(Object)` as the way to match drawing endpoints** (Section 2.6.2) is a fragile coupling. A misimplemented `equals` breaks line drawing in a non-obvious way. Use explicit named-port references on both sides.

14. **No first-class concept of "results"** in the preprocessor API. Plotting, time-series visualization, and result overlays are deferred to the post-processor (separate plug-in, not described here). The boundary creates friction. STREAM.jl could unify: an `MTKSolution` is a first-class artifact attached to a model, and views auto-bind to it.

15. **Java Swing era assumptions everywhere** — modal dialogs, `OptionPane`, manual menu wiring, manual toolbar stacking, mouse handlers as classes with verbose lifecycle. A modern declarative UI framework (web-based, Makie, Qt-Quick, or similar) replaces a dozen of these utilities with a few patterns.

16. **`SwingWorker` for any GUI interaction inside `complete()`** (Section 2.5.1) — the threading model leaks into component authoring. STREAM.jl should keep threading concerns out of the component API surface.

17. **The "Special menu" for rarely-used actions** (Section 2.5.1, `getCustomPopupItems`) is a UX smell — it suggests the team had so many actions that the popup menu would be unusable, so they hid some. Better organization (search, command palette, keyboard shortcuts) is preferable.

18. **No keyboard-first navigation described.** All interaction is described as menu-driven or mouse-driven. Modern engineering tools need command palettes (Ctrl-Shift-P), quick-jump-to-component, fuzzy search.

19. **The Mainframe is described as a god-object** that owns nearly everything: menus, dialogs, models, undo stack, message window, registered dialogs, plug-in registry, current model, units state. It has many concerns. STREAM.jl can split these into separate services (event bus, command registry, model registry, undo service, message bus) — easier to test, easier to reason about.

20. **Documentation gap: the document repeatedly defers to Source Code Documentation / Appendix A JavaDoc.** Many concepts (`ZoomablePanel` coordinate system, exact `Configurator` API, `BeanBox` selection semantics) are mentioned but not described. The Main Report alone is insufficient to design a full plug-in. STREAM.jl should commit to a complete, single-document architecture spec for its GUI.

---

## Notes on Ambiguity (explicit GREYs)

- **Coordinate system / units of the canvas.** The document describes `ZoomablePanel`, `BeanBox`, "x,y locations" but never specifies whether positions are in pixels, abstract canvas units, or model-physical units, nor how zoom interacts with anchor-point offsets (`Pad`).
- **3D view architecture.** Multi-View is said to support 3D representations; nothing more is said about the 3D infrastructure in this Main Report.
- **Wire protocol to the Calculation Server.** Submission is mentioned (`submitModel`, `LocalSubmitDialog`), but the protocol, return-results path, and progress-reporting mechanism are not described.
- **Post-processor plug-in interface.** Manifest entry `ClientPlugin-Class` is mentioned; the API behind it is not in this Main Report.
- **Concurrency model.** `SwingWorker` is mentioned once, but the document does not describe how long-running operations (open, save, validate, submit) interact with the UI thread or whether there's a job queue.
- **Plug-in interaction with native code.** Some analysis codes are Fortran/C; how they're packaged with the plug-in is not described.
- **Versioning of the MED file beyond the 80-character version string.** Migration of older MED files when a plug-in upgrades is not described.
- **Does the Navigator reflect ordering changes from `getOrder/setOrder`?** Order is described as a sort key for export; whether it affects Navigator display is unclear.
- **How are `views` themselves edited?** They're stored in `CATVIEW` and persist with the model, but the editing flow for view layout (creating a new 2D view vs. opening one) is not described here.
- **Embedding 2D views inside 2D views (Drill-Down).** Mentioned as a capability in Section 1; no API description follows in the Main Report.

---

## Source page references (for traceability)
- Plug-in Architecture UML — Figure 1, p. 2-1.
- Multi-View Architecture UML — Figure 2, p. 2-9.
- Connection Class UML — Figure 3, p. 2-32.
- Plug-in implementation — §2.1–2.2 (pp. 2-1 – 2-5).
- Model creation — §2.4 (pp. 2-11 – 2-16).
- Bean components — §2.5 (pp. 2-17 – 2-21).
- Connections — §2.6, §2.9 (pp. 2-22 – 2-35).
- MED/PIB format — §2.7 (pp. 2-25 – 2-30).
- Undo/Redo — §2.8 (p. 2-31).
- Units — §2.10 (pp. 2-36 – 2-38).
- Validation — §2.11 (pp. 2-39 – 2-40).
- Property View — §2.12 (pp. 2-41 – 2-42).
- Registered Dialogs — §2.13 (p. 2-43).
- 2D View customization — §2.14 (pp. 2-44 – 2-45).
- Utility classes / editors — §2.15 (pp. 2-46 – 2-48).
- Packaging — §3 (p. 3-1).
- Python scripting — §4 (pp. 4-1 – 4-8).
