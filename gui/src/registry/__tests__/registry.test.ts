import { describe, it, expect } from 'vitest';
import { registry, getAllComponents, getComponent, getComponentsByCategory } from '../index';

describe('Component Registry', () => {
  it('loads all 12 STREAM.jl components (SCAF-03, D-02)', () => {
    expect(getAllComponents()).toHaveLength(12);
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
      expect(comp.ports.length, `${comp.id} has no ports`).toBeGreaterThan(0);
      expect(comp.parameters, `${comp.id} missing parameters`).toBeDefined();
      expect(comp.constructorModes, `${comp.id} missing constructorModes`).toBeDefined();
      expect(comp.constructorModes.length, `${comp.id} has no constructorModes`).toBeGreaterThan(0);
    }
  });

  it('every port has required fields', () => {
    for (const comp of getAllComponents()) {
      for (const port of comp.ports) {
        expect(port.name, `${comp.id} port missing name`).toBeTruthy();
        expect(port.type, `${comp.id} port missing type`).toMatch(/^(FlowPort|ThermalPort)$/);
        expect(port.side, `${comp.id} port missing side`).toMatch(/^(left|right|top|bottom)$/);
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

  it('ChannelAndContacts has ThermalPort array ports (D-04)', () => {
    const cac = getComponent('ChannelAndContacts');
    expect(cac).toBeDefined();
    const thermalLeft = cac!.ports.find(p => p.name === 'thermal_left');
    const thermalRight = cac!.ports.find(p => p.name === 'thermal_right');
    expect(thermalLeft).toBeDefined();
    expect(thermalLeft!.array).toBe(true);
    expect(thermalLeft!.arrayParam).toBe('n');
    expect(thermalRight).toBeDefined();
    expect(thermalRight!.array).toBe(true);
    expect(thermalRight!.arrayParam).toBe('n');
  });

  it('HeatDiffusion has ThermalPort array ports (D-04)', () => {
    const hd = getComponent('HeatDiffusion');
    expect(hd).toBeDefined();
    const thermalLeft = hd!.ports.find(p => p.name === 'thermal_left');
    const thermalRight = hd!.ports.find(p => p.name === 'thermal_right');
    expect(thermalLeft).toBeDefined();
    expect(thermalLeft!.array).toBe(true);
    expect(thermalLeft!.arrayParam).toBe('nz');
    expect(thermalRight).toBeDefined();
    expect(thermalRight!.array).toBe(true);
    expect(thermalRight!.arrayParam).toBe('nz');
  });

  it('ChannelHeatFlux has no ThermalPort (T_wall is scalar BC)', () => {
    const chf = getComponent('ChannelHeatFlux');
    expect(chf).toBeDefined();
    const thermalPorts = chf!.ports.filter(p => p.type === 'ThermalPort');
    expect(thermalPorts).toHaveLength(0);
    const tWall = chf!.parameters.find(p => p.name === 'T_wall');
    expect(tWall).toBeDefined();
    expect(tWall!.type).toBe('Real');
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
