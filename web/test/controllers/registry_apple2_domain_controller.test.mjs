import test from 'node:test';
import assert from 'node:assert/strict';
import { createApple2DomainController } from '../../app/controllers/registry_apple2_domain_controller.mjs';

test('createApple2DomainController groups Apple II ui and memory actions', () => {
  const fn = () => {};
  const domain = createApple2DomainController({
    isApple2UiEnabled: fn,
    updateIoToggleUi: fn,
    refreshApple2Screen: fn,
    refreshApple2Debug: fn,
    refreshMemoryView: fn,
    setApple2SoundEnabled: fn,
    updateApple2SpeakerAudio: fn,
    queueApple2Key: fn,
    performApple2ResetSequence: fn,
    setMemoryDumpStatus: fn,
    loadApple2DumpOrSnapshotFile: fn,
    saveApple2MemoryDump: fn,
    saveApple2MemorySnapshot: fn,
    loadLastSavedApple2Dump: fn,
    loadKaratekaDump: fn,
    resetApple2WithMemoryVectorOverride: fn
  });

  assert.equal(domain.isUiEnabled, fn);
  assert.equal(domain.updateSpeakerAudio, fn);
  assert.equal(domain.resetWithMemoryVectorOverride, fn);
});
