# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../../lib/rhdl/cli/tasks/utilities/web_apple2_arcilator_build'

# Integration tests for the arcilator WASM build pipeline.
# These test that the generated C wrapper source actually compiles and links
# to a valid WASM binary. They require clang and wasm-ld with wasm32 target
# support but do NOT require firtool or arcilator.
RSpec.describe 'WebApple2ArcilatorBuild WASM compilation integration', :slow do
  let(:mod) { RHDL::CLI::Tasks::WebApple2ArcilatorBuild }

  let(:offsets) do
    {
      'clk_14m' => { offset: 0, num_bits: 1 },
      'reset' => { offset: 1, num_bits: 1 },
      'ram_do' => { offset: 2, num_bits: 8 },
      'ps2_clk' => { offset: 3, num_bits: 1 },
      'ps2_data' => { offset: 4, num_bits: 1 },
      'ram_addr' => { offset: 10, num_bits: 16 },
      'ram_we' => { offset: 12, num_bits: 1 },
      'd' => { offset: 13, num_bits: 8 },
      'speaker' => { offset: 14, num_bits: 1 },
      'pc_debug' => { offset: 20, num_bits: 16 },
      'a_debug' => { offset: 22, num_bits: 8 },
      'x_debug' => { offset: 23, num_bits: 8 },
      'y_debug' => { offset: 24, num_bits: 8 },
      'pause' => { offset: 25, num_bits: 1 },
      'gameport' => { offset: 26, num_bits: 8 },
      'pd' => { offset: 27, num_bits: 8 },
      'flash_clk' => { offset: 28, num_bits: 1 }
    }
  end

  let(:stub_eval_source) do
    <<~C
      void apple2_apple2_eval(void *state) { (void)state; }
    C
  end

  before(:all) do
    @skip_reason = nil
    clang_ok = system('clang --target=wasm32-unknown-unknown -x c /dev/null -c -o /dev/null 2>/dev/null')
    wasm_ld_ok = system('wasm-ld --version >/dev/null 2>&1')
    unless clang_ok && wasm_ld_ok
      @skip_reason = 'clang with wasm32 target or wasm-ld not available'
    end
  end

  around do |example|
    skip(@skip_reason) if @skip_reason
    Dir.mktmpdir('arc_wasm_test') do |dir|
      @build_dir = dir
      example.run
    end
  end

  def compile_wasm
    wrapper_path = File.join(@build_dir, 'arc_wasm_wrapper.c')
    stub_path = File.join(@build_dir, 'stub_eval.c')
    wrapper_obj = File.join(@build_dir, 'wrapper.o')
    stub_obj = File.join(@build_dir, 'stub.o')
    @wasm_output = File.join(@build_dir, 'apple2_arcilator.wasm')

    source = mod.build_wrapper_source(offsets, 4096)
    File.write(wrapper_path, source)
    File.write(stub_path, stub_eval_source)

    system(
      'clang', '--target=wasm32-unknown-unknown', '-O2', '-c', '-fPIC',
      '-ffreestanding', '-Wno-incompatible-library-redeclaration',
      wrapper_path, '-o', wrapper_obj
    ) or raise 'clang wrapper compilation failed'

    system(
      'clang', '--target=wasm32-unknown-unknown', '-O2', '-c', '-fPIC',
      '-ffreestanding', stub_path, '-o', stub_obj
    ) or raise 'clang stub compilation failed'

    system(
      'wasm-ld', '--no-entry', '--export-dynamic', '--allow-undefined',
      '--initial-memory=4194304', '--max-memory=16777216',
      '-o', @wasm_output, wrapper_obj, stub_obj
    ) or raise 'wasm-ld linking failed'
  end

  it 'compiles the generated C wrapper to a valid WASM binary' do
    compile_wasm
    wasm_bytes = File.binread(@wasm_output)

    # Check WASM magic number (\0asm)
    expect(wasm_bytes[0..3].bytes).to eq([0x00, 0x61, 0x73, 0x6D])
    # Check WASM version 1
    expect(wasm_bytes[4..7].unpack1('V')).to eq(1)
  end

  it 'exports all required WasmIrSimulator API functions' do
    compile_wasm
    wasm_bytes = File.binread(@wasm_output)

    expected_exports = %w[
      sim_create sim_destroy sim_free_error sim_get_caps
      sim_signal sim_exec sim_trace sim_blob
      sim_wasm_alloc sim_wasm_dealloc
      runner_get_caps runner_mem runner_run runner_control runner_probe
    ]

    expected_exports.each do |fn|
      expect(wasm_bytes).to include(fn), "Missing export: #{fn}"
    end
  end

  it 'produces a loadable WASM that passes Node.js WebAssembly.compile' do
    compile_wasm

    # Use Node.js to validate the WASM is properly formed and instantiable
    node_script = <<~JS
      const fs = require('fs');
      async function main() {
        const wasm = fs.readFileSync(process.argv[2]);
        const module = await WebAssembly.compile(wasm);
        const exports = WebAssembly.Module.exports(module);
        const names = exports.filter(e => e.kind === 'function').map(e => e.name);

        const instance = await WebAssembly.instantiate(module, {});

        // Test basic API flow
        const ctx = instance.exports.sim_create(0, 0, 14, 0);
        if (!ctx) throw new Error('sim_create returned null');

        const kind = instance.exports.runner_probe(ctx, 0, 0);
        if (kind !== 1) throw new Error('runner_probe(KIND) expected 1, got ' + kind);

        instance.exports.sim_destroy(ctx);

        console.log(JSON.stringify({ ok: true, exports: names.length, kind: kind }));
      }
      main().catch(e => { console.error(e.message); process.exit(1); });
    JS

    script_path = File.join(@build_dir, 'validate.js')
    File.write(script_path, node_script)

    output = `node #{script_path} #{@wasm_output} 2>&1`
    expect($?).to be_success, "Node validation failed: #{output}"

    result = JSON.parse(output.lines.last)
    expect(result['ok']).to be true
    expect(result['exports']).to be >= 15
    expect(result['kind']).to eq(1) # RUNNER_KIND_APPLE2
  end

  it 'passes the runner_mem load/read round-trip via WASM' do
    compile_wasm

    node_script = <<~JS
      const fs = require('fs');
      async function main() {
        const wasm = fs.readFileSync(process.argv[2]);
        const result = await WebAssembly.instantiate(wasm, {});
        const { sim_create, sim_destroy, sim_wasm_alloc, runner_mem } = result.instance.exports;
        const mem = new Uint8Array(result.instance.exports.memory.buffer);

        const ctx = sim_create(0, 0, 14, 0);
        if (!ctx) throw new Error('sim_create returned null');

        // Write a test pattern to RAM via runner_mem LOAD
        const dataPtr = sim_wasm_alloc(256);
        for (let i = 0; i < 256; i++) mem[dataPtr + i] = i;
        const loaded = runner_mem(ctx, 0, 0, 0x100, dataPtr, 256, 0); // LOAD to MAIN at offset 0x100

        // Read back via runner_mem READ
        const readPtr = sim_wasm_alloc(256);
        const readCount = runner_mem(ctx, 1, 0, 0x100, readPtr, 256, 0); // READ from MAIN at offset 0x100

        let matches = 0;
        for (let i = 0; i < 256; i++) {
          if (mem[readPtr + i] === i) matches++;
        }

        sim_destroy(ctx);

        if (matches !== 256) throw new Error('Data mismatch: ' + matches + '/256 matched');
        console.log(JSON.stringify({ ok: true, loaded: loaded, read: readCount, matches: matches }));
      }
      main().catch(e => { console.error(e.message); process.exit(1); });
    JS

    script_path = File.join(@build_dir, 'mem_test.js')
    File.write(script_path, node_script)

    output = `node #{script_path} #{@wasm_output} 2>&1`
    expect($?).to be_success, "Memory round-trip test failed: #{output}"

    result = JSON.parse(output.lines.last)
    expect(result['ok']).to be true
    expect(result['loaded']).to eq(256)
    expect(result['read']).to eq(256)
    expect(result['matches']).to eq(256)
  end

  it 'correctly identifies signal count through sim_exec' do
    compile_wasm

    node_script = <<~JS
      const fs = require('fs');
      async function main() {
        const wasm = fs.readFileSync(process.argv[2]);
        const result = await WebAssembly.instantiate(wasm, {});
        const { sim_create, sim_destroy, sim_wasm_alloc, sim_exec } = result.instance.exports;
        const u32 = new Uint32Array(result.instance.exports.memory.buffer);

        const ctx = sim_create(0, 0, 14, 0);
        const outPtr = sim_wasm_alloc(4);
        sim_exec(ctx, 7, 0, 0, outPtr, 0); // SIGNAL_COUNT op
        const signalCount = u32[outPtr / 4];

        sim_exec(ctx, 0, 0, 0, outPtr, 0); // EVALUATE
        sim_exec(ctx, 1, 0, 0, outPtr, 0); // TICK

        sim_destroy(ctx);

        console.log(JSON.stringify({ ok: true, signalCount: signalCount }));
      }
      main().catch(e => { console.error(e.message); process.exit(1); });
    JS

    script_path = File.join(@build_dir, 'signal_test.js')
    File.write(script_path, node_script)

    output = `node #{script_path} #{@wasm_output} 2>&1`
    expect($?).to be_success, "Signal count test failed: #{output}"

    result = JSON.parse(output.lines.last)
    expect(result['ok']).to be true
    expect(result['signalCount']).to eq(offsets.count { |name, _| (mod::INPUT_SIGNALS + mod::OUTPUT_SIGNALS).include?(name) })
  end
end
