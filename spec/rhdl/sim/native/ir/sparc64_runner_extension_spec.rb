# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'

require_relative '../../../../../examples/sparc64/utilities/integration/import_loader'

module RHDL
  module SpecFixtures
    class Sparc64WishboneProbe < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      FLASH_ADDR = 0x0000_0003_FFFF_C000
      DRAM_ADDR = 0x0000_0000_0000_4000
      WRITE_DATA = 0x1122_3344_5566_7788
      WRITE_SEL = 0b1010_0101

      PHASE_READ_REQ = 0
      PHASE_READ_ACK = 1
      PHASE_WRITE_REQ = 2
      PHASE_WRITE_ACK = 3
      PHASE_DONE = 4

      input :sys_clock_i
      input :sys_reset_i
      input :eth_irq_i
      input :wbm_ack_i
      input :wbm_data_i, width: 64

      output :wbm_cycle_o
      output :wbm_strobe_o
      output :wbm_we_o
      output :wbm_addr_o, width: 64
      output :wbm_data_o, width: 64
      output :wbm_sel_o, width: 8
      output :phase, width: 3
      output :observed_read, width: 64

      behavior do
        read_request = local(:read_request, phase == lit(PHASE_READ_REQ, width: 3), width: 1)
        write_request = local(:write_request, phase == lit(PHASE_WRITE_REQ, width: 3), width: 1)
        active_request = local(:active_request, read_request | write_request, width: 1)

        wbm_cycle_o <= active_request
        wbm_strobe_o <= active_request
        wbm_we_o <= write_request
        wbm_addr_o <= mux(write_request, lit(DRAM_ADDR, width: 64), lit(FLASH_ADDR, width: 64))
        wbm_data_o <= mux(write_request, lit(WRITE_DATA, width: 64), lit(0, width: 64))
        wbm_sel_o <= mux(write_request, lit(WRITE_SEL, width: 8), lit(0xFF, width: 8))
      end

      sequential clock: :sys_clock_i, reset: :sys_reset_i, reset_values: { phase: PHASE_READ_REQ, observed_read: 0 } do
        next_phase = local(
          :next_phase,
          mux(
            phase == lit(PHASE_READ_REQ, width: 3),
            lit(PHASE_READ_ACK, width: 3),
            mux(
              phase == lit(PHASE_READ_ACK, width: 3),
              mux(wbm_ack_i, lit(PHASE_WRITE_REQ, width: 3), lit(PHASE_READ_ACK, width: 3)),
              mux(
                phase == lit(PHASE_WRITE_REQ, width: 3),
                lit(PHASE_WRITE_ACK, width: 3),
                mux(
                  phase == lit(PHASE_WRITE_ACK, width: 3),
                  mux(wbm_ack_i, lit(PHASE_DONE, width: 3), lit(PHASE_WRITE_ACK, width: 3)),
                  lit(PHASE_DONE, width: 3)
                )
              )
            )
          ),
          width: 3
        )

        phase <= next_phase
        observed_read <= mux(
          (phase == lit(PHASE_READ_ACK, width: 3)) & wbm_ack_i,
          wbm_data_i,
          observed_read
        )
      end
    end

    class Sparc64WishbonePartialReadProbe < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      FLASH_ADDR = Sparc64WishboneProbe::FLASH_ADDR

      input :sys_clock_i
      input :sys_reset_i
      input :eth_irq_i
      input :wbm_ack_i
      input :wbm_data_i, width: 64

      output :wbm_cycle_o
      output :wbm_strobe_o
      output :wbm_we_o
      output :wbm_addr_o, width: 64
      output :wbm_data_o, width: 64
      output :wbm_sel_o, width: 8
      output :done, width: 1
      output :observed_read, width: 64

      behavior do
        request_active = local(:request_active, done == lit(0, width: 1), width: 1)

        wbm_cycle_o <= request_active
        wbm_strobe_o <= request_active
        wbm_we_o <= lit(0, width: 1)
        wbm_addr_o <= lit(FLASH_ADDR, width: 64)
        wbm_data_o <= lit(0, width: 64)
        wbm_sel_o <= lit(0xF0, width: 8)
      end

      sequential clock: :sys_clock_i, reset: :sys_reset_i, reset_values: { done: 0, observed_read: 0 } do
        done <= mux(wbm_ack_i, lit(1, width: 1), done)
        observed_read <= mux(wbm_ack_i, wbm_data_i, observed_read)
      end
    end

    class Sparc64WishboneHighPhaseProbe < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      FLASH_ADDR = Sparc64WishboneProbe::FLASH_ADDR

      input :sys_clock_i
      input :sys_reset_i
      input :eth_irq_i
      input :wbm_ack_i
      input :wbm_data_i, width: 64

      output :wbm_cycle_o
      output :wbm_strobe_o
      output :wbm_we_o
      output :wbm_addr_o, width: 64
      output :wbm_data_o, width: 64
      output :wbm_sel_o, width: 8
      output :done, width: 1
      output :observed_read, width: 64

      behavior do
        request_active = local(
          :request_active,
          (done == lit(0, width: 1)) & sys_clock_i,
          width: 1
        )

        wbm_cycle_o <= request_active
        wbm_strobe_o <= request_active
        wbm_we_o <= lit(0, width: 1)
        wbm_addr_o <= lit(FLASH_ADDR, width: 64)
        wbm_data_o <= lit(0, width: 64)
        wbm_sel_o <= lit(0xFF, width: 8)
      end

      sequential clock: :sys_clock_i, reset: :sys_reset_i, reset_values: { done: 0, observed_read: 0 } do
        done <= mux(wbm_ack_i, lit(1, width: 1), done)
        observed_read <= mux(wbm_ack_i, wbm_data_i, observed_read)
      end
    end

    class Sparc64WishboneRepeatedHighPhaseReadProbe < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      FLASH_ADDR = Sparc64WishboneProbe::FLASH_ADDR

      input :sys_clock_i
      input :sys_reset_i
      input :eth_irq_i
      input :wbm_ack_i
      input :wbm_data_i, width: 64

      output :wbm_cycle_o
      output :wbm_strobe_o
      output :wbm_we_o
      output :wbm_addr_o, width: 64
      output :wbm_data_o, width: 64
      output :wbm_sel_o, width: 8
      output :ack_count, width: 3
      output :done, width: 1

      behavior do
        request_active = local(
          :request_active,
          (ack_count < lit(2, width: 3)) & sys_clock_i,
          width: 1
        )

        wbm_cycle_o <= request_active
        wbm_strobe_o <= request_active
        wbm_we_o <= lit(0, width: 1)
        wbm_addr_o <= lit(FLASH_ADDR, width: 64)
        wbm_data_o <= lit(0, width: 64)
        wbm_sel_o <= lit(0xF0, width: 8)
      end

      sequential clock: :sys_clock_i, reset: :sys_reset_i, reset_values: { ack_count: 0, done: 0 } do
        ack_count <= mux(wbm_ack_i, ack_count + lit(1, width: 3), ack_count)
        done <= mux(ack_count == lit(2, width: 3), lit(1, width: 1), done)
      end
    end

    class Sparc64WishboneInvertedPhaseReadProbe < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      FLASH_ADDR = Sparc64WishboneProbe::FLASH_ADDR

      input :sys_clock_i
      input :sys_reset_i
      input :eth_irq_i
      input :wbm_ack_i
      input :wbm_data_i, width: 64

      output :wbm_cycle_o
      output :wbm_strobe_o
      output :wbm_we_o
      output :wbm_addr_o, width: 64
      output :wbm_data_o, width: 64
      output :wbm_sel_o, width: 8
      output :done, width: 1
      output :observed_read, width: 64

      wire :inv_clock
      wire :issued, width: 1

      behavior do
        inv_clock <= (sys_clock_i ^ lit(1, width: 1))

        request_active = local(
          :request_active,
          issued & (done == lit(0, width: 1)),
          width: 1
        )

        wbm_cycle_o <= request_active
        wbm_strobe_o <= request_active
        wbm_we_o <= lit(0, width: 1)
        wbm_addr_o <= lit(FLASH_ADDR, width: 64)
        wbm_data_o <= lit(0, width: 64)
        wbm_sel_o <= lit(0xFF, width: 8)
      end

      sequential clock: :inv_clock, reset: :sys_reset_i, reset_values: { issued: 0, done: 0, observed_read: 0 } do
        issued <= lit(1, width: 1)
        done <= mux(wbm_ack_i, lit(1, width: 1), done)
        observed_read <= mux(wbm_ack_i, wbm_data_i, observed_read)
      end
    end
  end
