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
            trace_cs_cache_valid: 1,
            trace_prefetch_eip: 32,
            trace_fetch_valid: 4,
            trace_fetch_bytes: 64,
            trace_dec_acceptable: 4,
            trace_fetch_accept_length: 4,
            trace_prefetchfifo_accept_empty: 1,
            trace_prefetchfifo_accept_do: 1,
            trace_arch_new_export: 1,
            trace_arch_eax: 32,
            trace_arch_ebx: 32,
            trace_arch_ecx: 32,
            trace_arch_edx: 32,
            trace_arch_esi: 32,
            trace_arch_edi: 32,
            trace_arch_esp: 32,
            trace_arch_ebp: 32,
            trace_arch_eip: 32
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
            execute_inst = find_instance!(mod, 'execute_inst')
            fetch_inst = find_instance!(mod, 'fetch_inst')
            decode_inst = find_instance!(mod, 'decode_inst')
            write_inst = find_instance!(mod, 'write_inst')

            ensure_net(mod, 'write_inst_trace_wr_finished_1', 1)
            ensure_net(mod, 'write_inst_trace_wr_ready_1', 1)
            ensure_net(mod, 'write_inst_trace_wr_hlt_in_progress_1', 1)

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
            mod.ports << port(:trace_prefetch_eip, 32)
            mod.ports << port(:trace_fetch_valid, 4)
            mod.ports << port(:trace_fetch_bytes, 64)
            mod.ports << port(:trace_dec_acceptable, 4)
            mod.ports << port(:trace_fetch_accept_length, 4)
            mod.ports << port(:trace_arch_new_export, 1)
            mod.ports << port(:trace_arch_eax, 32)
            mod.ports << port(:trace_arch_ebx, 32)
            mod.ports << port(:trace_arch_ecx, 32)
            mod.ports << port(:trace_arch_edx, 32)
            mod.ports << port(:trace_arch_esi, 32)
            mod.ports << port(:trace_arch_edi, 32)
            mod.ports << port(:trace_arch_esp, 32)
            mod.ports << port(:trace_arch_ebp, 32)
            mod.ports << port(:trace_arch_eip, 32)
            mod.assigns << assign('trace_retired', retired_expr)
            mod.assigns << assign('trace_wr_finished', signal('write_inst_trace_wr_finished_1', 1))
            mod.assigns << assign('trace_wr_ready', signal('write_inst_trace_wr_ready_1', 1))
            mod.assigns << assign('trace_wr_hlt_in_progress', signal('write_inst_trace_wr_hlt_in_progress_1', 1))
            mod.assigns << assign('trace_cs_cache_valid', connection_signal!(write_inst, 'cs_cache_valid'))
            mod.assigns << assign('trace_prefetch_eip', connection_signal!(fetch_inst, 'prefetch_eip'))
            mod.assigns << assign('trace_fetch_valid', connection_signal!(fetch_inst, 'fetch_valid'))
            mod.assigns << assign('trace_fetch_bytes', connection_signal!(fetch_inst, 'fetch'))
            mod.assigns << assign('trace_dec_acceptable', connection_signal!(decode_inst, 'dec_acceptable'))
            mod.assigns << assign(
              'trace_fetch_accept_length',
              min_expr(connection_signal!(fetch_inst, 'fetch_valid'), connection_signal!(decode_inst, 'dec_acceptable'), 4)
            )
            mod.assigns << assign('trace_arch_new_export', connection_signal!(execute_inst, 'exe_ready'))
            mod.assigns << assign('trace_arch_eax', connection_signal!(write_inst, 'eax'))
            mod.assigns << assign('trace_arch_ebx', connection_signal!(write_inst, 'ebx'))
            mod.assigns << assign('trace_arch_ecx', connection_signal!(write_inst, 'ecx'))
            mod.assigns << assign('trace_arch_edx', connection_signal!(write_inst, 'edx'))
            mod.assigns << assign('trace_arch_esi', connection_signal!(write_inst, 'esi'))
            mod.assigns << assign('trace_arch_edi', connection_signal!(write_inst, 'edi'))
            mod.assigns << assign('trace_arch_esp', connection_signal!(write_inst, 'esp'))
            mod.assigns << assign('trace_arch_ebp', connection_signal!(write_inst, 'ebp'))
            mod.assigns << assign('trace_arch_eip', connection_signal!(decode_inst, 'eip'))
          end

          def patch_top_module!(modules)
            mod = find_module!(modules, 'ao486')
            memory_inst = find_instance!(mod, 'memory_inst')
            pipeline_inst = find_instance!(mod, 'pipeline_inst')

            ensure_net(mod, 'pipeline_inst_trace_retired_1', 1)
            ensure_net(mod, 'pipeline_inst_trace_wr_finished_1', 1)
            ensure_net(mod, 'pipeline_inst_trace_wr_ready_1', 1)
            ensure_net(mod, 'pipeline_inst_trace_wr_hlt_in_progress_1', 1)
            ensure_net(mod, 'pipeline_inst_cs_cache_valid_1', 1)
            ensure_net(mod, 'pipeline_inst_trace_prefetch_eip_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_fetch_valid_4', 4)
            ensure_net(mod, 'pipeline_inst_trace_fetch_bytes_64', 64)
            ensure_net(mod, 'pipeline_inst_trace_dec_acceptable_4', 4)
            ensure_net(mod, 'pipeline_inst_trace_fetch_accept_length_4', 4)
            ensure_net(mod, 'pipeline_inst_trace_arch_new_export_1', 1)
            ensure_net(mod, 'pipeline_inst_trace_arch_eax_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_ebx_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_ecx_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_edx_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_esi_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_edi_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_esp_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_ebp_32', 32)
            ensure_net(mod, 'pipeline_inst_trace_arch_eip_32', 32)

            pipeline_inst.connections << out_conn(:trace_retired, 'pipeline_inst_trace_retired_1', width: 1)
            pipeline_inst.connections << out_conn(:trace_wr_finished, 'pipeline_inst_trace_wr_finished_1', width: 1)
            pipeline_inst.connections << out_conn(:trace_wr_ready, 'pipeline_inst_trace_wr_ready_1', width: 1)
            pipeline_inst.connections << out_conn(:trace_wr_hlt_in_progress, 'pipeline_inst_trace_wr_hlt_in_progress_1', width: 1)
            pipeline_inst.connections << out_conn(:trace_cs_cache_valid, 'pipeline_inst_cs_cache_valid_1', width: 1)
            pipeline_inst.connections << out_conn(:trace_prefetch_eip, 'pipeline_inst_trace_prefetch_eip_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_fetch_valid, 'pipeline_inst_trace_fetch_valid_4', width: 4)
            pipeline_inst.connections << out_conn(:trace_fetch_bytes, 'pipeline_inst_trace_fetch_bytes_64', width: 64)
            pipeline_inst.connections << out_conn(:trace_dec_acceptable, 'pipeline_inst_trace_dec_acceptable_4', width: 4)
            pipeline_inst.connections << out_conn(:trace_fetch_accept_length, 'pipeline_inst_trace_fetch_accept_length_4', width: 4)
            pipeline_inst.connections << out_conn(:trace_arch_new_export, 'pipeline_inst_trace_arch_new_export_1', width: 1)
            pipeline_inst.connections << out_conn(:trace_arch_eax, 'pipeline_inst_trace_arch_eax_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_ebx, 'pipeline_inst_trace_arch_ebx_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_ecx, 'pipeline_inst_trace_arch_ecx_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_edx, 'pipeline_inst_trace_arch_edx_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_esi, 'pipeline_inst_trace_arch_esi_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_edi, 'pipeline_inst_trace_arch_edi_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_esp, 'pipeline_inst_trace_arch_esp_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_ebp, 'pipeline_inst_trace_arch_ebp_32', width: 32)
            pipeline_inst.connections << out_conn(:trace_arch_eip, 'pipeline_inst_trace_arch_eip_32', width: 32)

            TRACE_PORTS.each do |name, width|
              mod.ports << port(name, width)
            end

            mod.assigns << assign('trace_retired', signal('pipeline_inst_trace_retired_1', 1))
            mod.assigns << assign('trace_wr_finished', signal('pipeline_inst_trace_wr_finished_1', 1))
            mod.assigns << assign('trace_wr_ready', signal('pipeline_inst_trace_wr_ready_1', 1))
            mod.assigns << assign('trace_wr_hlt_in_progress', signal('pipeline_inst_trace_wr_hlt_in_progress_1', 1))
            mod.assigns << assign('trace_wr_eip', connection_signal!(pipeline_inst, 'wr_eip'))
            mod.assigns << assign('trace_wr_consumed', connection_signal!(pipeline_inst, 'wr_consumed'))
            mod.assigns << assign('trace_cs_cache', connection_signal!(pipeline_inst, 'cs_cache'))
            mod.assigns << assign('trace_cs_cache_valid', signal('pipeline_inst_cs_cache_valid_1', 1))
            mod.assigns << assign('trace_prefetch_eip', signal('pipeline_inst_trace_prefetch_eip_32', 32))
            mod.assigns << assign('trace_fetch_valid', signal('pipeline_inst_trace_fetch_valid_4', 4))
            mod.assigns << assign('trace_fetch_bytes', signal('pipeline_inst_trace_fetch_bytes_64', 64))
            mod.assigns << assign('trace_dec_acceptable', signal('pipeline_inst_trace_dec_acceptable_4', 4))
            mod.assigns << assign('trace_fetch_accept_length', signal('pipeline_inst_trace_fetch_accept_length_4', 4))
            mod.assigns << assign('trace_prefetchfifo_accept_empty', connection_signal!(memory_inst, 'prefetchfifo_accept_empty'))
            mod.assigns << assign('trace_prefetchfifo_accept_do', connection_signal!(memory_inst, 'prefetchfifo_accept_do'))
            mod.assigns << assign('trace_arch_new_export', signal('pipeline_inst_trace_arch_new_export_1', 1))
            mod.assigns << assign('trace_arch_eax', signal('pipeline_inst_trace_arch_eax_32', 32))
            mod.assigns << assign('trace_arch_ebx', signal('pipeline_inst_trace_arch_ebx_32', 32))
            mod.assigns << assign('trace_arch_ecx', signal('pipeline_inst_trace_arch_ecx_32', 32))
            mod.assigns << assign('trace_arch_edx', signal('pipeline_inst_trace_arch_edx_32', 32))
            mod.assigns << assign('trace_arch_esi', signal('pipeline_inst_trace_arch_esi_32', 32))
            mod.assigns << assign('trace_arch_edi', signal('pipeline_inst_trace_arch_edi_32', 32))
            mod.assigns << assign('trace_arch_esp', signal('pipeline_inst_trace_arch_esp_32', 32))
            mod.assigns << assign('trace_arch_ebp', signal('pipeline_inst_trace_arch_ebp_32', 32))
            mod.assigns << assign('trace_arch_eip', signal('pipeline_inst_trace_arch_eip_32', 32))
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

          def out_conn(port_name, signal_name, width: nil)
            RHDL::Codegen::CIRCT::IR::PortConnection.new(
              port_name: port_name,
              signal: signal_name,
              direction: :out,
              width: width
            )
          end

          def ensure_net(mod, name, width)
            return if mod.nets.any? { |net| net.name.to_s == name.to_s }
            return if mod.regs.any? { |reg| reg.name.to_s == name.to_s }
            return if mod.ports.any? { |port| port.name.to_s == name.to_s }

            mod.nets << RHDL::Codegen::CIRCT::IR::Net.new(name: name.to_sym, width: width)
          end

          def binop(op, left, right, width)
            RHDL::Codegen::CIRCT::IR::BinaryOp.new(
              op: op,
              left: left,
              right: right,
              width: width
            )
          end

          def min_expr(left, right, width)
            RHDL::Codegen::CIRCT::IR::Mux.new(
              condition: binop(:<, left, right, 1),
              when_true: left,
              when_false: right,
              width: width
            )
          end
        end
      end
    end
  end
end
