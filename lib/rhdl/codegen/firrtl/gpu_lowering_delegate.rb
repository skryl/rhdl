# frozen_string_literal: true

require 'json'
require 'set'

module RHDL
  module Codegen
    module FIRRTL
      # Shared lowering flow for Arc/Synth/GEM frontends.
      #
      # Frontends provide source text + parser semantics. This delegate handles
      # the shared profile transforms, validation, metadata, and code emission.
      module GpuLoweringDelegate
        module_function

        def lower(
          lowerer:,
          source_text:,
          parser:,
          gpu_mlir_path:,
          metadata_path: nil,
          metal_source_path: nil,
          profile: :cpu8bit,
          gem_kernel_interpreter: false,
          require_arc_define: true,
          metadata_version: 'ArcToGpuLoweringV2',
          lowering_label: 'ArcToGpuLowering'
        )
          profile_impl = lowerer.profile_module_for(profile)
          source = profile_impl.prepare_source(source: source_text, lowerer: lowerer)
          parsed = parser.call(source)
          parsed = profile_impl.post_parse_transform(parsed: parsed, lowerer: lowerer)
          summary = lowerer.summarize(parsed)

          unsupported = summary[:ops].keys.reject { |op| lowerer::SUPPORTED_OPS.include?(op) }
          unless unsupported.empty?
            raise lowerer::LoweringError,
              "#{lowering_label} does not support ops: #{unsupported.sort.join(', ')}"
          end

          lowerer.validate_top_module!(
            parsed,
            summary,
            required_inputs: profile_impl.required_inputs,
            required_outputs: profile_impl.required_outputs,
            require_arc_define: require_arc_define
          )

          gpu_mlir = lowerer.emit_gpu_mlir(summary, lowering_label: lowering_label)
          File.write(gpu_mlir_path, gpu_mlir)

          inferred_scalar_bits = lowerer.inferred_scalar_width_bits(parsed)
          pack_wide_scalars = profile_impl.pack_wide_scalars?(inferred_scalar_bits: inferred_scalar_bits)
          effective_scalar_bits = pack_wide_scalars ? lowerer::DEFAULT_SCALAR_WIDTH_BITS : inferred_scalar_bits

          state_layout = lowerer.build_state_layout(parsed, pack_wide_scalars: pack_wide_scalars)
          clock_tracking_slot_count = lowerer.count_clock_tracking_slots(parsed.fetch(:top_module).fetch(:ops))
          state_slots = state_layout.sum { |entry| entry.fetch(:slot_count, 1) }
          state_count = state_slots + clock_tracking_slot_count
          output_state_slots = lowerer.map_output_state_slots(parsed, state_layout)
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
              lowerer: lowerer,
              parsed: parsed,
              state_layout: state_layout,
              metal_entry: metal_entry,
              scalar_bits: effective_scalar_bits,
              pack_wide_scalars: pack_wide_scalars,
              gem_kernel_interpreter: gem_kernel_interpreter
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
              metadata[:metal][:introspection] = lowerer.riscv_runtime_introspection(parsed, state_layout, output_state_slots)
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
      end
    end
  end
end
