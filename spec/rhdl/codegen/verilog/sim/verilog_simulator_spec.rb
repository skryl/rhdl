# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../../lib/rhdl/codegen/verilog/sim/verilog_simulator'

RSpec.describe RHDL::Codegen::Verilog::VerilogSimulator do
  describe '#obj_dir' do
    it 'isolates obj_dir per library basename' do
      Dir.mktmpdir('rhdl_verilog_simulator') do |dir|
        sim_a = described_class.new(
          backend: :verilator,
          build_dir: dir,
          library_basename: 'gameboy_sim_a',
          top_module: 'gameboy',
          verilator_prefix: 'Vgameboy'
        )
        sim_b = described_class.new(
          backend: :verilator,
          build_dir: dir,
          library_basename: 'gameboy_sim_b',
          top_module: 'gameboy',
          verilator_prefix: 'Vgameboy'
        )

        expect(sim_a.obj_dir).not_to eq(sim_b.obj_dir)
        expect(sim_a.obj_dir).to end_with('/obj_dir/gameboy_sim_a')
        expect(sim_b.obj_dir).to end_with('/obj_dir/gameboy_sim_b')
      end
    end
  end

  describe '#shared_library_path' do
    it 'keeps the library inside the isolated obj_dir' do
      Dir.mktmpdir('rhdl_verilog_simulator') do |dir|
        simulator = described_class.new(
          backend: :verilator,
          build_dir: dir,
          library_basename: 'gameboy_sim_main',
          top_module: 'gameboy',
          verilator_prefix: 'Vgameboy'
        )

        expect(File.dirname(simulator.shared_library_path)).to end_with('/obj_dir/gameboy_sim_main')
        expect(File.basename(simulator.shared_library_path)).to match(/\Alibgameboy_sim_main\.(dylib|so|dll)\z/)
      end
    end
  end

  describe '#compile_verilator' do
    it 'adds the generated wrapper directory to the Verilator CFLAGS include path' do
      Dir.mktmpdir('rhdl_verilog_simulator') do |dir|
        simulator = described_class.new(
          backend: :verilator,
          build_dir: dir,
          library_basename: 'gameboy_sim_main',
          top_module: 'gameboy',
          verilator_prefix: 'Vgameboy'
        )
        simulator.prepare_build_dirs!

        wrapper_dir = File.join(dir, 'generated_wrapper')
        FileUtils.mkdir_p(wrapper_dir)
        wrapper_file = File.join(wrapper_dir, 'sim_wrapper.cpp')
        source_file = File.join(dir, 'gameboy.v')
        log_file = File.join(dir, 'build.log')
        File.write(wrapper_file, '// wrapper')
        File.write(source_file, 'module gameboy; endmodule')

        captured_verilate = nil
        allow(simulator).to receive(:system) do |*args, **kwargs|
          if args.first == 'verilator'
            captured_verilate = args
            true
          else
            true
          end
        end
        allow(simulator).to receive(:ensure_verilator_library_fresh).and_return(true)

        simulator.send(
          :compile_verilator,
          verilog_file: source_file,
          wrapper_file: wrapper_file,
          log_file: log_file
        )

        cflags_index = captured_verilate.index('-CFLAGS')
        expect(cflags_index).not_to be_nil
        expect(captured_verilate[cflags_index + 1]).to include("-I#{wrapper_dir}")
      end
    end
  end
end
