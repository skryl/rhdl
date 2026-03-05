# frozen_string_literal: true

require 'json'
require 'open3'
require 'set'
require 'tempfile'

module RHDL
  module Codegen
    module FIRRTL
      # Local Arc -> ArcToGPU lowering stage.
      #
      # Upstream arcilator currently does not expose an ArcToGPU lowering pass.
      # This stage consumes Arc MLIR emitted by arcilator (typically at
      # `--until-after=arc-opt`) and produces deterministic ArcToGPU artifacts:
      # - metadata JSON (operation/support summary + state/ABI map)
      # - GPU dialect MLIR skeleton for pipeline traceability
      # - Metal shader source implementing cycle execution on GPU
      module ArcToGpuLowering
        class LoweringError < StandardError; end

        TypeRef = Struct.new(:kind, :width, :length, :element, :index_width, keyword_init: true) do
          def fetch(key)
            value = public_send(key)
            raise KeyError, "missing #{key}" if value.nil?

            value
          end

          def scalar?
            kind == :scalar
          end

          def array?
            kind == :array
          end

          def memory?
            kind == :memory
          end
        end

        REQUIRED_TOP_OUTPUTS = %w[
          mem_data_out
          mem_addr
          mem_write_en
          mem_read_en
          pc_out
          acc_out
          sp_out
          halted
          state_out
          zero_flag_out
        ].freeze

        REQUIRED_TOP_INPUTS = %w[
          clk
          rst
          mem_data_in
        ].freeze

        REQUIRED_APPLE2_OUTPUTS = %w[
          ram_addr
          ram_we
          d
          speaker
          pc_debug
          a_debug
          x_debug
          y_debug
          p_debug
        ].freeze

        REQUIRED_APPLE2_INPUTS = %w[
          clk_14m
          reset
          ram_do
          ps2_clk
          ps2_data
          gameport
          pause
        ].freeze

        REQUIRED_RISCV_INPUTS = %w[
          clk
          rst
          irq_software
          irq_timer
          irq_external
          inst_data
          inst_ptw_pte1
          inst_ptw_pte0
          data_rdata
          data_ptw_pte1
          data_ptw_pte0
          debug_reg_addr
        ].freeze

        REQUIRED_RISCV_OUTPUTS = %w[
          inst_addr
          inst_ptw_addr1
          inst_ptw_addr0
          data_addr
          data_wdata
          data_we
          data_re
          data_funct3
          data_ptw_addr1
          data_ptw_addr0
          debug_pc
          debug_inst
          debug_x1
          debug_x2
          debug_x10
          debug_x11
          debug_reg_data
        ].freeze

        REQUIRED_RISCV_LOOP_OUTPUTS = %w[
          inst_addr
          inst_ptw_addr1
          inst_ptw_addr0
          data_addr
          data_wdata
          data_we
          data_re
          data_funct3
          data_ptw_addr1
          data_ptw_addr0
        ].freeze

        REQUIRED_RISCV_HIGH_LOOP_OUTPUTS = %w[
          inst_addr
          inst_ptw_addr1
          inst_ptw_addr0
          data_addr
          data_re
          data_funct3
          data_ptw_addr1
          data_ptw_addr0
        ].freeze

        REQUIRED_RISCV_FAST_LOOP_OUTPUTS = %w[
          inst_addr
          data_addr
          data_wdata
          data_we
          data_re
        ].freeze

        REQUIRED_RISCV_FAST_LOOP_OUTPUTS_NO_ADDR = %w[
          inst_addr
          data_wdata
          data_we
          data_re
        ].freeze

        REQUIRED_RISCV_FAST_LOOP_ADDR_OUTPUTS = %w[
          data_addr
        ].freeze

        REQUIRED_RISCV_FAST_LOOP_OUTPUTS_NO_WDATA = %w[
          inst_addr
          data_addr
          data_we
          data_re
        ].freeze

        REQUIRED_RISCV_FAST_LOOP_WDATA_OUTPUTS = %w[
          data_wdata
        ].freeze

        REQUIRED_RISCV_FAST_HIGH_LOOP_OUTPUTS = %w[
          inst_addr
          data_addr
          data_re
        ].freeze

        REQUIRED_RISCV_FAST_HIGH_LOOP_OUTPUTS_NO_ADDR = %w[
          inst_addr
          data_re
        ].freeze

        REQUIRED_RISCV_FAST_HIGH_LOOP_ADDR_OUTPUTS = %w[
          data_addr
        ].freeze

        RUNTIME_RISCV_OUTPUTS = [].freeze

        SUPPORTED_OPS = %w[
          arc.call
          arc.define
          arc.memory
          arc.memory_read_port
          arc.memory_write_port
          arc.output
          arc.state
          seq.firreg
          seq.firmem
          seq.firmem.read_port
          seq.firmem.write_port
          synth.aig.and_inv
          comb.add
          comb.and
          comb.concat
          comb.divu
          comb.extract
          comb.icmp
          comb.modu
          comb.mul
          comb.mux
          comb.or
          comb.replicate
          comb.shl
          comb.shru
          comb.sub
          comb.xor
          func.func
          hw.array
          hw.array_create
          hw.array_get
          hw.aggregate_constant
          hw.constant
          hw.output
          hw.module
          rhdl.alias
          seq.to_clock
        ].freeze

        DEFAULT_SCALAR_WIDTH_BITS = 32

        module_function

        def profile_module_for(profile)
          case profile.to_sym
          when :cpu8bit
            require_relative 'arc_to_gpu_lowering/profiles/cpu8bit'
            Profiles::Cpu8bit
          when :apple2
            require_relative 'arc_to_gpu_lowering/profiles/apple2'
            Profiles::Apple2
          when :riscv
            require_relative 'arc_to_gpu_lowering/profiles/riscv'
            Profiles::Riscv
          when :riscv_netlist
            require_relative 'arc_to_gpu_lowering/profiles/riscv_netlist'
            Profiles::RiscvNetlist
          else
            raise LoweringError, "Unsupported ArcToGPU profile: #{profile.inspect}"
          end
        end

        def lower(
          arc_mlir_path:,
          gpu_mlir_path:,
          metadata_path: nil,
          metal_source_path: nil,
          profile: :cpu8bit,
          require_arc_define: true,
          metadata_version: 'ArcToGpuLoweringV2',
          lowering_label: 'ArcToGpuLowering'
        )
          profile_impl = profile_module_for(profile)
          source = File.read(arc_mlir_path)
          source = profile_impl.prepare_source(source: source, lowerer: self)
          parsed = parse_arc_mlir(source)
          parsed = profile_impl.post_parse_transform(parsed: parsed, lowerer: self)
          summary = summarize(parsed)

          unsupported = summary[:ops].keys.reject { |op| SUPPORTED_OPS.include?(op) }
          unless unsupported.empty?
            raise LoweringError,
              "ArcToGPU lowering does not support ops: #{unsupported.sort.join(', ')}"
          end

          validate_top_module!(
            parsed,
            summary,
            required_inputs: profile_impl.required_inputs,
            required_outputs: profile_impl.required_outputs,
            require_arc_define: require_arc_define
          )

          gpu_mlir = emit_gpu_mlir(summary, lowering_label: lowering_label)
          File.write(gpu_mlir_path, gpu_mlir)

          inferred_scalar_bits = inferred_scalar_width_bits(parsed)
          pack_wide_scalars = profile_impl.pack_wide_scalars?(inferred_scalar_bits: inferred_scalar_bits)
          effective_scalar_bits = pack_wide_scalars ? DEFAULT_SCALAR_WIDTH_BITS : inferred_scalar_bits

          state_layout = build_state_layout(parsed, pack_wide_scalars: pack_wide_scalars)
          clock_tracking_slot_count = count_clock_tracking_slots(parsed.fetch(:top_module).fetch(:ops))
          state_slots = state_layout.sum { |entry| entry.fetch(:slot_count, 1) }
          state_count = state_slots + clock_tracking_slot_count
          output_state_slots = map_output_state_slots(parsed, state_layout)
          metal_entry = "#{summary[:top_module]}_arcgpu_kernel"
          top_input_layout = parsed.fetch(:top_module).fetch(:inputs).map do |p|
            { name: p.fetch(:name), width: p.fetch(:type).fetch(:width) }
          end
          top_output_layout = parsed.fetch(:top_module).fetch(:outputs).map do |p|
            { name: p.fetch(:name), width: p.fetch(:type).fetch(:width) }
          end

          runtime_input_name_set =
            if profile_impl.respond_to?(:runtime_input_names)
              profile_impl.runtime_input_names.to_set
            end
          runtime_output_name_set =
            if profile_impl.respond_to?(:runtime_output_names)
              profile_impl.runtime_output_names.to_set
            end
          runtime_input_layout =
            if runtime_input_name_set
              top_input_layout.select { |entry| runtime_input_name_set.include?(entry.fetch(:name)) }
            else
              top_input_layout
            end
          runtime_output_layout =
            if runtime_output_name_set
              top_output_layout.select { |entry| runtime_output_name_set.include?(entry.fetch(:name)) }
            else
              top_output_layout
            end

          if metal_source_path
            metal_source = profile_impl.emit_metal_source(
              lowerer: self,
              parsed: parsed,
              state_layout: state_layout,
              metal_entry: metal_entry,
              scalar_bits: effective_scalar_bits,
              pack_wide_scalars: pack_wide_scalars
            )
            File.write(metal_source_path, metal_source)
          end

          if metadata_path
            metadata = {
              version: metadata_version,
              profile: profile.to_s,
              module: summary[:top_module],
              top_inputs: summary[:top_inputs],
              top_outputs: summary[:top_outputs],
              top_input_layout: top_input_layout,
              top_output_layout: top_output_layout,
              op_counts: summary[:ops],
              arc_define_count: summary[:arc_define_count],
              arc_state_count: summary[:arc_state_count],
              arc_call_count: summary[:arc_call_count],
              source_bytes: source.bytesize,
              metal: {
                entry: metal_entry,
                state_count: state_count,
                io_struct: 'RhdlArcGpuIo',
                state_scalar_bits: effective_scalar_bits,
                state_scalar_msl_type: (effective_scalar_bits > 32 ? 'ulong' : 'uint'),
                packed_wide_scalars: pack_wide_scalars,
                runtime_input_layout: runtime_input_layout,
                runtime_output_layout: runtime_output_layout
              },
              state_layout: state_layout,
              output_state_slots: output_state_slots,
              poke_alias_state_slots: {
                'pc_reg__q' => output_state_slots['pc_out'],
                'acc_reg__q' => output_state_slots['acc_out'],
                'sp_reg__q' => output_state_slots['sp_out']
              }.compact
            }
            if profile_impl.respond_to?(:schedule_mode)
              metadata[:metal][:schedule_mode] = profile_impl.schedule_mode
            end
            if profile_impl.respond_to?(:fast_low_wdata_mode)
              metadata[:metal][:fast_low_wdata_mode] = profile_impl.fast_low_wdata_mode
            end
            if profile_impl.respond_to?(:fast_high_data_addr_mode)
              metadata[:metal][:fast_high_data_addr_mode] = profile_impl.fast_high_data_addr_mode
            end
            if profile_impl.respond_to?(:fast_low_data_addr_mode)
              metadata[:metal][:fast_low_data_addr_mode] = profile_impl.fast_low_data_addr_mode
            end
            if %i[riscv riscv_netlist].include?(profile.to_sym)
              metadata[:metal][:introspection] = riscv_runtime_introspection(parsed, state_layout, output_state_slots)
            end
            File.write(metadata_path, JSON.pretty_generate(metadata))
          end

          {
            module: summary[:top_module],
            profile: profile,
            arc_define_count: summary[:arc_define_count],
            arc_state_count: summary[:arc_state_count],
            arc_call_count: summary[:arc_call_count],
            op_counts: summary[:ops],
            metal_entry: metal_entry,
            state_count: state_count,
            state_scalar_bits: effective_scalar_bits
          }
        end

        def summarize(parsed)
          top = parsed.fetch(:top_module)
          {
            top_module: top.fetch(:name),
            top_inputs: top.fetch(:inputs).map { |p| p.fetch(:name) },
            top_outputs: top.fetch(:outputs).map { |p| p.fetch(:name) },
            arc_define_count: parsed.fetch(:functions).length,
            arc_state_count: top.fetch(:ops).count { |op| %i[arc_state seq_firreg].include?(op.fetch(:kind)) },
            arc_call_count: parsed.fetch(:functions).values.sum { |fn| fn.fetch(:ops).count { |op| op.fetch(:kind) == :arc_call } } +
              top.fetch(:ops).count { |op| op.fetch(:kind) == :arc_call },
            ops: parsed.fetch(:op_counts).sort.to_h
          }
        end

        def riscv_runtime_introspection(parsed, state_layout, output_state_slots)
          top = parsed.fetch(:top_module)
          output_widths = top.fetch(:outputs).each_with_object({}) do |output, acc|
            acc[output.fetch(:name)] = output.fetch(:type).fetch(:width).to_i
          end
          pc_slot = output_state_slots['debug_pc']
          pc_width = output_widths.fetch('debug_pc', 32)
          regfile_entry = state_layout.find do |entry|
            entry.fetch(:kind) == :arc_memory &&
              entry.fetch(:length, 0).to_i == 32 &&
              entry.fetch(:index_width, 0).to_i == 5 &&
              entry.fetch(:width, 0).to_i == 32 &&
              entry.fetch(:slots_per_element, 1).to_i == 1
          end

          {
            pc_slot: pc_slot ? pc_slot.to_i : -1,
            pc_width: pc_width,
            regfile_base_slot: regfile_entry ? regfile_entry.fetch(:index).to_i : -1,
            regfile_length: regfile_entry ? regfile_entry.fetch(:length).to_i : 0,
            regfile_slots_per_element: regfile_entry ? regfile_entry.fetch(:slots_per_element, 1).to_i : 0
          }
        end

        def validate_top_module!(
          parsed,
          summary,
          required_inputs: [],
          required_outputs: [],
          require_arc_define: true
        )
          if summary[:top_module].nil? || summary[:top_module].empty?
            raise LoweringError, 'ArcToGPU lowering could not find top hw.module in Arc MLIR'
          end

          if require_arc_define && summary[:arc_define_count].zero?
            raise LoweringError, 'ArcToGPU lowering expected at least one arc.define function'
          end

          if summary[:arc_state_count].zero?
            raise LoweringError, 'ArcToGPU lowering expected state register operations in top module'
          end

          missing_inputs = required_inputs - summary[:top_inputs]
          unless missing_inputs.empty?
            raise LoweringError,
              "ArcToGPU lowering top module missing required inputs: #{missing_inputs.join(', ')}"
          end

          missing_outputs = required_outputs - summary[:top_outputs]
          unless missing_outputs.empty?
            raise LoweringError,
              "ArcToGPU lowering top module missing required outputs: #{missing_outputs.join(', ')}"
          end

          functions = parsed.fetch(:functions)
          parsed.fetch(:top_module).fetch(:ops).each do |op|
            next unless %i[arc_call arc_state arc_memory_write_port].include?(op.fetch(:kind))

            callee = op.fetch(:callee)
            next if functions.key?(callee)

            raise LoweringError, "ArcToGPU lowering could not resolve callee @#{callee}"
          end

          parsed.fetch(:functions).each_value do |fn|
            fn.fetch(:ops).each do |op|
              next unless op.fetch(:kind) == :arc_call

              callee = op.fetch(:callee)
              next if functions.key?(callee)

              raise LoweringError, "ArcToGPU lowering could not resolve callee @#{callee}"
            end
          end
        end

        def emit_gpu_mlir(summary, lowering_label:)
          module_name = summary[:top_module]
          kernel_name = "#{module_name}_arc_to_gpu_eval"
          counts = [
            "arc_define=#{summary[:arc_define_count]}",
            "arc_state=#{summary[:arc_state_count]}",
            "arc_call=#{summary[:arc_call_count]}"
          ].join(', ')

          <<~MLIR
            // Auto-generated by RHDL::Codegen::FIRRTL::#{lowering_label}.
            // Source module: #{module_name}
            // Summary: #{counts}
            module attributes {rhdl.arc_to_gpu.version = "v2", rhdl.arc_to_gpu.module = "#{module_name}"} {
              gpu.module @#{module_name}_gpu {
                gpu.func @#{kernel_name}() kernel {
                  gpu.return
                }
              }
            }
          MLIR
        end

        def optimize_arc_mlir_source(source)
          return source if ENV['RHDL_ARC_TO_GPU_DISABLE_OPT'] == '1'
          return source unless command_available?('circt-opt')

          Tempfile.create(%w[rhdl_arc_to_gpu_input .mlir]) do |infile|
            Tempfile.create(%w[rhdl_arc_to_gpu_output .mlir]) do |outfile|
              infile.write(source)
              infile.flush

              cmd = [
                'circt-opt',
                infile.path,
                '--canonicalize',
                '--cse',
                '--symbol-dce',
                '-o',
                outfile.path
              ]
              _out, status = Open3.capture2e(*cmd)
              return source unless status.success?

              optimized = File.read(outfile.path)
              return optimized.empty? ? source : optimized
            end
          end
        rescue StandardError
          source
        end

        def run_circt_opt_pipeline(source, pass_args:)
          return source unless command_available?('circt-opt')

          Tempfile.create(%w[rhdl_arc_to_gpu_pipeline_input .mlir]) do |infile|
            Tempfile.create(%w[rhdl_arc_to_gpu_pipeline_output .mlir]) do |outfile|
              infile.write(source)
              infile.flush

              cmd = ['circt-opt', infile.path] + Array(pass_args) + ['-o', outfile.path]
              _out, status = Open3.capture2e(*cmd)
              return source unless status.success?

              transformed = File.read(outfile.path)
              return transformed.empty? ? source : transformed
            end
          end
        rescue StandardError
          source
        end

        def flatten_simple_arc_calls(parsed, max_ops: 12, max_depth: 2)
          return parsed if ENV['RHDL_ARC_TO_GPU_DISABLE_INLINE'] == '1'

          functions = deep_copy(parsed.fetch(:functions))
          top_module = deep_copy(parsed.fetch(:top_module))
          changed_any = false

          max_depth.times do
            candidates = functions.select do |name, fn|
              next false if fn.fetch(:ops).empty?
              next false if fn.fetch(:ops).length > max_ops
              next false if fn.fetch(:ops).any? { |op| op.fetch(:kind) == :arc_state }
              next false if fn.fetch(:ops).any? { |op| op.fetch(:kind) == :arc_call && op.fetch(:callee) == name }

              true
            end
            break if candidates.empty?

            changed_this_round = false
            candidates_set = candidates.keys.to_set

            functions.each_value do |fn|
              inlined_ops, changed = inline_calls_in_ops(
                ops: fn.fetch(:ops),
                functions: functions,
                candidates: candidates_set
              )
              fn[:ops] = inlined_ops
              changed_this_round ||= changed
            end

            top_inlined_ops, top_changed = inline_calls_in_ops(
              ops: top_module.fetch(:ops),
              functions: functions,
              candidates: candidates_set
            )
            top_module[:ops] = top_inlined_ops
            changed_this_round ||= top_changed

            changed_any ||= changed_this_round
            break unless changed_this_round
          end

          return parsed unless changed_any

          {
            functions: functions,
            top_module: top_module,
            op_counts: recompute_op_counts(functions: functions, top_module: top_module)
          }
        end

        # Fold constant-index array_get patterns produced by Arc/HW lowering:
        # - hw.array_get(hw.array_create(...), cst_idx) -> rhdl.alias(selected_operand)
        # - hw.array_get(hw.aggregate_constant(...), cst_idx) -> hw.constant(selected_value)
        #
        # This removes temporary array structs and array indexing branches in hot paths.
        def fold_constant_array_gets(parsed)
          functions = deep_copy(parsed.fetch(:functions))
          top_module = deep_copy(parsed.fetch(:top_module))
          changed_any = false

          fold_ops = lambda do |ops|
            producers = {}
            constant_values = {}
            transformed = []

            ops.each do |op|
              replacement = nil

              if op.fetch(:kind) == :array_get
                idx_value = constant_values[op.fetch(:index_ref)]
                array_producer = producers[op.fetch(:array_ref)]

                if !idx_value.nil? && array_producer
                  array_len = op.fetch(:array_type).fetch(:length).to_i
                  array_idx = idx_value.to_i
                  array_idx = 0 if array_idx >= array_len
                  array_idx = 0 if array_idx.negative?
                  producer_idx = (array_len - 1) - array_idx

                  case array_producer.fetch(:kind)
                  when :array_create
                    source_ref = array_producer.fetch(:operands).fetch(producer_idx)
                    replacement = {
                      kind: :alias,
                      op_name: 'rhdl.alias',
                      result_refs: op.fetch(:result_refs),
                      result_types: op.fetch(:result_types),
                      source_ref: source_ref
                    }
                  when :aggregate_constant
                    folded_value = array_producer.fetch(:values).fetch(producer_idx)
                    replacement = {
                      kind: :constant,
                      op_name: 'hw.constant',
                      result_refs: op.fetch(:result_refs),
                      result_types: op.fetch(:result_types),
                      value: folded_value
                    }
                  end
                end
              end

              current = replacement || op
              changed_any ||= !replacement.nil?
              transformed << current

              current.fetch(:result_refs).each do |ref|
                producers[ref] = current
              end

              if current.fetch(:kind) == :constant
                current.fetch(:result_refs).each { |ref| constant_values[ref] = current.fetch(:value) }
              elsif current.fetch(:kind) == :alias
                src = current.fetch(:source_ref)
                current.fetch(:result_refs).each do |ref|
                  if constant_values.key?(src)
                    constant_values[ref] = constant_values[src]
                  else
                    constant_values.delete(ref)
                  end
                end
              else
                current.fetch(:result_refs).each { |ref| constant_values.delete(ref) }
              end
            end

            transformed
          end

          functions.each_value do |fn|
            fn[:ops] = fold_ops.call(fn.fetch(:ops))
          end
          top_module[:ops] = fold_ops.call(top_module.fetch(:ops))

          return parsed unless changed_any

          {
            functions: functions,
            top_module: top_module,
            op_counts: recompute_op_counts(functions: functions, top_module: top_module)
          }
        end

        # Drop arc.define functions that are unreachable from top-module call/state/write roots.
        def prune_unreachable_functions(parsed)
          functions = parsed.fetch(:functions)
          return parsed if functions.empty?

          reachable = Set.new
          worklist = []

          enqueue_callees = lambda do |ops|
            ops.each do |op|
              case op.fetch(:kind)
              when :arc_call, :arc_state, :arc_memory_write_port
                callee = op[:callee]
                worklist << callee if callee && !reachable.include?(callee)
              end
            end
          end

          enqueue_callees.call(parsed.fetch(:top_module).fetch(:ops))

          until worklist.empty?
            callee = worklist.pop
            next if reachable.include?(callee)

            fn = functions[callee]
            next unless fn

            reachable << callee
            enqueue_callees.call(fn.fetch(:ops))
          end

          return parsed if reachable.length == functions.length

          pruned_functions = {}
          functions.each do |name, fn|
            pruned_functions[name] = deep_copy(fn) if reachable.include?(name)
          end

          top_module = deep_copy(parsed.fetch(:top_module))

          {
            functions: pruned_functions,
            top_module: top_module,
            op_counts: recompute_op_counts(functions: pruned_functions, top_module: top_module)
          }
        end

        def inline_calls_in_ops(ops:, functions:, candidates:)
          changed = false
          out = []

          ops.each do |op|
            if op.fetch(:kind) == :arc_call && candidates.include?(op.fetch(:callee))
              callee_fn = functions[op.fetch(:callee)]
              if callee_fn
                out.concat(inline_arc_call_op(call_op: op, callee_fn: callee_fn))
                changed = true
                next
              end
            end

            out << op
          end

          [out, changed]
        end

        def inline_arc_call_op(call_op:, callee_fn:)
          @inline_counter ||= 0
          call_id = @inline_counter
          @inline_counter += 1

          arg_ref_map = {}
          callee_fn.fetch(:args).each_with_index do |arg, idx|
            arg_ref_map[arg.fetch(:ref)] = call_op.fetch(:args).fetch(idx)
          end
          inner_result_map = {}

          map_ref = lambda do |ref|
            inner_result_map.fetch(ref, arg_ref_map.fetch(ref, ref))
          end

          inlined_ops = []
          callee_fn.fetch(:ops).each do |inner_op|
            cloned = deep_copy(inner_op)
            old_result_refs = cloned.fetch(:result_refs)
            new_result_refs = old_result_refs.map do |ref|
              token = sanitize_ident(ref.sub('%', ''))
              mapped = "%inl#{call_id}_#{token}"
              inner_result_map[ref] = mapped
              mapped
            end
            cloned[:result_refs] = new_result_refs

            case cloned.fetch(:kind)
            when :to_clock
              cloned[:input] = map_ref.call(cloned.fetch(:input))
            when :arc_call
              cloned[:args] = cloned.fetch(:args).map { |arg| map_ref.call(arg) }
            when :arc_state
              cloned[:args] = cloned.fetch(:args).map { |arg| map_ref.call(arg) }
              cloned[:clock_ref] = map_ref.call(cloned.fetch(:clock_ref))
              if cloned.fetch(:enable_ref)
                cloned[:enable_ref] = map_ref.call(cloned.fetch(:enable_ref))
              end
              if cloned.fetch(:reset_ref)
                cloned[:reset_ref] = map_ref.call(cloned.fetch(:reset_ref))
              end
            when :array_create, :icmp, :concat, :mux, :comb, :synth_aig_and_inv
              cloned[:operands] = cloned.fetch(:operands).map { |arg| map_ref.call(arg) }
            when :array_get
              cloned[:array_ref] = map_ref.call(cloned.fetch(:array_ref))
              cloned[:index_ref] = map_ref.call(cloned.fetch(:index_ref))
            when :extract, :replicate
              cloned[:input] = map_ref.call(cloned.fetch(:input))
            when :constant, :aggregate_constant
              # no-op
            else
              # keep unsupported kinds untouched
            end

            inlined_ops << cloned
          end

          callee_fn.fetch(:output_refs).each_with_index do |out_ref, idx|
            source_ref = map_ref.call(out_ref)
            target_ref = call_op.fetch(:result_refs).fetch(idx)
            next if source_ref == target_ref

            inlined_ops << {
              kind: :alias,
              op_name: 'rhdl.alias',
              result_refs: [target_ref],
              result_types: [call_op.fetch(:result_types).fetch(idx)],
              source_ref: source_ref
            }
          end

          inlined_ops
        end

        def recompute_op_counts(functions:, top_module:)
          counts = Hash.new(0)
          counts['arc.define'] = functions.length
          counts['func.func'] = functions.length
          counts['hw.module'] = 1
          counts['hw.output'] = 1

          functions.each_value do |fn|
            fn.fetch(:ops).each { |op| counts[op.fetch(:op_name)] += 1 }
            counts['arc.output'] += 1
          end
          top_module.fetch(:ops).each { |op| counts[op.fetch(:op_name)] += 1 }

          counts
        end

        def deep_copy(value)
          Marshal.load(Marshal.dump(value))
        end

        def parse_arc_mlir(text)
          lines = text.lines
          functions = {}
          top_module = nil
          op_counts = Hash.new(0)
          i = 0

          while i < lines.length
            line = clean_line(lines[i])
            stripped = line.strip

            if stripped.start_with?('arc.define @')
              header = stripped
              body = []
              i += 1
              while i < lines.length
                inner = clean_line(lines[i]).strip
                break if inner == '}'

                body << inner unless inner.empty?
                i += 1
              end
              fn = parse_define(header, body, op_counts)
              functions[fn.fetch(:name)] = fn
            elsif stripped.start_with?('hw.module @')
              header = stripped
              body = []
              i += 1
              while i < lines.length
                inner = clean_line(lines[i]).strip
                break if inner == '}'

                body << inner unless inner.empty?
                i += 1
              end
              top_module = parse_top_module(header, body, op_counts)
            elsif stripped.start_with?('func.func')
              op_counts['func.func'] += 1
            end

            i += 1
          end

          raise LoweringError, 'ArcToGPU lowering could not find top hw.module in Arc MLIR' unless top_module

          {
            functions: functions,
            top_module: top_module,
            op_counts: op_counts
          }
        end

        def parse_define(header, body_lines, op_counts)
          match = header.match(/\Aarc\.define\s+@([A-Za-z0-9_.$-]+)\((.*)\)\s*->\s*(.+?)\s*\{\z/)
          raise LoweringError, "Could not parse arc.define header: #{header}" unless match

          name = match[1]
          args = parse_arg_list(match[2])
          return_types = parse_return_types(match[3])

          ops = []
          output_refs = nil

          body_lines.each do |line|
            if line.start_with?('arc.output ')
              refs_raw, type_raw = line.sub('arc.output ', '').split(':', 2)
              refs = split_top_level(refs_raw).map(&:strip)
              types = parse_return_types(type_raw.to_s.strip)
              output_refs = refs
              op_counts['arc.output'] += 1
              next
            end

            op = parse_assignment(line)
            ops << op
            op_counts[op.fetch(:op_name)] += 1
          end

          raise LoweringError, "arc.define @#{name} missing arc.output" unless output_refs

          {
            name: name,
            args: args,
            return_types: return_types,
            ops: ops,
            output_refs: output_refs
          }
        end

        def parse_top_module(header, body_lines, op_counts)
          name, inputs, outputs = parse_hw_module_signature(header)
          raise LoweringError, "Could not parse hw.module signature: #{header}" if name.nil?

          ops = []
          hw_output_refs = nil

          body_lines.each do |line|
            if line.start_with?('hw.output ')
              refs_raw, _type_raw = line.sub('hw.output ', '').split(':', 2)
              hw_output_refs = split_top_level(refs_raw).map(&:strip)
              op_counts['hw.output'] += 1
              next
            end

            if line.start_with?('arc.memory_write_port ')
              op = parse_memory_write_port(line)
              ops << op
              op_counts[op.fetch(:op_name)] += 1
              next
            end

            if line.start_with?('seq.firmem.write_port ')
              op = parse_seq_firmem_write_port(line)
              ops << op
              op_counts[op.fetch(:op_name)] += 1
              next
            end

            op = parse_assignment(line, allow_arc_state: true)
            ops << op
            op_counts[op.fetch(:op_name)] += 1
          end

          raise LoweringError, 'Top hw.module missing hw.output' unless hw_output_refs
          op_counts['hw.module'] += 1

          {
            name: name,
            inputs: inputs,
            outputs: outputs,
            ops: ops,
            hw_output_refs: hw_output_refs
          }
        end

        def parse_assignment(line, allow_arc_state: false)
          match = line.match(/\A(%[A-Za-z0-9_.$#-]+(?::\d+)?)\s*=\s*(.+)\z/)
          raise LoweringError, "Could not parse assignment: #{line}" unless match

          lhs = match[1]
          rhs = match[2]
          result_refs = expand_lhs_result_refs(lhs)

          if (m = rhs.match(/\Ahw\.constant\s+(.+?)(?:\s*:\s*(.+))?\z/))
            value_raw = m[1].strip
            type = m[2] ? parse_type(m[2].strip) : TypeRef.new(kind: :scalar, width: 1)
            value = parse_constant_literal(value_raw, type)
            return {
              kind: :constant,
              op_name: 'hw.constant',
              result_refs: result_refs,
              result_types: [type],
              value: value
            }
          end

          if (m = rhs.match(/\Aseq\.to_clock\s+(%[A-Za-z0-9_.$#-]+)\z/))
            return {
              kind: :to_clock,
              op_name: 'seq.to_clock',
              result_refs: result_refs,
              result_types: [TypeRef.new(kind: :scalar, width: 1)],
              input: m[1]
            }
          end

          if (m = rhs.match(/\Aarc\.call\s+@([A-Za-z0-9_.$-]+)\((.*)\)\s*:\s*\((.*)\)\s*->\s*(.+)\z/))
            callee = m[1]
            args = parse_value_list(m[2])
            return_types = parse_return_types(m[4])
            return {
              kind: :arc_call,
              op_name: 'arc.call',
              result_refs: result_refs,
              result_types: return_types,
              callee: callee,
              args: args
            }
          end

          if allow_arc_state && (m = rhs.match(/\Aarc\.state\s+@([A-Za-z0-9_.$-]+)\((.*)\)\s+clock\s+(%[A-Za-z0-9_.$#-]+)(?:\s+enable\s+(%[A-Za-z0-9_.$#-]+))?(?:\s+reset\s+(%[A-Za-z0-9_.$#-]+))?\s+latency\s+(\d+)\s*:\s*\((.*)\)\s*->\s*(.+)\z/))
            callee = m[1]
            args = parse_value_list(m[2])
            clock_ref = m[3]
            enable_ref = m[4]
            reset_ref = m[5]
            latency = m[6].to_i
            return_types = parse_return_types(m[8].strip)
            if return_types.length != result_refs.length
              raise LoweringError,
                "arc.state result arity mismatch: refs=#{result_refs.length}, types=#{return_types.length}"
            end
            return {
              kind: :arc_state,
              op_name: 'arc.state',
              result_refs: result_refs,
              result_types: return_types,
              callee: callee,
              args: args,
              clock_ref: clock_ref,
              enable_ref: enable_ref,
              reset_ref: reset_ref,
              latency: latency
            }
          end

          if allow_arc_state && (m = rhs.match(/\Aseq\.firreg\s+(%[A-Za-z0-9_.$#-]+)\s+clock\s+(%[A-Za-z0-9_.$#-]+)\s+reset\s+(?:sync|async)\s+(%[A-Za-z0-9_.$#-]+)\s*,\s*(%[A-Za-z0-9_.$#-]+)(?:\s+\{[^{}]*\})?\s*:\s*(.+)\z/))
            source_ref = m[1]
            clock_ref = m[2]
            reset_ref = m[3]
            reset_value_ref = m[4]
            result_type = parse_type(m[5].strip)
            return {
              kind: :seq_firreg,
              op_name: 'seq.firreg',
              result_refs: result_refs,
              result_types: [result_type],
              source_ref: source_ref,
              clock_ref: clock_ref,
              reset_ref: reset_ref,
              reset_value_ref: reset_value_ref
            }
          end

          if allow_arc_state && (m = rhs.match(/\Aseq\.firreg\s+(%[A-Za-z0-9_.$#-]+)\s+clock\s+(%[A-Za-z0-9_.$#-]+)(?:\s+\{[^{}]*\})?\s*:\s*(.+)\z/))
            source_ref = m[1]
            clock_ref = m[2]
            result_type = parse_type(m[3].strip)
            return {
              kind: :seq_firreg,
              op_name: 'seq.firreg',
              result_refs: result_refs,
              result_types: [result_type],
              source_ref: source_ref,
              clock_ref: clock_ref,
              reset_ref: nil,
              reset_value_ref: nil
            }
          end

          if allow_arc_state && (m = rhs.match(/\Aseq\.firmem\s+.+\s*:\s*<\s*(\d+)\s*x\s*(\d+)\s*>\z/))
            memory_type = parse_seq_firmem_type(length_text: m[1], width_text: m[2])
            return {
              kind: :arc_memory,
              op_name: 'seq.firmem',
              result_refs: result_refs,
              result_types: [memory_type],
              memory_type: memory_type
            }
          end

          if allow_arc_state && (m = rhs.match(/\Aseq\.firmem\.read_port\s+(%[A-Za-z0-9_.$#-]+)\[(%[A-Za-z0-9_.$#-]+)\]\s*,\s*clock\s+(%[A-Za-z0-9_.$#-]+)(?:\s+\{[^{}]*\})?\s*:\s*<\s*(\d+)\s*x\s*(\d+)\s*>\z/))
            memory_ref = m[1]
            index_ref = m[2]
            memory_type = parse_seq_firmem_type(length_text: m[4], width_text: m[5])
            elem_type = memory_type.fetch(:element)
            return {
              kind: :arc_memory_read_port,
              op_name: 'seq.firmem.read_port',
              result_refs: result_refs,
              result_types: [elem_type],
              memory_ref: memory_ref,
              index_ref: index_ref,
              memory_type: memory_type,
              index_type: TypeRef.new(kind: :scalar, width: memory_type.fetch(:index_width))
            }
          end

          if allow_arc_state && (m = rhs.match(/\Aarc\.memory\s+(.+)\z/))
            memory_type = parse_type(m[1].strip)
            unless memory_type.memory?
              raise LoweringError, "arc.memory requires memory type, got #{m[1].strip}"
            end
            return {
              kind: :arc_memory,
              op_name: 'arc.memory',
              result_refs: result_refs,
              result_types: [memory_type],
              memory_type: memory_type
            }
          end

          if allow_arc_state && (m = rhs.match(/\Aarc\.memory_read_port\s+(%[A-Za-z0-9_.$#-]+)\[(%[A-Za-z0-9_.$#-]+)\]\s*:\s*(.+)\z/))
            memory_ref = m[1]
            index_ref = m[2]
            memory_type = parse_type(m[3].strip)
            unless memory_type.memory?
              raise LoweringError, "arc.memory_read_port requires memory type, got #{m[3].strip}"
            end
            elem_type = memory_type.fetch(:element)
            return {
              kind: :arc_memory_read_port,
              op_name: 'arc.memory_read_port',
              result_refs: result_refs,
              result_types: [elem_type],
              memory_ref: memory_ref,
              index_ref: index_ref,
              memory_type: memory_type,
              index_type: TypeRef.new(kind: :scalar, width: memory_type.fetch(:index_width))
            }
          end

          if (m = rhs.match(/\Ahw\.array_create\s+(.+)\s*:\s*(.+)\z/))
            operands = parse_value_list(m[1])
            elem_type = parse_type(m[2].strip)
            array_type = TypeRef.new(kind: :array, length: operands.length, element: elem_type)
            return {
              kind: :array_create,
              op_name: 'hw.array_create',
              result_refs: result_refs,
              result_types: [array_type],
              operands: operands,
              element_type: elem_type
            }
          end

          if (m = rhs.match(/\Ahw\.array_get\s+(%[A-Za-z0-9_.$#-]+)\[(%[A-Za-z0-9_.$#-]+)\]\s*:\s*(!hw\.array<[^>]+>),\s*(.+)\z/))
            array_ref = m[1]
            index_ref = m[2]
            array_type = parse_type(m[3])
            index_type = parse_type(m[4])
            elem_type = array_type.fetch(:element)
            return {
              kind: :array_get,
              op_name: 'hw.array_get',
              result_refs: result_refs,
              result_types: [elem_type],
              array_ref: array_ref,
              index_ref: index_ref,
              array_type: array_type,
              index_type: index_type
            }
          end

          if (m = rhs.match(/\Ahw\.aggregate_constant\s+\[(.*)\]\s*:\s*(.+)\z/))
            values_raw = split_top_level(m[1])
            out_type = parse_type(m[2].strip)
            unless out_type.array?
              raise LoweringError, 'hw.aggregate_constant currently only supported for !hw.array outputs'
            end

            elem_type = out_type.fetch(:element)
            values = values_raw.map do |entry|
              vm = entry.strip.match(/\A(.+?)\s*:\s*(.+)\z/)
              raise LoweringError, "Could not parse hw.aggregate_constant element: #{entry}" unless vm

              value = parse_constant_literal(vm[1].strip, elem_type)
              value_type = parse_type(vm[2].strip)
              unless value_type.scalar? && value_type.fetch(:width) == elem_type.fetch(:width)
                raise LoweringError,
                  "hw.aggregate_constant element type mismatch: expected i#{elem_type.fetch(:width)}, got #{vm[2].strip}"
              end
              value
            end

            unless values.length == out_type.fetch(:length)
              raise LoweringError,
                "hw.aggregate_constant length mismatch: expected #{out_type.fetch(:length)}, got #{values.length}"
            end

            return {
              kind: :aggregate_constant,
              op_name: 'hw.aggregate_constant',
              result_refs: result_refs,
              result_types: [out_type],
              values: values
            }
          end

          if (m = rhs.match(/\Acomb\.icmp(?:\s+bin)?\s+([A-Za-z_]+)\s+(.+)\s*:\s*(.+)\z/))
            predicate = m[1]
            operands = parse_value_list(m[2])
            return {
              kind: :icmp,
              op_name: 'comb.icmp',
              result_refs: result_refs,
              result_types: [TypeRef.new(kind: :scalar, width: 1)],
              predicate: predicate,
              operands: operands,
              operand_types: parse_return_types(m[3])
            }
          end

          if (m = rhs.match(/\Acomb\.concat\s+(.+)\s*:\s*(.+)\z/))
            operands = parse_value_list(m[1])
            operand_types = parse_return_types(m[2])
            total_width = operand_types.sum { |t| t.fetch(:width) }
            return {
              kind: :concat,
              op_name: 'comb.concat',
              result_refs: result_refs,
              result_types: [TypeRef.new(kind: :scalar, width: total_width)],
              operands: operands,
              operand_types: operand_types
            }
          end

          if (m = rhs.match(/\Acomb\.extract\s+(%[A-Za-z0-9_.$#-]+)(?:\s+\{[^{}]*\})?\s+from\s+(\d+)(?:\s+\{[^{}]*\})?\s*:\s*\((.+)\)\s*->\s*(.+)\z/))
            input = m[1]
            from = m[2].to_i
            input_type = parse_type(m[3].strip)
            result_type = parse_type(m[4].strip)
            return {
              kind: :extract,
              op_name: 'comb.extract',
              result_refs: result_refs,
              result_types: [result_type],
              input: input,
              from: from,
              input_type: input_type
            }
          end

          if (m = rhs.match(/\Acomb\.replicate\s+(%[A-Za-z0-9_.$#-]+)\s*:\s*\((.+)\)\s*->\s*(.+)\z/))
            input = m[1]
            input_type = parse_type(m[2].strip)
            result_type = parse_type(m[3].strip)
            return {
              kind: :replicate,
              op_name: 'comb.replicate',
              result_refs: result_refs,
              result_types: [result_type],
              input: input,
              input_type: input_type
            }
          end

          if (m = rhs.match(/\Acomb\.(add|sub|mul|divu|modu|shl|shru|xor|or|and|mux)(?:\s+bin)?\s+(.+)\s*:\s*(.+)\z/))
            op = m[1]
            operands = parse_value_list(m[2])
            result_type = parse_type(m[3].strip)
            kind = if op == 'mux'
              :mux
            else
              :comb
            end
            return {
              kind: kind,
              op_name: "comb.#{op}",
              comb_op: op,
              result_refs: result_refs,
              result_types: [result_type],
              operands: operands
            }
          end

          if (m = rhs.match(/\Asynth\.aig\.and_inv\s+(.+)\s*:\s*(.+)\z/))
            operand_refs = []
            invert_flags = []
            split_top_level(m[1]).map(&:strip).each do |entry|
              if (nm = entry.match(/\Anot\s+(%[A-Za-z0-9_.$#-]+)\b/))
                operand_refs << nm[1]
                invert_flags << true
              elsif (vm = entry.match(/\A(%[A-Za-z0-9_.$#-]+)\b/))
                operand_refs << vm[1]
                invert_flags << false
              else
                raise LoweringError, "Could not parse synth.aig.and_inv operand: #{entry}"
              end
            end
            result_type = parse_type(m[2].strip)
            return {
              kind: :synth_aig_and_inv,
              op_name: 'synth.aig.and_inv',
              result_refs: result_refs,
              result_types: [result_type],
              operands: operand_refs,
              invert_flags: invert_flags
            }
          end

          op_token = rhs.split(/\s+/, 2).first.to_s
          if op_token.include?('.')
            raise LoweringError, "ArcToGPU lowering does not support ops: #{op_token}"
          end

          raise LoweringError, "Unsupported Arc operation line: #{line}"
        end

        def parse_memory_write_port(line)
          m = line.match(/\Aarc\.memory_write_port\s+(%[A-Za-z0-9_.$#-]+)\s*,\s*@([A-Za-z0-9_.$-]+)\((.*)\)\s+clock\s+(%[A-Za-z0-9_.$#-]+)(?:\s+(enable))?\s+latency\s+(\d+)\s*:\s*(.+)\z/)
          raise LoweringError, "Could not parse arc.memory_write_port: #{line}" unless m

          memory_ref = m[1]
          callee = m[2]
          args = parse_value_list(m[3])
          clock_ref = m[4]
          has_enable = !m[5].nil?
          latency = m[6].to_i
          type_parts = split_top_level(m[7])
          raise LoweringError, "arc.memory_write_port missing type list: #{line}" if type_parts.empty?

          memory_type = parse_type(type_parts.first.strip)
          unless memory_type.memory?
            raise LoweringError,
              "arc.memory_write_port expected memory type first, got #{type_parts.first.strip}"
          end

          write_result_types = type_parts[1..].to_a.map { |part| parse_type(part.strip) }
          if write_result_types.length < 3
            raise LoweringError,
              "arc.memory_write_port expects at least addr/data/we tuple, got #{write_result_types.length}"
          end

          {
            kind: :arc_memory_write_port,
            op_name: 'arc.memory_write_port',
            result_refs: [],
            result_types: [],
            memory_ref: memory_ref,
            memory_type: memory_type,
            callee: callee,
            args: args,
            clock_ref: clock_ref,
            has_enable: has_enable,
            latency: latency,
            write_result_types: write_result_types
          }
        end

        def parse_seq_firmem_write_port(line)
          m = line.match(
            /\Aseq\.firmem\.write_port\s+(%[A-Za-z0-9_.$#-]+)\[(%[A-Za-z0-9_.$#-]+)\]\s*=\s*(%[A-Za-z0-9_.$#-]+)\s*,\s*clock\s+(%[A-Za-z0-9_.$#-]+)(?:\s+enable\s+(%[A-Za-z0-9_.$#-]+))?(?:\s+\{[^{}]*\})?\s*:\s*<\s*(\d+)\s*x\s*(\d+)\s*>\z/
          )
          raise LoweringError, "Could not parse seq.firmem.write_port: #{line}" unless m

          memory_ref = m[1]
          addr_ref = m[2]
          data_ref = m[3]
          clock_ref = m[4]
          enable_ref = m[5]
          memory_type = parse_seq_firmem_type(length_text: m[6], width_text: m[7])
          {
            kind: :seq_memory_write_port,
            op_name: 'seq.firmem.write_port',
            result_refs: [],
            result_types: [],
            memory_ref: memory_ref,
            addr_ref: addr_ref,
            data_ref: data_ref,
            clock_ref: clock_ref,
            enable_ref: enable_ref,
            memory_type: memory_type
          }
        end

        def parse_seq_firmem_type(length_text:, width_text:)
          length = length_text.to_i
          width = width_text.to_i
          raise LoweringError, "Invalid seq.firmem length: #{length_text}" if length <= 0
          raise LoweringError, "Invalid seq.firmem element width: #{width_text}" if width <= 0

          TypeRef.new(
            kind: :memory,
            length: length,
            element: TypeRef.new(kind: :scalar, width: width),
            index_width: index_width_for_length(length)
          )
        end

        def index_width_for_length(length)
          return 1 if length <= 1

          width = 0
          value = length - 1
          while value > 0
            value >>= 1
            width += 1
          end
          width
        end

        def parse_hw_module_signature(line)
          match = line.match(/\Ahw\.module\s+@([A-Za-z0-9_.$-]+)\((.*)\)\s*\{\z/)
          return [nil, [], []] unless match

          name = match[1]
          ports_raw = match[2]
          inputs = []
          outputs = []

          split_top_level(ports_raw).each do |port|
            if (m = port.match(/\Ain\s+%([A-Za-z0-9_.$-]+)\s*:\s*(.+)\z/))
              inputs << { name: m[1], type: parse_type(m[2].strip) }
              next
            end
            if (m = port.match(/\Aout\s+([A-Za-z0-9_.$-]+)\s*:\s*(.+)\z/))
              outputs << { name: m[1], type: parse_type(m[2].strip) }
            end
          end

          [name, inputs, outputs]
        end

        def parse_type(text)
          t = text.strip
          if (m = t.match(/\Ai(\d+)\z/))
            return TypeRef.new(kind: :scalar, width: m[1].to_i)
          end

          return TypeRef.new(kind: :scalar, width: 1) if t == '!seq.clock'

          if (m = t.match(/\A!hw\.array<(\d+)x(.+)>\z/))
            len = m[1].to_i
            elem = parse_type(m[2].strip)
            return TypeRef.new(kind: :array, length: len, element: elem)
          end

          if (m = t.match(/\A(?:!arc\.memory)?<\s*(\d+)\s*x\s*(.+)\s*,\s*(i\d+)\s*>\z/))
            len = m[1].to_i
            elem = parse_type(m[2].strip)
            idx = parse_type(m[3].strip)
            unless idx.scalar?
              raise LoweringError, "arc.memory index type must be scalar: #{m[3].strip}"
            end
            return TypeRef.new(kind: :memory, length: len, element: elem, index_width: idx.fetch(:width))
          end

          raise LoweringError, "Unsupported type in ArcToGPU lowering: #{text}"
        end

        def parse_return_types(text)
          raw = text.to_s.strip
          return [] if raw.empty?

          if raw.start_with?('(') && raw.end_with?(')')
            inner = raw[1..-2]
            split_top_level(inner).map { |entry| parse_type(entry.strip) }
          elsif split_top_level(raw).length > 1
            split_top_level(raw).map { |entry| parse_type(entry.strip) }
          else
            [parse_type(raw)]
          end
        end

        def parse_arg_list(text)
          return [] if text.to_s.strip.empty?

          split_top_level(text).map do |entry|
            m = entry.strip.match(/\A(%[A-Za-z0-9_.$#-]+)\s*:\s*(.+)\z/)
            raise LoweringError, "Could not parse arg entry: #{entry}" unless m

            {
              ref: m[1],
              type: parse_type(m[2].strip)
            }
          end
        end

        def parse_value_list(text)
          value_text = text.to_s.strip
          return [] if value_text.empty?

          split_top_level(value_text).map do |entry|
            parse_value_ref(entry)
          end
        end

        def parse_value_ref(entry)
          m = entry.to_s.strip.match(/\A(%[A-Za-z0-9_.$#-]+)\b/)
          raise LoweringError, "Could not parse SSA value reference: #{entry}" unless m

          m[1]
        end

        def parse_constant_literal(value_raw, type)
          token = value_raw.strip
          return 1 if token == 'true'
          return 0 if token == 'false'

          value = begin
            Integer(token, 0)
          rescue ArgumentError
            token.to_i
          end
          return mask_value(value, type.fetch(:width)) if type&.scalar?

          value
        end

        def expand_lhs_result_refs(lhs)
          if (m = lhs.match(/\A(%[A-Za-z0-9_.$#-]+):(\d+)\z/))
            base = m[1]
            count = m[2].to_i
            return Array.new(count) { |idx| "#{base}##{idx}" }
          end

          [lhs]
        end

        def with_scalar_config(bits, pack_wide_scalars: false, narrow_scalar_types: nil)
          prev = @scalar_width_bits
          prev_pack = @pack_wide_scalars
          prev_narrow = @narrow_scalar_types
          @scalar_width_bits = bits.to_i > 32 ? 64 : DEFAULT_SCALAR_WIDTH_BITS
          @pack_wide_scalars = !!pack_wide_scalars
          @narrow_scalar_types = if narrow_scalar_types.nil?
            ENV['RHDL_ARC_TO_GPU_NARROW_TYPES'] == '1'
          else
            !!narrow_scalar_types
          end
          yield
        ensure
          @scalar_width_bits = prev
          @pack_wide_scalars = prev_pack
          @narrow_scalar_types = prev_narrow
        end

        def scalar_width_bits
          bits = @scalar_width_bits || DEFAULT_SCALAR_WIDTH_BITS
          bits > 32 ? 64 : 32
        end

        def scalar_msl_type
          scalar_width_bits > 32 ? 'ulong' : 'uint'
        end

        def pack_wide_scalars?
          !!@pack_wide_scalars
        end

        def scalar_zero_literal
          scalar_width_bits > 32 ? '0ul' : '0u'
        end

        def scalar_one_literal
          scalar_width_bits > 32 ? '1ul' : '1u'
        end

        def scalar_full_mask_const
          scalar_width_bits > 32 ? '0xFFFFFFFFFFFFFFFFul' : '0xFFFFFFFFu'
        end

        def inferred_scalar_width_bits(parsed)
          max_width = 1
          visit_type = lambda do |type|
            next if type.nil?

            if type.scalar?
              max_width = [max_width, type.fetch(:width)].max
            elsif type.array?
              visit_type.call(type.fetch(:element))
            elsif type.memory?
              visit_type.call(type.fetch(:element))
            end
          end

          parsed.fetch(:functions).each_value do |fn|
            fn.fetch(:args).each { |arg| visit_type.call(arg.fetch(:type)) }
            fn.fetch(:return_types).each { |type| visit_type.call(type) }
            fn.fetch(:ops).each do |op|
              op.fetch(:result_types).each { |type| visit_type.call(type) }
              visit_type.call(op[:array_type]) if op.key?(:array_type)
            end
          end

          top = parsed.fetch(:top_module)
          top.fetch(:inputs).each { |input| visit_type.call(input.fetch(:type)) }
          top.fetch(:outputs).each { |output| visit_type.call(output.fetch(:type)) }
          top.fetch(:ops).each do |op|
            op.fetch(:result_types).each { |type| visit_type.call(type) }
            visit_type.call(op[:array_type]) if op.key?(:array_type)
          end

          max_width > 32 ? 64 : 32
        end

        def build_state_layout(parsed, pack_wide_scalars: false)
          state_layout = []
          next_index = 0
          parsed.fetch(:top_module).fetch(:ops).each do |op|
            case op.fetch(:kind)
            when :arc_state, :seq_firreg
              if op.fetch(:kind) == :arc_state && op.fetch(:latency) != 1
                raise LoweringError, 'ArcToGPU lowering currently requires arc.state latency 1'
              end

              op.fetch(:result_refs).each_with_index do |ref, idx|
                type = op.fetch(:result_types).fetch(idx)
                unless type.scalar?
                  raise LoweringError, 'ArcToGPU lowering only supports scalar state register outputs'
                end

                slot_count = if pack_wide_scalars && type.fetch(:width) > 32
                  (type.fetch(:width) + 31) / 32
                else
                  1
                end

                state_layout << {
                  index: next_index,
                  slot_count: slot_count,
                  result_ref: ref,
                  width: type.fetch(:width),
                  kind: :arc_state,
                  type: type,
                  callee: op[:callee],
                  has_enable: !op[:enable_ref].nil?,
                  has_reset: !op[:reset_ref].nil?
                }
                next_index += slot_count
              end
            when :arc_memory
              ref = op.fetch(:result_refs).first
              memory_type = op.fetch(:memory_type)
              element_type = memory_type.fetch(:element)
              unless element_type.scalar?
                raise LoweringError, 'ArcToGPU lowering only supports scalar arc.memory element types'
              end

              slots_per_element = if pack_wide_scalars && element_type.fetch(:width) > 32
                (element_type.fetch(:width) + 31) / 32
              else
                1
              end
              slot_count = memory_type.fetch(:length) * slots_per_element

              state_layout << {
                index: next_index,
                slot_count: slot_count,
                result_ref: ref,
                width: element_type.fetch(:width),
                kind: :arc_memory,
                type: memory_type,
                element_type: element_type,
                length: memory_type.fetch(:length),
                index_width: memory_type.fetch(:index_width),
                slots_per_element: slots_per_element
              }
              next_index += slot_count
            end
          end
          state_layout
        end

        def map_output_state_slots(parsed, state_layout)
          ref_to_slot = {}
          state_layout.each { |entry| ref_to_slot[entry.fetch(:result_ref)] = entry.fetch(:index) }

          top = parsed.fetch(:top_module)
          output_names = top.fetch(:outputs).map { |o| o.fetch(:name) }
          output_refs = top.fetch(:hw_output_refs)

          mapping = {}
          output_names.each_with_index do |name, idx|
            ref = output_refs[idx]
            mapping[name] = ref_to_slot[ref] if ref_to_slot.key?(ref)
          end

          mapping
        end

        def count_clock_tracking_slots(ops)
          ops.each_with_object(Set.new) do |op, refs|
            next unless %i[arc_state seq_firreg arc_memory_write_port seq_memory_write_port].include?(op.fetch(:kind))

            refs << op.fetch(:clock_ref)
          end.length
        end

        def emit_metal_source(
          parsed:,
          state_layout:,
          metal_entry:,
          scalar_bits:,
          pack_wide_scalars: false,
          use_state_snapshot: true,
          split_post_comb_liveness: false,
          trust_state_masks: false,
          load_state_in_comb_fn: false,
          eval_always_inline: false,
          schedule_aware_emit: false
        )
          with_scalar_config(scalar_bits, pack_wide_scalars: pack_wide_scalars) do
            top = parsed.fetch(:top_module)
            functions = parsed.fetch(:functions)

            array_types = collect_array_types(parsed)
            fn_ret_structs = functions.values.select { |fn| fn.fetch(:return_types).length > 1 }

            source = +""
            source << "#include <metal_stdlib>\n"
            source << "using namespace metal;\n\n"
            source << emit_wide_helpers << "\n" if pack_wide_scalars?

          source << "struct RhdlArcGpuIo {\n"
          source << "  uint rst;\n"
          source << "  uint clk;\n"
          source << "  uint last_clk;\n"
          source << "  uint mem_data_in;\n"
          source << "  uint mem_data_out;\n"
          source << "  uint mem_addr;\n"
          source << "  uint mem_write_en;\n"
          source << "  uint mem_read_en;\n"
          source << "  uint pc_out;\n"
          source << "  uint acc_out;\n"
          source << "  uint sp_out;\n"
          source << "  uint halted;\n"
          source << "  uint state_out;\n"
          source << "  uint zero_flag_out;\n"
          source << "  uint cycle_budget;\n"
          source << "  uint cycles_ran;\n"
          source << "};\n\n"

          array_types.each do |arr|
            source << "struct #{array_struct_name(arr)} {\n"
            source << "  #{array_element_metal_type(arr)} v[#{arr.fetch(:length)}];\n"
            source << "};\n\n"
          end

          fn_ret_structs.each do |fn|
            source << "struct #{ret_struct_name(fn.fetch(:name))} {\n"
            fn.fetch(:return_types).each_with_index do |ret_type, idx|
              source << "  #{metal_type_for(ret_type)} v#{idx};\n"
            end
            source << "};\n\n"
          end

          source << "struct #{top_output_struct_name(top.fetch(:name))} {\n"
          top.fetch(:outputs).each do |out|
            source << "  #{metal_type_for(out.fetch(:type))} #{sanitize_ident(out.fetch(:name))};\n"
          end
          source << "};\n\n"

          source << "static inline __attribute__((always_inline)) #{scalar_msl_type} rhdl_mask_bits(#{scalar_msl_type} value, uint width) {\n"
          source << "  if (width >= #{scalar_width_bits}u) { return value; }\n"
          source << "  if (width == 0u) { return #{scalar_zero_literal}; }\n"
          source << "  #{scalar_msl_type} mask = (#{scalar_one_literal} << width) - #{scalar_one_literal};\n"
          source << "  return value & mask;\n"
          source << "}\n\n"

            functions.values.each do |fn|
              source << emit_define_function(fn, functions)
              source << "\n"
            end

            source << emit_top_eval_function(
              top,
              functions,
              state_layout,
              use_state_snapshot: use_state_snapshot,
              split_post_comb_liveness: split_post_comb_liveness,
              trust_state_masks: trust_state_masks,
              load_state_in_comb_fn: load_state_in_comb_fn,
              schedule_aware_emit: schedule_aware_emit,
              schedule_phase_tag: "#{sanitize_ident(top.fetch(:name))}_main",
              always_inline_eval: eval_always_inline
            )
            source << "\n"
            source << emit_write_outputs_helper(top)
            source << "\n"
            source << emit_kernel(top: top, metal_entry: metal_entry, state_layout: state_layout)

            source
          end
        end

        def emit_metal_source_apple2(parsed:, state_layout:, metal_entry:)
          top = parsed.fetch(:top_module)
          functions = parsed.fetch(:functions)
          phase_split_enabled = ENV['RHDL_ARC_TO_GPU_PHASE_SPLIT'] == '1'
          dirty_settle_enabled = ENV['RHDL_ARC_TO_GPU_DIRTY_SETTLE'] == '1'
          full_eval_fn = top_eval_fn_name(top.fetch(:name))
          update_loop_eval_fn = "#{full_eval_fn}_update_loop"
          comb_loop_eval_fn = phase_split_enabled ? "#{full_eval_fn}_comb_loop" : update_loop_eval_fn
          low_loop_eval_fn = phase_split_enabled ? comb_loop_eval_fn : "#{full_eval_fn}_low_loop"

          array_types = collect_array_types(parsed)
          fn_ret_structs = functions.values.select { |fn| fn.fetch(:return_types).length > 1 }

          source = +""
          source << "#include <metal_stdlib>\n"
          source << "using namespace metal;\n\n"
          source << emit_wide_helpers << "\n" if pack_wide_scalars?

          source << "struct RhdlArcGpuIo {\n"
          source << "  uint cycle_budget;\n"
          source << "  uint cycles_ran;\n"
          source << "  uint last_clock;\n"
          source << "  uint prev_speaker;\n"
          source << "  uint speaker_toggles;\n"
          source << "  uint text_dirty;\n"
          top.fetch(:inputs).each do |input|
            source << "  uint #{sanitize_ident(input.fetch(:name))};\n"
          end
          top.fetch(:outputs).each do |out|
            source << "  uint #{sanitize_ident(out.fetch(:name))};\n"
          end
          source << "};\n\n"

          array_types.each do |arr|
            source << "struct #{array_struct_name(arr)} {\n"
            source << "  #{array_element_metal_type(arr)} v[#{arr.fetch(:length)}];\n"
            source << "};\n\n"
          end

          fn_ret_structs.each do |fn|
            source << "struct #{ret_struct_name(fn.fetch(:name))} {\n"
            fn.fetch(:return_types).each_with_index do |ret_type, idx|
              source << "  #{metal_type_for(ret_type)} v#{idx};\n"
            end
            source << "};\n\n"
          end

          source << "struct #{top_output_struct_name(top.fetch(:name))} {\n"
          top.fetch(:outputs).each do |out|
            source << "  #{metal_type_for(out.fetch(:type))} #{sanitize_ident(out.fetch(:name))};\n"
          end
          source << "};\n\n"

          loop_step_struct = "#{sanitize_ident(top.fetch(:name))}_loop_step"
          source << "struct #{loop_step_struct} {\n"
          source << "  #{scalar_msl_type} ram_addr;\n"
          source << "  #{scalar_msl_type} ram_we;\n"
          source << "  #{scalar_msl_type} d;\n"
          source << "  #{scalar_msl_type} speaker;\n"
          source << "  #{scalar_msl_type} state_dirty;\n"
          source << "};\n\n"

          source << "static inline __attribute__((always_inline)) #{scalar_msl_type} rhdl_mask_bits(#{scalar_msl_type} value, uint width) {\n"
          source << "  if (width >= #{scalar_width_bits}u) { return value; }\n"
          source << "  if (width == 0u) { return #{scalar_zero_literal}; }\n"
          source << "  #{scalar_msl_type} mask = (#{scalar_one_literal} << width) - #{scalar_one_literal};\n"
          source << "  return value & mask;\n"
          source << "}\n\n"

          functions.values.each do |fn|
            source << emit_define_function(fn, functions)
            source << "\n"
          end

          if phase_split_enabled
            source << emit_top_eval_function(
              top,
              functions,
              state_layout,
              state_address_space: 'thread',
              use_state_snapshot: false,
              fn_name: comb_loop_eval_fn,
              output_names: %w[ram_addr ram_we d speaker],
              out_struct: loop_step_struct,
              compact_output_struct: true,
              seed_all_outputs: true,
              update_state: false,
              extra_output_assignments: { 'state_dirty' => '0u' }
            )
            source << "\n"
          end

          unless phase_split_enabled
            source << emit_top_eval_function(
              top,
              functions,
              state_layout,
              state_address_space: 'thread',
              fn_name: low_loop_eval_fn,
              output_names: %w[ram_addr ram_we d speaker],
              out_struct: loop_step_struct,
              compact_output_struct: true,
              emit_post_comb: false,
              update_state: true,
              extra_output_assignments: { 'state_dirty' => '0u' }
            )
            source << "\n"
          end

          source << emit_top_eval_function(
            top,
            functions,
            state_layout,
            state_address_space: 'thread',
            fn_name: update_loop_eval_fn,
            output_names: %w[ram_addr ram_we d speaker],
            out_struct: loop_step_struct,
            compact_output_struct: true,
            emit_post_comb: false,
            update_state: true,
            track_state_dirty: dirty_settle_enabled,
            extra_output_assignments: { 'state_dirty' => (dirty_settle_enabled ? 'state_dirty' : '1u') }
          )
          source << "\n"

          source << emit_top_eval_function(
            top,
            functions,
            state_layout,
            state_address_space: 'thread',
            fn_name: full_eval_fn
          )
          source << "\n"
          source << emit_write_outputs_helper(top)
          source << "\n"
          source << emit_kernel_apple2(
            top: top,
            metal_entry: metal_entry,
            state_layout: state_layout,
            low_eval_fn: low_loop_eval_fn,
            comb_eval_fn: comb_loop_eval_fn,
            update_eval_fn: update_loop_eval_fn,
            phase_split_enabled: phase_split_enabled,
            dirty_settle_enabled: dirty_settle_enabled,
            full_eval_fn: full_eval_fn
          )

          source
        end

        def emit_metal_source_riscv(
          parsed:,
          state_layout:,
          metal_entry:,
          dirty_settle_enabled: false,
          schedule_aware_emit: false,
          split_low_wdata_eval: false,
          split_high_data_addr_eval: false,
          split_low_data_addr_eval: false,
          runtime_output_names: nil
        )
          top = parsed.fetch(:top_module)
          functions = parsed.fetch(:functions)
          cold_memory_layout = state_layout.select do |entry|
            entry.fetch(:kind) == :arc_memory && entry.fetch(:slot_count, 1).to_i >= 1024
          end
          cold_memory_bases = cold_memory_layout.map { |entry| entry.fetch(:index) }.to_set

          array_types = collect_array_types(parsed)
          fn_ret_structs = functions.values.select { |fn| fn.fetch(:return_types).length > 1 }

          source = +""
          source << "#include <metal_stdlib>\n"
          source << "using namespace metal;\n\n"
          source << emit_wide_helpers << "\n" if pack_wide_scalars?

          source << "struct RhdlArcGpuIo {\n"
          source << "  uint cycle_budget;\n"
          source << "  uint cycles_ran;\n"
          source << "  uint mem_mask;\n"
          source << "  uint _reserved;\n"
          top.fetch(:inputs).each do |input|
            source << "  uint #{sanitize_ident(input.fetch(:name))};\n"
          end
          runtime_output_name_set =
            if runtime_output_names
              runtime_output_names.map(&:to_s).to_set
            end
          runtime_output_entries = top.fetch(:outputs).select do |out|
            runtime_output_name_set.nil? || runtime_output_name_set.include?(out.fetch(:name))
          end
          runtime_output_entries.each do |out|
            source << "  uint #{sanitize_ident(out.fetch(:name))};\n"
          end
          source << "};\n\n"

          array_types.each do |arr|
            source << "struct #{array_struct_name(arr)} {\n"
            source << "  #{array_element_metal_type(arr)} v[#{arr.fetch(:length)}];\n"
            source << "};\n\n"
          end

          fn_ret_structs.each do |fn|
            source << "struct #{ret_struct_name(fn.fetch(:name))} {\n"
            fn.fetch(:return_types).each_with_index do |ret_type, idx|
              source << "  #{metal_type_for(ret_type)} v#{idx};\n"
            end
            source << "};\n\n"
          end

          source << "struct #{top_output_struct_name(top.fetch(:name))} {\n"
          top.fetch(:outputs).each do |out|
            source << "  #{metal_type_for(out.fetch(:type))} #{sanitize_ident(out.fetch(:name))};\n"
          end
          source << "};\n\n"

          source << "static inline __attribute__((always_inline)) #{scalar_msl_type} rhdl_mask_bits(#{scalar_msl_type} value, uint width) {\n"
          source << "  if (width >= #{scalar_width_bits}u) { return value; }\n"
          source << "  if (width == 0u) { return #{scalar_zero_literal}; }\n"
          source << "  #{scalar_msl_type} mask = (#{scalar_one_literal} << width) - #{scalar_one_literal};\n"
          source << "  return value & mask;\n"
          source << "}\n\n"
          source << emit_state_memory_helpers << "\n"

          source << <<~MSL
            static inline __attribute__((always_inline)) uint rhdl_read_word_le(device uchar* mem, uint mask, uint addr) {
              uint a = addr & mask;
              if (mask >= 3u && (a & 0x3u) == 0u && a <= (mask - 3u)) {
                return *(reinterpret_cast<device uint*>(mem + a));
              }
              return uint(mem[a]) |
                (uint(mem[(a + 1u) & mask]) << 8u) |
                (uint(mem[(a + 2u) & mask]) << 16u) |
                (uint(mem[(a + 3u) & mask]) << 24u);
            }

            static inline __attribute__((always_inline)) void rhdl_write_word_le(device uchar* mem, uint mask, uint addr, uint value) {
              uint a = addr & mask;
              if (mask >= 3u && (a & 0x3u) == 0u && a <= (mask - 3u)) {
                *(reinterpret_cast<device uint*>(mem + a)) = value;
                return;
              }
              mem[a] = uchar(value & 0xFFu);
              mem[(a + 1u) & mask] = uchar((value >> 8u) & 0xFFu);
              mem[(a + 2u) & mask] = uchar((value >> 16u) & 0xFFu);
              mem[(a + 3u) & mask] = uchar((value >> 24u) & 0xFFu);
            }

            static inline __attribute__((always_inline)) uint rhdl_read_mem_funct3(device uchar* mem, uint mask, uint addr, uint funct3) {
              uint a = addr & mask;
              switch (funct3 & 0x7u) {
                case 0u: {
                  uint v = uint(mem[a]);
                  return (v & 0x80u) != 0u ? (v | 0xFFFFFF00u) : v;
                }
                case 1u: {
                  uint v = uint(mem[a]) | (uint(mem[(a + 1u) & mask]) << 8u);
                  return (v & 0x8000u) != 0u ? (v | 0xFFFF0000u) : v;
                }
                case 2u:
                  return rhdl_read_word_le(mem, mask, a);
                case 4u:
                  return uint(mem[a]);
                case 5u:
                  return uint(mem[a]) | (uint(mem[(a + 1u) & mask]) << 8u);
                default:
                  return 0u;
              }
            }

            static inline __attribute__((always_inline)) void rhdl_write_mem_funct3(device uchar* mem, uint mask, uint addr, uint value, uint funct3) {
              uint a = addr & mask;
              switch (funct3 & 0x7u) {
                case 0u:
                case 4u:
                  mem[a] = uchar(value & 0xFFu);
                  break;
                case 1u:
                case 5u:
                  mem[a] = uchar(value & 0xFFu);
                  mem[(a + 1u) & mask] = uchar((value >> 8u) & 0xFFu);
                  break;
                case 2u:
                  rhdl_write_word_le(mem, mask, a, value);
                  break;
                default:
                  break;
              }
            }

          MSL

          functions.values.each do |fn|
            source << emit_define_function(fn, functions)
            source << "\n"
          end

          full_eval_fn = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_full"
          low_loop_eval_fn = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_low"
          high_loop_eval_fn = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_high"
          low_loop_eval_fn_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_low_fast"
          low_loop_wdata_eval_fn_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_low_wdata_fast"
          low_loop_data_addr_eval_fn_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_low_data_addr_fast"
          high_loop_eval_fn_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_high_fast"
          high_loop_data_addr_eval_fn_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_eval_high_data_addr_fast"
          low_loop_step_struct = "#{sanitize_ident(top.fetch(:name))}_riscv_low_loop_step"
          high_loop_step_struct = "#{sanitize_ident(top.fetch(:name))}_riscv_high_loop_step"
          low_loop_step_struct_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_low_loop_step_fast"
          low_loop_wdata_step_struct_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_low_loop_wdata_step_fast"
          low_loop_data_addr_step_struct_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_low_loop_data_addr_step_fast"
          high_loop_step_struct_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_high_loop_step_fast"
          high_loop_data_addr_step_struct_fast = "#{sanitize_ident(top.fetch(:name))}_riscv_high_loop_data_addr_step_fast"
          low_fast_output_names = REQUIRED_RISCV_FAST_LOOP_OUTPUTS.dup
          low_fast_output_names -= REQUIRED_RISCV_FAST_LOOP_WDATA_OUTPUTS if split_low_wdata_eval
          low_fast_output_names -= REQUIRED_RISCV_FAST_LOOP_ADDR_OUTPUTS if split_low_data_addr_eval
          high_fast_output_names = split_high_data_addr_eval ? REQUIRED_RISCV_FAST_HIGH_LOOP_OUTPUTS_NO_ADDR : REQUIRED_RISCV_FAST_HIGH_LOOP_OUTPUTS

          emit_step_struct = lambda do |struct_name, output_names, extra_fields = {}|
            source << "struct #{struct_name} {\n"
            emitted_field_count = 0
            output_names.each do |name|
              out = top.fetch(:outputs).find { |entry| entry.fetch(:name) == name }
              next unless out

              source << "  #{metal_type_for(out.fetch(:type))} #{sanitize_ident(name)};\n"
              emitted_field_count += 1
            end
            extra_fields.each do |field_name, field_type|
              source << "  #{field_type} #{sanitize_ident(field_name)};\n"
              emitted_field_count += 1
            end
            if emitted_field_count.zero?
              source << "  uint _unused;\n"
            end
            source << "};\n\n"
          end

          emit_step_struct.call(low_loop_step_struct, REQUIRED_RISCV_LOOP_OUTPUTS)
          emit_step_struct.call(high_loop_step_struct, REQUIRED_RISCV_HIGH_LOOP_OUTPUTS)
          emit_step_struct.call(low_loop_step_struct_fast, low_fast_output_names)
          if split_low_wdata_eval
            emit_step_struct.call(low_loop_wdata_step_struct_fast, REQUIRED_RISCV_FAST_LOOP_WDATA_OUTPUTS)
          end
          if split_low_data_addr_eval
            emit_step_struct.call(low_loop_data_addr_step_struct_fast, REQUIRED_RISCV_FAST_LOOP_ADDR_OUTPUTS)
          end
          if split_high_data_addr_eval
            emit_step_struct.call(high_loop_data_addr_step_struct_fast, REQUIRED_RISCV_FAST_HIGH_LOOP_ADDR_OUTPUTS)
          end
          emit_step_struct.call(
            high_loop_step_struct_fast,
            high_fast_output_names,
            dirty_settle_enabled ? { 'state_dirty' => scalar_msl_type } : {}
          )

          source << emit_top_eval_function(
            top,
            functions,
            state_layout,
            state_address_space: 'thread',
            fn_name: low_loop_eval_fn,
            output_names: REQUIRED_RISCV_LOOP_OUTPUTS,
            out_struct: low_loop_step_struct,
            compact_output_struct: true,
            use_state_snapshot: false,
            update_state: false,
            sync_clock_slots_when_comb_only: false,
            schedule_aware_emit: schedule_aware_emit,
            schedule_phase_tag: 'riscv_low_eval',
            trust_state_masks: true,
            cold_memory_bases: cold_memory_bases,
            cold_state_slots_address_space: 'device'
          )
          source << "\n"
          source << emit_top_eval_function(
            top,
            functions,
            state_layout,
            state_address_space: 'thread',
            fn_name: low_loop_eval_fn_fast,
            output_names: low_fast_output_names,
            out_struct: low_loop_step_struct_fast,
            compact_output_struct: true,
            use_state_snapshot: false,
            update_state: false,
            sync_clock_slots_when_comb_only: false,
            schedule_aware_emit: schedule_aware_emit,
            schedule_phase_tag: 'riscv_low_eval_fast',
            trust_state_masks: true,
            cold_memory_bases: cold_memory_bases,
            cold_state_slots_address_space: 'device'
          )
          source << "\n"
          if split_low_wdata_eval
            source << emit_top_eval_function(
              top,
              functions,
              state_layout,
              state_address_space: 'thread',
              fn_name: low_loop_wdata_eval_fn_fast,
              output_names: REQUIRED_RISCV_FAST_LOOP_WDATA_OUTPUTS,
              out_struct: low_loop_wdata_step_struct_fast,
              compact_output_struct: true,
              use_state_snapshot: false,
              update_state: false,
              sync_clock_slots_when_comb_only: false,
              schedule_aware_emit: schedule_aware_emit,
              schedule_phase_tag: 'riscv_low_eval_wdata_fast',
              trust_state_masks: true,
              cold_memory_bases: cold_memory_bases,
              cold_state_slots_address_space: 'device'
            )
            source << "\n"
          end
          if split_low_data_addr_eval
            source << emit_top_eval_function(
              top,
              functions,
              state_layout,
              state_address_space: 'thread',
              fn_name: low_loop_data_addr_eval_fn_fast,
              output_names: REQUIRED_RISCV_FAST_LOOP_ADDR_OUTPUTS,
              out_struct: low_loop_data_addr_step_struct_fast,
              compact_output_struct: true,
              use_state_snapshot: false,
              update_state: false,
              sync_clock_slots_when_comb_only: false,
              schedule_aware_emit: schedule_aware_emit,
              schedule_phase_tag: 'riscv_low_eval_data_addr_fast',
              trust_state_masks: true,
              cold_memory_bases: cold_memory_bases,
              cold_state_slots_address_space: 'device'
            )
            source << "\n"
          end
          source << emit_top_eval_function(
            top,
            functions,
            state_layout,
            state_address_space: 'thread',
            fn_name: high_loop_eval_fn_fast,
            output_names: high_fast_output_names,
            out_struct: high_loop_step_struct_fast,
            compact_output_struct: true,
            use_state_snapshot: false,
            update_state: true,
            split_post_comb_liveness: true,
            assume_rising_edges: false,
            track_state_dirty: dirty_settle_enabled,
            extra_output_assignments: (dirty_settle_enabled ? { 'state_dirty' => 'state_dirty' } : {}),
            schedule_aware_emit: schedule_aware_emit,
            schedule_phase_tag: 'riscv_high_eval_fast',
            trust_state_masks: true,
            cold_memory_bases: cold_memory_bases,
            cold_state_slots_address_space: 'device'
          )
          source << "\n"
          if split_high_data_addr_eval
            source << emit_top_eval_function(
              top,
              functions,
              state_layout,
              state_address_space: 'thread',
              fn_name: high_loop_data_addr_eval_fn_fast,
              output_names: REQUIRED_RISCV_FAST_HIGH_LOOP_ADDR_OUTPUTS,
              out_struct: high_loop_data_addr_step_struct_fast,
              compact_output_struct: true,
              use_state_snapshot: false,
              update_state: false,
              sync_clock_slots_when_comb_only: false,
              schedule_aware_emit: schedule_aware_emit,
              schedule_phase_tag: 'riscv_high_eval_data_addr_fast',
              trust_state_masks: true,
              cold_memory_bases: cold_memory_bases,
              cold_state_slots_address_space: 'device'
            )
            source << "\n"
          end
          source << emit_top_eval_function(
            top,
            functions,
            state_layout,
            state_address_space: 'thread',
            fn_name: high_loop_eval_fn,
            output_names: REQUIRED_RISCV_HIGH_LOOP_OUTPUTS,
            out_struct: high_loop_step_struct,
            compact_output_struct: true,
            use_state_snapshot: false,
            update_state: true,
            split_post_comb_liveness: true,
            assume_rising_edges: false,
            schedule_aware_emit: schedule_aware_emit,
            schedule_phase_tag: 'riscv_high_eval',
            trust_state_masks: true,
            cold_memory_bases: cold_memory_bases,
            cold_state_slots_address_space: 'device'
          )
          source << "\n"
          source << emit_top_eval_function(
            top,
            functions,
            state_layout,
            state_address_space: 'thread',
            fn_name: full_eval_fn,
            use_state_snapshot: false,
            update_state: false,
            sync_clock_slots_when_comb_only: false,
            schedule_aware_emit: schedule_aware_emit,
            schedule_phase_tag: 'riscv_full_eval',
            trust_state_masks: true,
            cold_memory_bases: cold_memory_bases,
            cold_state_slots_address_space: 'device'
          )
          source << "\n"
          source << emit_write_outputs_helper(top, output_names: runtime_output_entries.map { |out| out.fetch(:name) })
          source << "\n"
          source << emit_kernel_riscv(
            top: top,
            metal_entry: metal_entry,
            state_layout: state_layout,
            low_eval_fn: low_loop_eval_fn_fast,
            low_wdata_eval_fn: (split_low_wdata_eval ? low_loop_wdata_eval_fn_fast : nil),
            low_data_addr_eval_fn: (split_low_data_addr_eval ? low_loop_data_addr_eval_fn_fast : nil),
            high_eval_fn: high_loop_eval_fn_fast,
            high_data_addr_eval_fn: (split_high_data_addr_eval ? high_loop_data_addr_eval_fn_fast : nil),
            full_eval_fn: full_eval_fn,
            low_loop_step_struct: low_loop_step_struct_fast,
            low_wdata_step_struct: (split_low_wdata_eval ? low_loop_wdata_step_struct_fast : nil),
            low_data_addr_step_struct: (split_low_data_addr_eval ? low_loop_data_addr_step_struct_fast : nil),
            high_loop_step_struct: high_loop_step_struct_fast,
            high_data_addr_step_struct: (split_high_data_addr_eval ? high_loop_data_addr_step_struct_fast : nil),
            cold_memory_layout: cold_memory_layout,
            fast_path: true,
            dirty_settle_enabled: dirty_settle_enabled,
            split_low_wdata_eval: split_low_wdata_eval,
            split_high_data_addr_eval: split_high_data_addr_eval,
            split_low_data_addr_eval: split_low_data_addr_eval
          )

          source
        end

        def emit_define_function(fn, functions)
          fn_name = metal_fn_name(fn.fetch(:name))
          ret_types = fn.fetch(:return_types)
          args = fn.fetch(:args)

          arg_decls = args.map { |a| "#{metal_type_for(a.fetch(:type))} #{ref_var_name(a.fetch(:ref))}" }.join(', ')
          inline_spec = inline_qualifier(always_inline: prefer_always_inline_for_define?(fn))
          header = if ret_types.length == 1
            "#{inline_spec} #{metal_type_for(ret_types.first)} #{fn_name}(#{arg_decls})"
          else
            "#{inline_spec} #{ret_struct_name(fn.fetch(:name))} #{fn_name}(#{arg_decls})"
          end

          lines = []
          type_map = {}
          available_refs = Set.new
          args.each do |arg|
            ref = arg.fetch(:ref)
            type_map[ref] = arg.fetch(:type)
            available_refs << ref
          end

          sorted_ops, _sorted_type_map = topologically_sorted_ops(
            ops: fn.fetch(:ops),
            initial_type_map: type_map
          )
          live_ops, _live_refs = select_live_ops(
            sorted_ops: sorted_ops,
            seed_refs: fn.fetch(:output_refs)
          )
          schedule_ops_topologically(
            ops: live_ops,
            lines: lines,
            type_map: type_map,
            available_refs: available_refs,
            functions: functions,
            in_top_module: false
          )

          output_refs = fn.fetch(:output_refs)
          if ret_types.length == 1
            ref = output_refs.first
            out_type = ret_types.first
            lines << "return #{masked_expr(ref_var_name(ref), out_type)};"
          else
            struct_name = ret_struct_name(fn.fetch(:name))
            lines << "#{struct_name} out;"
            output_refs.each_with_index do |ref, idx|
              out_type = ret_types[idx]
              lines << "out.v#{idx} = #{masked_expr(ref_var_name(ref), out_type)};"
            end
            lines << 'return out;'
          end

          body = indent_lines(lines)
          "#{header} {\n#{body}\n}\n"
        end

        def emit_top_eval_function(
          top,
          functions,
          state_layout,
          state_address_space: 'device',
          use_state_snapshot: true,
          fn_name: nil,
          output_names: nil,
          out_struct: nil,
          compact_output_struct: false,
          seed_all_outputs: false,
          emit_post_comb: true,
          update_state: true,
          split_post_comb_liveness: false,
          assume_rising_edges: false,
          sync_clock_slots_when_comb_only: true,
          track_state_dirty: false,
          extra_output_assignments: {},
          trust_state_masks: false,
          load_state_in_comb_fn: false,
          cold_memory_bases: nil,
          cold_state_slots_address_space: 'device',
          schedule_aware_emit: false,
          schedule_phase_tag: nil,
          always_inline_eval: false
        )
          fn_name ||= top_eval_fn_name(top.fetch(:name))
          out_struct ||= top_output_struct_name(top.fetch(:name))
          cold_memory_bases ||= Set.new
          needs_cold_state_slots = !cold_memory_bases.empty?
          comb_tag = sanitize_ident(fn_name)
          comb_struct = "#{comb_tag}_comb_values"
          comb_fn = "compute_#{comb_tag}_comb"
          top_input_refs = top.fetch(:inputs).map { |input| "%#{input.fetch(:name)}" }
          snapshot_prefix = use_state_snapshot ? 'state_old_' : nil
          output_name_set = output_names ? output_names.map(&:to_s).to_set : nil
          selected_output_entries = top.fetch(:outputs).each_with_index.select do |out, _idx|
            output_name_set.nil? || output_name_set.include?(out.fetch(:name))
          end
          output_seed_entries = if seed_all_outputs
            top.fetch(:outputs).each_with_index.to_a
          else
            selected_output_entries
          end

          state_ref_to_slot = {}
          base_type_map = {}

          top.fetch(:inputs).each do |input|
            ref = "%#{input.fetch(:name)}"
            base_type_map[ref] = input.fetch(:type)
          end

          top.fetch(:ops).each do |op|
            next unless %i[arc_state seq_firreg arc_memory].include?(op.fetch(:kind))

            op.fetch(:result_refs).each_with_index do |ref, idx|
              type = op.fetch(:result_types).fetch(idx)
              slot_entry = state_layout.find { |entry| entry.fetch(:result_ref) == ref }
              state_ref_to_slot[ref] = {
                index: slot_entry.fetch(:index),
                type: type,
                slot_count: slot_entry.fetch(:slot_count, 1),
                length: slot_entry[:length],
                slots_per_element: slot_entry[:slots_per_element]
              }
              base_type_map[ref] = type
            end
          end

          clock_ref_to_slot = {}
          next_clock_slot = state_layout.sum { |entry| entry.fetch(:slot_count, 1) }
          top.fetch(:ops).each do |op|
            next unless %i[arc_state seq_firreg arc_memory_write_port seq_memory_write_port].include?(op.fetch(:kind))

            clock_ref = op.fetch(:clock_ref)
            clock_slot = clock_ref_to_slot[clock_ref]
            unless clock_slot
              clock_slot = next_clock_slot
              clock_ref_to_slot[clock_ref] = clock_slot
              next_clock_slot += 1
            end
          end

          needed_refs = []
          if update_state
            top.fetch(:ops).each do |op|
              case op.fetch(:kind)
              when :arc_state
                needed_refs << op.fetch(:clock_ref)
                needed_refs.concat(op.fetch(:args))
                needed_refs << op.fetch(:enable_ref) if op.fetch(:enable_ref)
                needed_refs << op.fetch(:reset_ref) if op.fetch(:reset_ref)
              when :seq_firreg
                needed_refs << op.fetch(:clock_ref)
                needed_refs << op.fetch(:source_ref)
                needed_refs << op.fetch(:reset_ref) if op.fetch(:reset_ref)
                needed_refs << op.fetch(:reset_value_ref) if op.fetch(:reset_value_ref)
              when :arc_memory_write_port
                needed_refs << op.fetch(:clock_ref)
                needed_refs.concat(op.fetch(:args))
                needed_refs << op.fetch(:memory_ref)
              when :seq_memory_write_port
                needed_refs << op.fetch(:clock_ref)
                needed_refs << op.fetch(:memory_ref)
                needed_refs << op.fetch(:addr_ref)
                needed_refs << op.fetch(:data_ref)
                needed_refs << op.fetch(:enable_ref) if op.fetch(:enable_ref)
              end
            end
          end
          seed_outputs_in_comb_pre = !(split_post_comb_liveness && emit_post_comb && update_state)
          if seed_outputs_in_comb_pre
            output_seed_entries.each do |_out, idx|
              needed_refs << top.fetch(:hw_output_refs)[idx]
            end
          end
          needed_refs.uniq!

          combinational_ops = top.fetch(:ops).reject do |op|
            %i[arc_state seq_firreg arc_memory arc_memory_write_port seq_memory_write_port].include?(op.fetch(:kind))
          end
          sorted_ops, all_comb_type_map = topologically_sorted_ops(
            ops: combinational_ops,
            initial_type_map: base_type_map
          )
          all_type_map = base_type_map.merge(all_comb_type_map)
          comb_produced_refs = sorted_ops.flat_map { |op| op.fetch(:result_refs) }.to_set
          needed_comb_refs = needed_refs.select { |ref| comb_produced_refs.include?(ref) }
          live_ops, live_comb_refs = select_live_ops(sorted_ops: sorted_ops, seed_refs: needed_comb_refs)

          ordered_state_refs = (
            needed_refs.select { |ref| state_ref_to_slot.key?(ref) } +
            live_comb_refs.select { |ref| state_ref_to_slot.key?(ref) }
          ).uniq.select do |ref|
            info = state_ref_to_slot.fetch(ref)
            info.fetch(:type).scalar?
          end.sort_by { |ref| state_ref_to_slot.fetch(ref).fetch(:index) }

          uses_memory_reads = live_ops.any? { |op| op.fetch(:kind) == :arc_memory_read_port }

          comb_lines = []
          runtime_type_map = base_type_map.dup
          if load_state_in_comb_fn
            ordered_state_refs.each do |ref|
              info = state_ref_to_slot.fetch(ref)
              comb_lines << "#{metal_type_for(info.fetch(:type))} #{ref_var_name(ref)} = #{state_load_expr(info, trust_state_masks: trust_state_masks)};"
            end
          end
          emit_ops_with_optional_schedule(
            ops: live_ops,
            lines: comb_lines,
            runtime_type_map: runtime_type_map,
            functions: functions,
            in_top_module: true,
            state_ref_to_slot: state_ref_to_slot,
            cold_memory_bases: cold_memory_bases,
            cold_state_slots_var: (needs_cold_state_slots ? 'cold_state_slots' : nil),
            schedule_aware_emit: schedule_aware_emit,
            phase_tag: schedule_phase_tag || "#{comb_fn}_pre"
          )

          comb_lines << "#{comb_struct} comb;"
          needed_comb_refs.each do |ref|
            type = all_type_map.fetch(ref)
            comb_lines << "comb.#{comb_field_name(ref)} = #{masked_expr(ref_var_name(ref), type)};"
          end
          comb_lines << 'return comb;'

          compute_fn_text = +""
          compute_fn_text << "struct #{comb_struct} {\n"
          needed_comb_refs.each do |ref|
            compute_fn_text << "  #{metal_type_for(all_type_map.fetch(ref))} #{comb_field_name(ref)};\n"
          end
          compute_fn_text << "};\n\n"

          eval_input_arg_decls = top.fetch(:inputs).map do |input|
            ref = "%#{input.fetch(:name)}"
            "#{metal_type_for(input.fetch(:type))} #{ref_var_name(ref)}"
          end
          comb_arg_decls = eval_input_arg_decls.dup
          if load_state_in_comb_fn
            comb_arg_decls << "#{state_address_space} #{scalar_msl_type}* state_slots" if uses_memory_reads || !ordered_state_refs.empty?
          else
            comb_arg_decls.concat(
              ordered_state_refs.map do |ref|
                info = state_ref_to_slot.fetch(ref)
                "#{metal_type_for(info.fetch(:type))} #{ref_var_name(ref)}"
              end
            )
            comb_arg_decls << "#{state_address_space} #{scalar_msl_type}* state_slots" if uses_memory_reads
          end
          if uses_memory_reads && needs_cold_state_slots
            comb_arg_decls << "#{cold_state_slots_address_space} #{scalar_msl_type}* cold_state_slots"
          end
          input_arg_exprs = top.fetch(:inputs).map { |input| ref_var_name("%#{input.fetch(:name)}") }
          compute_fn_text << "#{inline_qualifier(always_inline: always_inline_eval)} #{comb_struct} #{comb_fn}(#{comb_arg_decls.join(', ')}) {\n"
          compute_fn_text << indent_lines(comb_lines)
          compute_fn_text << "\n}\n\n"

          output_comb_struct = comb_struct
          output_comb_fn = comb_fn
          output_comb_state_refs = ordered_state_refs
          output_comb_uses_memory_reads = uses_memory_reads

          if split_post_comb_liveness && emit_post_comb && update_state
            post_needed_refs = output_seed_entries.map { |_out, idx| top.fetch(:hw_output_refs)[idx] }.uniq
            post_needed_comb_refs = post_needed_refs.select { |ref| comb_produced_refs.include?(ref) }
            post_live_ops, post_live_comb_refs = select_live_ops(sorted_ops: sorted_ops, seed_refs: post_needed_comb_refs)

            post_ordered_state_refs = (
              post_needed_refs.select { |ref| state_ref_to_slot.key?(ref) } +
              post_live_comb_refs.select { |ref| state_ref_to_slot.key?(ref) }
            ).uniq.select do |ref|
              info = state_ref_to_slot.fetch(ref)
              info.fetch(:type).scalar?
            end.sort_by { |ref| state_ref_to_slot.fetch(ref).fetch(:index) }

            post_uses_memory_reads = post_live_ops.any? { |op| op.fetch(:kind) == :arc_memory_read_port }
            post_comb_struct = "#{comb_tag}_post_comb_values"
            post_comb_fn = "compute_#{comb_tag}_post_comb"
            post_runtime_type_map = base_type_map.dup
            post_comb_lines = []
            if load_state_in_comb_fn
              post_ordered_state_refs.each do |ref|
                info = state_ref_to_slot.fetch(ref)
                post_comb_lines << "#{metal_type_for(info.fetch(:type))} #{ref_var_name(ref)} = #{state_load_expr(info, trust_state_masks: trust_state_masks)};"
              end
            end
            emit_ops_with_optional_schedule(
              ops: post_live_ops,
              lines: post_comb_lines,
              runtime_type_map: post_runtime_type_map,
              functions: functions,
              in_top_module: true,
              state_ref_to_slot: state_ref_to_slot,
              cold_memory_bases: cold_memory_bases,
              cold_state_slots_var: (needs_cold_state_slots ? 'cold_state_slots' : nil),
              schedule_aware_emit: schedule_aware_emit,
              phase_tag: schedule_phase_tag ? "#{schedule_phase_tag}_post" : "#{post_comb_fn}_post"
            )

            post_comb_lines << "#{post_comb_struct} comb;"
            post_needed_comb_refs.each do |ref|
              type = all_type_map.fetch(ref)
              post_comb_lines << "comb.#{comb_field_name(ref)} = #{masked_expr(ref_var_name(ref), type)};"
            end
            post_comb_lines << 'return comb;'

            post_comb_arg_decls = eval_input_arg_decls.dup
            if load_state_in_comb_fn
              post_comb_arg_decls << "#{state_address_space} #{scalar_msl_type}* state_slots" if post_uses_memory_reads || !post_ordered_state_refs.empty?
            else
              post_comb_arg_decls.concat(
                post_ordered_state_refs.map do |ref|
                  info = state_ref_to_slot.fetch(ref)
                  "#{metal_type_for(info.fetch(:type))} #{ref_var_name(ref)}"
                end
              )
              post_comb_arg_decls << "#{state_address_space} #{scalar_msl_type}* state_slots" if post_uses_memory_reads
            end
            if post_uses_memory_reads && needs_cold_state_slots
              post_comb_arg_decls << "#{cold_state_slots_address_space} #{scalar_msl_type}* cold_state_slots"
            end

            compute_fn_text << "struct #{post_comb_struct} {\n"
            post_needed_comb_refs.each do |ref|
              compute_fn_text << "  #{metal_type_for(all_type_map.fetch(ref))} #{comb_field_name(ref)};\n"
            end
            compute_fn_text << "};\n\n"
            compute_fn_text << "#{inline_qualifier(always_inline: always_inline_eval)} #{post_comb_struct} #{post_comb_fn}(#{post_comb_arg_decls.join(', ')}) {\n"
            compute_fn_text << indent_lines(post_comb_lines)
            compute_fn_text << "\n}\n\n"

            output_comb_struct = post_comb_struct
            output_comb_fn = post_comb_fn
            output_comb_state_refs = post_ordered_state_refs
            output_comb_uses_memory_reads = post_uses_memory_reads
          end

          eval_lines = []
          dirty_var = track_state_dirty ? 'state_dirty' : nil
          eval_lines << "#{scalar_msl_type} #{dirty_var} = 0u;" if dirty_var

          comb_state_args = if load_state_in_comb_fn
            []
          else
            ordered_state_refs.map do |ref|
              state_load_expr(state_ref_to_slot.fetch(ref), trust_state_masks: trust_state_masks)
            end
          end

          if update_state
            force_rising_edges = assume_rising_edges && clock_ref_to_slot.length == 1
            if use_state_snapshot
              ordered_state_refs.each do |ref|
                info = state_ref_to_slot.fetch(ref)
                eval_lines << "#{metal_type_for(info.fetch(:type))} #{snapshot_prefix}#{info.fetch(:index)} = #{state_load_expr(info, trust_state_masks: trust_state_masks)};"
              end
            end
            comb_pre_state_args = if load_state_in_comb_fn
              []
            else
              ordered_state_refs.map do |ref|
                info = state_ref_to_slot.fetch(ref)
                use_state_snapshot ? "#{snapshot_prefix}#{info.fetch(:index)}" : state_load_expr(info, trust_state_masks: trust_state_masks)
              end
            end
            comb_pre_args = input_arg_exprs + comb_pre_state_args
            comb_pre_args << 'state_slots' if uses_memory_reads || (load_state_in_comb_fn && !ordered_state_refs.empty?)
            comb_pre_args << 'cold_state_slots' if uses_memory_reads && needs_cold_state_slots
            eval_lines << "#{comb_struct} comb_pre = #{comb_fn}(#{comb_pre_args.join(', ')});"

            clock_rising_var_by_ref = {}
            unless force_rising_edges
              clock_ref_to_slot.each do |clock_ref, clock_slot|
                clock_expr = value_expr_for_ref(
                  clock_ref,
                  type_map: all_type_map,
                  state_ref_to_slot: state_ref_to_slot,
                  comb_var: 'comb_pre',
                  state_snapshot_prefix: snapshot_prefix,
                  top_input_refs: top_input_refs,
                  trust_state_masks: trust_state_masks
                )
                eval_lines << "#{scalar_msl_type} clock_prev_#{clock_slot} = rhdl_mask_bits(state_slots[#{clock_slot}], 1u);"
                eval_lines << "#{scalar_msl_type} clock_now_#{clock_slot} = (#{clock_expr} & 1u);"
                eval_lines << "#{scalar_msl_type} rising_#{clock_slot} = ((clock_prev_#{clock_slot} ^ clock_now_#{clock_slot}) & clock_now_#{clock_slot}) & 1u;"
                eval_lines << "state_slots[#{clock_slot}] = clock_now_#{clock_slot};"
                clock_rising_var_by_ref[clock_ref] = "rising_#{clock_slot}"
              end
            end

            active_clock_ref = nil
            top.fetch(:ops).each_with_index do |op, op_idx|
              case op.fetch(:kind)
              when :arc_state
                clock_ref = op.fetch(:clock_ref)
                unless force_rising_edges
                  if active_clock_ref != clock_ref
                    eval_lines << '}' if active_clock_ref
                    rising_var = clock_rising_var_by_ref.fetch(clock_ref)
                    eval_lines << "if (#{rising_var} != 0u) {"
                    active_clock_ref = clock_ref
                  end
                end

                slot_infos = op.fetch(:result_refs).each_with_index.map do |ref, idx|
                  info = state_ref_to_slot.fetch(ref)
                  { index: info.fetch(:index), type: op.fetch(:result_types).fetch(idx) }
                end

                emit_state_update = lambda do |indent|
                  arg_exprs = op.fetch(:args).map do |arg_ref|
                    value_expr_for_ref(
                      arg_ref,
                      type_map: all_type_map,
                      state_ref_to_slot: state_ref_to_slot,
                      comb_var: 'comb_pre',
                      state_snapshot_prefix: snapshot_prefix,
                      top_input_refs: top_input_refs,
                      trust_state_masks: trust_state_masks
                    )
                  end
                  call_expr = generate_call_expr(
                    callee: op.fetch(:callee),
                    args: op.fetch(:args),
                    result_types: op.fetch(:result_types),
                    type_map: all_type_map,
                    functions: functions,
                    temp_prefix: "state_#{slot_infos.first.fetch(:index)}_next",
                    arg_exprs: arg_exprs
                  )
                  call_expr.fetch(:setup_lines).each { |line| eval_lines << "#{indent}#{line}" }
                  slot_infos.each_with_index do |slot_info, idx|
                    store_expr = masked_expr(call_expr.fetch(:result_exprs)[idx], slot_info.fetch(:type))
                    eval_lines.concat(
                      emit_state_store_lines(
                        slot_info: slot_info,
                        value_expr: store_expr,
                        indent: indent,
                        dirty_var: dirty_var
                      )
                    )
                  end
                end

                if op.fetch(:reset_ref)
                  reset_expr = value_expr_for_ref(
                    op.fetch(:reset_ref),
                    type_map: all_type_map,
                    state_ref_to_slot: state_ref_to_slot,
                    comb_var: 'comb_pre',
                    state_snapshot_prefix: snapshot_prefix,
                    top_input_refs: top_input_refs,
                    trust_state_masks: trust_state_masks
                  )
                  eval_lines << "  if ((#{reset_expr} & 1u) != 0u) {"
                  slot_infos.each do |slot_info|
                    eval_lines.concat(
                      emit_state_store_lines(
                        slot_info: slot_info,
                        value_expr: constant_literal(0, slot_info.fetch(:type)),
                        indent: '    ',
                        dirty_var: dirty_var
                      )
                    )
                  end
                  eval_lines << '  } else {'
                  if op.fetch(:enable_ref)
                    enable_expr = value_expr_for_ref(
                      op.fetch(:enable_ref),
                      type_map: all_type_map,
                      state_ref_to_slot: state_ref_to_slot,
                      comb_var: 'comb_pre',
                      state_snapshot_prefix: snapshot_prefix,
                      top_input_refs: top_input_refs,
                      trust_state_masks: trust_state_masks
                    )
                    eval_lines << "    if ((#{enable_expr} & 1u) != 0u) {"
                    emit_state_update.call('      ')
                    eval_lines << '    }'
                  else
                    emit_state_update.call('    ')
                  end
                  eval_lines << '  }'
                else
                  if op.fetch(:enable_ref)
                    enable_expr = value_expr_for_ref(
                      op.fetch(:enable_ref),
                      type_map: all_type_map,
                      state_ref_to_slot: state_ref_to_slot,
                      comb_var: 'comb_pre',
                      state_snapshot_prefix: snapshot_prefix,
                      top_input_refs: top_input_refs,
                      trust_state_masks: trust_state_masks
                    )
                    eval_lines << "  if ((#{enable_expr} & 1u) != 0u) {"
                    emit_state_update.call('    ')
                    eval_lines << '  }'
                  else
                    emit_state_update.call('  ')
                  end
                end
              when :seq_firreg
                clock_ref = op.fetch(:clock_ref)
                unless force_rising_edges
                  if active_clock_ref != clock_ref
                    eval_lines << '}' if active_clock_ref
                    rising_var = clock_rising_var_by_ref.fetch(clock_ref)
                    eval_lines << "if (#{rising_var} != 0u) {"
                    active_clock_ref = clock_ref
                  end
                end

                slot_info = begin
                  ref = op.fetch(:result_refs).first
                  info = state_ref_to_slot.fetch(ref)
                  { index: info.fetch(:index), type: op.fetch(:result_types).first }
                end

                source_expr = value_expr_for_ref(
                  op.fetch(:source_ref),
                  type_map: all_type_map,
                  state_ref_to_slot: state_ref_to_slot,
                  comb_var: 'comb_pre',
                  state_snapshot_prefix: snapshot_prefix,
                  top_input_refs: top_input_refs,
                  trust_state_masks: trust_state_masks
                )
                source_store_expr = masked_expr(source_expr, slot_info.fetch(:type))

                if op.fetch(:reset_ref)
                  reset_expr = value_expr_for_ref(
                    op.fetch(:reset_ref),
                    type_map: all_type_map,
                    state_ref_to_slot: state_ref_to_slot,
                    comb_var: 'comb_pre',
                    state_snapshot_prefix: snapshot_prefix,
                    top_input_refs: top_input_refs,
                    trust_state_masks: trust_state_masks
                  )
                  reset_value_expr = value_expr_for_ref(
                    op.fetch(:reset_value_ref),
                    type_map: all_type_map,
                    state_ref_to_slot: state_ref_to_slot,
                    comb_var: 'comb_pre',
                    state_snapshot_prefix: snapshot_prefix,
                    top_input_refs: top_input_refs,
                    trust_state_masks: trust_state_masks
                  )
                  reset_store_expr = masked_expr(reset_value_expr, slot_info.fetch(:type))
                  eval_lines << "  if ((#{reset_expr} & 1u) != 0u) {"
                  eval_lines.concat(
                    emit_state_store_lines(
                      slot_info: slot_info,
                      value_expr: reset_store_expr,
                      indent: '    ',
                      dirty_var: dirty_var
                    )
                  )
                  eval_lines << '  } else {'
                  eval_lines.concat(
                    emit_state_store_lines(
                      slot_info: slot_info,
                      value_expr: source_store_expr,
                      indent: '    ',
                      dirty_var: dirty_var
                    )
                  )
                  eval_lines << '  }'
                else
                  eval_lines.concat(
                    emit_state_store_lines(
                      slot_info: slot_info,
                      value_expr: source_store_expr,
                      indent: '  ',
                      dirty_var: dirty_var
                    )
                  )
                end
              when :arc_memory_write_port
                clock_ref = op.fetch(:clock_ref)
                unless force_rising_edges
                  if active_clock_ref != clock_ref
                    eval_lines << '}' if active_clock_ref
                    rising_var = clock_rising_var_by_ref.fetch(clock_ref)
                    eval_lines << "if (#{rising_var} != 0u) {"
                    active_clock_ref = clock_ref
                  end
                end

                memory_info = state_ref_to_slot.fetch(op.fetch(:memory_ref))
                memory_type = memory_info.fetch(:type)
                element_type = memory_type.fetch(:element)

                arg_exprs = op.fetch(:args).map do |arg_ref|
                  value_expr_for_ref(
                    arg_ref,
                    type_map: all_type_map,
                    state_ref_to_slot: state_ref_to_slot,
                    comb_var: 'comb_pre',
                    state_snapshot_prefix: snapshot_prefix,
                    top_input_refs: top_input_refs,
                    trust_state_masks: trust_state_masks
                  )
                end
                call_expr = generate_call_expr(
                  callee: op.fetch(:callee),
                  args: op.fetch(:args),
                  result_types: op.fetch(:write_result_types),
                  type_map: all_type_map,
                  functions: functions,
                  temp_prefix: "memwrite_#{memory_info.fetch(:index)}_#{op_idx}",
                  arg_exprs: arg_exprs
                )
                call_expr.fetch(:setup_lines).each { |line| eval_lines << line }

                index_type = TypeRef.new(kind: :scalar, width: memory_type.fetch(:index_width))
                addr_expr = masked_expr(call_expr.fetch(:result_exprs)[0], index_type)
                data_expr = masked_expr(call_expr.fetch(:result_exprs)[1], element_type)
                write_enable_expr = masked_expr(call_expr.fetch(:result_exprs)[2], TypeRef.new(kind: :scalar, width: 1))

                eval_lines << "  if ((#{write_enable_expr} & 1u) != 0u) {"
                    if wide_scalar?(element_type)
                      target_state_slots = if needs_cold_state_slots && cold_memory_bases.include?(memory_info.fetch(:index))
                        'cold_state_slots'
                      else
                        'state_slots'
                      end
                      eval_lines << "    rhdl_write_memory_wide(#{target_state_slots}, #{memory_info.fetch(:index)}u, #{memory_info.fetch(:length)}u, #{addr_expr}, #{data_expr}, #{element_type.fetch(:width)}u);"
                    else
                      target_state_slots = if needs_cold_state_slots && cold_memory_bases.include?(memory_info.fetch(:index))
                        'cold_state_slots'
                      else
                        'state_slots'
                      end
                      eval_lines << "    rhdl_write_memory_scalar(#{target_state_slots}, #{memory_info.fetch(:index)}u, #{memory_info.fetch(:length)}u, #{addr_expr}, #{data_expr}, #{element_type.fetch(:width)}u);"
                    end
                eval_lines << '  }'
              when :seq_memory_write_port
                clock_ref = op.fetch(:clock_ref)
                unless force_rising_edges
                  if active_clock_ref != clock_ref
                    eval_lines << '}' if active_clock_ref
                    rising_var = clock_rising_var_by_ref.fetch(clock_ref)
                    eval_lines << "if (#{rising_var} != 0u) {"
                    active_clock_ref = clock_ref
                  end
                end

                memory_info = state_ref_to_slot.fetch(op.fetch(:memory_ref))
                memory_type = memory_info.fetch(:type)
                element_type = memory_type.fetch(:element)
                index_type = TypeRef.new(kind: :scalar, width: memory_type.fetch(:index_width))

                addr_expr = value_expr_for_ref(
                  op.fetch(:addr_ref),
                  type_map: all_type_map,
                  state_ref_to_slot: state_ref_to_slot,
                  comb_var: 'comb_pre',
                  state_snapshot_prefix: snapshot_prefix,
                  top_input_refs: top_input_refs,
                  trust_state_masks: trust_state_masks
                )
                data_expr = value_expr_for_ref(
                  op.fetch(:data_ref),
                  type_map: all_type_map,
                  state_ref_to_slot: state_ref_to_slot,
                  comb_var: 'comb_pre',
                  state_snapshot_prefix: snapshot_prefix,
                  top_input_refs: top_input_refs,
                  trust_state_masks: trust_state_masks
                )
                write_enable_expr = if op.fetch(:enable_ref)
                  enable_expr = value_expr_for_ref(
                    op.fetch(:enable_ref),
                    type_map: all_type_map,
                    state_ref_to_slot: state_ref_to_slot,
                    comb_var: 'comb_pre',
                    state_snapshot_prefix: snapshot_prefix,
                    top_input_refs: top_input_refs,
                    trust_state_masks: trust_state_masks
                  )
                  masked_expr(enable_expr, TypeRef.new(kind: :scalar, width: 1))
                else
                  scalar_one_literal
                end

                masked_addr_expr = masked_expr(addr_expr, index_type)
                masked_data_expr = masked_expr(data_expr, element_type)
                eval_lines << "  if ((#{write_enable_expr} & 1u) != 0u) {"
                if wide_scalar?(element_type)
                  target_state_slots = if needs_cold_state_slots && cold_memory_bases.include?(memory_info.fetch(:index))
                    'cold_state_slots'
                  else
                    'state_slots'
                  end
                  eval_lines << "    rhdl_write_memory_wide(#{target_state_slots}, #{memory_info.fetch(:index)}u, #{memory_info.fetch(:length)}u, #{masked_addr_expr}, #{masked_data_expr}, #{element_type.fetch(:width)}u);"
                else
                  target_state_slots = if needs_cold_state_slots && cold_memory_bases.include?(memory_info.fetch(:index))
                    'cold_state_slots'
                  else
                    'state_slots'
                  end
                  eval_lines << "    rhdl_write_memory_scalar(#{target_state_slots}, #{memory_info.fetch(:index)}u, #{memory_info.fetch(:length)}u, #{masked_addr_expr}, #{masked_data_expr}, #{element_type.fetch(:width)}u);"
                end
                eval_lines << '  }'
              end
            end
            eval_lines << '}' if active_clock_ref && !force_rising_edges
          end

          output_comb_var =
            if emit_post_comb
              comb_args = if load_state_in_comb_fn
                input_arg_exprs.dup
              else
                input_arg_exprs + output_comb_state_refs.map do |ref|
                  state_load_expr(state_ref_to_slot.fetch(ref), trust_state_masks: trust_state_masks)
                end
              end
              comb_args << 'state_slots' if output_comb_uses_memory_reads || (load_state_in_comb_fn && !output_comb_state_refs.empty?)
              comb_args << 'cold_state_slots' if output_comb_uses_memory_reads && needs_cold_state_slots
              eval_lines << "#{output_comb_struct} comb = #{output_comb_fn}(#{comb_args.join(', ')});"
              'comb'
            elsif update_state
              'comb_pre'
            else
              comb_args = input_arg_exprs + comb_state_args
              comb_args << 'state_slots' if uses_memory_reads || (load_state_in_comb_fn && !ordered_state_refs.empty?)
              comb_args << 'cold_state_slots' if uses_memory_reads && needs_cold_state_slots
              eval_lines << "#{comb_struct} comb = #{comb_fn}(#{comb_args.join(', ')});"
              'comb'
            end
          if !update_state && sync_clock_slots_when_comb_only
            clock_ref_to_slot.each do |clock_ref, clock_slot|
              clock_expr = value_expr_for_ref(
                clock_ref,
                type_map: all_type_map,
                state_ref_to_slot: state_ref_to_slot,
                comb_var: 'comb',
                top_input_refs: top_input_refs,
                trust_state_masks: trust_state_masks
              )
              eval_lines << "state_slots[#{clock_slot}] = (#{clock_expr} & 1u);"
            end
          end
          eval_lines << "#{out_struct} out;"
          if compact_output_struct
            selected_output_entries.each do |out, idx|
              out_name = out.fetch(:name)
              ref = top.fetch(:hw_output_refs)[idx]
              out_expr = value_expr_for_ref(
                ref,
                type_map: all_type_map,
                state_ref_to_slot: state_ref_to_slot,
                comb_var: output_comb_var,
                top_input_refs: top_input_refs,
                trust_state_masks: trust_state_masks
              )
              out_linesafe = masked_expr(out_expr, out.fetch(:type))
              eval_lines << "out.#{sanitize_ident(out_name)} = #{out_linesafe};"
            end
          else
            top.fetch(:outputs).each_with_index do |out, idx|
              out_name = out.fetch(:name)
              if output_name_set && !output_name_set.include?(out_name)
                eval_lines << "out.#{sanitize_ident(out_name)} = #{constant_literal(0, out.fetch(:type))};"
                next
              end

              ref = top.fetch(:hw_output_refs)[idx]
              out_expr = value_expr_for_ref(
                ref,
                type_map: all_type_map,
                state_ref_to_slot: state_ref_to_slot,
                comb_var: output_comb_var,
                top_input_refs: top_input_refs,
                trust_state_masks: trust_state_masks
              )
              out_linesafe = masked_expr(out_expr, out.fetch(:type))
              eval_lines << "out.#{sanitize_ident(out_name)} = #{out_linesafe};"
            end
          end
          extra_output_assignments.each do |field_name, expr|
            eval_lines << "out.#{sanitize_ident(field_name)} = #{expr};"
          end
          eval_lines << 'return out;'

          eval_fn_arg_decls = eval_input_arg_decls.dup
          eval_fn_arg_decls << "#{state_address_space} #{scalar_msl_type}* state_slots"
          if needs_cold_state_slots
            eval_fn_arg_decls << "#{cold_state_slots_address_space} #{scalar_msl_type}* cold_state_slots"
          end
          compute_fn_text +
            "#{inline_qualifier(always_inline: always_inline_eval)} #{out_struct} #{fn_name}(#{eval_fn_arg_decls.join(', ')}) {\n#{indent_lines(eval_lines)}\n}\n"
        end

        def emit_write_outputs_helper(top, output_names: nil)
          out_struct = top_output_struct_name(top.fetch(:name))
          fn_name = "write_#{sanitize_ident(top.fetch(:name))}_outputs"

          lines = []
          output_name_set = output_names ? output_names.map(&:to_s).to_set : nil
          selected_outputs = top.fetch(:outputs).select do |out|
            output_name_set.nil? || output_name_set.include?(out.fetch(:name))
          end
          selected_outputs.each do |out|
            name = sanitize_ident(out.fetch(:name))
            if wide_scalar?(out.fetch(:type))
              lines << "io->#{name} = out.#{name}.x;"
            else
              lines << "io->#{name} = out.#{name};"
            end
          end

          <<~MSL
            static inline __attribute__((always_inline)) void #{fn_name}(device RhdlArcGpuIo* io, #{out_struct} out) {
            #{indent_lines(lines)}
            }
          MSL
        end

        def emit_kernel(top:, metal_entry:, state_layout:)
          eval_fn = top_eval_fn_name(top.fetch(:name))
          out_struct = top_output_struct_name(top.fetch(:name))
          write_fn = "write_#{sanitize_ident(top.fetch(:name))}_outputs"
          clock_slots = count_clock_tracking_slots(top.fetch(:ops))
          state_slot_count = state_layout.sum { |entry| entry.fetch(:slot_count, 1) } + clock_slots

          if cpu8bit_gem_kernel_interpreter_enabled?
            return <<~MSL
              static inline __attribute__((always_inline)) uint rhdl_gem_read_io_word(uint field, device RhdlArcGpuIo* io) {
                switch (field) {
                  case 0u: return io->rst;
                  case 1u: return io->clk;
                  case 2u: return io->last_clk;
                  case 3u: return io->mem_data_in;
                  case 4u: return io->mem_data_out;
                  case 5u: return io->mem_addr;
                  case 6u: return io->mem_write_en;
                  case 7u: return io->mem_read_en;
                  case 8u: return io->pc_out;
                  case 9u: return io->acc_out;
                  case 10u: return io->sp_out;
                  case 11u: return io->halted;
                  case 12u: return io->state_out;
                  case 13u: return io->zero_flag_out;
                  case 14u: return io->cycle_budget;
                  case 15u: return io->cycles_ran;
                  default: return 0u;
                }
              }

              static inline __attribute__((always_inline)) void rhdl_gem_write_io_word(uint field, uint value, device RhdlArcGpuIo* io) {
                switch (field) {
                  case 0u: io->rst = value & 0x1u; break;
                  case 1u: io->clk = value & 0x1u; break;
                  case 2u: io->last_clk = value & 0x1u; break;
                  case 3u: io->mem_data_in = value & 0xFFu; break;
                  case 4u: io->mem_data_out = value & 0xFFu; break;
                  case 5u: io->mem_addr = value & 0xFFFFu; break;
                  case 6u: io->mem_write_en = value & 0x1u; break;
                  case 7u: io->mem_read_en = value & 0x1u; break;
                  case 8u: io->pc_out = value & 0xFFFFu; break;
                  case 9u: io->acc_out = value & 0xFFu; break;
                  case 10u: io->sp_out = value & 0xFFu; break;
                  case 11u: io->halted = value & 0x1u; break;
                  case 12u: io->state_out = value & 0xFFu; break;
                  case 13u: io->zero_flag_out = value & 0x1u; break;
                  case 14u: io->cycle_budget = value; break;
                  case 15u: io->cycles_ran = value; break;
                  default: break;
                }
              }

              static inline __attribute__((always_inline)) uint rhdl_gem_decode_extern_descriptor(
                uint desc,
                device #{scalar_msl_type}* state_slots,
                device RhdlArcGpuIo* io) {
                uint desc_kind = desc & 0x7u;
                switch (desc_kind) {
                  case 0u: {
                    return (desc >> 3u) & 0x1u;
                  }
                  case 1u: {
                    uint state_index = (desc >> 3u) & 0x3FFu;
                    uint bit_index = (desc >> 13u) & 0x3Fu;
                    if (state_index < #{state_slot_count}u && bit_index < 32u) {
                      return (uint(state_slots[state_index]) >> bit_index) & 0x1u;
                    }
                    return 0u;
                  }
                  case 2u: {
                    uint field = (desc >> 3u) & 0xFFu;
                    uint bit_index = (desc >> 11u) & 0x3Fu;
                    if (bit_index < 32u) {
                      return (rhdl_gem_read_io_word(field, io) >> bit_index) & 0x1u;
                    }
                    return 0u;
                  }
                  case 4u:
                  case 5u: {
                    uint lhs_state_index = (desc >> 3u) & 0x3FFu;
                    uint rhs_state_index = (desc >> 13u) & 0x3FFu;
                    uint bit_index = (desc >> 23u) & 0x3Fu;
                    if (lhs_state_index < #{state_slot_count}u && rhs_state_index < #{state_slot_count}u && bit_index < 32u) {
                      uint lhs = uint(state_slots[lhs_state_index]) & 0xFFu;
                      uint rhs = uint(state_slots[rhs_state_index]) & 0xFFu;
                      uint result = 0u;
                      if (rhs != 0u) {
                        result = desc_kind == 4u ? (lhs / rhs) : (lhs % rhs);
                      }
                      return (result >> bit_index) & 0x1u;
                    }
                    return 0u;
                  }
                  default: {
                    return 0u;
                  }
                }
              }

              static inline __attribute__((always_inline)) uint rhdl_gem_decode_src(
                uint packed,
                thread uchar* node_vals,
                device const uint* gem_instr,
                uint gem_flags,
                uint extern_off,
                uint extern_count,
                uint extern_desc_off,
                uint extern_desc_count,
                device #{scalar_msl_type}* state_slots,
                device RhdlArcGpuIo* io,
                thread const uint* extern_values,
                uint extern_value_count) {
                constexpr uint kGemNodeCap = 4096u;
                uint inv = packed & 1u;
                uint kind = (packed >> 1u) & 1u;
                uint id = packed >> 2u;
                uint value = 0u;
                if (kind == 0u) {
                  if (id < kGemNodeCap) {
                    value = uint(node_vals[id]) & 1u;
                  }
                } else {
                  if (id < extern_value_count) {
                    value = extern_values[id] & 0x1u;
                  } else if ((gem_flags & 0x8u) != 0u && id < extern_desc_count) {
                    uint desc = gem_instr[extern_desc_off + 1u + id];
                    value = rhdl_gem_decode_extern_descriptor(desc, state_slots, io);
                  } else if ((gem_flags & 0x4u) != 0u) {
                    if (id < extern_count) {
                      value = gem_instr[extern_off + 1u + id] & 1u;
                    }
                  } else {
                    value = id & 1u;
                  }
                }
                return (value ^ inv) & 1u;
              }

              static inline __attribute__((always_inline)) void rhdl_gem_fill_extern_values(
                device const uint* gem_instr,
                uint gem_flags,
                uint extern_off,
                uint extern_count,
                uint extern_desc_off,
                uint extern_desc_count,
                device #{scalar_msl_type}* state_slots,
                device RhdlArcGpuIo* io,
                thread uint* extern_values,
                uint extern_value_count) {
                for (uint e = 0u; e < extern_value_count; ++e) {
                  uint value = 0u;
                  if ((gem_flags & 0x8u) != 0u && e < extern_desc_count) {
                    uint desc = gem_instr[extern_desc_off + 1u + e];
                    value = rhdl_gem_decode_extern_descriptor(desc, state_slots, io);
                  } else if ((gem_flags & 0x4u) != 0u && e < extern_count) {
                    value = gem_instr[extern_off + 1u + e] & 1u;
                  } else {
                    value = e & 1u;
                  }
                  extern_values[e] = value & 0x1u;
                }
              }

              static inline __attribute__((always_inline)) void rhdl_gem_eval_nodes(
                device const uint* gem_instr,
                uint instr_count,
                uint gem_flags,
                uint extern_off,
                uint extern_count,
                uint extern_desc_off,
                uint extern_desc_count,
                device #{scalar_msl_type}* state_slots,
                device RhdlArcGpuIo* io,
                thread const uint* extern_values,
                uint extern_value_count,
                thread uchar* node_vals) {
                constexpr uint kGemNodeCap = 4096u;
                for (uint idx = 0u; idx < kGemNodeCap; ++idx) {
                  node_vals[idx] = 0u;
                }
                for (uint idx = 0u; idx < instr_count; ++idx) {
                  uint off = 2u + (idx * 4u);
                  uint dst = gem_instr[off];
                  if (dst >= kGemNodeCap) {
                    continue;
                  }
                  uint src0_packed = gem_instr[off + 1u];
                  uint src1_packed = gem_instr[off + 2u];
                  uint src0 = rhdl_gem_decode_src(
                    src0_packed, node_vals, gem_instr, gem_flags,
                    extern_off, extern_count, extern_desc_off, extern_desc_count,
                    state_slots, io, extern_values, extern_value_count);
                  uint src1 = rhdl_gem_decode_src(
                    src1_packed, node_vals, gem_instr, gem_flags,
                    extern_off, extern_count, extern_desc_off, extern_desc_count,
                    state_slots, io, extern_values, extern_value_count);
                  uint value = (src0 & src1) & 1u;
                  node_vals[dst] = uchar(value);
                }
              }

              static inline __attribute__((always_inline)) uint rhdl_gem_materialize_word(
                device const uint* gem_instr,
                uint source_off,
                uint width,
                thread uchar* node_vals,
                uint gem_flags,
                uint extern_off,
                uint extern_count,
                uint extern_desc_off,
                uint extern_desc_count,
                device #{scalar_msl_type}* state_slots,
                device RhdlArcGpuIo* io,
                thread const uint* extern_values,
                uint extern_value_count) {
                uint word = 0u;
                uint bit_count = width > 32u ? 32u : width;
                for (uint bit = 0u; bit < bit_count; ++bit) {
                  uint packed = gem_instr[source_off + bit];
                  uint value = rhdl_gem_decode_src(
                    packed, node_vals, gem_instr, gem_flags,
                    extern_off, extern_count, extern_desc_off, extern_desc_count,
                    state_slots, io, extern_values, extern_value_count);
                  word |= (value & 0x1u) << bit;
                }
                return word;
              }

              static inline __attribute__((always_inline)) uint rhdl_gem_execute_shadow(
                device const uint* gem_instr,
                device #{scalar_msl_type}* state_slots,
                device RhdlArcGpuIo* io,
                thread uint* watch_bits) {
                constexpr uint kGemNodeCap = 4096u;
                uint instr_count = gem_instr[0];
                uint gem_flags = gem_instr[1];
                bool emit_shadow_hash = (gem_flags & 0x2u) != 0u;
                if (instr_count > kGemNodeCap) {
                  instr_count = kGemNodeCap;
                }
                uint watch_off = 2u + (instr_count * 4u);
                uint watch_count = gem_instr[watch_off];
                if (watch_count > 32u) {
                  watch_count = 32u;
                }
                uint control_off = watch_off + 1u + watch_count;
                uint control_count = gem_instr[control_off];
                if (control_count > 32u) {
                  control_count = 32u;
                }
                uint extern_off = control_off + 1u + control_count;
                uint extern_count = gem_instr[extern_off];
                if (extern_count > 16384u) {
                  extern_count = 16384u;
                }
                uint extern_desc_off = extern_off + 1u + extern_count;
                uint extern_desc_count = gem_instr[extern_desc_off];
                if (extern_desc_count > 16384u) {
                  extern_desc_count = 16384u;
                }
                uint watch_eval_off = extern_desc_off + 1u + extern_desc_count;
                uint watch_eval_count = gem_instr[watch_eval_off];
                if (watch_eval_count > instr_count) {
                  watch_eval_count = instr_count;
                }
                bool use_watch_subset = ((gem_flags & 0x1u) != 0u) && watch_eval_count > 0u;
                constexpr uint kGemExternValueCap = 512u;
                thread uint extern_values[kGemExternValueCap];
                uint extern_value_count = extern_desc_count > extern_count ? extern_desc_count : extern_count;
                if (extern_value_count > kGemExternValueCap) {
                  extern_value_count = kGemExternValueCap;
                }
                for (uint e = 0u; e < extern_value_count; ++e) {
                  uint value = 0u;
                  if ((gem_flags & 0x8u) != 0u && e < extern_desc_count) {
                    uint desc = gem_instr[extern_desc_off + 1u + e];
                    uint desc_kind = desc & 0x3u;
                    switch (desc_kind) {
                      case 0u: {
                        value = (desc >> 2u) & 0x1u;
                        break;
                      }
                      case 1u: {
                        uint state_index = (desc >> 2u) & 0xFFFFu;
                        uint bit_index = (desc >> 18u) & 0x3Fu;
                        if (state_index < #{state_slot_count}u && bit_index < 32u) {
                          value = (uint(state_slots[state_index]) >> bit_index) & 0x1u;
                        }
                        break;
                      }
                      case 2u: {
                        uint field = (desc >> 2u) & 0xFFu;
                        uint bit_index = (desc >> 10u) & 0x3Fu;
                        if (bit_index < 32u) {
                          value = (rhdl_gem_read_io_word(field, io) >> bit_index) & 0x1u;
                        }
                        break;
                      }
                      default: {
                        value = 0u;
                        break;
                      }
                    }
                  } else if ((gem_flags & 0x4u) != 0u && e < extern_count) {
                    value = gem_instr[extern_off + 1u + e] & 1u;
                  } else {
                    value = e & 1u;
                  }
                  extern_values[e] = value & 0x1u;
                }

                thread uchar node_vals[kGemNodeCap];
                if (use_watch_subset) {
                  for (uint wi = 0u; wi < watch_eval_count; ++wi) {
                    uint idx = gem_instr[watch_eval_off + 1u + wi];
                    if (idx >= instr_count) {
                      continue;
                    }
                    uint off = 2u + (idx * 4u);
                    uint dst = gem_instr[off];
                    if (dst < kGemNodeCap) {
                      node_vals[dst] = 0u;
                    }
                  }
                } else {
                  for (uint i = 0u; i < kGemNodeCap; ++i) {
                    node_vals[i] = 0u;
                  }
                }

                uint shadow = 0u;
                if (use_watch_subset) {
                  if (emit_shadow_hash) {
                    for (uint wi = 0u; wi < watch_eval_count; ++wi) {
                      uint idx = gem_instr[watch_eval_off + 1u + wi];
                      if (idx >= instr_count) {
                        continue;
                      }
                      uint off = 2u + (idx * 4u);
                      uint dst = gem_instr[off];
                      uint src0_packed = gem_instr[off + 1u];
                      uint src1_packed = gem_instr[off + 2u];
                      if (dst >= kGemNodeCap) {
                        continue;
                      }

                      uint src0 = rhdl_gem_decode_src(
                        src0_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint src1 = rhdl_gem_decode_src(
                        src1_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint value = (src0 & src1) & 1u;
                      node_vals[dst] = uchar(value);
                      shadow = ((shadow << 1u) | (shadow >> 31u)) ^ (value << (idx & 31u));
                    }
                  } else {
                    for (uint wi = 0u; wi < watch_eval_count; ++wi) {
                      uint idx = gem_instr[watch_eval_off + 1u + wi];
                      if (idx >= instr_count) {
                        continue;
                      }
                      uint off = 2u + (idx * 4u);
                      uint dst = gem_instr[off];
                      uint src0_packed = gem_instr[off + 1u];
                      uint src1_packed = gem_instr[off + 2u];
                      if (dst >= kGemNodeCap) {
                        continue;
                      }

                      uint src0 = rhdl_gem_decode_src(
                        src0_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint src1 = rhdl_gem_decode_src(
                        src1_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint value = (src0 & src1) & 1u;
                      node_vals[dst] = uchar(value);
                    }
                  }
                } else {
                  if (emit_shadow_hash) {
                    for (uint idx = 0u; idx < instr_count; ++idx) {
                      uint off = 2u + (idx * 4u);
                      uint dst = gem_instr[off];
                      uint src0_packed = gem_instr[off + 1u];
                      uint src1_packed = gem_instr[off + 2u];
                      if (dst >= kGemNodeCap) {
                        continue;
                      }

                      uint src0 = rhdl_gem_decode_src(
                        src0_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint src1 = rhdl_gem_decode_src(
                        src1_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint value = (src0 & src1) & 1u;
                      node_vals[dst] = uchar(value);
                      shadow = ((shadow << 1u) | (shadow >> 31u)) ^ (value << (idx & 31u));
                    }
                  } else {
                    for (uint idx = 0u; idx < instr_count; ++idx) {
                      uint off = 2u + (idx * 4u);
                      uint dst = gem_instr[off];
                      uint src0_packed = gem_instr[off + 1u];
                      uint src1_packed = gem_instr[off + 2u];
                      if (dst >= kGemNodeCap) {
                        continue;
                      }

                      uint src0 = rhdl_gem_decode_src(
                        src0_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint src1 = rhdl_gem_decode_src(
                        src1_packed, node_vals, gem_instr, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint value = (src0 & src1) & 1u;
                      node_vals[dst] = uchar(value);
                    }
                  }
                }

                if (watch_bits != nullptr) {
                  uint watch = 0u;
                  for (uint w = 0u; w < watch_count; ++w) {
                    uint packed = gem_instr[watch_off + 1u + w];
                    uint bit = rhdl_gem_decode_src(
                      packed, node_vals, gem_instr, gem_flags,
                      extern_off, extern_count, extern_desc_off, extern_desc_count,
                      state_slots, io, extern_values, extern_value_count);
                    watch |= (bit & 1u) << w;
                  }
                  *watch_bits = watch;
                }

                if ((gem_flags & 0x2u) != 0u && watch_bits != nullptr) {
                  threadgroup_barrier(mem_flags::mem_none);
                }

                return shadow;
              }

              kernel void #{metal_entry}(
                device #{scalar_msl_type}* all_state_slots [[buffer(0)]],
                device uchar* all_memory [[buffer(1)]],
                device RhdlArcGpuIo* all_io [[buffer(2)]],
                device const uint* gem_instr [[buffer(3)]],
                uint tid [[thread_position_in_grid]]) {
                device #{scalar_msl_type}* state_slots = all_state_slots + (tid * #{state_slot_count}u);
                device uchar* memory = all_memory + (tid * 65536u);
                device RhdlArcGpuIo* io = all_io + tid;

                io->cycles_ran = 0u;
                uint budget = io->cycle_budget;
                uint gem_flags = gem_instr[1];
                uint instr_count = gem_instr[0];
                if (instr_count > 4096u) {
                  instr_count = 4096u;
                }
                uint watch_off = 2u + (instr_count * 4u);
                uint watch_count = gem_instr[watch_off];
                if (watch_count > 32u) {
                  watch_count = 32u;
                }
                uint control_off = watch_off + 1u + watch_count;
                uint control_count = gem_instr[control_off];
                if (control_count > 32u) {
                  control_count = 32u;
                }
                uint extern_off = control_off + 1u + control_count;
                uint extern_count = gem_instr[extern_off];
                if (extern_count > 16384u) {
                  extern_count = 16384u;
                }
                uint extern_desc_off = extern_off + 1u + extern_count;
                uint extern_desc_count = gem_instr[extern_desc_off];
                if (extern_desc_count > 16384u) {
                  extern_desc_count = 16384u;
                }
                uint watch_eval_off = extern_desc_off + 1u + extern_desc_count;
                uint watch_eval_count = gem_instr[watch_eval_off];
                if (watch_eval_count > instr_count) {
                  watch_eval_count = instr_count;
                }
                uint output_field_off = watch_eval_off + 1u + watch_eval_count;
                uint output_field_count = gem_instr[output_field_off];
                if (output_field_count > 64u) {
                  output_field_count = 64u;
                }
                uint output_width_off = output_field_off + 1u + output_field_count;
                uint output_width_count = gem_instr[output_width_off];
                if (output_width_count > output_field_count) {
                  output_width_count = output_field_count;
                }
                uint output_bits_off = output_width_off + 1u + output_width_count;
                uint output_bit_count = gem_instr[output_bits_off];
                if (output_bit_count > 32768u) {
                  output_bit_count = 32768u;
                }
                uint state_slot_off = output_bits_off + 1u + output_bit_count;
                uint state_slot_count_stream = gem_instr[state_slot_off];
                if (state_slot_count_stream > #{state_slot_count}u) {
                  state_slot_count_stream = #{state_slot_count}u;
                }
                uint state_width_off = state_slot_off + 1u + state_slot_count_stream;
                uint state_width_count = gem_instr[state_width_off];
                if (state_width_count > state_slot_count_stream) {
                  state_width_count = state_slot_count_stream;
                }
                uint state_next_off = state_width_off + 1u + state_width_count;
                uint state_next_count = gem_instr[state_next_off];
                if (state_next_count > 32768u) {
                  state_next_count = 32768u;
                }
                uint state_reset_off = state_next_off + 1u + state_next_count;
                uint state_reset_count = gem_instr[state_reset_off];
                if (state_reset_count > 32768u) {
                  state_reset_count = 32768u;
                }
                uint state_reset_en_off = state_reset_off + 1u + state_reset_count;
                uint state_reset_en_count = gem_instr[state_reset_en_off];
                if (state_reset_en_count > state_slot_count_stream) {
                  state_reset_en_count = state_slot_count_stream;
                }

                constexpr ushort kOpCycleBegin = 0u;
                constexpr ushort kOpEvalLow = 1u;
                constexpr ushort kOpMemWrite = 2u;
                constexpr ushort kOpMemRead = 3u;
                constexpr ushort kOpEvalHigh = 4u;
                constexpr ushort kOpOutput = 5u;
                constexpr ushort kOpCycleEnd = 6u;
                constexpr ushort kGemControlOps[7] = {
                  kOpCycleBegin,
                  kOpEvalLow,
                  kOpMemWrite,
                  kOpMemRead,
                  kOpEvalHigh,
                  kOpOutput,
                  kOpCycleEnd
                };
                uint op_count = control_count > 0u ? control_count : 7u;
                thread ushort control_ops[32];
                if (control_count > 0u) {
                  for (uint op_idx = 0u; op_idx < op_count; ++op_idx) {
                    control_ops[op_idx] = ushort(gem_instr[control_off + 1u + op_idx] & 0xFFFFu);
                  }
                }
                bool control_matches_default = control_count == 0u;
                if (!control_matches_default && control_count == 7u) {
                  control_matches_default = true;
                  for (uint op_idx = 0u; op_idx < 7u; ++op_idx) {
                    if (control_ops[op_idx] != kGemControlOps[op_idx]) {
                      control_matches_default = false;
                      break;
                    }
                  }
                }
                bool use_fast_default_loop = control_matches_default && (gem_flags & 0x3u) == 0u;
                uint output_width_total = 0u;
                for (uint idx = 0u; idx < output_width_count; ++idx) {
                  output_width_total += gem_instr[output_width_off + 1u + idx] & 0x3Fu;
                }
                uint state_width_total = 0u;
                for (uint idx = 0u; idx < state_width_count; ++idx) {
                  state_width_total += gem_instr[state_width_off + 1u + idx] & 0x3Fu;
                }
                bool stream_semantics_ready =
                  (gem_flags & 0x10u) != 0u &&
                  output_field_count > 0u &&
                  output_width_count == output_field_count &&
                  output_bit_count == output_width_total &&
                  state_slot_count_stream > 0u &&
                  state_width_count == state_slot_count_stream &&
                  state_next_count == state_width_total &&
                  state_reset_count == state_width_total &&
                  state_reset_en_count == state_slot_count_stream;

                if (budget == 0u) {
                  uint clk_now = io->clk & 1u;
                  io->last_clk = clk_now;
                  #{out_struct} out = #{eval_fn}(clk_now, io->rst, io->mem_data_in, state_slots);
                  #{write_fn}(io, out);
                  return;
                }

                if (stream_semantics_ready && (gem_flags & 0x3u) == 0u) {
                  constexpr uint kGemNodeCap = 4096u;
                  constexpr uint kGemExternValueCap = 1024u;
                  constexpr uint kGemStateStageCap = #{state_slot_count}u;
                  thread uchar node_vals[kGemNodeCap];
                  thread uint extern_values[kGemExternValueCap];
                  thread uint staged_state_values[kGemStateStageCap];
                  uint extern_value_count = extern_desc_count > extern_count ? extern_desc_count : extern_count;
                  if (extern_value_count > kGemExternValueCap) {
                    extern_value_count = kGemExternValueCap;
                  }
                  uint mem_data_out_offset = 0xFFFFFFFFu;
                  uint mem_data_out_width = 0u;
                  uint mem_addr_offset = 0xFFFFFFFFu;
                  uint mem_addr_width = 0u;
                  uint mem_write_en_offset = 0xFFFFFFFFu;
                  uint mem_write_en_width = 0u;
                  uint output_cursor_scan = 0u;
                  for (uint out_idx = 0u; out_idx < output_field_count; ++out_idx) {
                    uint field = gem_instr[output_field_off + 1u + out_idx] & 0xFFu;
                    uint width = gem_instr[output_width_off + 1u + out_idx] & 0x3Fu;
                    if (field == 4u) {
                      mem_data_out_offset = output_cursor_scan;
                      mem_data_out_width = width;
                    } else if (field == 5u) {
                      mem_addr_offset = output_cursor_scan;
                      mem_addr_width = width;
                    } else if (field == 6u) {
                      mem_write_en_offset = output_cursor_scan;
                      mem_write_en_width = width;
                    }
                    output_cursor_scan += width;
                  }

                  for (uint i = 0u; i < budget; ++i) {
                    if ((io->halted & 1u) != 0u) {
                      break;
                    }

                    uint low_clk = 0u;
                    io->last_clk = low_clk;
                    io->clk = low_clk;
                    rhdl_gem_fill_extern_values(
                      gem_instr, gem_flags, extern_off, extern_count, extern_desc_off, extern_desc_count,
                      state_slots, io, extern_values, extern_value_count);
                    rhdl_gem_eval_nodes(
                      gem_instr, instr_count, gem_flags, extern_off, extern_count, extern_desc_off, extern_desc_count,
                      state_slots, io, extern_values, extern_value_count, node_vals);

                    uint low_mem_data_out = 0u;
                    uint low_mem_addr = 0u;
                    uint low_mem_write_en = 0u;
                    if (mem_data_out_offset != 0xFFFFFFFFu && mem_data_out_width > 0u) {
                      low_mem_data_out = rhdl_gem_materialize_word(
                        gem_instr, output_bits_off + 1u + mem_data_out_offset, mem_data_out_width, node_vals, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count) & 0xFFu;
                    }
                    if (mem_addr_offset != 0xFFFFFFFFu && mem_addr_width > 0u) {
                      low_mem_addr = rhdl_gem_materialize_word(
                        gem_instr, output_bits_off + 1u + mem_addr_offset, mem_addr_width, node_vals, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count) & 0xFFFFu;
                    }
                    if (mem_write_en_offset != 0xFFFFFFFFu && mem_write_en_width > 0u) {
                      low_mem_write_en = rhdl_gem_materialize_word(
                        gem_instr, output_bits_off + 1u + mem_write_en_offset, mem_write_en_width, node_vals, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count) & 0x1u;
                    }

                    uint addr = low_mem_addr & 0xFFFFu;
                    if ((low_mem_write_en & 1u) != 0u) {
                      memory[addr] = uchar(low_mem_data_out & 0xFFu);
                    }
                    io->mem_data_in = uint(memory[addr]);

                    uint high_clk = 1u;
                    io->last_clk = high_clk;
                    io->clk = high_clk;
                    rhdl_gem_fill_extern_values(
                      gem_instr, gem_flags, extern_off, extern_count, extern_desc_off, extern_desc_count,
                      state_slots, io, extern_values, extern_value_count);
                    rhdl_gem_eval_nodes(
                      gem_instr, instr_count, gem_flags, extern_off, extern_count, extern_desc_off, extern_desc_count,
                      state_slots, io, extern_values, extern_value_count, node_vals);

                    uint next_cursor = 0u;
                    uint reset_cursor = 0u;
                    for (uint state_idx = 0u; state_idx < state_slot_count_stream; ++state_idx) {
                      uint slot = gem_instr[state_slot_off + 1u + state_idx];
                      uint width = gem_instr[state_width_off + 1u + state_idx] & 0x3Fu;
                      uint next_value = rhdl_gem_materialize_word(
                        gem_instr, state_next_off + 1u + next_cursor, width, node_vals, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint reset_value = rhdl_gem_materialize_word(
                        gem_instr, state_reset_off + 1u + reset_cursor, width, node_vals, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, extern_value_count);
                      uint reset_enable = io->rst & 1u;
                      if (state_idx < state_reset_en_count) {
                        uint packed_reset_enable = gem_instr[state_reset_en_off + 1u + state_idx];
                        reset_enable = rhdl_gem_decode_src(
                          packed_reset_enable, node_vals, gem_instr, gem_flags,
                          extern_off, extern_count, extern_desc_off, extern_desc_count,
                          state_slots, io, extern_values, extern_value_count);
                      }
                      uint value = (reset_enable & 1u) != 0u ? reset_value : next_value;
                      if (state_idx < kGemStateStageCap && slot < #{state_slot_count}u && width > 0u) {
                        uint mask = width >= 32u ? 0xFFFFFFFFu : ((1u << width) - 1u);
                        staged_state_values[state_idx] = value & mask;
                      }
                      next_cursor += width;
                      reset_cursor += width;
                    }

                    for (uint state_idx = 0u; state_idx < state_slot_count_stream; ++state_idx) {
                      uint slot = gem_instr[state_slot_off + 1u + state_idx];
                      uint width = gem_instr[state_width_off + 1u + state_idx] & 0x3Fu;
                      if (state_idx < kGemStateStageCap && slot < #{state_slot_count}u && width > 0u) {
                        state_slots[slot] = (#{scalar_msl_type})staged_state_values[state_idx];
                      }
                    }

                    uint output_cursor = 0u;
                    uint live_output_extern_count = 0u;
                    for (uint out_idx = 0u; out_idx < output_field_count; ++out_idx) {
                      uint field = gem_instr[output_field_off + 1u + out_idx] & 0xFFu;
                      uint width = gem_instr[output_width_off + 1u + out_idx] & 0x3Fu;
                      uint value = rhdl_gem_materialize_word(
                        gem_instr, output_bits_off + 1u + output_cursor, width, node_vals, gem_flags,
                        extern_off, extern_count, extern_desc_off, extern_desc_count,
                        state_slots, io, extern_values, live_output_extern_count);
                      rhdl_gem_write_io_word(field, value, io);
                      output_cursor += width;
                    }

                    io->cycles_ran = i + 1u;
                    if ((io->halted & 1u) != 0u) {
                      break;
                    }
                  }
                  return;
                }

                if (use_fast_default_loop) {
                  for (uint i = 0u; i < budget; ++i) {
                    if ((io->halted & 1u) != 0u) {
                      break;
                    }

                    uint low_clk = 0u;
                    io->last_clk = low_clk;
                    io->clk = low_clk;
                    #{out_struct} low = #{eval_fn}(io->clk, io->rst, io->mem_data_in, state_slots);
                    uint addr = low.mem_addr & 0xFFFFu;
                    if ((low.mem_write_en & 1u) != 0u) {
                      memory[addr] = uchar(low.mem_data_out & 0xFFu);
                    }
                    io->mem_data_in = uint(memory[addr]);

                    uint high_clk = 1u;
                    io->last_clk = high_clk;
                    io->clk = high_clk;
                    #{out_struct} high = #{eval_fn}(io->clk, io->rst, io->mem_data_in, state_slots);
                    #{write_fn}(io, high);
                    io->cycles_ran = i + 1u;

                    if ((io->halted & 1u) != 0u) {
                      break;
                    }
                  }
                  return;
                }

                for (uint i = 0u; i < budget; ++i) {
                  if ((io->halted & 1u) != 0u) {
                    break;
                  }

                  #{out_struct} low;
                  #{out_struct} high;
                  bool have_low = false;
                  bool have_high = false;
                  uint addr = 0u;
                  uint gem_shadow = 0u;
                  uint gem_watch_bits = 0u;

                  for (uint op_idx = 0u; op_idx < op_count; ++op_idx) {
                    ushort op = control_count > 0u ? control_ops[op_idx] : kGemControlOps[op_idx];
                    switch (op) {
                      case kOpCycleBegin: {
                        break;
                      }
                      case kOpEvalLow: {
                        bool need_watch_override = (gem_flags & 0x1u) != 0u;
                        bool need_debug_shadow = (gem_flags & 0x2u) != 0u;
                        if (need_watch_override || (i == 0u && need_debug_shadow)) {
                          gem_shadow = rhdl_gem_execute_shadow(gem_instr, state_slots, io, &gem_watch_bits);
                          if (need_debug_shadow && (gem_shadow & 1u) != 0u) {
                            threadgroup_barrier(mem_flags::mem_none);
                          }
                        }
                        uint low_clk = 0u;
                        io->last_clk = low_clk;
                        io->clk = low_clk;
                        low = #{eval_fn}(io->clk, io->rst, io->mem_data_in, state_slots);
                        have_low = true;
                        break;
                      }
                      case kOpMemWrite: {
                        if (have_low) {
                          addr = low.mem_addr & 0xFFFFu;
                          if ((low.mem_write_en & 1u) != 0u) {
                            memory[addr] = uchar(low.mem_data_out & 0xFFu);
                          }
                        }
                        break;
                      }
                      case kOpMemRead: {
                        if (have_low) {
                          uint mem_in = uint(memory[addr]);
                          io->mem_data_in = mem_in;
                        }
                        break;
                      }
                      case kOpEvalHigh: {
                        uint high_clk = 1u;
                        io->last_clk = high_clk;
                        io->clk = high_clk;
                        high = #{eval_fn}(io->clk, io->rst, io->mem_data_in, state_slots);
                        if ((gem_flags & 0x1u) != 0u) {
                          high.mem_write_en = (gem_watch_bits >> 0u) & 1u;
                          high.mem_read_en = (gem_watch_bits >> 1u) & 1u;
                          high.zero_flag_out = (gem_watch_bits >> 3u) & 1u;
                        }
                        have_high = true;
                        break;
                      }
                      case kOpOutput: {
                        if (have_high) {
                          #{write_fn}(io, high);
                          io->cycles_ran = i + 1u;
                        }
                        break;
                      }
                      case kOpCycleEnd: {
                        break;
                      }
                      default: {
                        break;
                      }
                    }
                  }

                  if ((io->halted & 1u) != 0u) {
                    break;
                  }
                }
              }
            MSL
          end

          <<~MSL
            kernel void #{metal_entry}(
              device #{scalar_msl_type}* all_state_slots [[buffer(0)]],
              device uchar* all_memory [[buffer(1)]],
              device RhdlArcGpuIo* all_io [[buffer(2)]],
              uint tid [[thread_position_in_grid]]) {
              device #{scalar_msl_type}* state_slots = all_state_slots + (tid * #{state_slot_count}u);
              device uchar* memory = all_memory + (tid * 65536u);
              device RhdlArcGpuIo* io = all_io + tid;

              io->cycles_ran = 0u;
              uint budget = io->cycle_budget;

              if (budget == 0u) {
                uint clk_now = io->clk & 1u;
                io->last_clk = clk_now;
                #{out_struct} out = #{eval_fn}(clk_now, io->rst, io->mem_data_in, state_slots);
                #{write_fn}(io, out);
                return;
              }

              for (uint i = 0u; i < budget; ++i) {
                if ((io->halted & 1u) != 0u) {
                  break;
                }

                uint low_clk = 0u;
                io->last_clk = low_clk;
                io->clk = low_clk;
                #{out_struct} low = #{eval_fn}(io->clk, io->rst, io->mem_data_in, state_slots);
                uint addr = low.mem_addr & 0xFFFFu;
                if ((low.mem_write_en & 1u) != 0u) {
                  memory[addr] = uchar(low.mem_data_out & 0xFFu);
                }

                uint mem_in = uint(memory[addr]);
                io->mem_data_in = mem_in;

                uint high_clk = 1u;
                io->last_clk = high_clk;
                io->clk = high_clk;
                #{out_struct} high = #{eval_fn}(io->clk, io->rst, io->mem_data_in, state_slots);
                #{write_fn}(io, high);
                io->cycles_ran = i + 1u;

                if ((io->halted & 1u) != 0u) {
                  break;
                }
              }
            }
          MSL
        end

        def cpu8bit_gem_kernel_interpreter_enabled?
          ENV.fetch('RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER', '0') == '1'
        end
        private :cpu8bit_gem_kernel_interpreter_enabled?

        def emit_kernel_riscv(
          top:,
          metal_entry:,
          state_layout:,
          low_eval_fn:,
          low_wdata_eval_fn: nil,
          low_data_addr_eval_fn: nil,
          high_eval_fn:,
          high_data_addr_eval_fn: nil,
          full_eval_fn:,
          low_loop_step_struct:,
          low_wdata_step_struct: nil,
          low_data_addr_step_struct: nil,
          high_loop_step_struct:,
          high_data_addr_step_struct: nil,
          cold_memory_layout: [],
          fast_path: false,
          dirty_settle_enabled: false,
          split_low_wdata_eval: false,
          split_high_data_addr_eval: false,
          split_low_data_addr_eval: false
        )
          out_struct = top_output_struct_name(top.fetch(:name))
          write_fn = "write_#{sanitize_ident(top.fetch(:name))}_outputs"
          clock_slots = count_clock_tracking_slots(top.fetch(:ops))
          state_value_slot_count = state_layout.sum { |entry| entry.fetch(:slot_count, 1) }
          state_slot_count = state_value_slot_count + clock_slots
          low_clock_reset_block =
            if clock_slots <= 0
              nil
            elsif clock_slots == 1
              "state_slots[#{state_value_slot_count}u] = 0u;"
            else
              <<~MSL.strip
                for (uint clock_slot = #{state_value_slot_count}u; clock_slot < #{state_slot_count}u; ++clock_slot) {
                  state_slots[clock_slot] = 0u;
                }
              MSL
            end

          cold_ranges = cold_memory_layout.filter_map do |entry|
            start_idx = entry.fetch(:index).to_i
            slot_count = entry.fetch(:slot_count, 1).to_i
            finish_idx = start_idx + slot_count
            next if finish_idx <= 0 || start_idx >= state_value_slot_count

            [start_idx.clamp(0, state_value_slot_count), finish_idx.clamp(0, state_value_slot_count)]
          end.sort_by(&:first)
          merged_cold_ranges = []
          cold_ranges.each do |start_idx, finish_idx|
            if merged_cold_ranges.empty? || start_idx > merged_cold_ranges.last[1]
              merged_cold_ranges << [start_idx, finish_idx]
            else
              merged_cold_ranges.last[1] = [merged_cold_ranges.last[1], finish_idx].max
            end
          end
          hot_ranges = []
          hot_cursor = 0
          merged_cold_ranges.each do |start_idx, finish_idx|
            hot_ranges << [hot_cursor, start_idx] if hot_cursor < start_idx
            hot_cursor = finish_idx
          end
          hot_ranges << [hot_cursor, state_value_slot_count] if hot_cursor < state_value_slot_count
          has_cold_memory = !merged_cold_ranges.empty?

          hot_copy_in_lines = hot_ranges.flat_map do |start_idx, finish_idx|
            if (finish_idx - start_idx) == 1
              ["local_state[#{start_idx}u] = global_state_slots[#{start_idx}u];"]
            else
              [
                "for (uint si = #{start_idx}u; si < #{finish_idx}u; ++si) {",
                '  local_state[si] = global_state_slots[si];',
                '}'
              ]
            end
          end

          hot_copy_out_lines = hot_ranges.flat_map do |start_idx, finish_idx|
            if (finish_idx - start_idx) == 1
              ["global_state_slots[#{start_idx}u] = state_slots[#{start_idx}u];"]
            else
              [
                "for (uint si = #{start_idx}u; si < #{finish_idx}u; ++si) {",
                '  global_state_slots[si] = state_slots[si];',
                '}'
              ]
            end
          end

          state_init_lines =
            if has_cold_memory
              lines = []
              lines << 'if (budget == 0u) {'
              lines << "  for (uint si = 0u; si < #{state_slot_count}u; ++si) {"
              lines << '    local_state[si] = global_state_slots[si];'
              lines << '  }'
              lines << '} else {'
              hot_copy_in_lines.each { |line| lines << "  #{line}" }
              if clock_slots.positive?
                lines << "  for (uint si = #{state_value_slot_count}u; si < #{state_slot_count}u; ++si) {"
                lines << '    local_state[si] = 0u;'
                lines << '  }'
              end
              lines << '}'
              lines
            else
              [
                "uint state_copy_count = (budget == 0u) ? #{state_slot_count}u : #{state_value_slot_count}u;",
                'for (uint si = 0u; si < state_copy_count; ++si) {',
                '  local_state[si] = global_state_slots[si];',
                '}',
                'if (budget != 0u) {',
                "  for (uint si = #{state_value_slot_count}u; si < #{state_slot_count}u; ++si) {",
                '    local_state[si] = 0u;',
                '  }',
                '}'
              ]
            end

          state_copy_back_lines =
            if has_cold_memory
              hot_copy_out_lines
            else
              [
                "for (uint si = 0u; si < #{state_value_slot_count}u; ++si) {",
                '  global_state_slots[si] = state_slots[si];',
                '}'
              ]
            end

          input_layout = top.fetch(:inputs).map do |input|
            { name: sanitize_ident(input.fetch(:name)), width: input.fetch(:type).fetch(:width).to_i }
          end
          input_by_name = {}
          input_layout.each { |entry| input_by_name[entry.fetch(:name)] = entry }
          constant_input_values = riscv_kernel_constant_inputs(input_layout)

          mask_expr = lambda do |width|
            return nil if width >= 32

            ((1 << width) - 1).to_s
          end

          constant_input_literals = {}
          constant_input_values.each do |name, value|
            entry = input_by_name[name]
            next unless entry

            width = entry.fetch(:width)
            masked_value =
              if width <= 0
                0
              elsif width >= 32
                value & 0xFFFF_FFFF
              else
                value & ((1 << width) - 1)
              end
            constant_input_literals[name] = "#{masked_value}u"
          end

          input_local_lines = input_layout.map do |entry|
            name = entry.fetch(:name)
            if constant_input_literals.key?(name)
              next "uint in_#{name} = #{constant_input_literals.fetch(name)};"
            end

            width = entry.fetch(:width)
            mask = mask_expr.call(width)
            if mask
              "uint in_#{name} = io->#{name} & #{mask}u;"
            else
              "uint in_#{name} = io->#{name};"
            end
          end

          input_writeback_lines = input_layout.filter_map do |entry|
            name = entry.fetch(:name)
            next if constant_input_literals.key?(name)

            width = entry.fetch(:width)
            mask = mask_expr.call(width)
            if mask
              "io->#{name} = in_#{name} & #{mask}u;"
            else
              "io->#{name} = in_#{name};"
            end
          end

          clk_field = sanitize_ident('clk')
          inst_data_field = sanitize_ident('inst_data')
          data_rdata_field = sanitize_ident('data_rdata')
          inst_ptw_pte0_field = sanitize_ident('inst_ptw_pte0')
          inst_ptw_pte1_field = sanitize_ident('inst_ptw_pte1')
          data_ptw_pte0_field = sanitize_ident('data_ptw_pte0')
          data_ptw_pte1_field = sanitize_ident('data_ptw_pte1')

          required_input_names = [
            clk_field,
            inst_data_field,
            data_rdata_field,
            inst_ptw_pte0_field,
            inst_ptw_pte1_field,
            data_ptw_pte0_field,
            data_ptw_pte1_field
          ]
          missing = required_input_names.reject { |name| input_by_name.key?(name) }
          unless missing.empty?
            raise LoweringError, "RISC-V kernel emission missing expected inputs: #{missing.join(', ')}"
          end

          eval_input_args = input_layout.map do |entry|
            name = entry.fetch(:name)
            if constant_input_literals.key?(name)
              constant_input_literals.fetch(name)
            else
              "in_#{name}"
            end
          end.join(', ')

          low_eval_args = if has_cold_memory
            "#{eval_input_args}, state_slots, cold_state_slots"
          else
            "#{eval_input_args}, state_slots"
          end
          high_eval_args = low_eval_args
          full_eval_args = low_eval_args
          ptw_zero_loop_invariant_lines = [
            "in_#{inst_ptw_pte0_field} = 0u;",
            "in_#{inst_ptw_pte1_field} = 0u;",
            "in_#{data_ptw_pte0_field} = 0u;",
            "in_#{data_ptw_pte1_field} = 0u;"
          ]

          if fast_path
            return <<~MSL
              kernel void #{metal_entry}(
                device #{scalar_msl_type}* all_state_slots [[buffer(0)]],
                device uchar* all_inst_mem [[buffer(1)]],
                device uchar* all_data_mem [[buffer(2)]],
                device RhdlArcGpuIo* all_io [[buffer(3)]],
                uint tid [[thread_position_in_grid]]) {
                device RhdlArcGpuIo* io = all_io + tid;
                uint mem_mask = io->mem_mask;
                uint mem_span = mem_mask + 1u;
                device #{scalar_msl_type}* global_state_slots = all_state_slots + (tid * #{state_slot_count}u);
                uint budget = io->cycle_budget;
                thread #{scalar_msl_type} local_state[#{state_slot_count}];
              #{indent_lines(state_init_lines)}
                thread #{scalar_msl_type}* state_slots = local_state;
              #{indent_lines(has_cold_memory ? ["device #{scalar_msl_type}* cold_state_slots = global_state_slots;"] : [])}
                // RISC-V Metal runner uses unified instruction/data memory.
                (void)all_inst_mem;
                device uchar* mem = all_data_mem + (tid * mem_span);

                io->cycles_ran = 0u;
                uint local_cycles_ran = 0u;
              #{indent_lines(input_local_lines)}

                if (budget == 0u) {
                  #{out_struct} out = #{full_eval_fn}(#{full_eval_args});
                  #{write_fn}(io, out);
                  for (uint si = 0u; si < #{state_slot_count}u; ++si) {
                    global_state_slots[si] = state_slots[si];
                  }
              #{indent_lines(input_writeback_lines)}
                  return;
                }

              #{indent_lines(ptw_zero_loop_invariant_lines)}
                for (uint i = 0u; i < budget; ++i) {
                  in_#{clk_field} = 0u;
                  #{low_loop_step_struct} low0 = #{low_eval_fn}(#{low_eval_args});
              #{indent_lines([low_clock_reset_block].compact)}

                  in_#{inst_data_field} = rhdl_read_word_le(mem, mem_mask, low0.inst_addr & mem_mask);

              #{indent_lines(
                if split_low_data_addr_eval
                  [
                    'uint low_data_addr = 0u;',
                    'if (((low0.data_re | low0.data_we) & 1u) != 0u) {',
                    "  #{low_data_addr_step_struct} low_addr = #{low_data_addr_eval_fn}(#{low_eval_args});",
                    '  low_data_addr = low_addr.data_addr & mem_mask;',
                    '}'
                  ]
                else
                  ['uint low_data_addr = low0.data_addr & mem_mask;']
                end
              )}
                  uint low_data_rdata = ((low0.data_re & 1u) != 0u) ? rhdl_read_word_le(mem, mem_mask, low_data_addr) : 0u;
                  in_#{data_rdata_field} = low_data_rdata;

                  in_#{clk_field} = 1u;
              #{indent_lines(
                if split_low_wdata_eval
                  [
                    'if ((low0.data_we & 1u) != 0u) {',
                    "  #{low_wdata_step_struct} loww = #{low_wdata_eval_fn}(#{low_eval_args});",
                    '  rhdl_write_word_le(mem, mem_mask, low_data_addr, loww.data_wdata);',
                    '}'
                  ]
                else
                  [
                    'if ((low0.data_we & 1u) != 0u) {',
                    '  rhdl_write_word_le(mem, mem_mask, low_data_addr, low0.data_wdata);',
                    '}'
                  ]
                end
              )}
                  #{high_loop_step_struct} high = #{high_eval_fn}(#{high_eval_args});

                  in_#{clk_field} = 0u;
                  in_#{inst_data_field} = rhdl_read_word_le(mem, mem_mask, high.inst_addr & mem_mask);
              #{indent_lines(
                if split_high_data_addr_eval
                  [
                    'uint post_data_rdata = 0u;',
                    'if ((high.data_re & 1u) != 0u) {',
                    "  #{high_data_addr_step_struct} high_addr = #{high_data_addr_eval_fn}(#{high_eval_args});",
                    '  uint post_data_addr = high_addr.data_addr & mem_mask;',
                    '  post_data_rdata = rhdl_read_word_le(mem, mem_mask, post_data_addr);',
                    '}'
                  ]
                else
                  [
                    'uint post_data_addr = high.data_addr & mem_mask;',
                    'uint post_data_rdata = ((high.data_re & 1u) != 0u) ? rhdl_read_word_le(mem, mem_mask, post_data_addr) : 0u;'
                  ]
                end
              )}
                  in_#{data_rdata_field} = post_data_rdata;
                  local_cycles_ran = i + 1u;
              #{indent_lines(
                if dirty_settle_enabled
                  [
                    "if ((high.state_dirty & 1u) == 0u && (low0.data_we & 1u) == 0u) {",
                    '  local_cycles_ran = budget;',
                    '  break;',
                    '}'
                  ]
                else
                  []
                end
              )}
                }

                io->cycles_ran = local_cycles_ran;
                if (local_cycles_ran == 0u) {
                  in_#{clk_field} = 0u;
                  #{out_struct} out = #{full_eval_fn}(#{full_eval_args});
                  #{write_fn}(io, out);
                }
              #{indent_lines(state_copy_back_lines)}

              #{indent_lines(input_writeback_lines)}
              }
            MSL
          end

          <<~MSL
            kernel void #{metal_entry}(
              device #{scalar_msl_type}* all_state_slots [[buffer(0)]],
              device uchar* all_inst_mem [[buffer(1)]],
              device uchar* all_data_mem [[buffer(2)]],
              device RhdlArcGpuIo* all_io [[buffer(3)]],
              uint tid [[thread_position_in_grid]]) {
              device RhdlArcGpuIo* io = all_io + tid;
              uint mem_mask = io->mem_mask;
              uint mem_span = mem_mask + 1u;
              device #{scalar_msl_type}* global_state_slots = all_state_slots + (tid * #{state_slot_count}u);
              uint budget = io->cycle_budget;
              thread #{scalar_msl_type} local_state[#{state_slot_count}];
            #{indent_lines(state_init_lines)}
              thread #{scalar_msl_type}* state_slots = local_state;
            #{indent_lines(has_cold_memory ? ["device #{scalar_msl_type}* cold_state_slots = global_state_slots;"] : [])}
              // RISC-V Metal runner uses unified instruction/data memory.
              (void)all_inst_mem;
              device uchar* mem = all_data_mem + (tid * mem_span);

              io->cycles_ran = 0u;
              uint local_cycles_ran = 0u;
            #{indent_lines(input_local_lines)}
              uint inst_ptw_addr0_cached = 0u;
              uint inst_ptw_addr1_cached = 0u;
              uint data_ptw_addr0_cached = 0u;
              uint data_ptw_addr1_cached = 0u;
              uint inst_ptw_pte0_cached = 0u;
              uint inst_ptw_pte1_cached = 0u;
              uint data_ptw_pte0_cached = 0u;
              uint data_ptw_pte1_cached = 0u;
              bool inst_ptw_addr0_valid = false;
              bool inst_ptw_addr1_valid = false;
              bool data_ptw_addr0_valid = false;
              bool data_ptw_addr1_valid = false;

              if (budget == 0u) {
                #{out_struct} out = #{full_eval_fn}(#{full_eval_args});
                #{write_fn}(io, out);
                for (uint si = 0u; si < #{state_slot_count}u; ++si) {
                  global_state_slots[si] = state_slots[si];
                }
            #{indent_lines(input_writeback_lines)}
                return;
              }

              for (uint i = 0u; i < budget; ++i) {
                in_#{clk_field} = 0u;
                #{low_loop_step_struct} low0 = #{low_eval_fn}(#{low_eval_args});
            #{indent_lines([low_clock_reset_block].compact)}

                in_#{inst_data_field} = rhdl_read_word_le(mem, mem_mask, low0.inst_addr & mem_mask);
                uint low_inst_ptw_addr0 = low0.inst_ptw_addr0 & mem_mask;
                uint low_inst_ptw_addr1 = low0.inst_ptw_addr1 & mem_mask;
                uint low_data_ptw_addr0 = low0.data_ptw_addr0 & mem_mask;
                uint low_data_ptw_addr1 = low0.data_ptw_addr1 & mem_mask;
                uint low_inst_ptw_word0 = low_inst_ptw_addr0 & ~0x3u;
                uint low_inst_ptw_word1 = low_inst_ptw_addr1 & ~0x3u;
                uint low_data_ptw_word0 = low_data_ptw_addr0 & ~0x3u;
                uint low_data_ptw_word1 = low_data_ptw_addr1 & ~0x3u;
                if (!inst_ptw_addr0_valid || inst_ptw_addr0_cached != low_inst_ptw_word0) {
                  inst_ptw_addr0_cached = low_inst_ptw_word0;
                  inst_ptw_pte0_cached = rhdl_read_word_le(mem, mem_mask, low_inst_ptw_addr0);
                  inst_ptw_addr0_valid = true;
                }
                if (!inst_ptw_addr1_valid || inst_ptw_addr1_cached != low_inst_ptw_word1) {
                  inst_ptw_addr1_cached = low_inst_ptw_word1;
                  inst_ptw_pte1_cached = rhdl_read_word_le(mem, mem_mask, low_inst_ptw_addr1);
                  inst_ptw_addr1_valid = true;
                }
                if (!data_ptw_addr0_valid || data_ptw_addr0_cached != low_data_ptw_word0) {
                  data_ptw_addr0_cached = low_data_ptw_word0;
                  data_ptw_pte0_cached = rhdl_read_word_le(mem, mem_mask, low_data_ptw_addr0);
                  data_ptw_addr0_valid = true;
                }
                if (!data_ptw_addr1_valid || data_ptw_addr1_cached != low_data_ptw_word1) {
                  data_ptw_addr1_cached = low_data_ptw_word1;
                  data_ptw_pte1_cached = rhdl_read_word_le(mem, mem_mask, low_data_ptw_addr1);
                  data_ptw_addr1_valid = true;
                }
                in_#{inst_ptw_pte0_field} = inst_ptw_pte0_cached;
                in_#{inst_ptw_pte1_field} = inst_ptw_pte1_cached;
                in_#{data_ptw_pte0_field} = data_ptw_pte0_cached;
                in_#{data_ptw_pte1_field} = data_ptw_pte1_cached;

                uint low_data_addr = low0.data_addr & mem_mask;
                uint low_data_funct3 = low0.data_funct3 & 0x7u;
                uint low_data_rdata = 0u;
                if ((low0.data_re & 1u) != 0u) {
                  if (low_data_funct3 == 2u) {
                    low_data_rdata = rhdl_read_word_le(mem, mem_mask, low_data_addr);
                  } else {
                    low_data_rdata = rhdl_read_mem_funct3(mem, mem_mask, low_data_addr, low_data_funct3);
                  }
                }
                in_#{data_rdata_field} = low_data_rdata;

                in_#{clk_field} = 1u;
                if ((low0.data_we & 1u) != 0u) {
                  if (low_data_funct3 == 2u) {
                    uint low_word_addr = low_data_addr & mem_mask;
                    uint low_wdata = low0.data_wdata;
                    rhdl_write_word_le(mem, mem_mask, low_word_addr, low_wdata);
                  } else {
                    rhdl_write_mem_funct3(mem, mem_mask, low_data_addr, low0.data_wdata, low_data_funct3);
                  }
                  uint low_write_word = low_data_addr & ~0x3u;
                  if (inst_ptw_addr0_valid && inst_ptw_addr0_cached == low_write_word) {
                    inst_ptw_addr0_valid = false;
                  }
                  if (inst_ptw_addr1_valid && inst_ptw_addr1_cached == low_write_word) {
                    inst_ptw_addr1_valid = false;
                  }
                  if (data_ptw_addr0_valid && data_ptw_addr0_cached == low_write_word) {
                    data_ptw_addr0_valid = false;
                  }
                  if (data_ptw_addr1_valid && data_ptw_addr1_cached == low_write_word) {
                    data_ptw_addr1_valid = false;
                  }
                }
                #{high_loop_step_struct} high = #{high_eval_fn}(#{high_eval_args});

                in_#{clk_field} = 0u;
                in_#{inst_data_field} = rhdl_read_word_le(mem, mem_mask, high.inst_addr & mem_mask);
                uint high_inst_ptw_addr0 = high.inst_ptw_addr0 & mem_mask;
                uint high_inst_ptw_addr1 = high.inst_ptw_addr1 & mem_mask;
                uint high_data_ptw_addr0 = high.data_ptw_addr0 & mem_mask;
                uint high_data_ptw_addr1 = high.data_ptw_addr1 & mem_mask;
                uint high_inst_ptw_word0 = high_inst_ptw_addr0 & ~0x3u;
                uint high_inst_ptw_word1 = high_inst_ptw_addr1 & ~0x3u;
                uint high_data_ptw_word0 = high_data_ptw_addr0 & ~0x3u;
                uint high_data_ptw_word1 = high_data_ptw_addr1 & ~0x3u;
                if (!inst_ptw_addr0_valid || inst_ptw_addr0_cached != high_inst_ptw_word0) {
                  inst_ptw_addr0_cached = high_inst_ptw_word0;
                  inst_ptw_pte0_cached = rhdl_read_word_le(mem, mem_mask, high_inst_ptw_addr0);
                  inst_ptw_addr0_valid = true;
                }
                if (!inst_ptw_addr1_valid || inst_ptw_addr1_cached != high_inst_ptw_word1) {
                  inst_ptw_addr1_cached = high_inst_ptw_word1;
                  inst_ptw_pte1_cached = rhdl_read_word_le(mem, mem_mask, high_inst_ptw_addr1);
                  inst_ptw_addr1_valid = true;
                }
                if (!data_ptw_addr0_valid || data_ptw_addr0_cached != high_data_ptw_word0) {
                  data_ptw_addr0_cached = high_data_ptw_word0;
                  data_ptw_pte0_cached = rhdl_read_word_le(mem, mem_mask, high_data_ptw_addr0);
                  data_ptw_addr0_valid = true;
                }
                if (!data_ptw_addr1_valid || data_ptw_addr1_cached != high_data_ptw_word1) {
                  data_ptw_addr1_cached = high_data_ptw_word1;
                  data_ptw_pte1_cached = rhdl_read_word_le(mem, mem_mask, high_data_ptw_addr1);
                  data_ptw_addr1_valid = true;
                }
                in_#{inst_ptw_pte0_field} = inst_ptw_pte0_cached;
                in_#{inst_ptw_pte1_field} = inst_ptw_pte1_cached;
                in_#{data_ptw_pte0_field} = data_ptw_pte0_cached;
                in_#{data_ptw_pte1_field} = data_ptw_pte1_cached;

                uint post_data_addr = high.data_addr & mem_mask;
                uint post_data_funct3 = high.data_funct3 & 0x7u;
                uint post_data_rdata = 0u;
                if ((high.data_re & 1u) != 0u) {
                  if (post_data_funct3 == 2u) {
                    post_data_rdata = rhdl_read_word_le(mem, mem_mask, post_data_addr);
                  } else {
                    post_data_rdata = rhdl_read_mem_funct3(mem, mem_mask, post_data_addr, post_data_funct3);
                  }
                }
                in_#{data_rdata_field} = post_data_rdata;
                local_cycles_ran = i + 1u;
              }

              io->cycles_ran = local_cycles_ran;
              if (local_cycles_ran == 0u) {
                in_#{clk_field} = 0u;
                #{out_struct} out = #{full_eval_fn}(#{full_eval_args});
                #{write_fn}(io, out);
              }
            #{indent_lines(state_copy_back_lines)}

            #{indent_lines(input_writeback_lines)}
            }
          MSL
        end

        def emit_kernel_apple2(top:, metal_entry:, state_layout:, low_eval_fn:, comb_eval_fn:, update_eval_fn:, phase_split_enabled:, dirty_settle_enabled:, full_eval_fn:)
          out_struct = top_output_struct_name(top.fetch(:name))
          write_fn = "write_#{sanitize_ident(top.fetch(:name))}_outputs"
          loop_step_struct = "#{sanitize_ident(top.fetch(:name))}_loop_step"

          input_names = top.fetch(:inputs).map { |input| sanitize_ident(input.fetch(:name)) }
          clock_field = sanitize_ident('clk_14m')
          ram_do_field = sanitize_ident('ram_do')
          speaker_field = sanitize_ident('speaker')
          clock_slots = count_clock_tracking_slots(top.fetch(:ops))
          state_slot_count = state_layout.sum { |entry| entry.fetch(:slot_count, 1) } + clock_slots
          input_locals = input_names.map do |name|
            case name
            when clock_field
              "uint in_#{name} = io->#{name} & 1u;"
            when ram_do_field
              "uint in_#{name} = io->#{name} & 0xFFu;"
            else
              "uint in_#{name} = io->#{name};"
            end
          end
          input_args = input_names.map { |name| "in_#{name}" }.join(', ')

          <<~MSL
            kernel void #{metal_entry}(
              device #{scalar_msl_type}* all_state_slots [[buffer(0)]],
              device uchar* all_ram [[buffer(1)]],
              device uchar* all_rom [[buffer(2)]],
              device RhdlArcGpuIo* all_io [[buffer(3)]],
              uint tid [[thread_position_in_grid]]) {
              device #{scalar_msl_type}* state_slots = all_state_slots + (tid * #{state_slot_count}u);
              device uchar* ram = all_ram + (tid * 65536u);
              device uchar* rom = all_rom + (tid * 12288u);
              device RhdlArcGpuIo* io = all_io + tid;
              (void)rom;

              uint budget = io->cycle_budget;
              uint local_cycles_ran = 0u;
              uint local_speaker_toggles = 0u;
              uint local_text_dirty = 0u;
              uint local_prev_speaker = io->prev_speaker & 1u;
            #{indent_lines(input_locals)}
              uint local_last_clock = in_#{clock_field} & 1u;
              thread #{scalar_msl_type} local_state[#{state_slot_count}];
              for (uint si = 0u; si < #{state_slot_count}u; ++si) {
                local_state[si] = state_slots[si];
              }

              if (budget == 0u) {
                uint clk_now = in_#{clock_field} & 1u;
                in_#{clock_field} = clk_now;
                local_last_clock = clk_now;
                #{out_struct} out = #{full_eval_fn}(#{input_args}, local_state);
                #{write_fn}(io, out);
                io->cycles_ran = local_cycles_ran;
                io->speaker_toggles = local_speaker_toggles;
                io->text_dirty = local_text_dirty;
                io->prev_speaker = local_prev_speaker;
                io->#{clock_field} = in_#{clock_field};
                io->#{ram_do_field} = in_#{ram_do_field};
                io->last_clock = local_last_clock;
                for (uint si = 0u; si < #{state_slot_count}u; ++si) {
                  state_slots[si] = local_state[si];
                }
                return;
              }

              for (uint i = 0u; i < budget; ++i) {
                in_#{clock_field} = 0u;
                local_last_clock = in_#{clock_field};
                #{loop_step_struct} low = #{low_eval_fn}(#{input_args}, local_state);

                uint addr = low.ram_addr & 0xFFFFu;
                uint ram_value = uint(ram[addr]);
                in_#{ram_do_field} = ram_value & 0xFFu;

                in_#{clock_field} = 1u;
                local_last_clock = in_#{clock_field};
                #{loop_step_struct} high = #{update_eval_fn}(#{input_args}, local_state);
                #{loop_step_struct} step = high;
            #{if phase_split_enabled && dirty_settle_enabled
              "    if ((high.state_dirty & 1u) != 0u) {\n      step = #{comb_eval_fn}(#{input_args}, local_state);\n    }"
            elsif phase_split_enabled
              ''
            else
              ''
            end}

                uint write_addr = step.ram_addr & 0xFFFFu;
                if ((step.ram_we & 1u) != 0u && write_addr < 0xC000u) {
                  ram[write_addr] = uchar(step.d & 0xFFu);
                  if ((write_addr >= 0x0400u && write_addr <= 0x07FFu) ||
                      (write_addr >= 0x2000u && write_addr <= 0x5FFFu)) {
                    local_text_dirty = 1u;
                  }
                }

                uint speaker_now = step.#{speaker_field} & 1u;
                if (speaker_now != local_prev_speaker) {
                  local_speaker_toggles = local_speaker_toggles + 1u;
                  local_prev_speaker = speaker_now;
                }

                local_cycles_ran = i + 1u;
              }

              #{out_struct} final_out = #{full_eval_fn}(#{input_args}, local_state);
              #{write_fn}(io, final_out);
              io->cycles_ran = local_cycles_ran;
              io->speaker_toggles = local_speaker_toggles;
              io->text_dirty = local_text_dirty;
              io->prev_speaker = local_prev_speaker;
              io->#{clock_field} = in_#{clock_field};
              io->#{ram_do_field} = in_#{ram_do_field};
              io->last_clock = local_last_clock;
              for (uint si = 0u; si < #{state_slot_count}u; ++si) {
                state_slots[si] = local_state[si];
              }
            }
          MSL
        end

        def riscv_kernel_constant_inputs(input_layout)
          return {} unless ENV['RHDL_ARC_TO_GPU_RISCV_CORE_SPECIALIZE'] == '1'

          defaults = {
            sanitize_ident('irq_software') => 0,
            sanitize_ident('irq_timer') => 0,
            sanitize_ident('irq_external') => 0
          }
          available = input_layout.map { |entry| entry.fetch(:name) }.to_set
          defaults.select { |name, _value| available.include?(name) }
        end

        def generate_state_read_lines(op, state_layout)
          ref = op.fetch(:result_refs).first
          out_type = op.fetch(:result_types).first
          slot = state_layout.find { |entry| entry.fetch(:result_ref) == ref }
          raise LoweringError, "Missing state slot for #{ref}" unless slot

          slot_index = slot.fetch(:index)
          width = out_type.fetch(:width)

          ["#{scalar_msl_type} #{ref_var_name(ref)} = rhdl_mask_bits(state_slots[#{slot_index}], #{width}u);"]
        end

        def generate_state_update_lines(op, type_map, functions, state_layout)
          ref = op.fetch(:result_refs).first
          out_type = op.fetch(:result_types).first
          slot = state_layout.find { |entry| entry.fetch(:result_ref) == ref }
          raise LoweringError, "Missing state slot for #{ref}" unless slot

          slot_index = slot.fetch(:index)
          lines = []

          call_expr = generate_call_expr(
            callee: op.fetch(:callee),
            args: op.fetch(:args),
            result_types: [out_type],
            type_map: type_map,
            functions: functions,
            temp_prefix: "state_#{slot_index}_next"
          )

          lines.concat(call_expr.fetch(:setup_lines))
          next_value_expr = call_expr.fetch(:result_exprs).first

          clock_cond = "(#{masked_expr(ref_var_name(op.fetch(:clock_ref)), TypeRef.new(kind: :scalar, width: 1))} != 0u)"
          enable_cond = if op.fetch(:enable_ref)
            "(#{masked_expr(ref_var_name(op.fetch(:enable_ref)), TypeRef.new(kind: :scalar, width: 1))} != 0u)"
          else
            'true'
          end

          lines << "if (#{clock_cond}) {"
          if op.fetch(:reset_ref)
            reset_cond = "(#{masked_expr(ref_var_name(op.fetch(:reset_ref)), TypeRef.new(kind: :scalar, width: 1))} != 0u)"
            lines << "  if (#{reset_cond}) {"
            lines << "    next_state_#{slot_index} = #{scalar_zero_literal};"
            lines << "  } else if (#{enable_cond}) {"
            lines << "    next_state_#{slot_index} = #{masked_expr(next_value_expr, out_type)};"
            lines << '  }'
          else
            lines << "  if (#{enable_cond}) {"
            lines << "    next_state_#{slot_index} = #{masked_expr(next_value_expr, out_type)};"
            lines << '  }'
          end
          lines << '}'

          lines
        end

        def generate_op_lines(
          op,
          type_map,
          functions,
          in_top_module:,
          state_ref_to_slot: nil,
          cold_memory_bases: nil,
          cold_state_slots_var: nil
        )
          cold_memory_bases ||= Set.new
          kind = op.fetch(:kind)

          case kind
          when :constant
            type = op.fetch(:result_types).first
            var = ref_var_name(op.fetch(:result_refs).first)
            literal = constant_literal(op.fetch(:value), type)
            ["#{metal_type_for(type)} #{var} = #{literal};"]
          when :to_clock
            out = ref_var_name(op.fetch(:result_refs).first)
            inp = ref_var_name(op.fetch(:input))
            ["#{metal_type_for(TypeRef.new(kind: :scalar, width: 1))} #{out} = #{masked_expr(inp, TypeRef.new(kind: :scalar, width: 1))};"]
          when :arc_call
            call = generate_call_expr(
              callee: op.fetch(:callee),
              args: op.fetch(:args),
              result_types: op.fetch(:result_types),
              type_map: type_map,
              functions: functions,
              temp_prefix: ref_var_name(op.fetch(:result_refs).first)
            )
            lines = []
            lines.concat(call.fetch(:setup_lines))
            op.fetch(:result_refs).each_with_index do |ref, idx|
              type = op.fetch(:result_types)[idx]
              lines << "#{metal_type_for(type)} #{ref_var_name(ref)} = #{masked_expr(call.fetch(:result_exprs)[idx], type)};"
            end
            lines
          when :arc_memory
            if in_top_module
              []
            else
              raise LoweringError, 'arc.memory unsupported in arc.define body'
            end
          when :arc_memory_read_port
            raise LoweringError, 'arc.memory_read_port requires top-module state layout context' if state_ref_to_slot.nil?

            emit_memory_read_port_lines(
              op,
              type_map,
              state_ref_to_slot: state_ref_to_slot,
              cold_memory_bases: cold_memory_bases,
              cold_state_slots_var: cold_state_slots_var
            )
          when :arc_memory_write_port
            if in_top_module
              raise LoweringError, 'arc.memory_write_port must be handled in top module generation path'
            end
            raise LoweringError, 'arc.memory_write_port unsupported in arc.define body'
          when :seq_memory_write_port
            if in_top_module
              raise LoweringError, 'seq.firmem.write_port must be handled in top module generation path'
            end
            raise LoweringError, 'seq.firmem.write_port unsupported in arc.define body'
          when :comb
            emit_comb_lines(op, type_map)
          when :synth_aig_and_inv
            emit_synth_aig_and_inv_lines(op, type_map)
          when :mux
            emit_mux_lines(op, type_map)
          when :icmp
            emit_icmp_lines(op, type_map)
          when :concat
            emit_concat_lines(op, type_map)
          when :extract
            emit_extract_lines(op, type_map)
          when :replicate
            emit_replicate_lines(op, type_map)
          when :array_create
            emit_array_create_lines(op, type_map)
          when :aggregate_constant
            emit_aggregate_constant_lines(op)
          when :array_get
            emit_array_get_lines(op, type_map)
          when :alias
            out = ref_var_name(op.fetch(:result_refs).first)
            out_type = op.fetch(:result_types).first
            src_expr = masked_expr(ref_var_name(op.fetch(:source_ref)), out_type)
            ["#{metal_type_for(out_type)} #{out} = #{masked_expr(src_expr, out_type)};"]
          when :arc_state
            if in_top_module
              raise LoweringError, 'arc.state must be handled in top module generation path'
            end
            raise LoweringError, 'arc.state unsupported in arc.define body'
          when :seq_firreg
            if in_top_module
              raise LoweringError, 'seq.firreg must be handled in top module generation path'
            end
            raise LoweringError, 'seq.firreg unsupported in arc.define body'
          else
            raise LoweringError, "Unsupported op kind in codegen: #{kind}"
          end
        end

        def emit_aggregate_constant_lines(op)
          out = ref_var_name(op.fetch(:result_refs).first)
          arr_type = op.fetch(:result_types).first
          arr_struct = array_struct_name(arr_type)
          elem_type = arr_type.fetch(:element)
          values = op.fetch(:values)

          ordered_values = values.reverse
          literal_values = ordered_values.map { |value| constant_literal(value, elem_type) }
          ["#{arr_struct} #{out} = { {#{literal_values.join(', ')}} };"]
        end

        def emit_comb_lines(op, type_map)
          comb_op = op.fetch(:comb_op)
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          operand_refs = op.fetch(:operands)
          operand_types = operand_refs.map { |ref| type_map.fetch(ref) }
          operands = operand_refs.map { |ref| masked_expr(ref_var_name(ref), type_map.fetch(ref)) }

          if wide_scalar?(out_type) || operand_types.any? { |t| wide_scalar?(t) }
            wide_operands = operand_refs.zip(operand_types).map do |ref, ref_type|
              ref_expr = masked_expr(ref_var_name(ref), ref_type)
              wide_scalar?(ref_type) ? "(#{ref_expr})" : "rhdl_wide_make(#{ref_expr}, 0u)"
            end
            shift_expr =
              if operand_types.length >= 2
                raw = if wide_scalar?(operand_types[1])
                  "(#{masked_expr(ref_var_name(operand_refs[1]), operand_types[1])}).x"
                else
                  masked_expr(ref_var_name(operand_refs[1]), operand_types[1])
                end
                "(#{raw} & 63u)"
              else
                '0u'
              end

            wide_expr = case comb_op
            when 'add'
              wide_operands.reduce { |lhs, rhs| "rhdl_wide_add(#{lhs}, #{rhs})" }
            when 'sub'
              wide_operands[1..].reduce(wide_operands[0]) { |lhs, rhs| "rhdl_wide_sub(#{lhs}, #{rhs})" }
            when 'mul'
              wide_operands[1..].reduce(wide_operands[0]) { |lhs, rhs| "rhdl_wide_mul(#{lhs}, #{rhs})" }
            when 'divu'
              lhs = wide_operands[0]
              rhs = wide_operands[1]
              "(rhdl_wide_to_ulong(#{rhs}) == 0ul ? rhdl_wide_make(0u, 0u) : rhdl_wide_from_ulong(rhdl_wide_to_ulong(#{lhs}) / rhdl_wide_to_ulong(#{rhs})))"
            when 'modu'
              lhs = wide_operands[0]
              rhs = wide_operands[1]
              "(rhdl_wide_to_ulong(#{rhs}) == 0ul ? rhdl_wide_make(0u, 0u) : rhdl_wide_from_ulong(rhdl_wide_to_ulong(#{lhs}) % rhdl_wide_to_ulong(#{rhs})))"
            when 'shl'
              "rhdl_wide_shlu(#{wide_operands[0]}, #{shift_expr})"
            when 'shru'
              "rhdl_wide_shru(#{wide_operands[0]}, #{shift_expr})"
            when 'xor'
              wide_operands.reduce { |lhs, rhs| "rhdl_wide_xor(#{lhs}, #{rhs})" }
            when 'or'
              wide_operands.reduce { |lhs, rhs| "rhdl_wide_or(#{lhs}, #{rhs})" }
            when 'and'
              wide_operands.reduce { |lhs, rhs| "rhdl_wide_and(#{lhs}, #{rhs})" }
            else
              raise LoweringError, "ArcToGPU lowering does not support wide comb.#{comb_op} in packed mode"
            end

            if wide_scalar?(out_type)
              return ["#{metal_type_for(out_type)} #{out} = #{masked_expr(wide_expr, out_type)};"]
            end

            return ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{wide_expr}).x", out_type)};"]
          end

          expr = case comb_op
          when 'add'
            "#{operands[0]} + #{operands[1]}"
          when 'sub'
            "#{operands[0]} - #{operands[1]}"
          when 'mul'
            "#{operands[0]} * #{operands[1]}"
          when 'divu'
            "(#{operands[1]} == #{scalar_zero_literal} ? #{scalar_zero_literal} : (#{operands[0]} / #{operands[1]}))"
          when 'modu'
            "(#{operands[1]} == #{scalar_zero_literal} ? #{scalar_zero_literal} : (#{operands[0]} % #{operands[1]}))"
          when 'shl'
            "(#{operands[0]} << (#{operands[1]} & #{scalar_width_bits - 1}u))"
          when 'shru'
            "(#{operands[0]} >> (#{operands[1]} & #{scalar_width_bits - 1}u))"
          when 'xor'
            operands.join(' ^ ')
          when 'or'
            operands.join(' | ')
          when 'and'
            operands.join(' & ')
          else
            raise LoweringError, "Unsupported comb op: #{comb_op}"
          end

          ["#{metal_type_for(out_type)} #{out} = #{masked_expr(expr, out_type)};"]
        end

        def emit_synth_aig_and_inv_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          operand_refs = op.fetch(:operands)
          invert_flags = op.fetch(:invert_flags)
          operand_types = operand_refs.map { |ref| type_map.fetch(ref) }

          raise LoweringError, 'synth.aig.and_inv requires at least one operand' if operand_refs.empty?

          if wide_scalar?(out_type) || operand_types.any? { |t| wide_scalar?(t) }
            wide_terms = operand_refs.each_with_index.map do |ref, idx|
              ref_type = operand_types[idx]
              expr = masked_expr(ref_var_name(ref), ref_type)
              wide_expr = wide_scalar?(ref_type) ? "(#{expr})" : "rhdl_wide_make(#{expr}, 0u)"
              if invert_flags[idx]
                "rhdl_wide_xor(#{wide_expr}, rhdl_wide_make(0xFFFFFFFFu, 0xFFFFFFFFu))"
              else
                wide_expr
              end
            end
            wide_expr = wide_terms[1..].reduce(wide_terms[0]) { |lhs, rhs| "rhdl_wide_and(#{lhs}, #{rhs})" }

            if wide_scalar?(out_type)
              return ["#{metal_type_for(out_type)} #{out} = #{masked_expr(wide_expr, out_type)};"]
            end

            return ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{wide_expr}).x", out_type)};"]
          end

          terms = operand_refs.each_with_index.map do |ref, idx|
            expr = masked_expr(ref_var_name(ref), operand_types[idx])
            invert_flags[idx] ? "(~(#{expr}))" : "(#{expr})"
          end
          expr = terms.join(' & ')
          ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{expr})", out_type)};"]
        end

        def emit_mux_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          cond_ref, true_ref, false_ref = op.fetch(:operands)
          cond_expr = truthy_expr(ref: cond_ref, type_map: type_map)
          true_expr = masked_expr(ref_var_name(true_ref), type_map.fetch(true_ref))
          false_expr = masked_expr(ref_var_name(false_ref), type_map.fetch(false_ref))

          if wide_scalar?(out_type)
            lines = []
            lines << "#{metal_type_for(out_type)} #{out};"
            lines << "if (#{cond_expr}) {"
            lines << "  #{out} = #{masked_expr(true_expr, out_type)};"
            lines << '} else {'
            lines << "  #{out} = #{masked_expr(false_expr, out_type)};"
            lines << '}'
            lines << "#{out} = #{masked_expr(out, out_type)};"
            lines
          else
            ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{cond_expr} ? #{true_expr} : #{false_expr})", out_type)};"]
          end
        end

        def emit_icmp_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          lhs_ref, rhs_ref = op.fetch(:operands)
          lhs_expr = masked_expr(ref_var_name(lhs_ref), type_map.fetch(lhs_ref))
          rhs_expr = masked_expr(ref_var_name(rhs_ref), type_map.fetch(rhs_ref))
          predicate = op.fetch(:predicate)

          cmp_expr =
            if wide_scalar?(type_map.fetch(lhs_ref)) || wide_scalar?(type_map.fetch(rhs_ref))
              unless wide_scalar?(type_map.fetch(lhs_ref)) && wide_scalar?(type_map.fetch(rhs_ref))
                raise LoweringError, 'ArcToGPU lowering cannot compare mixed-width packed/non-packed values'
              end

              case predicate
              when 'eq'
                "rhdl_wide_eq(#{lhs_expr}, #{rhs_expr})"
              when 'ne'
                "!rhdl_wide_eq(#{lhs_expr}, #{rhs_expr})"
              when 'ult'
                "(rhdl_wide_to_ulong(#{lhs_expr}) < rhdl_wide_to_ulong(#{rhs_expr}))"
              when 'ule'
                "(rhdl_wide_to_ulong(#{lhs_expr}) <= rhdl_wide_to_ulong(#{rhs_expr}))"
              when 'ugt'
                "(rhdl_wide_to_ulong(#{lhs_expr}) > rhdl_wide_to_ulong(#{rhs_expr}))"
              when 'uge'
                "(rhdl_wide_to_ulong(#{lhs_expr}) >= rhdl_wide_to_ulong(#{rhs_expr}))"
              else
                raise LoweringError, "ArcToGPU lowering does not support comb.icmp predicate #{predicate} for packed wide values"
              end
            else
              case predicate
              when 'eq'
                "(#{lhs_expr} == #{rhs_expr})"
              when 'ne'
                "(#{lhs_expr} != #{rhs_expr})"
              when 'ult'
                "(#{lhs_expr} < #{rhs_expr})"
              when 'ule'
                "(#{lhs_expr} <= #{rhs_expr})"
              when 'ugt'
                "(#{lhs_expr} > #{rhs_expr})"
              when 'uge'
                "(#{lhs_expr} >= #{rhs_expr})"
              when 'slt', 'sle', 'sgt', 'sge'
                lhs_type = type_map.fetch(lhs_ref)
                rhs_type = type_map.fetch(rhs_ref)
                signed_width = [lhs_type.fetch(:width), rhs_type.fetch(:width)].max
                lhs_signed = signed_cast_expr(lhs_expr, signed_width)
                rhs_signed = signed_cast_expr(rhs_expr, signed_width)
                case predicate
                when 'slt'
                  "(#{lhs_signed} < #{rhs_signed})"
                when 'sle'
                  "(#{lhs_signed} <= #{rhs_signed})"
                when 'sgt'
                  "(#{lhs_signed} > #{rhs_signed})"
                else
                  "(#{lhs_signed} >= #{rhs_signed})"
                end
              else
                raise LoweringError, "ArcToGPU lowering does not support comb.icmp predicate #{predicate}"
              end
            end

          ["#{metal_type_for(TypeRef.new(kind: :scalar, width: 1))} #{out} = #{cmp_expr} ? #{scalar_one_literal} : #{scalar_zero_literal};"]
        end

        def emit_concat_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          operands = op.fetch(:operands)
          operand_types = operands.map { |ref| type_map.fetch(ref) }

          if wide_scalar?(out_type) || operand_types.any? { |t| wide_scalar?(t) }
            shift = 0
            accum_expr = 'rhdl_wide_make(0u, 0u)'
            operands.zip(operand_types).reverse_each do |ref, ref_type|
              ref_expr = masked_expr(ref_var_name(ref), ref_type)
              wide_expr =
                if wide_scalar?(ref_type)
                  "(#{ref_expr})"
                else
                  "rhdl_wide_make(#{ref_expr}, 0u)"
                end
              shifted = shift.zero? ? wide_expr : "rhdl_wide_shlu(#{wide_expr}, #{shift}u)"
              accum_expr = "rhdl_wide_or(#{accum_expr}, #{shifted})"
              shift += ref_type.fetch(:width)
            end

            if wide_scalar?(out_type)
              return ["#{metal_type_for(out_type)} #{out} = #{masked_expr(accum_expr, out_type)};"]
            end

            return ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{accum_expr}).x", out_type)};"]
          end

          shift = 0
          parts = []
          operands.zip(operand_types).reverse_each do |ref, ref_type|
            ref_expr = masked_expr(ref_var_name(ref), ref_type)
            part = shift.zero? ? "(#{ref_expr})" : "((#{ref_expr}) << #{shift}u)"
            parts << part
            shift += ref_type.fetch(:width)
          end

          expr = parts.join(' | ')
          ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{expr})", out_type)};"]
        end

        def emit_extract_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          from = op.fetch(:from)
          input_type = type_map.fetch(op.fetch(:input))
          inp = masked_expr(ref_var_name(op.fetch(:input)), input_type)

          if wide_scalar?(input_type)
            if wide_scalar?(out_type)
              expr = "rhdl_wide_shru(#{inp}, #{from}u)"
              ["#{metal_type_for(out_type)} #{out} = #{masked_expr(expr, out_type)};"]
            else
              expr = "rhdl_wide_shru(#{inp}, #{from}u).x"
              ["#{metal_type_for(out_type)} #{out} = #{masked_expr(expr, out_type)};"]
            end
          else
            ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{inp} >> #{from}u)", out_type)};"]
          end
        end

        def emit_replicate_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          inp_type = type_map.fetch(op.fetch(:input))
          inp = masked_expr(ref_var_name(op.fetch(:input)), inp_type)

          src_w = inp_type.fetch(:width)
          dst_w = out_type.fetch(:width)
          if wide_scalar?(out_type) || wide_scalar?(inp_type)
            wide_inp = if wide_scalar?(inp_type)
              "(#{inp})"
            else
              "rhdl_wide_make(#{inp}, 0u)"
            end

            accum_expr = 'rhdl_wide_make(0u, 0u)'
            offset = 0
            while offset < dst_w
              shifted = offset.zero? ? wide_inp : "rhdl_wide_shlu(#{wide_inp}, #{offset}u)"
              accum_expr = "rhdl_wide_or(#{accum_expr}, #{shifted})"
              offset += src_w
            end

            if wide_scalar?(out_type)
              return ["#{metal_type_for(out_type)} #{out} = #{masked_expr(accum_expr, out_type)};"]
            end

            return ["#{metal_type_for(out_type)} #{out} = #{masked_expr("(#{accum_expr}).x", out_type)};"]
          end

          pieces = []
          offset = 0
          while offset < dst_w
            pieces << "(#{inp} << #{offset}u)"
            offset += src_w
          end
          expr = pieces.join(' | ')
          ["#{metal_type_for(out_type)} #{out} = #{masked_expr(expr, out_type)};"]
        end

        def emit_array_create_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          arr_type = op.fetch(:result_types).first
          arr_struct = array_struct_name(arr_type)
          elem_type = arr_type.fetch(:element)

          lines = ["#{arr_struct} #{out};"]
          operands = op.fetch(:operands)
          last_index = operands.length - 1
          operands.each_with_index do |ref, idx|
            # Match CIRCT HW lowering semantics: array_create operand 0 maps to the
            # highest index, and the last operand maps to index 0.
            array_idx = last_index - idx
            expr = masked_expr(ref_var_name(ref), type_map.fetch(ref))
            lines << "#{out}.v[#{array_idx}] = #{masked_expr(expr, elem_type)};"
          end
          lines
        end

        def emit_array_get_lines(op, type_map)
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          arr_type = op.fetch(:array_type)
          idx_type = op.fetch(:index_type)
          arr_ref = ref_var_name(op.fetch(:array_ref))
          idx_ref = masked_expr(ref_var_name(op.fetch(:index_ref)), idx_type)
          len = arr_type.fetch(:length)

          lines = []
          lines << "uint #{out}_idx = #{idx_ref};"
          lines << "if (#{out}_idx >= #{len}u) { #{out}_idx = 0u; }"
          lines << "#{metal_type_for(out_type)} #{out} = #{masked_expr("#{arr_ref}.v[#{out}_idx]", out_type)};"
          lines
        end

        def emit_memory_read_port_lines(
          op,
          type_map,
          state_ref_to_slot:,
          cold_memory_bases: nil,
          cold_state_slots_var: nil
        )
          cold_memory_bases ||= Set.new
          out = ref_var_name(op.fetch(:result_refs).first)
          out_type = op.fetch(:result_types).first
          memory_ref = op.fetch(:memory_ref)
          memory_info = state_ref_to_slot.fetch(memory_ref) do
            raise LoweringError, "Unknown arc.memory reference #{memory_ref} in memory_read_port"
          end
          memory_type = memory_info.fetch(:type)
          idx_expr = masked_expr(ref_var_name(op.fetch(:index_ref)), op.fetch(:index_type))
          base = memory_info.fetch(:index)
          length = memory_type.fetch(:length)
          state_slots_var =
            if cold_state_slots_var && cold_memory_bases.include?(base)
              cold_state_slots_var
            else
              'state_slots'
            end

          expr = if wide_scalar?(out_type)
            "rhdl_read_memory_wide(#{state_slots_var}, #{base}u, #{length}u, #{idx_expr}, #{out_type.fetch(:width)}u)"
          else
            "rhdl_read_memory_scalar(#{state_slots_var}, #{base}u, #{length}u, #{idx_expr}, #{out_type.fetch(:width)}u)"
          end
          ["#{metal_type_for(out_type)} #{out} = #{masked_expr(expr, out_type)};"]
        end

        def generate_call_expr(callee:, args:, result_types:, type_map:, functions:, temp_prefix:, arg_exprs: nil)
          fn = functions[callee]
          raise LoweringError, "ArcToGPU lowering could not resolve callee @#{callee}" unless fn

          fn_name = metal_fn_name(callee)
          arg_exprs ||= args.map do |arg_ref|
            arg_type = type_map.fetch(arg_ref) { raise LoweringError, "Unknown call arg ref #{arg_ref} for @#{callee}" }
            masked_expr(ref_var_name(arg_ref), arg_type)
          end

          if result_types.length == 1
            {
              setup_lines: [],
              result_exprs: ["#{fn_name}(#{arg_exprs.join(', ')})"]
            }
          else
            temp = "#{temp_prefix}_ret"
            struct = ret_struct_name(callee)
            {
              setup_lines: ["#{struct} #{temp} = #{fn_name}(#{arg_exprs.join(', ')});"],
              result_exprs: Array.new(result_types.length) { |idx| "#{temp}.v#{idx}" }
            }
          end
        end

        def schedule_ops_topologically(ops:, lines:, type_map:, available_refs:, functions:, in_top_module:)
          pending = ops.dup
          until pending.empty?
            ready = []
            blocked = []

            pending.each do |op|
              deps = op_dependencies(op)
              missing = deps.reject { |ref| available_refs.include?(ref) }
              if missing.empty?
                ready << op
              else
                blocked << [op, missing]
              end
            end

            if ready.empty?
              op, missing = blocked.first
              raise LoweringError,
                "Could not schedule #{op.fetch(:op_name)}; unresolved refs: #{missing.join(', ')}"
            end

            ready.each do |op|
              lines.concat(generate_op_lines(op, type_map, functions, in_top_module: in_top_module))
              op.fetch(:result_refs).each_with_index do |ref, idx|
                type_map[ref] = op.fetch(:result_types)[idx]
                available_refs << ref
              end
            end

            pending = blocked.map(&:first)
          end
        end

        def emit_ops_with_optional_schedule(
          ops:,
          lines:,
          runtime_type_map:,
          functions:,
          in_top_module:,
          state_ref_to_slot: nil,
          cold_memory_bases: Set.new,
          cold_state_slots_var: nil,
          schedule_aware_emit: false,
          phase_tag: nil
        )
          if schedule_aware_emit
            levels = levelize_sorted_ops(
              sorted_ops: ops,
              initial_refs: runtime_type_map.keys
            )
            lines << "// schedule_phase: #{phase_tag}" if phase_tag
            levels.each_with_index do |level_ops, level_idx|
              lines << "// schedule_level #{level_idx} (ops=#{level_ops.length})"
              level_ops.each do |op|
                lines.concat(
                  generate_op_lines(
                    op,
                    runtime_type_map,
                    functions,
                    in_top_module: in_top_module,
                    state_ref_to_slot: state_ref_to_slot,
                    cold_memory_bases: cold_memory_bases,
                    cold_state_slots_var: cold_state_slots_var
                  )
                )
                op.fetch(:result_refs).each_with_index do |ref, idx|
                  runtime_type_map[ref] = op.fetch(:result_types)[idx]
                end
              end
            end
            return
          end

          ops.each do |op|
            lines.concat(
              generate_op_lines(
                op,
                runtime_type_map,
                functions,
                in_top_module: in_top_module,
                state_ref_to_slot: state_ref_to_slot,
                cold_memory_bases: cold_memory_bases,
                cold_state_slots_var: cold_state_slots_var
              )
            )
            op.fetch(:result_refs).each_with_index do |ref, idx|
              runtime_type_map[ref] = op.fetch(:result_types)[idx]
            end
          end
        end

        def levelize_sorted_ops(sorted_ops:, initial_refs:)
          ref_levels = {}
          initial_refs.each { |ref| ref_levels[ref] = -1 }
          levels = []

          sorted_ops.each do |op|
            deps = op_dependencies(op)
            missing = deps.reject { |ref| ref_levels.key?(ref) }
            unless missing.empty?
              raise LoweringError,
                "Could not levelize #{op.fetch(:op_name)}; unresolved refs: #{missing.join(', ')}"
            end

            base_level = deps.empty? ? -1 : deps.map { |ref| ref_levels.fetch(ref) }.max
            level = base_level + 1
            levels[level] ||= []
            levels[level] << op
            op.fetch(:result_refs).each { |ref| ref_levels[ref] = level }
          end

          levels.compact
        end

        def op_dependencies(op)
          case op.fetch(:kind)
          when :constant
            []
          when :to_clock
            [op.fetch(:input)]
          when :arc_call
            op.fetch(:args)
          when :arc_state
            deps = [op.fetch(:clock_ref)]
            deps.concat(op.fetch(:args))
            deps << op.fetch(:enable_ref) if op.fetch(:enable_ref)
            deps << op.fetch(:reset_ref) if op.fetch(:reset_ref)
            deps
          when :seq_firreg
            deps = [op.fetch(:source_ref), op.fetch(:clock_ref)]
            deps << op.fetch(:reset_ref) if op.fetch(:reset_ref)
            deps << op.fetch(:reset_value_ref) if op.fetch(:reset_value_ref)
            deps
          when :arc_memory
            []
          when :arc_memory_read_port
            [op.fetch(:memory_ref), op.fetch(:index_ref)]
          when :arc_memory_write_port
            deps = [op.fetch(:memory_ref), op.fetch(:clock_ref)]
            deps.concat(op.fetch(:args))
            deps
          when :seq_memory_write_port
            deps = [op.fetch(:memory_ref), op.fetch(:addr_ref), op.fetch(:data_ref), op.fetch(:clock_ref)]
            deps << op.fetch(:enable_ref) if op.fetch(:enable_ref)
            deps
          when :array_create
            op.fetch(:operands)
          when :aggregate_constant
            []
          when :array_get
            [op.fetch(:array_ref), op.fetch(:index_ref)]
          when :alias
            [op.fetch(:source_ref)]
          when :icmp
            op.fetch(:operands)
          when :concat
            op.fetch(:operands)
          when :extract
            [op.fetch(:input)]
          when :replicate
            [op.fetch(:input)]
          when :mux, :comb
            op.fetch(:operands)
          when :synth_aig_and_inv
            op.fetch(:operands)
          else
            []
          end
        end

        def topologically_sorted_ops(ops:, initial_type_map:)
          pending = ops.dup
          available_refs = Set.new(initial_type_map.keys)
          type_map = initial_type_map.dup
          sorted = []

          until pending.empty?
            progress = false
            next_pending = []

            pending.each do |op|
              deps = op_dependencies(op)
              missing = deps.reject { |ref| available_refs.include?(ref) }
              if missing.empty?
                sorted << op
                op.fetch(:result_refs).each_with_index do |ref, idx|
                  type_map[ref] = op.fetch(:result_types)[idx]
                  available_refs << ref
                end
                progress = true
              else
                next_pending << [op, missing]
              end
            end

            unless progress
              op, missing = next_pending.first
              raise LoweringError,
                "Could not schedule #{op.fetch(:op_name)}; unresolved refs: #{missing.join(', ')}"
            end

            pending = next_pending.map(&:first)
          end

          [sorted, type_map]
        end

        def select_live_ops(sorted_ops:, seed_refs:)
          live_refs = Set.new(seed_refs)
          live_ops_reversed = []

          sorted_ops.reverse_each do |op|
            produced = op.fetch(:result_refs)
            next unless produced.any? { |ref| live_refs.include?(ref) }

            live_ops_reversed << op
            op_dependencies(op).each { |dep| live_refs << dep }
          end

          [live_ops_reversed.reverse, live_refs]
        end

        def comb_field_name(ref)
          sanitize_ident("comb_#{ref.to_s.sub('%', '')}")
        end

        def value_expr_for_ref(
          ref,
          type_map:,
          state_ref_to_slot:,
          comb_var:,
          state_snapshot_prefix: nil,
          top_input_refs: [],
          trust_state_masks: false
        )
          type = type_map.fetch(ref) { raise LoweringError, "Unknown reference #{ref}" }
          expr =
            if state_ref_to_slot.key?(ref)
              slot = state_ref_to_slot.fetch(ref)
              if state_snapshot_prefix
                "#{state_snapshot_prefix}#{slot.fetch(:index)}"
              else
                state_load_expr(slot, trust_state_masks: trust_state_masks)
              end
            elsif top_input_refs.include?(ref)
              ref_var_name(ref)
            else
              "#{comb_var}.#{comb_field_name(ref)}"
            end

          masked_expr(expr, type)
        end

        def collect_array_types(parsed)
          seen = {}
          out = []

          visit_type = lambda do |type|
            if type&.array?
              key = [type.fetch(:length), type.fetch(:element).fetch(:width)]
              next if seen[key]

              seen[key] = true
              out << { length: key[0], element_width: key[1] }
            end
          end

          parsed.fetch(:functions).each_value do |fn|
            fn.fetch(:args).each { |arg| visit_type.call(arg.fetch(:type)) }
            fn.fetch(:return_types).each { |t| visit_type.call(t) }
            fn.fetch(:ops).each do |op|
              op.fetch(:result_types).each { |t| visit_type.call(t) }
              visit_type.call(op[:array_type]) if op.key?(:array_type)
            end
          end

          parsed.fetch(:top_module).fetch(:inputs).each { |arg| visit_type.call(arg.fetch(:type)) }
          parsed.fetch(:top_module).fetch(:outputs).each { |arg| visit_type.call(arg.fetch(:type)) }
          parsed.fetch(:top_module).fetch(:ops).each do |op|
            op.fetch(:result_types).each { |t| visit_type.call(t) }
            visit_type.call(op[:array_type]) if op.key?(:array_type)
          end

          out
        end

        def emit_state_store_lines(slot_info:, value_expr:, indent:, dirty_var: nil)
          type = slot_info.fetch(:type)
          index = slot_info.fetch(:index)
          if wide_scalar?(type)
            lines = []
            if dirty_var
              lines << "#{indent}if (#{dirty_var} == 0u && !rhdl_wide_eq(rhdl_load_wide_state(state_slots, #{index}u, #{type.fetch(:width)}u), #{value_expr})) { #{dirty_var} = 1u; }"
            end
            lines << "#{indent}rhdl_store_wide_state(state_slots, #{index}u, #{value_expr}, #{type.fetch(:width)}u);"
            lines
          else
            lines = []
            if dirty_var
              lines << "#{indent}if (#{dirty_var} == 0u && rhdl_mask_bits(state_slots[#{index}], #{type.fetch(:width)}u) != (#{value_expr})) { #{dirty_var} = 1u; }"
            end
            lines << "#{indent}state_slots[#{index}] = #{value_expr};"
            lines
          end
        end

        def state_load_expr(info = nil, index: nil, type: nil, trust_state_masks: false)
          if info
            index = info.fetch(:index)
            type = info.fetch(:type)
          end

          if wide_scalar?(type)
            "rhdl_load_wide_state(state_slots, #{index}u, #{type.fetch(:width)}u)"
          elsif trust_state_masks
            "state_slots[#{index}]"
          else
            "rhdl_mask_bits(state_slots[#{index}], #{type.fetch(:width)}u)"
          end
        end

        def top_eval_fn_name(module_name)
          "eval_#{sanitize_ident(module_name)}"
        end

        def top_output_struct_name(module_name)
          "#{sanitize_ident(module_name)}_outputs"
        end

        def metal_fn_name(name)
          "fn_#{sanitize_ident(name)}"
        end

        def ret_struct_name(name)
          "ret_#{sanitize_ident(name)}"
        end

        def array_struct_name(type_or_hash)
          if type_or_hash.is_a?(TypeRef)
            len = type_or_hash.fetch(:length)
            width = type_or_hash.fetch(:element).fetch(:width)
            return "arr_#{len}_i#{width}"
          end

          len = type_or_hash.fetch(:length)
          width = type_or_hash.fetch(:element_width)
          "arr_#{len}_i#{width}"
        end

        def sanitize_ident(name)
          out = name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          out = "_#{out}" if out.match?(/\A\d/)
          out
        end

        def ref_var_name(ref)
          sanitize_ident("v_#{ref.to_s.sub('%', '')}")
        end

        def wide_scalar?(type)
          pack_wide_scalars? && type&.scalar? && type.fetch(:width) > 32
        end

        def narrow_scalar_type_for_width(width)
          return scalar_msl_type unless @narrow_scalar_types
          return 'uchar' if width <= 8
          return 'ushort' if width <= 16

          scalar_msl_type
        end

        def metal_type_for(type)
          return scalar_msl_type unless type&.scalar?

          return 'RhdlWide' if wide_scalar?(type)

          narrow_scalar_type_for_width(type.fetch(:width))
        end

        def array_element_metal_type(array_info)
          width = array_info.fetch(:element_width)
          if wide_scalar?(TypeRef.new(kind: :scalar, width: width))
            'RhdlWide'
          else
            narrow_scalar_type_for_width(width)
          end
        end

        def truthy_expr(ref:, type_map:)
          type = type_map.fetch(ref)
          value = masked_expr(ref_var_name(ref), type)
          if wide_scalar?(type)
            "rhdl_wide_ne_zero(#{value})"
          else
            "(#{value} != #{scalar_zero_literal})"
          end
        end

        def emit_state_memory_helpers
          text = <<~MSL
            static inline __attribute__((always_inline)) uint rhdl_memory_index(uint idx, uint length) {
              if (length == 0u) {
                return 0u;
              }
              if ((length & (length - 1u)) == 0u) {
                return idx & (length - 1u);
              }
              return idx % length;
            }

            static inline __attribute__((always_inline)) #{scalar_msl_type} rhdl_read_memory_scalar(device #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, uint width) {
              uint pos = rhdl_memory_index(idx, length);
              return rhdl_mask_bits(state_slots[base + pos], width);
            }

            static inline __attribute__((always_inline)) #{scalar_msl_type} rhdl_read_memory_scalar(thread #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, uint width) {
              uint pos = rhdl_memory_index(idx, length);
              return rhdl_mask_bits(state_slots[base + pos], width);
            }

            static inline __attribute__((always_inline)) void rhdl_write_memory_scalar(device #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, #{scalar_msl_type} value, uint width) {
              uint pos = rhdl_memory_index(idx, length);
              state_slots[base + pos] = rhdl_mask_bits(value, width);
            }

            static inline __attribute__((always_inline)) void rhdl_write_memory_scalar(thread #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, #{scalar_msl_type} value, uint width) {
              uint pos = rhdl_memory_index(idx, length);
              state_slots[base + pos] = rhdl_mask_bits(value, width);
            }
          MSL

          if pack_wide_scalars?
            text << <<~MSL

              static inline __attribute__((always_inline)) RhdlWide rhdl_read_memory_wide(device #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, uint width) {
                uint pos = rhdl_memory_index(idx, length);
                uint elem = base + (pos * 2u);
                return rhdl_wide_mask(rhdl_wide_make(state_slots[elem], state_slots[elem + 1u]), width);
              }

              static inline __attribute__((always_inline)) RhdlWide rhdl_read_memory_wide(thread #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, uint width) {
                uint pos = rhdl_memory_index(idx, length);
                uint elem = base + (pos * 2u);
                return rhdl_wide_mask(rhdl_wide_make(state_slots[elem], state_slots[elem + 1u]), width);
              }

              static inline __attribute__((always_inline)) void rhdl_write_memory_wide(device #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, RhdlWide value, uint width) {
                uint pos = rhdl_memory_index(idx, length);
                uint elem = base + (pos * 2u);
                RhdlWide masked = rhdl_wide_mask(value, width);
                state_slots[elem] = masked.x;
                state_slots[elem + 1u] = masked.y;
              }

              static inline __attribute__((always_inline)) void rhdl_write_memory_wide(thread #{scalar_msl_type}* state_slots, uint base, uint length, uint idx, RhdlWide value, uint width) {
                uint pos = rhdl_memory_index(idx, length);
                uint elem = base + (pos * 2u);
                RhdlWide masked = rhdl_wide_mask(value, width);
                state_slots[elem] = masked.x;
                state_slots[elem + 1u] = masked.y;
              }
            MSL
          end

          text
        end

        def inline_qualifier(always_inline:)
          always_inline ? 'static inline __attribute__((always_inline))' : 'static inline'
        end

        def prefer_always_inline_for_define?(fn)
          return false if ENV['RHDL_ARC_TO_GPU_DISABLE_ALWAYS_INLINE'] == '1'
          return true if ENV['RHDL_ARC_TO_GPU_FORCE_ALWAYS_INLINE'] == '1'

          inline_op_limit = ENV.fetch('RHDL_ARC_TO_GPU_ALWAYS_INLINE_MAX_OPS', '12').to_i
          inline_op_limit = 12 if inline_op_limit <= 0
          inline_return_limit = ENV.fetch('RHDL_ARC_TO_GPU_ALWAYS_INLINE_MAX_RETURNS', '2').to_i
          inline_return_limit = 2 if inline_return_limit <= 0

          op_count = fn.fetch(:ops).length
          return false if op_count > inline_op_limit

          fn.fetch(:return_types).length <= inline_return_limit
        end

        def emit_wide_helpers
          <<~MSL
            struct RhdlWide {
              uint x;
              uint y;
            };

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_make(uint lo, uint hi) {
              RhdlWide v;
              v.x = lo;
              v.y = hi;
              return v;
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_mask(RhdlWide value, uint width) {
              if (width >= 64u) { return value; }
              if (width == 0u) { return rhdl_wide_make(0u, 0u); }
              if (width <= 32u) {
                uint mask = (width == 32u) ? 0xFFFFFFFFu : ((1u << width) - 1u);
                return rhdl_wide_make(value.x & mask, 0u);
              }
              uint hi_width = width - 32u;
              uint hi_mask = (hi_width == 32u) ? 0xFFFFFFFFu : ((1u << hi_width) - 1u);
              return rhdl_wide_make(value.x, value.y & hi_mask);
            }

            static inline __attribute__((always_inline)) bool rhdl_wide_eq(RhdlWide lhs, RhdlWide rhs) {
              return lhs.x == rhs.x && lhs.y == rhs.y;
            }

            static inline __attribute__((always_inline)) bool rhdl_wide_ne_zero(RhdlWide value) {
              return (value.x | value.y) != 0u;
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_or(RhdlWide lhs, RhdlWide rhs) {
              return rhdl_wide_make(lhs.x | rhs.x, lhs.y | rhs.y);
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_xor(RhdlWide lhs, RhdlWide rhs) {
              return rhdl_wide_make(lhs.x ^ rhs.x, lhs.y ^ rhs.y);
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_and(RhdlWide lhs, RhdlWide rhs) {
              return rhdl_wide_make(lhs.x & rhs.x, lhs.y & rhs.y);
            }

            static inline __attribute__((always_inline)) ulong rhdl_wide_to_ulong(RhdlWide value) {
              return (ulong(value.y) << 32u) | ulong(value.x);
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_from_ulong(ulong value) {
              return rhdl_wide_make(uint(value & 0xFFFFFFFFul), uint((value >> 32u) & 0xFFFFFFFFul));
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_add(RhdlWide lhs, RhdlWide rhs) {
              return rhdl_wide_from_ulong(rhdl_wide_to_ulong(lhs) + rhdl_wide_to_ulong(rhs));
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_sub(RhdlWide lhs, RhdlWide rhs) {
              return rhdl_wide_from_ulong(rhdl_wide_to_ulong(lhs) - rhdl_wide_to_ulong(rhs));
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_mul(RhdlWide lhs, RhdlWide rhs) {
              return rhdl_wide_from_ulong(rhdl_wide_to_ulong(lhs) * rhdl_wide_to_ulong(rhs));
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_shlu(RhdlWide value, uint shift) {
              if (shift >= 64u) { return rhdl_wide_make(0u, 0u); }
              if (shift == 0u) { return value; }
              if (shift < 32u) {
                uint lo = value.x << shift;
                uint hi = (value.y << shift) | (value.x >> (32u - shift));
                return rhdl_wide_make(lo, hi);
              }
              if (shift == 32u) {
                return rhdl_wide_make(0u, value.x);
              }
              return rhdl_wide_make(0u, value.x << (shift - 32u));
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_wide_shru(RhdlWide value, uint shift) {
              if (shift >= 64u) { return rhdl_wide_make(0u, 0u); }
              if (shift == 0u) { return value; }
              if (shift < 32u) {
                uint lo = (value.x >> shift) | (value.y << (32u - shift));
                uint hi = (value.y >> shift);
                return rhdl_wide_make(lo, hi);
              }
              if (shift == 32u) {
                return rhdl_wide_make(value.y, 0u);
              }
              return rhdl_wide_make(value.y >> (shift - 32u), 0u);
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_load_wide_state(device uint* state_slots, uint base, uint width) {
              RhdlWide value = rhdl_wide_make(state_slots[base], state_slots[base + 1u]);
              return rhdl_wide_mask(value, width);
            }

            static inline __attribute__((always_inline)) RhdlWide rhdl_load_wide_state(thread uint* state_slots, uint base, uint width) {
              RhdlWide value = rhdl_wide_make(state_slots[base], state_slots[base + 1u]);
              return rhdl_wide_mask(value, width);
            }

            static inline __attribute__((always_inline)) void rhdl_store_wide_state(device uint* state_slots, uint base, RhdlWide value, uint width) {
              RhdlWide masked = rhdl_wide_mask(value, width);
              state_slots[base] = masked.x;
              state_slots[base + 1u] = masked.y;
            }

            static inline __attribute__((always_inline)) void rhdl_store_wide_state(thread uint* state_slots, uint base, RhdlWide value, uint width) {
              RhdlWide masked = rhdl_wide_mask(value, width);
              state_slots[base] = masked.x;
              state_slots[base + 1u] = masked.y;
            }
          MSL
        end

        def mask_value(value, width)
          return value if width >= 64

          mask = (1 << width) - 1
          value & mask
        end

        def mask_const(width)
          if width >= scalar_width_bits
            scalar_full_mask_const
          else
            format("0x%X%s", (1 << width) - 1, scalar_width_bits > 32 ? 'ul' : 'u')
          end
        end

        def masked_expr(expr, type)
          return expr unless type&.scalar?

          width = type.fetch(:width)
          if wide_scalar?(type)
            return "rhdl_wide_mask((#{expr}), #{width}u)"
          end

          return expr if width >= scalar_width_bits

          "((#{expr}) & #{mask_const(width)})"
        end

        def constant_literal(value, type)
          return scalar_zero_literal unless type&.scalar?

          masked = mask_value(value.to_i, type.fetch(:width))
          if wide_scalar?(type)
            lo = masked & 0xFFFFFFFF
            hi = (masked >> 32) & 0xFFFFFFFF
            return format('rhdl_wide_make(0x%Xu, 0x%Xu)', lo, hi)
          end

          format("0x%X%s", masked, scalar_width_bits > 32 ? 'ul' : 'u')
        end

        def split_top_level(text)
          parts = []
          current = +''
          depth_angle = 0
          depth_paren = 0
          depth_square = 0

          text.to_s.each_char do |ch|
            case ch
            when '<'
              depth_angle += 1
            when '>'
              depth_angle -= 1 if depth_angle.positive?
            when '('
              depth_paren += 1
            when ')'
              depth_paren -= 1 if depth_paren.positive?
            when '['
              depth_square += 1
            when ']'
              depth_square -= 1 if depth_square.positive?
            when ','
              if depth_angle.zero? && depth_paren.zero? && depth_square.zero?
                parts << current.strip
                current = +''
                next
              end
            end
            current << ch
          end

          parts << current.strip unless current.strip.empty?
          parts
        end

        def clean_line(line)
          line.to_s.split('//', 2).first.to_s
        end

        def command_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            File.executable?(File.join(path, tool))
          end
        end

        def indent_lines(lines, spaces: 2)
          prefix = ' ' * spaces
          lines.map { |line| "#{prefix}#{line}" }.join("\n")
        end
      end
    end
  end
end
