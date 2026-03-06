# frozen_string_literal: true

require 'rhdl/codegen'
require_relative 'cpu_trace_package'

module RHDL
  module Examples
    module AO486
      module Import
        # Builds a parity-oriented imported AO486 CPU package.
        #
        # This helper is intentionally scoped to the CPU-top runtime parity
        # harness. It preserves the imported CPU top and imported pipeline
        # structure, adds stable retire-trace outputs, and replaces the imported
        # `l1_icache` behavior with a direct fetch model inside `icache`.
        #
        # The bypass is only valid for the parity harness configuration where
        # `cache_disable=1` is held high.
        module CpuParityPackage
          module_function

          def from_cleaned_mlir(mlir_text, top: 'ao486', strict: false)
            imported = RHDL::Codegen.import_circt_mlir(mlir_text, strict: strict, top: top)
            return CpuTracePackage.failure_from_import(imported) unless imported.success?

            modules = Array(imported.modules).map { |mod| CpuTracePackage.dup_module(mod) }
            patch_icache_bypass!(modules)

            package = CpuTracePackage.build_from_modules(modules)

            {
              success: true,
              package: package,
              mlir: RHDL::Codegen::CIRCT::MLIR.generate(package),
              diagnostics: []
            }
          rescue StandardError => e
            {
              success: false,
              package: nil,
              mlir: nil,
              diagnostics: [e.message]
            }
          end

          def patch_icache_bypass!(modules)
            mod = CpuTracePackage.find_module!(modules, 'icache')
            inst = CpuTracePackage.find_instance!(mod, 'l1_icache_inst')

            cpu_valid_name = output_signal_name!(inst, 'CPU_VALID')
            cpu_done_name = output_signal_name!(inst, 'CPU_DONE')
            cpu_data_name = output_signal_name!(inst, 'CPU_DATA')
            mem_req_name = output_signal_name!(inst, 'MEM_REQ')
            mem_addr_name = output_signal_name!(inst, 'MEM_ADDR')

            cpu_req_expr = connection_expr!(inst, 'CPU_REQ')
            cpu_addr_expr = connection_expr!(inst, 'CPU_ADDR')
            prefetched_length_expr = assign_expr!(mod, 'prefetched_length')

            mod.instances.reject! { |entry| entry.name.to_s == 'l1_icache_inst' }
            mod.assigns << CpuTracePackage.assign(mem_req_name, cpu_req_expr)
            mod.assigns << CpuTracePackage.assign(mem_addr_name, cpu_addr_expr)
            mod.assigns << CpuTracePackage.assign(cpu_valid_name, CpuTracePackage.signal('readcode_done', 1))
            mod.assigns << CpuTracePackage.assign(cpu_data_name, CpuTracePackage.signal('readcode_partial', 32))
            mod.assigns << CpuTracePackage.assign(
              cpu_done_name,
              CpuTracePackage.binop(
                :&,
                CpuTracePackage.signal('readcode_done', 1),
                CpuTracePackage.binop(
                  :<=,
                  CpuTracePackage.signal('v9_5', 5),
                  prefetched_length_expr,
                  1
                ),
                1
              )
            )
          end

          def output_signal_name!(inst, port_name)
            conn = inst.connections.find do |entry|
              entry.direction.to_s == 'out' && entry.port_name.to_s == port_name.to_s
            end
            raise KeyError, "Output connection '#{port_name}' not found on instance '#{inst.name}'" unless conn

            conn.signal.to_s
          end

          def connection_expr!(inst, port_name)
            conn = inst.connections.find { |entry| entry.port_name.to_s == port_name.to_s }
            raise KeyError, "Connection '#{port_name}' not found on instance '#{inst.name}'" unless conn

            case conn.signal
            when RHDL::Codegen::CIRCT::IR::Expr
              conn.signal
            else
              CpuTracePackage.signal(conn.signal.to_s, conn.width || 1)
            end
          end

          def assign_expr!(mod, target)
            assign = mod.assigns.find { |entry| entry.target.to_s == target.to_s }
            raise KeyError, "Assign target '#{target}' not found in module '#{mod.name}'" unless assign

            assign.expr
          end
        end
      end
    end
  end
end
