# frozen_string_literal: true

require 'rhdl/codegen'
require_relative '../../../../lib/rhdl/codegen/circt/mlir'

module RHDL
  module Examples
    module AO486
      module Import
        # Adds stable retire-trace ports to the imported AO486 CPU package.
        #
        # The transform stays on canonical CIRCT IR: it imports the cleaned
        # package, exposes the write-stage retire event from `write`, carries
        # that up through `pipeline`, and finally publishes the trace outputs on
        # the `ao486` top.
        module CpuTracePackage
          WRITE_TRACE_PORTS = {
            trace_wr_finished: 1,
            trace_wr_ready: 1,
            trace_wr_hlt_in_progress: 1
          }.freeze

          TRACE_PORTS = {
            trace_retired: 1,
            trace_wr_finished: 1,
            trace_wr_ready: 1,
            trace_wr_hlt_in_progress: 1,
            trace_wr_eip: 32,
            trace_wr_consumed: 4,
            trace_cs_cache: 64,
            trace_cs_cache_valid: 1
          }.freeze

          module_function

          def from_cleaned_mlir(mlir_text, top: 'ao486', strict: false)
            imported = RHDL::Codegen.import_circt_mlir(mlir_text, strict: strict, top: top)
            return failure_from_import(imported) unless imported.success?

            package = build_from_modules(imported.modules)

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

          def build_from_modules(modules)
            updated = Array(modules).map { |mod| dup_module(mod) }

            patch_write_module!(updated)
            patch_pipeline_module!(updated)
            patch_top_module!(updated)

            RHDL::Codegen::CIRCT::IR::Package.new(modules: updated)
          end

          def failure_from_import(imported)
            diagnostics = Array(imported.diagnostics).map do |diag|
              if diag.respond_to?(:severity) && diag.respond_to?(:message)
                "[#{diag.severity}]#{diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''} #{diag.message}"
              else
                diag.to_s
              end
            end
            {
              success: false,
              package: nil,
              mlir: nil,
              diagnostics: diagnostics
            }
          end

          def patch_write_module!(modules)
            mod = find_module!(modules, 'write')
            write_commands = find_instance!(mod, 'write_commands_inst')
            write_debug = find_instance!(mod, 'write_debug_inst')

            ready_expr = connection_signal!(write_commands, 'wr_ready')
            hlt_signal = connection_signal!(write_commands, 'wr_hlt_in_progress')
            finished_expr = connection_signal!(write_debug, 'wr_finished')

            WRITE_TRACE_PORTS.each do |name, width|
              mod.ports << port(name, width)
            end
            mod.assigns << assign('trace_wr_finished', finished_expr)
            mod.assigns << assign('trace_wr_ready', ready_expr)
            mod.assigns << assign('trace_wr_hlt_in_progress', hlt_signal)
          end

          def patch_pipeline_module!(modules)
            mod = find_module!(modules, 'pipeline')
            write_inst = find_instance!(mod, 'write_inst')

            write_inst.connections << out_conn(:trace_wr_finished, 'write_inst_trace_wr_finished_1')
            write_inst.connections << out_conn(:trace_wr_ready, 'write_inst_trace_wr_ready_1')
            write_inst.connections << out_conn(:trace_wr_hlt_in_progress, 'write_inst_trace_wr_hlt_in_progress_1')

            retired_expr = binop(
              :|,
              signal('write_inst_trace_wr_finished_1', 1),
              binop(
                :&,
                signal('write_inst_trace_wr_ready_1', 1),
                signal('write_inst_trace_wr_hlt_in_progress_1', 1),
                1
              ),
              1
            )

            mod.ports << port(:trace_retired, 1)
            mod.ports << port(:trace_wr_finished, 1)
            mod.ports << port(:trace_wr_ready, 1)
            mod.ports << port(:trace_wr_hlt_in_progress, 1)
            mod.ports << port(:trace_cs_cache_valid, 1)
            mod.assigns << assign('trace_retired', retired_expr)
            mod.assigns << assign('trace_wr_finished', signal('write_inst_trace_wr_finished_1', 1))
            mod.assigns << assign('trace_wr_ready', signal('write_inst_trace_wr_ready_1', 1))
            mod.assigns << assign('trace_wr_hlt_in_progress', signal('write_inst_trace_wr_hlt_in_progress_1', 1))
            mod.assigns << assign('trace_cs_cache_valid', signal('write_inst_cs_cache_valid_1', 1))
          end

          def patch_top_module!(modules)
            mod = find_module!(modules, 'ao486')
            pipeline_inst = find_instance!(mod, 'pipeline_inst')

            pipeline_inst.connections << out_conn(:trace_retired, 'pipeline_inst_trace_retired_1')
            pipeline_inst.connections << out_conn(:trace_wr_finished, 'pipeline_inst_trace_wr_finished_1')
            pipeline_inst.connections << out_conn(:trace_wr_ready, 'pipeline_inst_trace_wr_ready_1')
            pipeline_inst.connections << out_conn(:trace_wr_hlt_in_progress, 'pipeline_inst_trace_wr_hlt_in_progress_1')
            pipeline_inst.connections << out_conn(:trace_cs_cache_valid, 'pipeline_inst_cs_cache_valid_1')

            TRACE_PORTS.each do |name, width|
              mod.ports << port(name, width)
            end

            mod.assigns << assign('trace_retired', signal('pipeline_inst_trace_retired_1', 1))
            mod.assigns << assign('trace_wr_finished', signal('pipeline_inst_trace_wr_finished_1', 1))
            mod.assigns << assign('trace_wr_ready', signal('pipeline_inst_trace_wr_ready_1', 1))
            mod.assigns << assign('trace_wr_hlt_in_progress', signal('pipeline_inst_trace_wr_hlt_in_progress_1', 1))
            mod.assigns << assign('trace_wr_eip', signal('pipeline_inst_wr_eip_32', 32))
            mod.assigns << assign('trace_wr_consumed', signal('pipeline_inst_wr_consumed_4', 4))
            mod.assigns << assign('trace_cs_cache', signal('pipeline_inst_cs_cache_64', 64))
            mod.assigns << assign('trace_cs_cache_valid', signal('pipeline_inst_cs_cache_valid_1', 1))
          end

          def find_module!(modules, name)
            Array(modules).find { |mod| mod.name.to_s == name.to_s } ||
              raise(KeyError, "CIRCT module '#{name}' not found")
          end

          def find_instance!(mod, name)
            mod.instances.find { |inst| inst.name.to_s == name.to_s } ||
              raise(KeyError, "Instance '#{name}' not found in module '#{mod.name}'")
          end

          def connection_signal!(inst, port_name)
            conn = inst.connections.find { |entry| entry.port_name.to_s == port_name.to_s }
            raise KeyError, "Connection '#{port_name}' not found on instance '#{inst.name}'" unless conn

            expr_for_connection(conn.signal, width: conn.width || 1)
          end

          def dup_module(mod)
            ir = RHDL::Codegen::CIRCT::IR
            ir::ModuleOp.new(
              name: mod.name,
              ports: mod.ports.dup,
              nets: mod.nets.dup,
              regs: mod.regs.dup,
              assigns: mod.assigns.dup,
              processes: mod.processes.dup,
              instances: mod.instances.map { |inst| dup_instance(inst) },
              memories: mod.memories.dup,
              write_ports: mod.write_ports.dup,
              sync_read_ports: mod.sync_read_ports.dup,
              parameters: mod.parameters || {}
            )
          end

          def dup_instance(inst)
            ir = RHDL::Codegen::CIRCT::IR
            ir::Instance.new(
              name: inst.name,
              module_name: inst.module_name,
              connections: inst.connections.map { |conn| dup_conn(conn) },
              parameters: inst.parameters || {}
            )
          end

          def dup_conn(conn)
            ir = RHDL::Codegen::CIRCT::IR
            ir::PortConnection.new(
              port_name: conn.port_name,
              signal: conn.signal,
              direction: conn.direction,
              width: conn.width
            )
          end

          def port(name, width)
            RHDL::Codegen::CIRCT::IR::Port.new(name: name, direction: :out, width: width)
          end

          def signal(name, width)
            RHDL::Codegen::CIRCT::IR::Signal.new(name: name, width: width)
          end

          def expr_for_connection(signal_or_expr, width:)
            case signal_or_expr
            when RHDL::Codegen::CIRCT::IR::Expr
              signal_or_expr
            else
              signal(signal_or_expr.to_s, width)
            end
          end

          def assign(target, expr)
            RHDL::Codegen::CIRCT::IR::Assign.new(target: target, expr: expr)
          end

          def out_conn(port_name, signal_name)
            RHDL::Codegen::CIRCT::IR::PortConnection.new(
              port_name: port_name,
              signal: signal_name,
              direction: :out
            )
          end

          def binop(op, left, right, width)
            RHDL::Codegen::CIRCT::IR::BinaryOp.new(
              op: op,
              left: left,
              right: right,
              width: width
            )
          end
        end
      end
    end
  end
end
