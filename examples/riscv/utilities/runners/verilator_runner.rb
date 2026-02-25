# frozen_string_literal: true

# RV32I Verilator Runner - Native RTL simulation via Verilator
#
# Exports the single-cycle CPU to Verilog, compiles with Verilator, and drives
# via Fiddle FFI with batched C++ cycle execution.

require 'rhdl/codegen'
require_relative 'runner'
require_relative '../../hdl/cpu'

module RHDL
  module Examples
    module RISCV
      class VerilogRunner < Runner
        BUILD_BASE = File.expand_path('../../.hdl_build', __dir__)

        def initialize(mem_size: Memory::DEFAULT_SIZE)
          super(backend_sym: :verilator, simulator_type_sym: :hdl_verilator, mem_size: mem_size)
        end

        private

        def check_tools_available!
          raise LoadError, 'verilator not found in PATH' unless command_available?('verilator')
        end

        def build_dir
          @build_dir ||= File.join(BUILD_BASE, 'verilator')
        end

        def build_simulation
          FileUtils.mkdir_p(build_dir)

          verilog_dir = File.join(build_dir, 'verilog')
          obj_dir = File.join(build_dir, 'obj_dir')
          FileUtils.mkdir_p(verilog_dir)
          FileUtils.mkdir_p(obj_dir)

          verilog_file = File.join(verilog_dir, 'riscv_cpu.v')
          wrapper_file = File.join(verilog_dir, 'sim_wrapper.cpp')
          header_file = File.join(verilog_dir, 'sim_wrapper.h')

          cpu_source = File.expand_path('../../hdl/cpu.rb', __dir__)
          export_deps = [__FILE__, cpu_source].select { |p| File.exist?(p) }
          needs_export = !File.exist?(verilog_file) ||
                         export_deps.any? { |p| File.mtime(p) > File.mtime(verilog_file) }

          if needs_export
            puts '  Exporting RISC-V CPU to Verilog...'
            verilog_code = CPU.to_verilog_hierarchy
            File.write(verilog_file, verilog_code)
          end

          write_verilator_wrapper(wrapper_file, header_file)

          @verilog_simulator = RHDL::Codegen::Verilog::VerilogSimulator.new(
            backend: :verilator,
            build_dir: build_dir,
            library_basename: 'riscv_sim',
            top_module: 'riscv_cpu',
            verilator_prefix: 'Vriscv',
            x_assign: '0',
            x_initial: 'unique'
          )

          lib_file = @verilog_simulator.shared_library_path
          needs_build = !File.exist?(lib_file) ||
                        File.mtime(verilog_file) > File.mtime(lib_file) ||
                        File.mtime(wrapper_file) > File.mtime(lib_file) ||
                        File.mtime(__FILE__) > File.mtime(lib_file)

          if needs_build
            puts '  Compiling with Verilator...'
            @verilog_simulator.compile_backend(verilog_file: verilog_file, wrapper_file: wrapper_file)
          end

          @lib_path = lib_file
        end

        def write_verilator_wrapper(cpp_file, header_file)
          header = <<~H
            #ifndef SIM_WRAPPER_H
            #define SIM_WRAPPER_H
            #ifdef __cplusplus
            extern "C" {
            #endif
            void* sim_create(unsigned int mem_size);
            void sim_destroy(void* sim);
            void sim_reset(void* sim);
            void sim_eval(void* sim);
            void sim_poke(void* sim, const char* name, unsigned int value);
            unsigned int sim_peek(void* sim, const char* name);
            void sim_write_pc(void* sim, unsigned int value);
            void sim_load_mem(void* sim, int mem_type, const unsigned char* data, unsigned int size, unsigned int base_addr);
            void sim_run_cycles(void* sim, unsigned int n_cycles);
            #ifdef __cplusplus
            }
            #endif
            #endif
          H

          cpp = <<~CPP
            #include "Vriscv.h"
            #include "Vriscv___024root.h"
            #include "verilated.h"
            #include "sim_wrapper.h"
            #include <cstring>
            #include <cstdlib>

            double sc_time_stamp() { return 0; }

            #{riscv_sim_common_types}

            struct SimContext {
                Vriscv* dut;
                MemState mem;
            };

            // Verilator DUT port access macros (lvalue-capable via struct members)
            #define CTX(c) (static_cast<SimContext*>(c))
            #define DUT_CLK(c)                (CTX(c)->dut->clk)
            #define DUT_RST(c)                (CTX(c)->dut->rst)
            #define DUT_IRQ_SOFTWARE(c)       (CTX(c)->dut->irq_software)
            #define DUT_IRQ_TIMER(c)          (CTX(c)->dut->irq_timer)
            #define DUT_IRQ_EXTERNAL(c)       (CTX(c)->dut->irq_external)
            #define DUT_INST_DATA(c)          (CTX(c)->dut->inst_data)
            #define DUT_DATA_RDATA(c)         (CTX(c)->dut->data_rdata)
            #define DUT_DEBUG_REG_ADDR(c)     (CTX(c)->dut->debug_reg_addr)
            #define DUT_INST_PTW_PTE0(c)      (CTX(c)->dut->inst_ptw_pte0)
            #define DUT_INST_PTW_PTE1(c)      (CTX(c)->dut->inst_ptw_pte1)
            #define DUT_DATA_PTW_PTE0(c)      (CTX(c)->dut->data_ptw_pte0)
            #define DUT_DATA_PTW_PTE1(c)      (CTX(c)->dut->data_ptw_pte1)
            #define DUT_INST_ADDR(c)          (CTX(c)->dut->inst_addr)
            #define DUT_INST_PTW_ADDR0(c)     (CTX(c)->dut->inst_ptw_addr0)
            #define DUT_INST_PTW_ADDR1(c)     (CTX(c)->dut->inst_ptw_addr1)
            #define DUT_DATA_ADDR(c)          (CTX(c)->dut->data_addr)
            #define DUT_DATA_WDATA(c)         (CTX(c)->dut->data_wdata)
            #define DUT_DATA_WE(c)            (CTX(c)->dut->data_we)
            #define DUT_DATA_RE(c)            (CTX(c)->dut->data_re)
            #define DUT_DATA_FUNCT3(c)        (CTX(c)->dut->data_funct3)
            #define DUT_DATA_PTW_ADDR0(c)     (CTX(c)->dut->data_ptw_addr0)
            #define DUT_DATA_PTW_ADDR1(c)     (CTX(c)->dut->data_ptw_addr1)
            #define DUT_DEBUG_PC(c)           (CTX(c)->dut->debug_pc)
            #define DUT_EVAL(c)               (CTX(c)->dut->eval())

            #{riscv_sim_run_cycles_impl}

            extern "C" {

            void* sim_create(unsigned int mem_size) {
                const char* empty_args[] = {""};
                Verilated::commandArgs(1, empty_args);
                SimContext* ctx = new SimContext();
                ctx->dut = new Vriscv();
                mem_init(&ctx->mem, mem_size);
                ctx->dut->clk = 0;
                ctx->dut->rst = 1;
                ctx->dut->irq_software = 0;
                ctx->dut->irq_timer = 0;
                ctx->dut->irq_external = 0;
                ctx->dut->inst_data = 0;
                ctx->dut->data_rdata = 0;
                ctx->dut->debug_reg_addr = 0;
                ctx->dut->inst_ptw_pte0 = 0;
                ctx->dut->inst_ptw_pte1 = 0;
                ctx->dut->data_ptw_pte0 = 0;
                ctx->dut->data_ptw_pte1 = 0;
                ctx->dut->eval();
                return ctx;
            }

            void sim_destroy(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                mem_free(&ctx->mem);
                delete ctx->dut;
                delete ctx;
            }

            void sim_reset(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                ctx->dut->rst = 1;
                ctx->dut->clk = 0;
                ctx->dut->eval();
                ctx->dut->clk = 1;
                ctx->dut->eval();
                ctx->dut->clk = 0;
                ctx->dut->rst = 0;
                ctx->dut->eval();
            }

            void sim_eval(void* sim) {
                static_cast<SimContext*>(sim)->dut->eval();
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if      (!strcmp(name, "clk"))             ctx->dut->clk = value;
                else if (!strcmp(name, "rst"))             ctx->dut->rst = value;
                else if (!strcmp(name, "irq_software"))    ctx->dut->irq_software = value;
                else if (!strcmp(name, "irq_timer"))       ctx->dut->irq_timer = value;
                else if (!strcmp(name, "irq_external"))    ctx->dut->irq_external = value;
                else if (!strcmp(name, "inst_data"))       ctx->dut->inst_data = value;
                else if (!strcmp(name, "data_rdata"))      ctx->dut->data_rdata = value;
                else if (!strcmp(name, "debug_reg_addr"))  ctx->dut->debug_reg_addr = value;
                else if (!strcmp(name, "inst_ptw_pte0"))   ctx->dut->inst_ptw_pte0 = value;
                else if (!strcmp(name, "inst_ptw_pte1"))   ctx->dut->inst_ptw_pte1 = value;
                else if (!strcmp(name, "data_ptw_pte0"))   ctx->dut->data_ptw_pte0 = value;
                else if (!strcmp(name, "data_ptw_pte1"))   ctx->dut->data_ptw_pte1 = value;
            }

            unsigned int sim_peek(void* sim, const char* name) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if      (!strcmp(name, "inst_addr"))       return ctx->dut->inst_addr;
                else if (!strcmp(name, "inst_ptw_addr0"))  return ctx->dut->inst_ptw_addr0;
                else if (!strcmp(name, "inst_ptw_addr1"))  return ctx->dut->inst_ptw_addr1;
                else if (!strcmp(name, "data_addr"))       return ctx->dut->data_addr;
                else if (!strcmp(name, "data_wdata"))      return ctx->dut->data_wdata;
                else if (!strcmp(name, "data_we"))         return ctx->dut->data_we;
                else if (!strcmp(name, "data_re"))         return ctx->dut->data_re;
                else if (!strcmp(name, "data_funct3"))     return ctx->dut->data_funct3;
                else if (!strcmp(name, "data_ptw_addr0"))  return ctx->dut->data_ptw_addr0;
                else if (!strcmp(name, "data_ptw_addr1"))  return ctx->dut->data_ptw_addr1;
                else if (!strcmp(name, "debug_pc"))        return ctx->dut->debug_pc;
                else if (!strcmp(name, "debug_inst"))      return ctx->dut->debug_inst;
                else if (!strcmp(name, "debug_x1"))        return ctx->dut->debug_x1;
                else if (!strcmp(name, "debug_x2"))        return ctx->dut->debug_x2;
                else if (!strcmp(name, "debug_x10"))       return ctx->dut->debug_x10;
                else if (!strcmp(name, "debug_x11"))       return ctx->dut->debug_x11;
                else if (!strcmp(name, "debug_reg_data"))  return ctx->dut->debug_reg_data;
                return 0;
            }

            void sim_write_pc(void* sim, unsigned int value) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                ctx->dut->rootp->riscv_cpu__DOT__pc_reg___05Fpc = value;
                ctx->dut->eval();
            }

            void sim_load_mem(void* sim, int mem_type, const unsigned char* data, unsigned int size, unsigned int base_addr) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                load_mem(&ctx->mem, mem_type, data, size, base_addr);
            }

            void sim_run_cycles(void* sim, unsigned int n_cycles) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                run_cycles_impl(ctx, &ctx->mem, n_cycles);
            }

            } // extern "C"
          CPP

          write_file_if_changed(header_file, header)
          write_file_if_changed(cpp_file, cpp)
        end
      end
    end
  end
end
