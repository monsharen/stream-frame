import { demo } from './demo.ts';
import { netflix } from './netflix.ts';
import type { ServiceAdapter } from './types.ts';

export const services: ServiceAdapter[] = [netflix, demo];

export function getService(id: string): ServiceAdapter | undefined {
  return services.find((s) => s.id === id);
}
