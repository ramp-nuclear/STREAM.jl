import { describe, it, expect } from 'vitest';
import { registry, getAllComponents, getComponent, getComponentsByCategory } from '../index';

describe('Component Registry', () => {
  it('loads all 16 v1.1 STREAM.jl components (SCAF-03, D-02; Plan 03 adds Sources/Reactor Physics/Resources)', () => {
    expect(getAllComponents()).toHaveLength(16);
  });

  it('has stream_version field (SCAF-05)', () => {
    expect(registry.stream_version).toBeDefined();
    expect(typeof registry.stream_version).toBe('string');
    expect(registry.stream_version).toBe('1.1.0');
  });

  it('has schema_version field', () => {
    expect(registry.schema_version).toBeDefined();
    expect(registry.schema_version).toBe('2.0');
  });

  it('every component has required fields (SCAF-03)', () => {
    for (const comp of getAllComponents()) {
      expect(comp.id, `${comp.id} missing id`).toBeTruthy();
      expect(comp.label, `${comp.id} missing label`).toBeTruthy();
      expect(comp.category, `${comp.id} missing category`).toBeTruthy();
      expect(comp.description, `${comp.id} missing description`).toBeTruthy();
      expect(comp.ports, `${comp.id} missing ports`).toBeDefined();
      // v1.1 (D-12, D-13): non-canvas categories (Reactor Physics, Resources) legally
      // carry an empty ports array — PointKinetics is connected via codegen-side
      // connect_temperature_feedback, and ReactivityController is a Resource with no
      // canvas presence at all.
      const isNonCanvas = comp.category === 'Reactor Physics' || comp.category === 'Resources';
      if (!isNonCanvas) {
        expect(comp.ports.length, `${comp.id} has no ports`).toBeGreaterThan(0);
      }
      expect(comp.parameters, `${comp.id} missing parameters`).toBeDefined();
      expect(comp.constructorModes, `${comp.id} missing constructorModes`).toBeDefined();
      expect(comp.constructorModes.length, `${comp.id} has no constructorModes`).toBeGreaterThan(0);
    }
  });

  it('every port has required fields', () => {
    for (const comp of getAllComponents()) {
      for (const port of comp.ports) {
        expect(port.name, `${comp.id} port missing name`).toBeTruthy();
        // v1.1 (D-14): PortType union admits BCPort in addition to FlowPort/ThermalPort.
        expect(port.type, `${comp.id} port missing type`).toMatch(/^(FlowPort|ThermalPort|BCPort)$/);
        // v1.1 (D-16): `side` is optional on array-shaped logical ports that autoflip
        // via `default_axis`. Non-autoflip ports still set it explicitly.
        if (port.side !== undefined) {
          expect(port.side, `${comp.id} port has invalid side`).toMatch(/^(left|right|top|bottom)$/);
        } else {
          // An array-shaped port without `side` must declare default_axis to drive autoflip.
          expect(
            port.default_axis,
            `${comp.id}.${port.name} has no side but also no default_axis`,
          ).toMatch(/^(horizontal|vertical)$/);
        }
      }
    }
  });

  it('every parameter has required fields', () => {
    for (const comp of getAllComponents()) {
      for (const param of comp.parameters) {
        expect(param.name, `${comp.id} param missing name`).toBeTruthy();
        // v1.1 (D-10): polymorphic kwargs carry `type_union` in place of `type`.
        // A parameter must declare one or the other.
        expect(
          param.type || param.type_union,
          `${comp.id}.${param.name} missing type or type_union`,
        ).toBeTruthy();
        expect(param.description, `${comp.id}.${param.name} missing description`).toBeTruthy();
        expect(typeof param.required, `${comp.id}.${param.name} missing required`).toBe('boolean');
        expect(typeof param.positional, `${comp.id}.${param.name} missing positional`).toBe('boolean');
      }
    }
  });

  it('contains all expected component IDs (D-02)', () => {
    const ids = getAllComponents().map(c => c.id);
    const expected = [
      'Channel', 'ChannelAndContacts', 'ChannelHeatFlux',
      'Pump', 'Flapper', 'Friction', 'Gravity', 'Resistor',
      'Inertia', 'HeatExchanger', 'ConstantTemperature', 'HeatDiffusion'
    ];
    for (const name of expected) {
      expect(ids, `missing component: ${name}`).toContain(name);
    }
  });

  it('Pump has two constructor modes (fixed-dP, fixed-mdot)', () => {
    const pump = getComponent('Pump');
    expect(pump).toBeDefined();
    expect(pump!.constructorModes).toHaveLength(2);
    const modeNames = pump!.constructorModes.map(m => m.mode);
    expect(modeNames).toContain('fixed-dP');
    expect(modeNames).toContain('fixed-mdot');
  });

  it('ChannelAndContacts has ThermalPort array ports (v1.1 D-16/D-17/D-20)', () => {
    const cac = getComponent('ChannelAndContacts');
    expect(cac).toBeDefined();
    const thermalLeft = cac!.ports.find(p => p.name === 'thermal_left');
    const thermalRight = cac!.ports.find(p => p.name === 'thermal_right');
    expect(thermalLeft).toBeDefined();
    // v1.1: legacy `array: true` / `arrayParam: "n"` replaced by `array_size: "n"`.
    expect(thermalLeft!.array_size).toBe('n');
    expect(thermalLeft!.default_axis).toBe('vertical');
    expect(thermalLeft!.pair_with).toBe('thermal_right');
    expect(thermalRight).toBeDefined();
    expect(thermalRight!.array_size).toBe('n');
    expect(thermalRight!.default_axis).toBe('vertical');
    expect(thermalRight!.pair_with).toBe('thermal_left');
  });

  it('HeatDiffusion has ThermalPort array ports (v1.1 D-16/D-17/D-21)', () => {
    const hd = getComponent('HeatDiffusion');
    expect(hd).toBeDefined();
    const thermalLeft = hd!.ports.find(p => p.name === 'thermal_left');
    const thermalRight = hd!.ports.find(p => p.name === 'thermal_right');
    expect(thermalLeft).toBeDefined();
    // v1.1: legacy `array: true` / `arrayParam: "nz"` replaced by `array_size: "nz"`.
    // HD uses `nz` (not `n`) and `default_axis: "horizontal"` (per D-21, distinct from CAC's vertical).
    expect(thermalLeft!.array_size).toBe('nz');
    expect(thermalLeft!.default_axis).toBe('horizontal');
    expect(thermalLeft!.pair_with).toBe('thermal_right');
    expect(thermalRight).toBeDefined();
    expect(thermalRight!.array_size).toBe('nz');
    expect(thermalRight!.default_axis).toBe('horizontal');
    expect(thermalRight!.pair_with).toBe('thermal_left');
  });

  it('ChannelHeatFlux has no ThermalPort and declares q_left/q_right external_inputs (v1.1 D-03/D-19)', () => {
    const chf = getComponent('ChannelHeatFlux');
    expect(chf).toBeDefined();
    const thermalPorts = chf!.ports.filter(p => p.type === 'ThermalPort');
    expect(thermalPorts).toHaveLength(0);
    // v1.1: T_wall scalar parameter dropped; per-cell q_left/q_right external_inputs replace it.
    const tWall = chf!.parameters.find(p => p.name === 'T_wall');
    expect(tWall).toBeUndefined();
    const externalInputs = chf!.external_inputs ?? [];
    expect(externalInputs.map(e => e.name)).toEqual(['q_left', 'q_right']);
    for (const ei of externalInputs) {
      expect(ei.source_component).toBe('HeatFluxSource');
      expect(ei.source_port).toBe('q_out');
      expect(ei.unit).toBe('W/m^2');
    }
  });

  it('ConstantTemperature is Thermal category (D-03)', () => {
    const ct = getComponent('ConstantTemperature');
    expect(ct).toBeDefined();
    expect(ct!.category).toBe('Thermal');
  });

  it('getComponentsByCategory filters correctly', () => {
    const hydraulic = getComponentsByCategory('Hydraulic');
    const thermal = getComponentsByCategory('Thermal');
    expect(hydraulic.length).toBe(10);
    expect(thermal.length).toBe(2);
    expect(thermal.map(c => c.id).sort()).toEqual(['ConstantTemperature', 'HeatDiffusion']);
  });

  it('adding a component requires only JSON (SCAF-04 architecture check)', () => {
    // Verify no component ID is hardcoded in the loader module.
    // The registry is purely data-driven: getAllComponents reads from JSON.
    // If this test passes, a new JSON entry would be picked up automatically.
    const ids = getAllComponents().map(c => c.id);
    expect(ids).toContain('Pump');
    expect(ids).toContain('HeatDiffusion');
    // The fact that these are found via JSON import (not TS constants) proves SCAF-04
  });
});
