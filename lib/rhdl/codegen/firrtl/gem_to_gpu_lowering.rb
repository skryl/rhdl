# frozen_string_literal: true

require 'json'
require 'set'
require 'digest'
require_relative 'synth_to_gpu_lowering'

module RHDL
  module Codegen
    module FIRRTL
      # GEM-inspired CPU8bit Synth->GPU lowering shim.
      #
      # This stage keeps existing SynthToGpuLowering code generation, and adds a
      # deterministic graph analysis pass that emits GEM-style partition/layer
      # metadata for execution planning and profiling.
      module GemToGpuLowering
        class LoweringError < StandardError; end

        module_function

        DEFAULT_PARTITION_SIZE = 256

        def lower(
          synth_mlir_path:,
          gpu_mlir_path:,
          metadata_path: nil,
          metal_source_path: nil,
          profile: :cpu8bit,
          partition_size: DEFAULT_PARTITION_SIZE
        )
          part_size = [partition_size.to_i, 1].max
          synth_source = File.read(synth_mlir_path)
          gem_stats = analyze_synth_graph(synth_source, partition_size: part_size)
          gem_stats[:execution][:kernel_mode] = kernel_mode

          summary = SynthToGpuLowering.lower(
            synth_mlir_path: synth_mlir_path,
            gpu_mlir_path: gpu_mlir_path,
            metadata_path: metadata_path,
            metal_source_path: metal_source_path,
            profile: profile
          )

          return summary unless metadata_path

          metadata = JSON.parse(File.read(metadata_path))
          enrich_instruction_stream_with_runtime_sources!(
            stream: gem_stats[:instruction_stream],
            synth_source: synth_source,
            state_layout: Array(metadata['state_layout']),
            top_input_layout: Array(metadata['top_input_layout']),
            top_output_layout: Array(metadata['top_output_layout'])
          )
          metadata['version'] = 'GemToGpuLoweringV1'
          metadata['gem'] = gem_stats
          File.write(metadata_path, JSON.pretty_generate(metadata))

          summary.merge(gem: gem_stats)
        rescue SynthToGpuLowering::LoweringError => e
          raise LoweringError, e.message
        end

        def analyze_synth_graph(source, partition_size:)
          nodes = []
          ref_to_node = {}
          output_ref_map = extract_output_ref_map(source)

          source.each_line do |line|
            stripped = line.strip
            next unless stripped.include?('= synth.aig.and_inv ')

            match = stripped.match(/\A(%[A-Za-z0-9_.$#-]+(?::\d+)?)\s*=\s*synth\.aig\.and_inv\s+(.+?)\s*:\s*(.+)\z/)
            next unless match

            result_ref = match[1]
            operand_text = strip_outer_parens(match[2])
            operands = parse_and_inv_operands(operand_text)
            refs = operands.map { |op| op.fetch(:ref) }.uniq

            node = {
              id: nodes.length,
              result_ref: normalize_ref(result_ref),
              input_refs: refs,
              input_operands: operands
            }
            nodes << node
            ref_to_node[node.fetch(:result_ref)] = node.fetch(:id)
          end

          if nodes.empty?
            stats = empty_stats(partition_size)
            stats[:execution] = build_execution_plan(stats)
            stats[:instruction_stream] = build_instruction_stream(
              nodes: nodes,
              partition_size: partition_size,
              output_ref_map: output_ref_map
            )
            return stats
          end

          depths = Array.new(nodes.length, 0)
          dependency_edges = 0
          cross_partition_edges = 0
          partition_node_counts = Hash.new(0)
          partition_dep_edge_counts = Hash.new(0)
          layer_sizes = Hash.new(0)
          partition_layer_sizes = Hash.new { |h, k| h[k] = Hash.new(0) }

          nodes.each do |node|
            node_id = node.fetch(:id)
            partition = node_id / partition_size
            partition_node_counts[partition] += 1

            dep_ids = node.fetch(:input_refs).map { |ref| ref_to_node[ref] }.compact
            dependency_edges += dep_ids.length

            if dep_ids.empty?
              depth = 0
            else
              depth = dep_ids.map { |id| depths[id] }.max + 1
              dep_ids.each do |dep_id|
                dep_partition = dep_id / partition_size
                next unless dep_partition != partition

                cross_partition_edges += 1
                partition_dep_edge_counts[[dep_partition, partition]] += 1
              end
            end

            depths[node_id] = depth
            layer_sizes[depth] += 1
            partition_layer_sizes[partition][depth] += 1
          end

          partition_layer_depths = partition_layer_sizes.transform_values do |layer_map|
            layer_map.keys.max.to_i + 1
          end

          stats = {
            partition_size: partition_size,
            node_count: nodes.length,
            edge_count: dependency_edges,
            partition_count: partition_node_counts.length,
            max_layer_depth: depths.max.to_i + 1,
            average_layer_width: average(layer_sizes.values),
            max_layer_width: layer_sizes.values.max.to_i,
            cross_partition_edges: cross_partition_edges,
            partition_dependency_edges: build_partition_dependency_edges(partition_dep_edge_counts),
            partitions: partition_node_counts.keys.sort.map do |partition_id|
              {
                id: partition_id,
                node_count: partition_node_counts.fetch(partition_id),
                layer_count: partition_layer_depths.fetch(partition_id, 0),
                max_layer_width: partition_layer_sizes.fetch(partition_id, {}).values.max.to_i
              }
            end
          }
          stats[:execution] = build_execution_plan(stats)
          stats[:instruction_stream] = build_instruction_stream(
            nodes: nodes,
            partition_size: partition_size,
            output_ref_map: output_ref_map
          )
          stats
        end

        def normalize_ref(ref)
          ref.to_s.split(':').first
        end
        private_class_method :normalize_ref

        def strip_outer_parens(text)
          body = text.to_s.strip
          return body unless body.start_with?('(') && body.end_with?(')')

          body[1...-1].strip
        end
        private_class_method :strip_outer_parens

        def parse_and_inv_operands(operand_text)
          split_operands(operand_text).filter_map { |token| parse_operand_token(token) }
        end
        private_class_method :parse_and_inv_operands

        def parse_operand_token(token)
          body = token.to_s.strip
          return nil if body.empty?

          inverted = false
          if body.start_with?('not ')
            inverted = true
            body = body.sub(/\Anot\s+/, '').strip
          end

          ref_match = body.match(/(%[A-Za-z0-9_.$#-]+(?::\d+)?)/)
          return nil unless ref_match

          {
            ref: normalize_ref(ref_match[1]),
            inverted: inverted
          }
        end
        private_class_method :parse_operand_token

        def average(values)
          return 0.0 if values.empty?

          values.sum.to_f / values.length.to_f
        end
        private_class_method :average

        def empty_stats(partition_size)
          {
            partition_size: partition_size,
            node_count: 0,
            edge_count: 0,
            partition_count: 0,
            max_layer_depth: 0,
            average_layer_width: 0.0,
            max_layer_width: 0,
            cross_partition_edges: 0,
            partitions: []
          }
        end
        private_class_method :empty_stats

        def build_instruction_stream(nodes:, partition_size:, output_ref_map:)
          extern_ref_ids = {}
          extern_refs = []
          node_ref_ids = {}
          nodes.each { |node| node_ref_ids[node.fetch(:result_ref)] = node.fetch(:id) }

          instructions = []
          temp_node_id = nodes.length

          emit_instruction = lambda do |dst_node, src0, src1|
            instructions << {
              pc: instructions.length,
              op: 'and_inv',
              dst_node: dst_node,
              src: [src0, src1]
            }
          end

          intern_extern_ref = lambda do |ref|
            extern_id = extern_ref_ids[ref]
            return extern_id if extern_id

            extern_id = extern_refs.length
            extern_ref_ids[ref] = extern_id
            extern_refs << ref
            extern_id
          end

          encode_operand = lambda do |operand|
            src_ref = operand.fetch(:ref)
            src_node_id = node_ref_ids[src_ref]
            if src_node_id
              {
                kind: 'node',
                id: src_node_id,
                inverted: operand.fetch(:inverted)
              }
            else
              {
                kind: 'extern',
                id: intern_extern_ref.call(src_ref),
                inverted: operand.fetch(:inverted)
              }
            end
          end

          nodes.each do |node|
            operands = node.fetch(:input_operands).map { |operand| encode_operand.call(operand) }
            const_true_id = intern_extern_ref.call('%ctrue')
            const_true = { kind: 'extern', id: const_true_id, inverted: false }

            if operands.empty?
              emit_instruction.call(node.fetch(:id), const_true, const_true)
              next
            end

            if operands.length == 1
              emit_instruction.call(node.fetch(:id), operands.first, const_true)
              next
            end

            current_src = operands[0]
            operands[1..].each_with_index do |operand, idx|
              final = idx == operands.length - 2
              dst_node = final ? node.fetch(:id) : temp_node_id
              emit_instruction.call(dst_node, current_src, operand)
              current_src = { kind: 'node', id: dst_node, inverted: false }
              temp_node_id += 1 unless final
            end
          end

          block_boundaries = [0]
          node_count = nodes.length
          if partition_size.positive?
            idx = partition_size
            while idx < node_count
              block_boundaries << idx
              idx += partition_size
            end
          end
          block_boundaries << node_count unless block_boundaries.last == node_count

          control_program = [
            { op: 'cycle_begin' },
            { op: 'eval_low' },
            { op: 'mem_write' },
            { op: 'mem_read' },
            { op: 'eval_high' },
            { op: 'output_materialize' },
            { op: 'cycle_end' }
          ]

          primitive_counts = {
            and_inv: instructions.length,
            state_read: extern_refs.length,
            state_write: 0,
            mem_read: 1,
            mem_write: 1,
            output_materialize: 1
          }
          watch_names = %w[mem_write_en mem_read_en halted zero_flag_out]
          output_watch_sources = build_output_watch_sources(
            watch_names: watch_names,
            output_ref_map: output_ref_map,
            node_ref_ids: node_ref_ids,
            extern_ref_ids: extern_ref_ids,
            extern_refs: extern_refs
          )
          watch_eval_indices = build_watch_eval_indices(instructions: instructions, output_watch_sources: output_watch_sources)

          payload = {
            version: 'GemInstructionStreamV1',
            instruction_count: instructions.length,
            block_boundaries: block_boundaries,
            extern_refs: extern_refs,
            extern_ref_kinds: extern_refs.map { |ref| known_const_ref?(ref) ? 'const' : 'unknown' },
            extern_ref_values: extern_refs.map { |ref| const_ref_value(ref) },
            extern_sources: extern_refs.map { |ref| known_const_ref?(ref) ? { kind: 'const', value: const_ref_value(ref) } : { kind: 'unknown' } },
            instructions: instructions,
            output_watch_names: watch_names,
            output_watch_sources: output_watch_sources,
            watch_eval_indices: watch_eval_indices,
            opcode_groups: {
              compute: %w[and_inv],
              state: %w[state_read state_write],
              memory: %w[mem_read mem_write],
              output: %w[output_materialize],
              control: control_program.map { |step| step.fetch(:op) }
            },
            primitive_counts: primitive_counts,
            control_program: control_program
          }
          payload[:checksum_sha256] = Digest::SHA256.hexdigest(JSON.generate(payload))
          payload
        end
        private_class_method :build_instruction_stream

        def build_watch_eval_indices(instructions:, output_watch_sources:)
          instruction_by_dst = {}
          Array(instructions).each_with_index do |instruction, index|
            instruction_by_dst[instruction.fetch(:dst_node).to_i] = [instruction, index]
          end
          required = Set.new
          queue = []
          Array(output_watch_sources).each do |source|
            kind = source.fetch(:kind, source[:kind]).to_s
            next unless kind == 'node'

            node_id = source.fetch(:id, source[:id]).to_i
            next if required.include?(node_id)

            required << node_id
            queue << node_id
          end
          until queue.empty?
            node_id = queue.shift
            info = instruction_by_dst[node_id]
            next unless info

            instruction = info.first
            Array(instruction.fetch(:src, [])).each do |operand|
              next unless operand.is_a?(Hash)
              next unless operand.fetch(:kind, operand[:kind]).to_s == 'node'

              dep_id = operand.fetch(:id, operand[:id]).to_i
              next if required.include?(dep_id)

              required << dep_id
              queue << dep_id
            end
          end

          required.to_a.sort.map do |node_id|
            info = instruction_by_dst[node_id]
            info ? info.last : nil
          end.compact
        end
        private_class_method :build_watch_eval_indices

        def enrich_instruction_stream_with_runtime_sources!(
          stream:,
          synth_source:,
          state_layout:,
          top_input_layout:,
          top_output_layout:
        )
          extern_refs = Array(stream[:extern_refs]).map { |ref| normalize_ref(ref) }
          definition_map = build_definition_map(synth_source)
          node_ref_ids = build_node_ref_ids(synth_source)
          output_ref_map = extract_output_ref_map(synth_source)
          firreg_map = extract_firreg_map(synth_source)

          state_ref_to_index = {}
          state_ref_to_width = {}
          state_layout.each do |entry|
            ref = normalize_ref(entry['result_ref'])
            next if ref.empty?

            state_ref_to_index[ref] = entry['index'].to_i
            state_ref_to_width[ref] = [entry['width'].to_i, 1].max
          end

          input_ref_to_name = {}
          input_ref_to_width = {}
          top_input_layout.each do |entry|
            name = entry['name'].to_s
            next if name.empty?

            ref = normalize_ref("%#{name}")
            input_ref_to_name[ref] = name
            input_ref_to_width[ref] = [entry['width'].to_i, 1].max
          end

          extern_cache = {}
          extern_sources = extern_refs.map do |ref|
            resolve_extern_source(
              ref: ref,
              definition_map: definition_map,
              state_ref_to_index: state_ref_to_index,
              input_ref_to_name: input_ref_to_name,
              cache: extern_cache
            )
          end

          source_key_to_id = {}
          extern_sources.each_with_index do |source, idx|
            key = canonical_source_key(source)
            source_key_to_id[key] ||= idx
          end

          intern_extern_source = lambda do |source, hint|
            key = canonical_source_key(source)
            existing = source_key_to_id[key]
            return existing if existing

            id = extern_refs.length
            source_key_to_id[key] = id
            extern_refs << hint
            extern_sources << source
            id
          end

          width_cache = {}
          bit_source_cache = {}
          context = {
            definition_map: definition_map,
            node_ref_ids: node_ref_ids,
            state_ref_to_index: state_ref_to_index,
            state_ref_to_width: state_ref_to_width,
            input_ref_to_name: input_ref_to_name,
            input_ref_to_width: input_ref_to_width,
            width_cache: width_cache,
            bit_source_cache: bit_source_cache
          }

          rewrite_instruction_sources!(
            stream: stream,
            extern_refs: extern_refs,
            intern_extern_source: intern_extern_source,
            context: context
          )

          output_fields = []
          output_widths = []
          output_bit_sources = []
          top_output_layout.each do |entry|
            name = entry['name'].to_s
            width = [entry['width'].to_i, 0].max
            next if name.empty? || width <= 0

            signal = output_ref_map[name] || { literal: 'false', inverted: false }
            packed_bits = pack_runtime_bit_sources(
              bit_sources: build_signal_bit_sources(signal: signal, width: width, context: context),
              intern_extern_source: intern_extern_source
            )
            output_fields << name
            output_widths << width
            output_bit_sources.concat(packed_bits)
          end

          state_slot_indices = []
          state_widths = []
          state_next_bit_sources = []
          state_reset_bit_sources = []
          state_reset_enable_sources = []
          Array(state_layout).sort_by { |entry| entry['index'].to_i }.each do |entry|
            slot_index = entry['index'].to_i
            width = [entry['width'].to_i, 0].max
            next if width <= 0

            ref = normalize_ref(entry['result_ref'])
            firreg = firreg_map[ref] || {}
            next_signal = firreg[:next_signal] || { ref: ref, inverted: false }
            reset_signal = firreg[:reset_value_signal] || { literal: 'false', inverted: false }
            reset_enable_signal = firreg[:reset_enable_signal] || { ref: '%rst', inverted: false }

            state_slot_indices << slot_index
            state_widths << width
            state_next_bit_sources.concat(
              pack_runtime_bit_sources(
                bit_sources: build_signal_bit_sources(signal: next_signal, width: width, context: context),
                intern_extern_source: intern_extern_source
              )
            )
            state_reset_bit_sources.concat(
              pack_runtime_bit_sources(
                bit_sources: build_signal_bit_sources(signal: reset_signal, width: width, context: context),
                intern_extern_source: intern_extern_source
              )
            )
            reset_enable_bits = build_signal_bit_sources(signal: reset_enable_signal, width: 1, context: context)
            state_reset_enable_sources.concat(
              pack_runtime_bit_sources(
                bit_sources: reset_enable_bits,
                intern_extern_source: intern_extern_source
              )
            )
          end

          stream[:extern_refs] = extern_refs
          stream[:extern_sources] = extern_sources.map(&:dup)
          stream[:extern_ref_kinds] = extern_sources.map do |source|
            case source.fetch(:kind)
            when 'const'
              'const'
            when 'state_bit', 'io_bit', 'state_divu_bit', 'state_modu_bit'
              'dynamic'
            else
              'unknown'
            end
          end
          stream[:extern_ref_values] = extern_sources.map { |source| source.fetch(:kind) == 'const' ? source.fetch(:value, 0).to_i & 0x1 : 0 }
          stream[:output_fields] = output_fields
          stream[:output_widths] = output_widths
          stream[:output_bit_sources] = output_bit_sources
          stream[:state_slot_indices] = state_slot_indices
          stream[:state_widths] = state_widths
          stream[:state_next_bit_sources] = state_next_bit_sources
          stream[:state_reset_bit_sources] = state_reset_bit_sources
          stream[:state_reset_enable_sources] = state_reset_enable_sources

          if stream[:primitive_counts].is_a?(Hash)
            stream[:primitive_counts][:state_write] = state_next_bit_sources.length
          end
          refresh_instruction_stream_checksum!(stream)
        end
        private_class_method :enrich_instruction_stream_with_runtime_sources!

        def build_definition_map(source)
          map = {}
          source.each_line do |line|
            stripped = line.strip
            next unless stripped.start_with?('%')
            next unless stripped.include?(' = ')

            lhs, rhs = stripped.split(' = ', 2)
            next if lhs.nil? || rhs.nil?

            map[normalize_ref(lhs)] = rhs.strip
          end
          map
        end
        private_class_method :build_definition_map

        def build_node_ref_ids(source)
          node_ref_ids = {}
          next_id = 0
          source.each_line do |line|
            stripped = line.strip
            match = stripped.match(/\A(%[A-Za-z0-9_.$#-]+(?::\d+)?)\s*=\s*synth\.aig\.and_inv\b/)
            next unless match

            node_ref_ids[normalize_ref(match[1])] = next_id
            next_id += 1
          end
          node_ref_ids
        end
        private_class_method :build_node_ref_ids

        def extract_firreg_map(source)
          map = {}
          source.each_line do |line|
            stripped = line.strip
            match = stripped.match(/\A(%[A-Za-z0-9_.$#-]+(?::\d+)?)\s*=\s*seq\.firreg\s+(.+)\z/)
            next unless match

            ref = normalize_ref(match[1])
            body = match[2]
            next_ref = body[/\A(%[A-Za-z0-9_.$#-]+(?::\d+)?)/, 1]
            reset_match = body.match(/\breset\s+\w+\s+([^,\s]+)\s*,\s*([^ \{]+)/)
            reset_signal = reset_match && reset_match[1]
            reset_value = reset_match && reset_match[2]
            map[ref] = {
              next_signal: parse_signal_token(next_ref),
              reset_enable_signal: parse_signal_token(reset_signal),
              reset_value_signal: parse_signal_token(reset_value)
            }
          end
          map
        end
        private_class_method :extract_firreg_map

        def build_signal_bit_sources(signal:, width:, context:)
          bit_count = [width.to_i, 0].max
          return [] if bit_count.zero?

          (0...bit_count).map do |bit|
            resolve_signal_bit_source(signal: signal, bit: bit, context: context)
          end
        end
        private_class_method :build_signal_bit_sources

        def resolve_signal_bit_source(signal:, bit:, context:)
          sig = signal || { literal: 'false', inverted: false }
          inverted = sig.fetch(:inverted, false)
          if sig.key?(:literal)
            value = literal_token_value(sig.fetch(:literal).to_s)
            value ^= 1 if inverted
            return {
              kind: 'extern',
              source: { kind: 'const', value: bit.zero? ? value : 0 },
              hint: "%c#{bit.zero? ? value : 0}"
            }
          end

          ref = normalize_ref(sig.fetch(:ref, ''))
          source = resolve_ref_bit_source(ref: ref, bit: bit, context: context)
          return source unless inverted

          source = source.dup
          source[:inverted] = !source.fetch(:inverted, false)
          source
        rescue KeyError
          {
            kind: 'extern',
            source: { kind: 'const', value: 0 },
            hint: '%c0'
          }
        end
        private_class_method :resolve_signal_bit_source

        def resolve_ref_bit_source(ref:, bit:, context:, depth: 0)
          key = normalize_ref(ref)
          return { kind: 'extern', source: { kind: 'const', value: 0 }, hint: '%c0' } if key.empty?
          return { kind: 'extern', source: { kind: 'const', value: 0 }, hint: '%c0' } if depth > 32

          cache_key = "#{key}:#{bit}"
          cached = context.fetch(:bit_source_cache)[cache_key]
          return cached if cached

          node_ref_ids = context.fetch(:node_ref_ids)
          if node_ref_ids.key?(key)
            source = if bit.zero?
              { kind: 'node', id: node_ref_ids.fetch(key), inverted: false }
            else
              { kind: 'extern', source: { kind: 'const', value: 0 }, hint: '%c0' }
            end
            context.fetch(:bit_source_cache)[cache_key] = source
            return source
          end

          if known_const_ref?(key)
            source = {
              kind: 'extern',
              source: { kind: 'const', value: bit.zero? ? const_ref_value(key) : 0 },
              hint: const_ref_value(key) == 1 ? '%ctrue' : '%cfalse'
            }
            context.fetch(:bit_source_cache)[cache_key] = source
            return source
          end

          state_ref_to_index = context.fetch(:state_ref_to_index)
          if state_ref_to_index.key?(key)
            source = {
              kind: 'extern',
              source: { kind: 'state_bit', state_index: state_ref_to_index.fetch(key), bit: bit.to_i },
              hint: "%state_#{state_ref_to_index.fetch(key)}_b#{bit.to_i}"
            }
            context.fetch(:bit_source_cache)[cache_key] = source
            return source
          end

          input_ref_to_name = context.fetch(:input_ref_to_name)
          if input_ref_to_name.key?(key)
            source = {
              kind: 'extern',
              source: { kind: 'io_bit', field: input_ref_to_name.fetch(key), bit: bit.to_i },
              hint: "%io_#{input_ref_to_name.fetch(key)}_b#{bit.to_i}"
            }
            context.fetch(:bit_source_cache)[cache_key] = source
            return source
          end

          rhs = context.fetch(:definition_map)[key].to_s
          if rhs.start_with?('hw.constant ')
            value, = parse_hw_constant_value(rhs)
            source = {
              kind: 'extern',
              source: { kind: 'const', value: (value >> bit.to_i) & 0x1 },
              hint: "%c#{(value >> bit.to_i) & 0x1}"
            }
            context.fetch(:bit_source_cache)[cache_key] = source
            return source
          end

          extract_match = rhs.match(/\Acomb\.extract\s+(%[A-Za-z0-9_.$#-]+(?::\d+)?)\s+from\s+(\d+)/)
          if extract_match
            base = normalize_ref(extract_match[1])
            from = extract_match[2].to_i
            source = if bit.zero?
              resolve_ref_bit_source(ref: base, bit: from, context: context, depth: depth + 1)
            else
              { kind: 'extern', source: { kind: 'const', value: 0 }, hint: '%c0' }
            end
            context.fetch(:bit_source_cache)[cache_key] = source
            return source
          end

          concat_match = rhs.match(/\Acomb\.concat\s+(.+?)\s*:\s*(.+)\z/)
          if concat_match
            operands = split_operands(concat_match[1])
            remaining = bit.to_i
            operands.reverse_each do |token|
              width = signal_token_width(token: token, context: context)
              width = 1 if width <= 0
              if remaining < width
                source = resolve_signal_bit_source(
                  signal: parse_signal_token(token) || { literal: 'false', inverted: false },
                  bit: remaining,
                  context: context
                )
                context.fetch(:bit_source_cache)[cache_key] = source
                return source
              end
              remaining -= width
            end
          end

          replicate_match = rhs.match(/\Acomb\.replicate\s+(.+?)\s*:\s*\(([^)]+)\)\s*->\s*([^\s]+)\z/)
          if replicate_match
            operand_token = replicate_match[1].to_s.strip
            in_width = type_width(replicate_match[2])
            out_width = type_width(replicate_match[3])
            in_width = signal_token_width(token: operand_token, context: context) if in_width <= 0
            in_width = 1 if in_width <= 0
            if bit.to_i < out_width
              source = resolve_signal_bit_source(
                signal: parse_signal_token(operand_token) || { literal: 'false', inverted: false },
                bit: bit.to_i % in_width,
                context: context
              )
              context.fetch(:bit_source_cache)[cache_key] = source
              return source
            end
            source = { kind: 'extern', source: { kind: 'const', value: 0 }, hint: '%c0' }
            context.fetch(:bit_source_cache)[cache_key] = source
            return source
          end

          divmod_match = rhs.match(/\Acomb\.(divu|modu)\s+bin\s+(.+?)\s*,\s*(.+?)\s*:\s*.+\z/)
          if divmod_match
            op = divmod_match[1]
            lhs = parse_signal_token(divmod_match[2])
            rhs_signal = parse_signal_token(divmod_match[3])
            if lhs&.key?(:ref) && rhs_signal&.key?(:ref) &&
               !lhs.fetch(:inverted, false) && !rhs_signal.fetch(:inverted, false)
              lhs_ref = normalize_ref(lhs.fetch(:ref))
              rhs_ref = normalize_ref(rhs_signal.fetch(:ref))
              state_ref_to_index = context.fetch(:state_ref_to_index)
              if state_ref_to_index.key?(lhs_ref) && state_ref_to_index.key?(rhs_ref)
                source = {
                  kind: 'extern',
                  source: {
                    kind: op == 'divu' ? 'state_divu_bit' : 'state_modu_bit',
                    lhs_state_index: state_ref_to_index.fetch(lhs_ref),
                    rhs_state_index: state_ref_to_index.fetch(rhs_ref),
                    bit: bit.to_i
                  },
                  hint: "%#{op}_s#{state_ref_to_index.fetch(lhs_ref)}_s#{state_ref_to_index.fetch(rhs_ref)}_b#{bit.to_i}"
                }
                context.fetch(:bit_source_cache)[cache_key] = source
                return source
              end
            end
          end

          source = { kind: 'extern', source: { kind: 'unknown' }, hint: "%unknown_#{key}_b#{bit.to_i}" }
          context.fetch(:bit_source_cache)[cache_key] = source
          source
        end
        private_class_method :resolve_ref_bit_source

        def signal_token_width(token:, context:)
          signal = parse_signal_token(token)
          return 1 unless signal&.key?(:ref)

          ref_width(ref: signal.fetch(:ref), context: context)
        end
        private_class_method :signal_token_width

        def ref_width(ref:, context:, depth: 0)
          key = normalize_ref(ref)
          return 1 if key.empty?
          return 1 if depth > 32

          cache = context.fetch(:width_cache)
          return cache[key] if cache.key?(key)

          state_ref_to_width = context.fetch(:state_ref_to_width)
          if state_ref_to_width.key?(key)
            cache[key] = state_ref_to_width.fetch(key)
            return cache[key]
          end

          input_ref_to_width = context.fetch(:input_ref_to_width)
          if input_ref_to_width.key?(key)
            cache[key] = input_ref_to_width.fetch(key)
            return cache[key]
          end

          if context.fetch(:node_ref_ids).key?(key)
            cache[key] = 1
            return 1
          end

          rhs = context.fetch(:definition_map)[key].to_s
          width =
            if rhs.start_with?('hw.constant ')
              _, const_width = parse_hw_constant_value(rhs)
              const_width
            elsif rhs.start_with?('comb.extract ')
              1
            elsif rhs.start_with?('synth.aig.and_inv ')
              1
            elsif rhs.start_with?('seq.firreg ')
              type_token = rhs.split(':').last.to_s.strip
              type_width(type_token)
            elsif rhs.start_with?('comb.concat ')
              concat_match = rhs.match(/\Acomb\.concat\s+(.+?)\s*:\s*(.+)\z/)
              if concat_match
                split_operands(concat_match[1]).sum do |token|
                  signal = parse_signal_token(token)
                  if signal&.key?(:ref)
                    ref_width(ref: signal.fetch(:ref), context: context, depth: depth + 1)
                  else
                    1
                  end
                end
              else
                1
              end
            elsif rhs.start_with?('comb.replicate ')
              replicate_match = rhs.match(/\Acomb\.replicate\s+.+\s*:\s*\(([^)]+)\)\s*->\s*([^\s]+)\z/)
              if replicate_match
                out_width = type_width(replicate_match[2])
                out_width.positive? ? out_width : 1
              else
                1
              end
            else
              1
            end
          cache[key] = [width.to_i, 1].max
        end
        private_class_method :ref_width

        def type_width(type_token)
          match = type_token.to_s.match(/[iu](\d+)/i)
          return 1 unless match

          [match[1].to_i, 1].max
        end
        private_class_method :type_width

        def literal_token_value(token)
          text = token.to_s.strip.downcase
          return 1 if %w[1 true].include?(text)

          0
        end
        private_class_method :literal_token_value

        def pack_runtime_bit_sources(bit_sources:, intern_extern_source:)
          Array(bit_sources).map do |source|
            if source.fetch(:kind).to_s == 'node'
              {
                kind: 'node',
                id: source.fetch(:id).to_i,
                inverted: source.fetch(:inverted, false)
              }
            else
              descriptor = source.fetch(:source, { kind: 'unknown' })
              hint = source.fetch(:hint, infer_extern_ref_name_from_source(descriptor))
              extern_id = intern_extern_source.call(descriptor, hint)
              {
                kind: 'extern',
                id: extern_id,
                inverted: source.fetch(:inverted, false)
              }
            end
          end
        end
        private_class_method :pack_runtime_bit_sources

        def canonical_source_key(source)
          kind = source.fetch(:kind).to_s
          case kind
          when 'const'
            "const:#{source.fetch(:value, 0).to_i & 0x1}"
          when 'state_bit'
            "state:#{source.fetch(:state_index, 0).to_i}:#{source.fetch(:bit, 0).to_i}"
          when 'io_bit'
            "io:#{source.fetch(:field, '').to_s}:#{source.fetch(:bit, 0).to_i}"
          when 'state_divu_bit'
            "state_divu:#{source.fetch(:lhs_state_index, 0).to_i}:#{source.fetch(:rhs_state_index, 0).to_i}:#{source.fetch(:bit, 0).to_i}"
          when 'state_modu_bit'
            "state_modu:#{source.fetch(:lhs_state_index, 0).to_i}:#{source.fetch(:rhs_state_index, 0).to_i}:#{source.fetch(:bit, 0).to_i}"
          else
            'unknown'
          end
        end
        private_class_method :canonical_source_key

        def infer_extern_ref_name_from_source(source)
          kind = source.fetch(:kind, 'unknown').to_s
          case kind
          when 'const'
            source.fetch(:value, 0).to_i & 0x1 == 1 ? '%ctrue' : '%cfalse'
          when 'state_bit'
            "%state_#{source.fetch(:state_index, 0)}_b#{source.fetch(:bit, 0)}"
          when 'io_bit'
            "%io_#{source.fetch(:field, 'unknown')}_b#{source.fetch(:bit, 0)}"
          when 'state_divu_bit'
            "%divu_s#{source.fetch(:lhs_state_index, 0)}_s#{source.fetch(:rhs_state_index, 0)}_b#{source.fetch(:bit, 0)}"
          when 'state_modu_bit'
            "%modu_s#{source.fetch(:lhs_state_index, 0)}_s#{source.fetch(:rhs_state_index, 0)}_b#{source.fetch(:bit, 0)}"
          else
            '%cfalse'
          end
        end
        private_class_method :infer_extern_ref_name_from_source

        def rewrite_instruction_sources!(stream:, extern_refs:, intern_extern_source:, context:)
          instructions = Array(stream[:instructions] || stream['instructions'])
          instructions.each do |instruction|
            src_list = Array(instruction[:src] || instruction['src'])
            src_list.each do |src|
              next unless src.is_a?(Hash)

              src_kind = src.fetch(:kind, src['kind']).to_s
              next unless src_kind == 'extern'

              old_id = src.fetch(:id, src['id']).to_i
              ref = old_id >= 0 ? extern_refs[old_id] : nil
              signal = if ref
                { ref: normalize_ref(ref), inverted: false }
              else
                { literal: 'false', inverted: false }
              end
              resolved = resolve_signal_bit_source(signal: signal, bit: 0, context: context)
              src_inverted = src.fetch(:inverted, src['inverted']) ? true : false
              resolved_inverted = resolved.fetch(:inverted, false)
              combined_inverted = src_inverted ^ resolved_inverted

              if resolved.fetch(:kind).to_s == 'node'
                src[:kind] = src['kind'] = 'node'
                src[:id] = src['id'] = resolved.fetch(:id).to_i
                src[:inverted] = src['inverted'] = combined_inverted
              else
                descriptor = resolved.fetch(:source, { kind: 'unknown' })
                hint = resolved.fetch(:hint, infer_extern_ref_name_from_source(descriptor))
                extern_id = intern_extern_source.call(descriptor, hint)
                src[:kind] = src['kind'] = 'extern'
                src[:id] = src['id'] = extern_id
                src[:inverted] = src['inverted'] = combined_inverted
              end
            end
          end
          stream[:instructions] = instructions
        end
        private_class_method :rewrite_instruction_sources!

        def resolve_extern_source(ref:, definition_map:, state_ref_to_index:, input_ref_to_name:, cache:, depth: 0)
          key = normalize_ref(ref)
          return cache[key] if cache.key?(key)
          return { kind: 'unknown' } if depth > 16

          if known_const_ref?(key)
            source = { kind: 'const', value: const_ref_value(key) }
            cache[key] = source
            return source
          end

          if state_ref_to_index.key?(key)
            source = { kind: 'state_bit', state_index: state_ref_to_index.fetch(key), bit: 0 }
            cache[key] = source
            return source
          end
          if input_ref_to_name.key?(key)
            source = { kind: 'io_bit', field: input_ref_to_name.fetch(key), bit: 0 }
            cache[key] = source
            return source
          end

          rhs = definition_map[key].to_s
          if rhs.start_with?('hw.constant ')
            value = parse_hw_constant_bit(rhs)
            source = { kind: 'const', value: value }
            cache[key] = source
            return source
          end

          extract_match = rhs.match(/\Acomb\.extract\s+(%[A-Za-z0-9_.$#-]+(?::\d+)?)\s+from\s+(\d+)/)
          if extract_match
            base = normalize_ref(extract_match[1])
            bit = extract_match[2].to_i
            if state_ref_to_index.key?(base)
              source = { kind: 'state_bit', state_index: state_ref_to_index.fetch(base), bit: bit }
              cache[key] = source
              return source
            end
            if input_ref_to_name.key?(base)
              source = { kind: 'io_bit', field: input_ref_to_name.fetch(base), bit: bit }
              cache[key] = source
              return source
            end

            base_source = resolve_extern_source(
              ref: base,
              definition_map: definition_map,
              state_ref_to_index: state_ref_to_index,
              input_ref_to_name: input_ref_to_name,
              cache: cache,
              depth: depth + 1
            )
            if base_source.fetch(:kind) == 'const'
              source = { kind: 'const', value: base_source.fetch(:value, 0).to_i >> bit & 0x1 }
              cache[key] = source
              return source
            end
          end

          source = { kind: 'unknown' }
          cache[key] = source
          source
        end
        private_class_method :resolve_extern_source

        def parse_hw_constant_bit(rhs)
          value, = parse_hw_constant_value(rhs)
          value & 0x1
        end
        private_class_method :parse_hw_constant_bit

        def parse_hw_constant_value(rhs)
          body = rhs.sub(/\Ahw\.constant\s+/, '').strip
          token, type = body.split(':', 2).map { |part| part.to_s.strip }
          width = type_width(type)
          return [1, width] if token.casecmp('true').zero?
          return [0, width] if token.casecmp('false').zero?

          begin
            value = Integer(token, 0)
            if width.positive?
              mask = (1 << width) - 1
              value &= mask
            end
            [value, width]
          rescue ArgumentError
            [0, width]
          end
        end
        private_class_method :parse_hw_constant_value

        def refresh_instruction_stream_checksum!(stream)
          payload = stream.dup
          payload.delete(:checksum_sha256)
          stream[:checksum_sha256] = Digest::SHA256.hexdigest(JSON.generate(payload))
        end
        private_class_method :refresh_instruction_stream_checksum!

        def known_const_ref?(ref)
          text = ref.to_s
          text.match?(/ctrue|c1\b|true/i) || text.match?(/cfalse|c0\b|false/i)
        end
        private_class_method :known_const_ref?

        def const_ref_value(ref)
          known_const_ref?(ref) && ref.to_s.match?(/ctrue|c1\b|true/i) ? 1 : 0
        end
        private_class_method :const_ref_value

        def build_output_watch_sources(watch_names:, output_ref_map:, node_ref_ids:, extern_ref_ids:, extern_refs:)
          Array(watch_names).filter_map do |name|
            source = output_ref_map[name]
            next unless source

            if source.key?(:ref)
              ref = source.fetch(:ref)
              node_id = node_ref_ids[ref]
              if node_id
                {
                  kind: 'node',
                  id: node_id,
                  inverted: source.fetch(:inverted, false)
                }
              else
                extern_id = extern_ref_ids[ref]
                unless extern_id
                  extern_id = extern_refs.length
                  extern_ref_ids[ref] = extern_id
                  extern_refs << ref
                end
                {
                  kind: 'extern',
                  id: extern_id,
                  inverted: source.fetch(:inverted, false)
                }
              end
            elsif source.key?(:literal)
              literal_ref = source.fetch(:literal) == 'true' ? '%ctrue' : '%cfalse'
              extern_id = extern_ref_ids[literal_ref]
              unless extern_id
                extern_id = extern_refs.length
                extern_ref_ids[literal_ref] = extern_id
                extern_refs << literal_ref
              end
              {
                kind: 'extern',
                id: extern_id,
                inverted: source.fetch(:inverted, false)
              }
            end
          end
        end
        private_class_method :build_output_watch_sources

        def extract_output_ref_map(source)
          output_names = extract_output_names(source)
          output_values = extract_hw_output_values(source)
          return {} if output_names.empty? || output_values.empty?

          output_names.each_with_index.each_with_object({}) do |(name, idx), acc|
            token = output_values[idx]
            parsed = parse_signal_token(token)
            acc[name] = parsed if parsed
          end
        end
        private_class_method :extract_output_ref_map

        def extract_output_names(source)
          signature = source.match(/hw\.module\s+@[^(]+\((.*?)\)\s*\{/m)
          return [] unless signature

          signature[1].scan(/\bout\s+([A-Za-z0-9_.$#-]+)\s*:/).flatten
        end
        private_class_method :extract_output_names

        def extract_hw_output_values(source)
          match = source.match(/hw\.output\s+(.+?)\s*:\s*.+/m)
          return [] unless match

          split_operands(match[1])
        end
        private_class_method :extract_hw_output_values

        def split_operands(text)
          operands = []
          depth = 0
          start = 0
          body = text.to_s.strip
          body.each_char.with_index do |ch, idx|
            case ch
            when '('
              depth += 1
            when ')'
              depth -= 1 if depth.positive?
            when ','
              next unless depth.zero?

              operands << body[start...idx].to_s.strip
              start = idx + 1
            end
          end
          tail = body[start..]
          operands << tail.to_s.strip unless tail.to_s.strip.empty?
          operands
        end
        private_class_method :split_operands

        def parse_signal_token(token)
          body = token.to_s.strip
          return nil if body.empty?

          inverted = false
          if body.start_with?('not ')
            inverted = true
            body = body.sub(/\Anot\s+/, '').strip
          end

          ref_match = body.match(/(%[A-Za-z0-9_.$#-]+(?::\d+)?)/)
          if ref_match
            return {
              ref: normalize_ref(ref_match[1]),
              inverted: inverted
            }
          end

          literal = body.downcase
          if %w[true false 0 1].include?(literal)
            return {
              literal: (%w[true 1].include?(literal) ? 'true' : 'false'),
              inverted: inverted
            }
          end

          nil
        end
        private_class_method :parse_signal_token

        def build_partition_dependency_edges(edge_counts)
          edge_counts.keys.sort_by { |(from, to)| [from, to] }.map do |from, to|
            {
              from: from,
              to: to,
              count: edge_counts.fetch([from, to], 0)
            }
          end
        end
        private_class_method :build_partition_dependency_edges

        def build_execution_plan(stats)
          partition_count = [stats.fetch(:partition_count, 0).to_i, 1].max
          layer_count = [stats.fetch(:max_layer_depth, 0).to_i, 1].max
          dispatch_cycle_granularity = [partition_count * layer_count, 1].max
          partition_order = Array(stats.fetch(:partitions, [])).map { |partition| partition.fetch(:id).to_i }
          dependency_edges = Array(stats.fetch(:partition_dependency_edges, []))
          ready_layers = compute_partition_ready_layers(partition_order: partition_order, dependency_edges: dependency_edges)

          {
            schedule_version: 'GemExecutionPlanV1',
            partition_order: partition_order,
            layer_count: layer_count,
            dispatch_cycle_granularity: dispatch_cycle_granularity,
            partition_dependency_edge_count: dependency_edges.length,
            ready_layer_count: ready_layers.length,
            ready_layers: ready_layers
          }
        end
        private_class_method :build_execution_plan

        def kernel_mode
          ENV.fetch('RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER', '0') == '1' ? 'instruction_stream_control' : 'legacy_eval'
        end
        private_class_method :kernel_mode

        def compute_partition_ready_layers(partition_order:, dependency_edges:)
          return [partition_order] if dependency_edges.empty?

          indegree = {}
          adjacency = Hash.new { |h, k| h[k] = [] }
          partition_order.each { |id| indegree[id] = 0 }

          dependency_edges.each do |edge|
            from = edge.fetch(:from).to_i
            to = edge.fetch(:to).to_i
            next if from == to

            adjacency[from] << to
            indegree[to] = indegree.fetch(to, 0) + 1
            indegree[from] = indegree.fetch(from, 0)
          end

          queue = partition_order.select { |id| indegree.fetch(id, 0).zero? }
          layers = []
          visited = 0

          until queue.empty?
            current = queue.sort
            queue = []
            layers << current
            current.each do |node|
              visited += 1
              adjacency.fetch(node, []).uniq.sort.each do |dst|
                indegree[dst] = indegree.fetch(dst, 0) - 1
                queue << dst if indegree[dst].zero?
              end
            end
          end

          # Fallback for malformed/possibly cyclic metadata: preserve deterministic static order.
          return [partition_order] if visited < partition_order.length

          layers
        end
        private_class_method :compute_partition_ready_layers
      end
    end
  end
end
