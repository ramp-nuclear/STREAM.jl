// index.ts — Registry loader and accessor functions for STREAM.jl component metadata

import registryData from './components.json';
import type { ComponentRegistry, ComponentDefinition } from './types';

const registry: ComponentRegistry = registryData as ComponentRegistry;

export function getComponent(id: string): ComponentDefinition | undefined {
  return registry.components.find(c => c.id === id);
}

export function getComponentsByCategory(category: string): ComponentDefinition[] {
  return registry.components.filter(c => c.category === category);
}

export function getAllComponents(): ComponentDefinition[] {
  return registry.components;
}

export { registry };
