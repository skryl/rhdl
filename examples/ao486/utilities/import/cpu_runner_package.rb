# frozen_string_literal: true

require 'rhdl/codegen'
require_relative 'cpu_parity_package'

module RHDL
  module Examples
    module AO486
      module Import
        # Builds a runner-oriented imported AO486 CPU package.
        #
        # The DOS/BIOS runner needs the imported CPU top to progress past the
        # reset vector, but it does not need the stronger parity-specific
        # prefetch rewrites used by the runtime parity package. This package
        # keeps the direct icache + register-fifo patches that unblock startup,
        # while preserving a prefetch flow closer to the original RTL so BIOS
        # helper code does not drift into the parity-only execution corner.
        module CpuRunnerPackage
          module_function

          def from_cleaned_mlir(mlir_text, top: 'ao486', strict: false)
            imported = RHDL::Codegen.import_circt_mlir(mlir_text, strict: strict, top: top)
            return CpuTracePackage.failure_from_import(imported) unless imported.success?

            modules = Array(imported.modules).map { |mod| CpuTracePackage.dup_module(mod) }
            patch_icache_runner_bypass!(modules)
            patch_prefetch_fifo_runner_model!(modules)
            patch_prefetch_runner_flow!(modules)
            patch_memory_runner_bridges!(modules)
            CpuParityPackage.patch_fetch_threshold_logic!(modules)
            patch_execute_call_relative_target!(modules)
            patch_execute_call_return_push!(modules)

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

          def patch_icache_runner_bypass!(modules)
            mod = CpuTracePackage.find_module!(modules, 'icache')
            inst = CpuTracePackage.find_instance!(mod, 'l1_icache_inst')
            ir = RHDL::Codegen::CIRCT::IR

            CpuParityPackage.ensure_reg(mod, 'runner_readcode_burst_active', 1, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_readcode_beat_index', 4, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_readcode_drain_count', 4, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_readcode_request_pending', 1, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_readcode_request_armed', 1, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_readcode_request_addr', 32, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_readcode_drop_fill', 1, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_cache_valid', 1, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_cache_base', 32, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_output_active', 1, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_output_index', 4, 0)
            CpuParityPackage.ensure_reg(mod, 'runner_outputs_remaining', 3, 0)
            8.times do |index|
              CpuParityPackage.ensure_reg(mod, "runner_cache_word_#{index}", 32, 0)
            end
            cpu_valid_name = CpuParityPackage.output_signal_name!(inst, 'CPU_VALID')
            cpu_done_name = CpuParityPackage.output_signal_name!(inst, 'CPU_DONE')
            cpu_data_name = CpuParityPackage.output_signal_name!(inst, 'CPU_DATA')
            mem_req_name = CpuParityPackage.output_signal_name!(inst, 'MEM_REQ')
            mem_addr_name = CpuParityPackage.output_signal_name!(inst, 'MEM_ADDR')
            rst_n_expr = CpuTracePackage.signal('rst_n', 1)
            pr_reset_expr = CpuTracePackage.signal('pr_reset', 1)
            reset_prefetch_expr = CpuTracePackage.signal('reset_prefetch', 1)
            cpu_req_expr = CpuParityPackage.connection_expr!(inst, 'CPU_REQ')
            cpu_addr_expr = CpuParityPackage.connection_expr!(inst, 'CPU_ADDR')
            prefetched_length_expr = CpuTracePackage.signal('prefetched_length', 5)
            readcode_burst_active = CpuTracePackage.signal('runner_readcode_burst_active', 1)
            readcode_beat_index = CpuTracePackage.signal('runner_readcode_beat_index', 4)
            readcode_drain_count = CpuTracePackage.signal('runner_readcode_drain_count', 4)
            readcode_request_pending = CpuTracePackage.signal('runner_readcode_request_pending', 1)
            readcode_request_armed = CpuTracePackage.signal('runner_readcode_request_armed', 1)
            readcode_request_addr = CpuTracePackage.signal('runner_readcode_request_addr', 32)
            readcode_drop_fill = CpuTracePackage.signal('runner_readcode_drop_fill', 1)
            runner_cache_valid = CpuTracePackage.signal('runner_cache_valid', 1)
            runner_cache_base = CpuTracePackage.signal('runner_cache_base', 32)
            runner_output_active = CpuTracePackage.signal('runner_output_active', 1)
            runner_output_index = CpuTracePackage.signal('runner_output_index', 4)
            runner_outputs_remaining = CpuTracePackage.signal('runner_outputs_remaining', 3)
            readcode_word_valid = CpuTracePackage.signal('readcode_done', 1)
            readcode_partial_expr = CpuTracePackage.signal('readcode_partial', 32)
            cache_words = 8.times.map { |index| CpuTracePackage.signal("runner_cache_word_#{index}", 32) }
            one1 = ir::Literal.new(value: 1, width: 1)
            one3 = ir::Literal.new(value: 1, width: 3)
            zero1 = ir::Literal.new(value: 0, width: 1)
            zero3 = ir::Literal.new(value: 0, width: 3)
            zero4 = ir::Literal.new(value: 0, width: 4)
            eight4 = ir::Literal.new(value: 8, width: 4)
            zero32 = ir::Literal.new(value: 0, width: 32)
            four3 = ir::Literal.new(value: 4, width: 3)
            seven4 = ir::Literal.new(value: 7, width: 4)
            has_pending_words = CpuTracePackage.binop(:!=, prefetched_length_expr, ir::Literal.new(value: 0, width: 5), 1)
            request_line_base = CpuTracePackage.binop(
              :&,
              cpu_addr_expr,
              ir::Literal.new(value: 0xFFFF_FFE0, width: 32),
              32
            )
            request_start_index = ir::Concat.new(
              parts: [
                zero1,
                ir::Slice.new(base: cpu_addr_expr, range: 2..4, width: 3)
              ],
              width: 4
            )
            # Keep fetch windows serialized. Allowing a new request to start
            # while the final visible word of the previous window is still
            # active is faster, but it risks byte-count drift on partial words.
            request_blocked_by_output = runner_output_active
            request_start = CpuTracePackage.binop(
              :&,
              cpu_req_expr,
              CpuTracePackage.binop(
                :^,
                request_blocked_by_output,
                one1,
                1
              ),
              1
            )
            cache_hit = CpuTracePackage.binop(
              :&,
              runner_cache_valid,
              CpuTracePackage.binop(:==, runner_cache_base, request_line_base, 1),
              1
            )
            request_start_hit = CpuTracePackage.binop(:&, request_start, cache_hit, 1)
            request_start_miss = CpuTracePackage.binop(
              :&,
              request_start,
              CpuTracePackage.binop(
                :&,
                CpuTracePackage.binop(:^, cache_hit, one1, 1),
                CpuTracePackage.binop(:^, readcode_burst_active, one1, 1),
                1
              ),
              1
            )
            request_retarget = CpuTracePackage.binop(
              :&,
              request_start,
              CpuTracePackage.binop(
                :&,
                CpuTracePackage.binop(:^, cache_hit, one1, 1),
                CpuTracePackage.binop(
                  :&,
                  readcode_burst_active,
                  CpuTracePackage.binop(:!=, readcode_request_addr, request_line_base, 1),
                  1
                ),
                1
              ),
              1
            )
            output_last_word = CpuTracePackage.binop(
              :&,
              runner_output_active,
              CpuTracePackage.binop(:==, runner_outputs_remaining, one3, 1),
              1
            )
            output_crosses_line = CpuTracePackage.binop(
              :&,
              runner_output_active,
              CpuTracePackage.binop(
                :&,
                CpuTracePackage.binop(:>, runner_outputs_remaining, one3, 1),
                CpuTracePackage.binop(:==, runner_output_index, seven4, 1),
                1
              ),
              1
            )
            fill_start = CpuTracePackage.binop(
              :|,
              request_start_miss,
              output_crosses_line,
              1
            )
            reset_window = CpuTracePackage.binop(
              :^,
              rst_n_expr,
              one1,
              1
            )
            flush_window = CpuTracePackage.binop(
              :|,
              reset_window,
              CpuTracePackage.binop(:|, pr_reset_expr, reset_prefetch_expr, 1),
              1
            )
            # The reference l1_icache treats reset_prefetch like an internal
            # cache reset. Keep the queued prefetch FIFO bytes, but clear the
            # runner-side request/cache window state so stale line metadata
            # cannot leak across a redirect.
            request_reset_window = flush_window
            drain_active = CpuTracePackage.binop(:!=, readcode_drain_count, zero4, 1)
            drain_count_next = ir::Mux.new(
              condition: reset_window,
              when_true: zero4,
              when_false: ir::Mux.new(
                condition: pr_reset_expr,
                when_true: ir::Mux.new(
                  condition: readcode_burst_active,
                  when_true: CpuTracePackage.binop(:-, eight4, readcode_beat_index, 4),
                  when_false: zero4,
                  width: 4
                ),
                when_false: ir::Mux.new(
                  condition: CpuTracePackage.binop(:&, drain_active, readcode_word_valid, 1),
                  when_true: CpuTracePackage.binop(:-, readcode_drain_count, ir::Literal.new(value: 1, width: 4), 4),
                  when_false: readcode_drain_count,
                  width: 4
                ),
                width: 4
              ),
              width: 4
            )
            accepted_readcode_word = CpuTracePackage.binop(
              :&,
              CpuTracePackage.binop(:^, request_retarget, one1, 1),
              CpuTracePackage.binop(
                :&,
                CpuTracePackage.binop(:^, drain_active, one1, 1),
                CpuTracePackage.binop(
                  :&,
                  readcode_word_valid,
                  ir::Mux.new(
                    condition: readcode_request_pending,
                    when_true: readcode_request_armed,
                    when_false: one1,
                    width: 1
                  ),
                  1
                ),
                1
              ),
              1
            )
            fill_complete = CpuTracePackage.binop(
              :&,
              accepted_readcode_word,
              CpuTracePackage.binop(
                :&,
                readcode_burst_active,
                CpuTracePackage.binop(:==, readcode_beat_index, seven4, 1),
                1
              ),
              1
            )
            speculative_fill = CpuTracePackage.binop(
              :&,
              request_start_miss,
              request_blocked_by_output,
              1
            )
            cache_word_store_do = CpuTracePackage.binop(
              :&,
              CpuTracePackage.binop(:&, accepted_readcode_word, readcode_burst_active, 1),
              CpuTracePackage.binop(
                :&,
                CpuTracePackage.binop(:^, request_start_hit, one1, 1),
                CpuTracePackage.binop(:^, readcode_drop_fill, one1, 1),
                1
              ),
              1
            )
            request_pending_next = ir::Mux.new(
              condition: request_reset_window,
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: request_start_hit,
                when_true: zero1,
                when_false: ir::Mux.new(
                  condition: request_retarget,
                  when_true: one1,
                  when_false: ir::Mux.new(
                    condition: fill_start,
                    when_true: one1,
                    when_false: ir::Mux.new(
                    condition: readcode_word_valid,
                    when_true: ir::Mux.new(
                      condition: accepted_readcode_word,
                      when_true: zero1,
                      when_false: readcode_request_pending,
                      width: 1
                    ),
                    when_false: readcode_request_pending,
                    width: 1
                    ),
                    width: 1
                  ),
                  width: 1
                ),
                width: 1
              ),
              width: 1
            )
            request_addr_next = ir::Mux.new(
              condition: request_reset_window,
              when_true: zero32,
              when_false: ir::Mux.new(
                condition: request_start_miss,
                when_true: request_line_base,
                when_false: ir::Mux.new(
                  condition: request_retarget,
                  when_true: request_line_base,
                  when_false: ir::Mux.new(
                    condition: output_crosses_line,
                    when_true: CpuTracePackage.binop(
                      :+,
                      runner_cache_base,
                      ir::Literal.new(value: 32, width: 32),
                      32
                    ),
                    when_false: readcode_request_addr,
                    width: 32
                  ),
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            request_armed_next = ir::Mux.new(
              condition: request_reset_window,
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: CpuTracePackage.binop(:|, request_start_hit, request_retarget, 1),
                when_true: zero1,
                when_false: ir::Mux.new(
                  condition: fill_start,
                  when_true: zero1,
                  when_false: ir::Mux.new(
                    condition: request_pending_next,
                    when_true: ir::Mux.new(
                      condition: CpuTracePackage.binop(
                        :|,
                        CpuTracePackage.binop(:!=, drain_count_next, zero4, 1),
                        readcode_word_valid,
                        1
                      ),
                      when_true: zero1,
                      when_false: one1,
                      width: 1
                    ),
                    when_false: zero1,
                    width: 1
                  ),
                  width: 1
                ),
                width: 1
              ),
              width: 1
            )
            drop_fill_next = ir::Mux.new(
              condition: request_reset_window,
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: request_start_hit,
                when_true: zero1,
                when_false: ir::Mux.new(
                  condition: request_retarget,
                  when_true: zero1,
                  when_false: ir::Mux.new(
                  condition: fill_start,
                  when_true: speculative_fill,
                  when_false: ir::Mux.new(
                    condition: fill_complete,
                    when_true: zero1,
                    when_false: readcode_drop_fill,
                    width: 1
                  ),
                    width: 1
                  ),
                  width: 1
                ),
                width: 1
              ),
              width: 1
            )
            burst_active_next = ir::Mux.new(
              condition: request_reset_window,
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: request_start_hit,
                when_true: zero1,
                when_false: ir::Mux.new(
                  condition: request_retarget,
                  when_true: one1,
                  when_false: ir::Mux.new(
                  condition: fill_start,
                  when_true: one1,
                  when_false: ir::Mux.new(
                  condition: fill_complete,
                  when_true: zero1,
                  when_false: readcode_burst_active,
                    width: 1
                  ),
                    width: 1
                  ),
                  width: 1
                ),
                width: 1
              ),
              width: 1
            )
            beat_index_next = ir::Mux.new(
              condition: request_reset_window,
              when_true: zero4,
              when_false: ir::Mux.new(
                condition: request_start_hit,
                when_true: zero4,
                when_false: ir::Mux.new(
                  condition: request_retarget,
                  when_true: zero4,
                  when_false: ir::Mux.new(
                  condition: fill_start,
                  when_true: zero4,
                  when_false: ir::Mux.new(
                    condition: CpuTracePackage.binop(:&, readcode_burst_active, accepted_readcode_word, 1),
                    when_true: ir::Mux.new(
                      condition: CpuTracePackage.binop(:==, readcode_beat_index, seven4, 1),
                      when_true: zero4,
                      when_false: CpuTracePackage.binop(:+, readcode_beat_index, ir::Literal.new(value: 1, width: 4), 4),
                      width: 4
                    ),
                    when_false: readcode_beat_index,
                    width: 4
                  ),
                    width: 4
                  ),
                  width: 4
                ),
                width: 4
              ),
              width: 4
            )
            cache_valid_next = ir::Mux.new(
              condition: flush_window,
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: request_start_hit,
                when_true: runner_cache_valid,
                when_false: ir::Mux.new(
                  condition: CpuTracePackage.binop(
                    :&,
                    fill_complete,
                    CpuTracePackage.binop(:^, readcode_drop_fill, one1, 1),
                    1
                  ),
                  when_true: one1,
                  when_false: runner_cache_valid,
                  width: 1
                ),
                width: 1
              ),
              width: 1
            )
            cache_base_next = ir::Mux.new(
              condition: flush_window,
              when_true: zero32,
              when_false: ir::Mux.new(
                condition: request_start_hit,
                when_true: runner_cache_base,
                when_false: ir::Mux.new(
                  condition: CpuTracePackage.binop(
                    :&,
                    fill_complete,
                    CpuTracePackage.binop(:^, readcode_drop_fill, one1, 1),
                    1
                  ),
                  when_true: readcode_request_addr,
                  when_false: runner_cache_base,
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            outputs_remaining_next = ir::Mux.new(
              condition: flush_window,
              when_true: zero3,
              when_false: ir::Mux.new(
                condition: CpuTracePackage.binop(
                  :|,
                  CpuTracePackage.binop(:|, request_start_hit, request_start_miss, 1),
                  request_retarget,
                  1
                ),
                when_true: four3,
                when_false: ir::Mux.new(
                  condition: runner_output_active,
                  when_true: CpuTracePackage.binop(:-, runner_outputs_remaining, one3, 3),
                  when_false: runner_outputs_remaining,
                  width: 3
                ),
                width: 3
              ),
              width: 3
            )
            output_active_next = ir::Mux.new(
              condition: flush_window,
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: CpuTracePackage.binop(
                  :|,
                  request_start_hit,
                  CpuTracePackage.binop(
                    :&,
                    fill_complete,
                    CpuTracePackage.binop(:^, readcode_drop_fill, one1, 1),
                    1
                  ),
                  1
                ),
                when_true: one1,
                when_false: ir::Mux.new(
                  condition: runner_output_active,
                  when_true: ir::Mux.new(
                    condition: CpuTracePackage.binop(:|, output_last_word, output_crosses_line, 1),
                    when_true: zero1,
                    when_false: one1,
                    width: 1
                  ),
                  when_false: runner_output_active,
                  width: 1
                ),
                width: 1
              ),
              width: 1
            )
            output_index_next = ir::Mux.new(
              condition: flush_window,
              when_true: zero4,
              when_false: ir::Mux.new(
                condition: CpuTracePackage.binop(
                  :|,
                  CpuTracePackage.binop(:|, request_start_hit, request_start_miss, 1),
                  request_retarget,
                  1
                ),
                when_true: request_start_index,
                when_false: ir::Mux.new(
                  condition: fill_complete,
                  when_true: runner_output_index,
                  when_false: ir::Mux.new(
                    condition: runner_output_active,
                    when_true: ir::Mux.new(
                      condition: output_last_word,
                      when_true: zero4,
                      when_false: ir::Mux.new(
                        condition: output_crosses_line,
                        when_true: zero4,
                        when_false: CpuTracePackage.binop(:+, runner_output_index, ir::Literal.new(value: 1, width: 4), 4),
                        width: 4
                      ),
                      width: 4
                    ),
                    when_false: runner_output_index,
                    width: 4
                  ),
                  width: 4
                ),
                width: 4
              ),
                width: 4
            )
            selected_cache_word = cache_words.each_with_index.to_a.reverse.reduce(nil) do |expr, (signal, index)|
              expr ||= signal
              ir::Mux.new(
                condition: CpuTracePackage.binop(:==, runner_output_index, ir::Literal.new(value: index, width: 4), 1),
                when_true: signal,
                when_false: expr,
                width: 32
              )
            end
            cpu_visible_word = CpuTracePackage.binop(
              :&,
              runner_output_active,
              CpuTracePackage.binop(:^, pr_reset_expr, one1, 1),
              1
            )
            mod.instances.reject! { |entry| entry.name.to_s == 'l1_icache_inst' }
            mod.assigns << CpuTracePackage.assign(mem_req_name, readcode_request_pending)
            mod.assigns << CpuTracePackage.assign(mem_addr_name, readcode_request_addr)
            mod.assigns << CpuTracePackage.assign(cpu_valid_name, cpu_visible_word)
            mod.assigns << CpuTracePackage.assign(cpu_data_name, selected_cache_word)
            mod.assigns << CpuTracePackage.assign(
              cpu_done_name,
              CpuTracePackage.binop(
                :|,
                output_last_word,
                CpuTracePackage.binop(:|, pr_reset_expr, reset_prefetch_expr, 1),
                1
              )
            )
            mod.processes << ir::Process.new(
              name: 'runner_icache_burst_window',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::SeqAssign.new(target: 'runner_readcode_drain_count', expr: drain_count_next),
                ir::SeqAssign.new(target: 'runner_readcode_request_pending', expr: request_pending_next),
                ir::SeqAssign.new(target: 'runner_readcode_request_armed', expr: request_armed_next),
                ir::SeqAssign.new(target: 'runner_readcode_request_addr', expr: request_addr_next),
                ir::SeqAssign.new(target: 'runner_readcode_drop_fill', expr: drop_fill_next),
                ir::SeqAssign.new(target: 'runner_readcode_burst_active', expr: burst_active_next),
                ir::SeqAssign.new(target: 'runner_readcode_beat_index', expr: beat_index_next),
                ir::SeqAssign.new(target: 'runner_cache_valid', expr: cache_valid_next),
                ir::SeqAssign.new(target: 'runner_cache_base', expr: cache_base_next),
                ir::SeqAssign.new(target: 'runner_output_active', expr: output_active_next),
                ir::SeqAssign.new(target: 'runner_output_index', expr: output_index_next),
                ir::SeqAssign.new(target: 'runner_outputs_remaining', expr: outputs_remaining_next)
              ]
            )
            cache_words.each_with_index do |signal, index|
              mod.processes << ir::Process.new(
                name: "runner_icache_cache_word_#{index}",
                clocked: true,
                clock: 'clk',
                statements: [
                  ir::SeqAssign.new(
                    target: signal.name.to_s,
                    expr: ir::Mux.new(
                      condition: flush_window,
                      when_true: zero32,
                      when_false: ir::Mux.new(
                        condition: CpuTracePackage.binop(
                          :&,
                          cache_word_store_do,
                          CpuTracePackage.binop(
                            :==,
                            readcode_beat_index,
                            ir::Literal.new(value: index, width: 4),
                            1
                          ),
                          1
                        ),
                        when_true: readcode_partial_expr,
                        when_false: signal,
                        width: 32
                      ),
                      width: 32
                    )
                  )
                ]
              )
            end
          end

          def patch_prefetch_fifo_runner_model!(modules)
            mod = CpuTracePackage.find_module!(modules, 'prefetch_fifo')
            ir = RHDL::Codegen::CIRCT::IR

            mod.instances.clear
            mod.assigns.clear
            mod.processes.clear

            8.times do |index|
              CpuParityPackage.ensure_reg(mod, "parity_fifo_entry_#{index}", 36, 0)
            end
            CpuParityPackage.ensure_reg(mod, 'parity_fifo_used', 5, 0)

            rst_n = CpuTracePackage.signal('rst_n', 1)
            pr_reset = CpuTracePackage.signal('pr_reset', 1)
            limit_do = CpuTracePackage.signal('prefetchfifo_signal_limit_do', 1)
            pf_do = CpuTracePackage.signal('prefetchfifo_signal_pf_do', 1)
            write_do = CpuTracePackage.signal('prefetchfifo_write_do', 1)
            write_data = CpuTracePackage.signal('prefetchfifo_write_data', 36)
            accept_do = CpuTracePackage.signal('prefetchfifo_accept_do', 1)
            fifo_used = CpuTracePackage.signal('parity_fifo_used', 5)
            fifo_entries = 8.times.map { |index| CpuTracePackage.signal("parity_fifo_entry_#{index}", 36) }

            one1 = ir::Literal.new(value: 1, width: 1)
            zero5 = ir::Literal.new(value: 0, width: 5)
            one5 = ir::Literal.new(value: 1, width: 5)
            eight5 = ir::Literal.new(value: 8, width: 5)
            zero32 = ir::Literal.new(value: 0, width: 32)
            zero36 = ir::Literal.new(value: 0, width: 36)

            empty = CpuTracePackage.binop(:==, fifo_used, zero5, 1)
            not_empty = CpuTracePackage.binop(:^, empty, one1, 1)
            full = CpuTracePackage.binop(:>=, fifo_used, eight5, 1)
            bypass = CpuTracePackage.binop(:&, write_do, empty, 1)
            accept_empty = CpuTracePackage.binop(:&, empty, CpuTracePackage.binop(:^, bypass, one1, 1), 1)
            effective_rd = CpuTracePackage.binop(:&, accept_do, not_empty, 1)
            raw_wrreq = CpuTracePackage.binop(
              :|,
              CpuTracePackage.binop(
                :|,
                CpuTracePackage.binop(
                  :&,
                  write_do,
                  CpuTracePackage.binop(
                    :|,
                    not_empty,
                    CpuTracePackage.binop(:^, accept_do, one1, 1),
                    1
                  ),
                  1
                ),
                limit_do,
                1
              ),
              pf_do,
              1
            )
            effective_wr = CpuTracePackage.binop(
              :&,
              raw_wrreq,
              CpuTracePackage.binop(
                :|,
                CpuTracePackage.binop(:^, full, one1, 1),
                effective_rd,
                1
              ),
              1
            )
            used_minus_one = CpuTracePackage.binop(:-, fifo_used, one5, 5)
            used_plus_one = CpuTracePackage.binop(:+, fifo_used, one5, 5)
            append_index = ir::Mux.new(
              condition: effective_rd,
              when_true: used_minus_one,
              when_false: fifo_used,
              width: 5
            )
            incoming_payload = ir::Mux.new(
              condition: limit_do,
              when_true: ir::Concat.new(
                parts: [
                  ir::Literal.new(value: 15, width: 4),
                  zero32
                ],
                width: 36
              ),
              when_false: ir::Mux.new(
                condition: pf_do,
                when_true: ir::Concat.new(
                  parts: [
                    ir::Literal.new(value: 14, width: 4),
                    zero32
                  ],
                  width: 36
                ),
                when_false: write_data,
                width: 36
              ),
              width: 36
            )

            entry0_payload = ir::Concat.new(
              parts: [
                ir::Slice.new(base: fifo_entries.first, range: 32..35, width: 4),
                zero32,
                ir::Slice.new(base: fifo_entries.first, range: 0..31, width: 32)
              ],
              width: 68
            )
            bypass_payload = ir::Concat.new(
              parts: [
                ir::Slice.new(base: write_data, range: 32..35, width: 4),
                zero32,
                ir::Slice.new(base: write_data, range: 0..31, width: 32)
              ],
              width: 68
            )

            mod.assigns << CpuTracePackage.assign('prefetchfifo_used', fifo_used)
            mod.assigns << CpuTracePackage.assign(
              'prefetchfifo_accept_data',
              ir::Mux.new(
                condition: bypass,
                when_true: bypass_payload,
                when_false: entry0_payload,
                width: 68
              )
            )
            mod.assigns << CpuTracePackage.assign('prefetchfifo_accept_empty', accept_empty)

            # Match the reference prefetch FIFO reset contract: reset_prefetch
            # realigns the icache/prefetch window, but it must not discard
            # already queued fetch bytes.
            reset_fifo = CpuTracePackage.binop(
              :|,
              CpuTracePackage.binop(:^, rst_n, one1, 1),
              pr_reset,
              1
            )
            next_used = ir::Mux.new(
              condition: reset_fifo,
              when_true: zero5,
              when_false: ir::Mux.new(
                condition: effective_rd,
                when_true: ir::Mux.new(
                  condition: effective_wr,
                  when_true: fifo_used,
                  when_false: used_minus_one,
                  width: 5
                ),
                when_false: ir::Mux.new(
                  condition: effective_wr,
                  when_true: used_plus_one,
                  when_false: fifo_used,
                  width: 5
                ),
                width: 5
              ),
              width: 5
            )

            statements = [ir::SeqAssign.new(target: 'parity_fifo_used', expr: next_used)]
            fifo_entries.each_with_index do |entry, index|
              shifted_entry = fifo_entries[index + 1] || zero36
              base_entry = ir::Mux.new(
                condition: effective_rd,
                when_true: shifted_entry,
                when_false: entry,
                width: 36
              )
              append_here = CpuTracePackage.binop(
                :&,
                effective_wr,
                CpuTracePackage.binop(:==, append_index, ir::Literal.new(value: index, width: 5), 1),
                1
              )
              next_entry = ir::Mux.new(
                condition: reset_fifo,
                when_true: zero36,
                when_false: ir::Mux.new(
                  condition: append_here,
                  when_true: incoming_payload,
                  when_false: base_entry,
                  width: 36
                ),
                width: 36
              )
              statements << ir::SeqAssign.new(target: "parity_fifo_entry_#{index}", expr: next_entry)
            end

            mod.processes << ir::Process.new(
              name: 'runner_prefetch_fifo_register_model',
              clocked: true,
              clock: 'clk',
              statements: statements
            )
          end

          def patch_prefetch_runner_flow!(modules)
            mod = CpuTracePackage.find_module!(modules, 'prefetch')
            ir = RHDL::Codegen::CIRCT::IR

            rst_n = CpuTracePackage.signal('rst_n', 1)
            pr_reset = CpuTracePackage.signal('pr_reset', 1)
            reset_prefetch = CpuTracePackage.signal('reset_prefetch', 1)
            prefetch_cpl = CpuTracePackage.signal('prefetch_cpl', 2)
            prefetch_eip = CpuTracePackage.signal('prefetch_eip', 32)
            cs_cache = CpuTracePackage.signal('cs_cache', 64)
            prefetched_do = CpuTracePackage.signal('prefetched_do', 1)
            prefetched_length = CpuTracePackage.signal('prefetched_length', 5)
            prefetched_accept_do = CpuTracePackage.signal('prefetched_accept_do', 1)
            prefetched_accept_length = CpuTracePackage.signal('prefetched_accept_length', 4)
            limit = CpuTracePackage.signal('limit', 32)
            linear = CpuTracePackage.signal('linear', 32)
            delivered_eip = CpuTracePackage.signal('delivered_eip', 32)
            limit_signaled = CpuTracePackage.signal('limit_signaled', 1)
            prefetched_accept_do_1 = CpuTracePackage.signal('prefetched_accept_do_1', 1)
            prefetched_accept_length_1 = CpuTracePackage.signal('prefetched_accept_length_1', 4)

            one1 = ir::Literal.new(value: 1, width: 1)
            one32 = ir::Literal.new(value: 1, width: 32)
            zero1 = ir::Literal.new(value: 0, width: 1)
            zero32 = ir::Literal.new(value: 0, width: 32)
            startup_linear = ir::Literal.new(value: 0xFFFF0, width: 32)
            startup_limit = ir::Literal.new(value: 16, width: 32)
            max_fetch_len32 = ir::Literal.new(value: 16, width: 32)
            max_fetch_len5 = ir::Literal.new(value: 16, width: 5)
            user_cpl = ir::Literal.new(value: 3, width: 2)

            cs_base = ir::Concat.new(
              parts: [
                ir::Slice.new(base: cs_cache, range: 56..63, width: 8),
                ir::Slice.new(base: cs_cache, range: 16..39, width: 24)
              ],
              width: 32
            )
            cs_limit_high = ir::Slice.new(base: cs_cache, range: 48..51, width: 4)
            cs_limit_low = ir::Slice.new(base: cs_cache, range: 0..15, width: 16)
            cs_limit = ir::Mux.new(
              condition: ir::Slice.new(base: cs_cache, range: 55..55, width: 1),
              when_true: ir::Concat.new(
                parts: [
                  cs_limit_high,
                  cs_limit_low,
                  ir::Literal.new(value: 0xFFF, width: 12)
                ],
                width: 32
              ),
              when_false: ir::Concat.new(
                parts: [
                  ir::Literal.new(value: 0, width: 12),
                  cs_limit_high,
                  cs_limit_low
                ],
                width: 32
              ),
              width: 32
            )
            prefetched_length_ext = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 0, width: 27),
                prefetched_length
              ],
              width: 32
            )
            accepted_length_ext = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 0, width: 28),
                prefetched_accept_length_1
              ],
              width: 32
            )
            current_length = ir::Mux.new(
              condition: CpuTracePackage.binop(:<, limit, prefetched_length_ext, 1),
              when_true: ir::Slice.new(base: limit, range: 0..4, width: 5),
              when_false: prefetched_length,
              width: 5
            )
            current_length_ext = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 0, width: 27),
                current_length
              ],
              width: 32
            )
            cs_base_prefetch_linear = CpuTracePackage.binop(:+, cs_base, prefetch_eip, 32)
            linear_advance = CpuTracePackage.binop(:+, linear, current_length_ext, 32)
            linear_next = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one1, 1),
              when_true: startup_linear,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: cs_base_prefetch_linear,
                when_false: ir::Mux.new(
                  condition: reset_prefetch,
                  when_true: ir::Mux.new(
                    condition: prefetched_accept_do_1,
                    when_true: CpuTracePackage.binop(:+, delivered_eip, accepted_length_ext, 32),
                    when_false: delivered_eip,
                    width: 32
                  ),
                  when_false: ir::Mux.new(
                    condition: prefetched_do,
                    when_true: linear_advance,
                    when_false: linear,
                    width: 32
                  ),
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            delivered_eip_next = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one1, 1),
              when_true: startup_linear,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: cs_base_prefetch_linear,
                when_false: ir::Mux.new(
                  condition: prefetched_accept_do_1,
                  when_true: CpuTracePackage.binop(:+, delivered_eip, accepted_length_ext, 32),
                  when_false: delivered_eip,
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            reset_limit = ir::Mux.new(
              condition: CpuTracePackage.binop(:>=, cs_limit, prefetch_eip, 1),
              when_true: CpuTracePackage.binop(
                :+,
                CpuTracePackage.binop(:-, cs_limit, prefetch_eip, 32),
                one32,
                32
              ),
              when_false: zero32,
              width: 32
            )
            limit_next = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one1, 1),
              when_true: startup_limit,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: reset_limit,
                when_false: ir::Mux.new(
                  condition: reset_prefetch,
                  when_true: reset_limit,
                  when_false: ir::Mux.new(
                    condition: prefetched_do,
                    when_true: CpuTracePackage.binop(:-, limit, current_length_ext, 32),
                    when_false: limit,
                    width: 32
                  ),
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            signal_limit_do = CpuTracePackage.binop(
              :&,
              CpuTracePackage.binop(:==, limit, zero32, 1),
              CpuTracePackage.binop(:^, limit_signaled, one1, 1),
              1
            )
            limit_signaled_next = ir::Mux.new(
              condition: CpuTracePackage.binop(
                :|,
                CpuTracePackage.binop(:^, rst_n, one1, 1),
                pr_reset,
                1
              ),
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: signal_limit_do,
                when_true: one1,
                when_false: limit_signaled,
                width: 1
              ),
              width: 1
            )

            mod.processes.clear
            mod.processes.concat(
              [
                ir::Process.new(
                  name: 'runner_prefetch_limit',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'limit', expr: limit_next)]
                ),
                ir::Process.new(
                  name: 'runner_prefetch_accept_do',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'prefetched_accept_do_1', expr: prefetched_accept_do)]
                ),
                ir::Process.new(
                  name: 'runner_prefetch_accept_length',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'prefetched_accept_length_1', expr: prefetched_accept_length)]
                ),
                ir::Process.new(
                  name: 'runner_prefetch_linear',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'linear', expr: linear_next)]
                ),
                ir::Process.new(
                  name: 'runner_prefetch_delivered_eip',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'delivered_eip', expr: delivered_eip_next)]
                ),
                ir::Process.new(
                  name: 'runner_prefetch_limit_signaled',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'limit_signaled', expr: limit_signaled_next)]
                )
              ]
            )

            mod.assigns.reject! do |assign|
              %w[prefetch_address prefetch_length prefetch_su prefetchfifo_signal_limit_do delivered_eip].include?(assign.target.to_s)
            end
            mod.assigns << CpuTracePackage.assign('prefetch_address', linear)
            mod.assigns << CpuTracePackage.assign(
              'prefetch_length',
              ir::Mux.new(
                condition: CpuTracePackage.binop(:>, limit, max_fetch_len32, 1),
                when_true: max_fetch_len5,
                when_false: ir::Slice.new(base: limit, range: 0..4, width: 5),
                width: 5
              )
            )
            mod.assigns << CpuTracePackage.assign(
              'prefetch_su',
              CpuTracePackage.binop(:==, prefetch_cpl, user_cpl, 1)
            )
            mod.assigns << CpuTracePackage.assign('prefetchfifo_signal_limit_do', signal_limit_do)
          end

          def patch_memory_runner_bridges!(modules)
            mod = CpuTracePackage.find_module!(modules, 'memory')

            {
              'icache_inst' => %w[
                reset_prefetch
                readcode_do
                readcode_address
                prefetchfifo_write_do
                prefetchfifo_write_data
                prefetched_do
                prefetched_length
              ],
              'prefetch_inst' => %w[
                prefetch_address
                prefetch_length
                prefetch_su
                prefetchfifo_signal_limit_do
                delivered_eip
              ],
              'prefetch_fifo_inst' => %w[
                prefetchfifo_used
                prefetchfifo_accept_data
                prefetchfifo_accept_empty
              ]
            }.each do |instance_name, ports|
              inst = CpuTracePackage.find_instance!(mod, instance_name)
              ports.each do |port_name|
                mod.assigns.reject! { |assign| assign.target.to_s == port_name }
                mod.assigns << CpuTracePackage.assign(port_name, CpuTracePackage.connection_signal!(inst, port_name))
              end
            end
          end

          def patch_execute_call_relative_target!(modules)
            nil
          end

          def patch_execute_call_return_push!(modules)
            nil
          end

        end
      end
    end
  end
end
