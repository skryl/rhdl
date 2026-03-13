# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'

module RHDL
  module SpecFixtures
    class Sparc64AdditionalBackendsWishboneProbe < RHDL::HDL::SequentialComponent
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

RSpec.describe 'SPARC64 runner extension on additional native IR backends' do
  FLASH_ADDR = RHDL::SpecFixtures::Sparc64AdditionalBackendsWishboneProbe::FLASH_ADDR
  DRAM_ADDR = RHDL::SpecFixtures::Sparc64AdditionalBackendsWishboneProbe::DRAM_ADDR
  FLASH_WORD = 0xDEAD_BEEF_FEED_FACE
  INITIAL_DRAM_BYTES = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22].freeze
  EXPECTED_DRAM_BYTES = [0x11, 0xBB, 0x33, 0xDD, 0xEE, 0x66, 0x11, 0x88].freeze

  def create_native_sim(ir, backend:)
    ir_json = RHDL::Sim::Native::IR.sim_json(ir, backend: backend)
    RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: backend)
  end

  def flash_bytes
    [0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED, 0xFA, 0xCE]
  end

  {
    interpreter: [:INTERPRETER_AVAILABLE, 'IR Interpreter'],
    jit: [:JIT_AVAILABLE, 'IR JIT']
  }.each do |backend, (availability_const, label)|
    context backend do
      before do
        skip "#{label} not available" unless RHDL::Sim::Native::IR.const_get(availability_const)
      end

      it 'detects :sparc64 and services wishbone-backed flash/dram accesses' do
        sim = create_native_sim(
          RHDL::SpecFixtures::Sparc64AdditionalBackendsWishboneProbe.to_flat_circt_nodes(
            top_name: "sparc64_additional_backends_#{backend}_probe"
          ),
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
        expect(sim.peek('phase')).to eq(RHDL::SpecFixtures::Sparc64AdditionalBackendsWishboneProbe::PHASE_DONE)
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
              sel: RHDL::SpecFixtures::Sparc64AdditionalBackendsWishboneProbe::WRITE_SEL,
              write_data: RHDL::SpecFixtures::Sparc64AdditionalBackendsWishboneProbe::WRITE_DATA,
              read_data: nil
            }
          ]
        )
        expect(sim.runner_sparc64_unmapped_accesses).to eq([])
      end
    end
  end
end