end

RSpec.describe 'IR native SPARC64 runner extension' do
  FLASH_ADDR = RHDL::SpecFixtures::Sparc64WishboneProbe::FLASH_ADDR
  DRAM_ADDR = RHDL::SpecFixtures::Sparc64WishboneProbe::DRAM_ADDR
  FLASH_WORD = 0xDEAD_BEEF_FEED_FACE
  INITIAL_DRAM_BYTES = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22].freeze
  EXPECTED_DRAM_BYTES = [0x11, 0xBB, 0x33, 0xDD, 0xEE, 0x66, 0x11, 0x88].freeze

  def create_simulator(ir, backend:, skip_signal_widths: false, retain_ir_json: true)
    ir_json = RHDL::Sim::Native::IR.sim_json(ir, backend: backend)
    RHDL::Sim::Native::IR::Simulator.new(
      ir_json,
      backend: backend,
      skip_signal_widths: skip_signal_widths,
      retain_ir_json: retain_ir_json
    )
  end

  def backend_available?(backend)
    case backend
    when :compiler
      RHDL::Sim::Native::IR::COMPILER_AVAILABLE
    when :jit
      RHDL::Sim::Native::IR::JIT_AVAILABLE
    when :interpreter
      RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE
    else
      false
    end
  end

  def flash_bytes
    [0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED, 0xFA, 0xCE]
  end

  def sparc64_import_tree_available?
    Dir.exist?(RHDL::Examples::SPARC64::Integration::ImportLoader::DEFAULT_IMPORT_DIR)
  end

  def imported_runner_signature_json(component_class)
    ports = component_class.send(:_port_defs).map do |port|
      {
        name: port[:name].to_s,
        direction: port[:direction] == :in ? 'in' : 'out',
        width: port[:width],
        default: nil
      }
    end

    JSON.generate(
      circt_json_version: 1,
      dialects: %w[hw comb seq],
      modules: [
        {
          name: component_class.verilog_module_name,
          ports: ports,
          nets: [],
          regs: [],
          assigns: [],
          processes: [],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        }
      ]
    )
  end

  shared_examples 'sparc64 native runner backend' do
    before do
      skip "IR #{backend} not available" unless backend_available?(backend)
    end

    it 'detects imported S1Top as a native :sparc64 runner' do
      skip 'SPARC64 import tree not available' unless sparc64_import_tree_available?

      component_class = RHDL::Examples::SPARC64::Integration::ImportLoader.load_component_class(top: 'S1Top')
      sim = create_simulator(
        imported_runner_signature_json(component_class),
        backend: backend,
        skip_signal_widths: true,
        retain_ir_json: false
      )

      expect(sim.compiled?).to be(true) if backend == :compiler
      expect(sim.runner_kind).to eq(:sparc64)
    end

    it 'services sparse flash and dram through one-cycle wishbone acknowledgements' do
      sim = create_simulator(
        RHDL::SpecFixtures::Sparc64WishboneProbe.to_flat_circt_nodes(top_name: 'sparc64_wishbone_probe'),
        backend: backend
      )

      expect(sim.runner_kind).to eq(:sparc64)

      sim.runner_load_rom(flash_bytes, FLASH_ADDR)
      sim.runner_load_memory(INITIAL_DRAM_BYTES, DRAM_ADDR, false)

      expect(sim.runner_read_rom(FLASH_ADDR, 8)).to eq(flash_bytes)
      expect(sim.runner_read_memory(FLASH_ADDR, 8, mapped: true)).to eq(flash_bytes)
      expect(sim.runner_read_memory(DRAM_ADDR, 8, mapped: false)).to eq(INITIAL_DRAM_BYTES)

      sim.reset
      result = sim.runner_run_cycles(8)

      expect(result[:cycles_run]).to eq(8)
      expect(sim.peek('observed_read')).to eq(FLASH_WORD)
      expect(sim.peek('phase')).to eq(RHDL::SpecFixtures::Sparc64WishboneProbe::PHASE_DONE)
      expect(sim.runner_read_memory(DRAM_ADDR, 8, mapped: false)).to eq(EXPECTED_DRAM_BYTES)
      expect(sim.runner_sparc64_wishbone_trace).to eq(
        [
          {
            cycle: 5,
            op: :read,
            addr: FLASH_ADDR,
            sel: 0xFF,
            write_data: nil,
            read_data: FLASH_WORD
          },
          {
            cycle: 7,
            op: :write,
            addr: DRAM_ADDR,
            sel: RHDL::SpecFixtures::Sparc64WishboneProbe::WRITE_SEL,
            write_data: RHDL::SpecFixtures::Sparc64WishboneProbe::WRITE_DATA,
            read_data: nil
          }
        ]
      )
      expect(sim.runner_sparc64_unmapped_accesses).to eq([])

      sim.runner_write_memory(DRAM_ADDR + 8, [0x10, 0x20, 0x30, 0x40], mapped: false)
      expect(sim.runner_read_memory(DRAM_ADDR + 8, 4, mapped: false)).to eq([0x10, 0x20, 0x30, 0x40])
    end

    it 'returns the full 64-bit bus word for partial read selects' do
      sim = create_simulator(
        RHDL::SpecFixtures::Sparc64WishbonePartialReadProbe.to_flat_circt_nodes(
          top_name: 'sparc64_wishbone_partial_read_probe'
        ),
        backend: backend
      )

      sim.runner_load_rom(flash_bytes, FLASH_ADDR)
      sim.reset
      result = sim.runner_run_cycles(6)

      expect(result[:cycles_run]).to eq(6)
      expect(sim.peek('done')).to eq(1)
      expect(sim.peek('observed_read')).to eq(FLASH_WORD)
      expect(sim.runner_sparc64_wishbone_trace).to eq(
        [
          {
            cycle: 5,
            op: :read,
            addr: FLASH_ADDR,
            sel: 0xF0,
            write_data: nil,
            read_data: FLASH_WORD
          }
        ]
      )
      expect(sim.runner_sparc64_unmapped_accesses).to eq([])
    end

    it 'captures requests that first become visible after the rising edge' do
      sim = create_simulator(
        RHDL::SpecFixtures::Sparc64WishboneHighPhaseProbe.to_flat_circt_nodes(
          top_name: 'sparc64_wishbone_high_phase_probe'
        ),
        backend: backend
      )

      sim.runner_load_rom(flash_bytes, FLASH_ADDR)
      sim.reset
      result = sim.runner_run_cycles(7)

      expect(result[:cycles_run]).to eq(7)
      expect(sim.peek('done')).to eq(1)
      expect(sim.peek('observed_read')).to eq(FLASH_WORD)
      expect(sim.runner_sparc64_wishbone_trace).to eq(
        [
          {
            cycle: 6,
            op: :read,
            addr: FLASH_ADDR,
            sel: 0xFF,
            write_data: nil,
            read_data: FLASH_WORD
          }
        ]
      )
      expect(sim.runner_sparc64_unmapped_accesses).to eq([])
    end

    it 'does not drop repeated identical high-phase read requests' do
      sim = create_simulator(
        RHDL::SpecFixtures::Sparc64WishboneRepeatedHighPhaseReadProbe.to_flat_circt_nodes(
          top_name: 'sparc64_wishbone_repeated_high_phase_read_probe'
        ),
        backend: backend
      )

      sim.runner_load_rom(flash_bytes, FLASH_ADDR)
      sim.reset
      result = sim.runner_run_cycles(10)

      expect(result[:cycles_run]).to eq(10)
      expect(sim.peek('ack_count')).to eq(2)
      expect(sim.runner_sparc64_wishbone_trace).to eq(
        [
          {
            cycle: 6,
            op: :read,
            addr: FLASH_ADDR,
            sel: 0xF0,
            write_data: nil,
            read_data: FLASH_WORD
          },
          {
            cycle: 8,
            op: :read,
            addr: FLASH_ADDR,
            sel: 0xF0,
            write_data: nil,
            read_data: FLASH_WORD
          }
        ]
      )
      expect(sim.runner_sparc64_unmapped_accesses).to eq([])
    end

    it 'services requests driven from an internally inverted clock domain' do
      sim = create_simulator(
        RHDL::SpecFixtures::Sparc64WishboneInvertedPhaseReadProbe.to_flat_circt_nodes(
          top_name: 'sparc64_wishbone_inverted_phase_read_probe'
        ),
        backend: backend
      )

      sim.runner_load_rom(flash_bytes, FLASH_ADDR)
      sim.reset
      result = sim.runner_run_cycles(8)
      trace = sim.runner_sparc64_wishbone_trace

      expect(result[:cycles_run]).to eq(8)
      expect(sim.peek('done')).to eq(1)
      expect(sim.peek('observed_read')).to eq(FLASH_WORD)
      expect(trace.length).to eq(1)
      expect(trace.first).to include(
        op: :read,
        addr: FLASH_ADDR,
        sel: 0xFF,
        read_data: FLASH_WORD
      )
      expect(sim.runner_sparc64_unmapped_accesses).to eq([])
    end
  end

  {
    interpreter: :interpreter,
    jit: :jit,
    compiler: :compiler
  }.each_value do |backend|
    context "with #{backend} backend" do
      let(:backend) { backend }

      include_examples 'sparc64 native runner backend'
    end
  end
end
