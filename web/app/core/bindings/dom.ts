import { createShellDomRefs } from '../../components/shell/bindings/dom_refs';
import { createRunnerDomRefs } from '../../components/runner/bindings/dom_refs';
import { createSimDomRefs } from '../../components/sim/bindings/dom_refs';
import { createWatchDomRefs } from '../../components/watch/bindings/dom_refs';
import { createApple2DomRefs } from '../../components/apple2/bindings/dom_refs';
import { createMemoryDomRefs } from '../../components/memory/bindings/dom_refs';
import { createExplorerDomRefs } from '../../components/explorer/bindings/dom_refs';

export function createDomRefs(documentRef = globalThis.document) {
  return {
    ...createShellDomRefs(documentRef),
    ...createRunnerDomRefs(documentRef),
    ...createSimDomRefs(documentRef),
    ...createWatchDomRefs(documentRef),
    ...createApple2DomRefs(documentRef),
    ...createMemoryDomRefs(documentRef),
    ...createExplorerDomRefs(documentRef)
  };
}
