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
  end
end

RSpec.describe 'IR compiler SPARC64 runner extension' do
  FLASH_ADDR = RHDL::SpecFixtures::Sparc64WishboneProbe::FLASH_ADDR
  DRAM_ADDR = RHDL::SpecFixtures::Sparc64WishboneProbe::DRAM_ADDR
  FLASH_WORD = 0xDEAD_BEEF_FEED_FACE
  INITIAL_DRAM_BYTES = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22].freeze
  EXPECTED_DRAM_BYTES = [0x11, 0xBB, 0x33, 0xDD, 0xEE, 0x66, 0x11, 0x88].freeze

  def create_compiler(ir, skip_signal_widths: false, retain_ir_json: true)
    ir_json = RHDL::Sim::Native::IR.sim_json(ir, backend: :compiler)
    RHDL::Sim::Native::IR::Simulator.new(
      ir_json,
      backend: :compiler,
      skip_signal_widths: skip_signal_widths,
      retain_ir_json: retain_ir_json
    )
  end

  def flash_bytes
    [0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED, 0xFA, 0xCE]
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

  before do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  it 'detects imported S1Top as a native :sparc64 runner' do
    component_class = RHDL::Examples::SPARC64::Integration::ImportLoader.load_component_class(top: 'S1Top')
    sim = create_compiler(imported_runner_signature_json(component_class), skip_signal_widths: true, retain_ir_json: false)

    expect(sim.compiled?).to be(true)
    expect(sim.runner_kind).to eq(:sparc64)
  end

  it 'services sparse flash and dram through one-cycle wishbone acknowledgements' do
    sim = create_compiler(
      RHDL::SpecFixtures::Sparc64WishboneProbe.to_flat_circt_nodes(top_name: 'sparc64_wishbone_probe')
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
end
