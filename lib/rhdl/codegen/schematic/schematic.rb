# frozen_string_literal: true

require 'json'
require 'set'
require 'time'

module RHDL
  module Codegen
    module Schematic
      module_function

      def bundle(top_class:, sim_ir:, runner: nil)
        sim_ir_hash = ir_to_hash(sim_ir)
        hier_ir = hierarchical_ir_hash(top_class: top_class, instance_name: 'top', parameters: {}, stack: [])

        live_names = Set.new
        %w[ports nets regs].each do |kind|
          Array(sim_ir_hash[kind]).each do |entry|
            name = entry['name'].to_s.strip
            live_names.add(name) unless name.empty?
          end
        end

        components = []
        walk_hierarchy(hier_ir, live_names: live_names, components: components, path_tokens: [], parent_path: nil)
        components.sort_by! { |entry| entry[:path].to_s }

        {
          format: 'rhdl.web.schematic.v1',
          runner: runner,
          generated_at: Time.now.utc.iso8601,
          top_path: 'top',
          components: components
        }.compact
      end

      def hierarchical_ir_hash(top_class:, instance_name:, parameters:, stack:)
        node = ir_to_hash(top_class.to_ir(parameters: parameters || {}))
        node['instance_name'] = instance_name.to_s
        node['component_class'] = top_class.name.to_s

        class_key = "#{top_class.name}|#{parameters.to_a.sort_by(&:first).inspect}"
        return node if stack.include?(class_key)

        children = []
        instance_defs = top_class.respond_to?(:_instance_defs) ? Array(top_class._instance_defs) : []
        instance_defs.each do |inst|
          child_class = inst[:component_class]
          next unless child_class.respond_to?(:to_ir)

          child_name = inst[:name].to_s
          child_params = inst[:parameters] || {}
          children << hierarchical_ir_hash(
            top_class: child_class,
            instance_name: child_name,
            parameters: child_params,
            stack: stack + [class_key]
          )
        end
        node['children'] = children unless children.empty?
        node
      end

      def walk_hierarchy(node, live_names:, components:, path_tokens:, parent_path:)
        path = path_tokens.empty? ? 'top' : path_tokens.join('.')

        ports = Array(node['ports']).map do |port|
          next unless port.is_a?(Hash)
          name = port['name'].to_s.strip
          next if name.empty?
          ref = signal_ref(name, path_tokens, live_names, width: port['width'])
          {
            name: name,
            direction: port['direction'].to_s,
            width: (port['width'].to_i.positive? ? port['width'].to_i : 1),
            signal: name,
            live_name: ref && ref[:live_name]
          }.compact
        end.compact

        nets = Array(node['nets']).map do |net|
          next unless net.is_a?(Hash)
          name = net['name'].to_s.strip
          next if name.empty?
          ref = signal_ref(name, path_tokens, live_names, width: net['width'])
          {
            name: name,
            width: (net['width'].to_i.positive? ? net['width'].to_i : 1),
            live_name: ref && ref[:live_name]
          }.compact
        end.compact

        regs = Array(node['regs']).map do |reg|
          next unless reg.is_a?(Hash)
          name = reg['name'].to_s.strip
          next if name.empty?
          ref = signal_ref(name, path_tokens, live_names, width: reg['width'])
          {
            name: name,
            width: (reg['width'].to_i.positive? ? reg['width'].to_i : 1),
            live_name: ref && ref[:live_name]
          }.compact
        end.compact

        raw_children = Array(node['children'])
        child_infos = []
        sibling_names = {}
        raw_children.each_with_index do |child, index|
          base_name = derive_component_name(child, "child_#{index}")
          child_name = base_name
          suffix = 1
          while sibling_names[child_name]
            suffix += 1
            child_name = "#{base_name}_#{suffix}"
          end
          sibling_names[child_name] = true
          child_tokens = path_tokens + [child_name]
          child_infos << {
            raw: child,
            name: child_name,
            path: child_tokens.join('.'),
            tokens: child_tokens
          }
        end

        child_port_connections = child_infos.flat_map do |child|
          Array(child[:raw]['ports']).map do |port|
            next unless port.is_a?(Hash)
            port_name = port['name'].to_s.strip
            next if port_name.empty?
            sig_ref = signal_ref(port_name, path_tokens, live_names, width: port['width'])
            {
              child_path: child[:path],
              child_name: child[:name],
              port_name: port_name,
              direction: port['direction'].to_s,
              signal: port_name,
              width: (port['width'].to_i.positive? ? port['width'].to_i : 1),
              live_name: sig_ref && sig_ref[:live_name]
            }.compact
          end
        end.compact

        assigns = Array(node['assigns']).map do |assign|
          target = assign['target'].to_s.strip
          next if target.empty?
          target_ref = signal_ref(target, path_tokens, live_names)
          sources = collect_expr_signal_names(assign['expr']).to_a.sort.map do |name|
            signal_ref(name, path_tokens, live_names)
          end.compact
          {
            target: target,
            target_live_name: target_ref && target_ref[:live_name],
            source_signals: uniq_signal_refs(sources)
          }.compact
        end.compact

        write_ports = Array(node['write_ports']).map do |port|
          clock_ref = signal_ref(port['clock'], path_tokens, live_names)
          {
            memory: port['memory'].to_s,
            addr_signals: port_signal_refs(port['addr'], path_tokens, live_names),
            data_signals: port_signal_refs(port['data'], path_tokens, live_names),
            enable_signals: port_signal_refs(port['enable'], path_tokens, live_names),
            clock_signals: clock_ref ? [clock_ref] : []
          }
        end

        sync_read_ports = Array(node['sync_read_ports']).map do |port|
          clock_ref = signal_ref(port['clock'], path_tokens, live_names)
          data_ref = signal_ref(port['data'], path_tokens, live_names)
          {
            memory: port['memory'].to_s,
            addr_signals: port_signal_refs(port['addr'], path_tokens, live_names),
            enable_signals: port_signal_refs(port['enable'], path_tokens, live_names),
            clock_signals: clock_ref ? [clock_ref] : [],
            data_signals: data_ref ? [data_ref] : []
          }
        end

        component_name = derive_component_name(node, path_tokens.empty? ? 'top' : path_tokens[-1])
        rich_schematic = build_rich_component_schematic(
          path: path,
          component_name: component_name,
          ports: ports,
          nets: nets,
          regs: regs,
          child_infos: child_infos,
          child_port_connections: child_port_connections,
          assigns: assigns,
          write_ports: write_ports,
          sync_read_ports: sync_read_ports
        )

        components << {
          path: path,
          parent_path: parent_path,
          name: component_name,
          instance_name: node['instance_name'],
          module_name: node['name'],
          component_class: node['component_class'],
          children: child_infos.map { |child| { path: child[:path], name: child[:name] } },
          schematic: rich_schematic
        }.compact

        child_infos.each do |child|
          walk_hierarchy(
            child[:raw],
            live_names: live_names,
            components: components,
            path_tokens: child[:tokens],
            parent_path: path
          )
        end
      end

      def build_rich_component_schematic(path:, component_name:, ports:, nets:, regs:, child_infos:, child_port_connections:, assigns:, write_ports:, sync_read_ports:)
        symbols = []
        pins = []
        nets_out = []
        wires = []

        symbol_map = {}
        pin_map = {}
        net_map = {}
        pin_order = Hash.new(0)
        net_endpoint_map = Hash.new { |h, k| h[k] = Set.new }
        net_driver_map = Hash.new { |h, k| h[k] = Set.new }
        net_load_map = Hash.new { |h, k| h[k] = Set.new }
        wire_dedupe = {}

        add_symbol = lambda do |id:, type:, label:, attrs: {}|
          symbol = symbol_map[id]
          if symbol
            symbol[:label] = label unless label.to_s.strip.empty?
            attrs.each { |key, value| symbol[key] = value unless value.nil? || (value.respond_to?(:empty?) && value.empty?) }
            return symbol
          end

          symbol = {
            id: id,
            type: type,
            label: label
          }
          attrs.each { |key, value| symbol[key] = value unless value.nil? || (value.respond_to?(:empty?) && value.empty?) }
          symbol_map[id] = symbol
          symbols << symbol
          symbol
        end

        ensure_pin = lambda do |symbol_id:, key:, name:, direction:, side:, signal_ref: nil|
          pin_id = make_schematic_id('pin', path, symbol_id, key)
          pin = pin_map[pin_id]
          normalized_direction = normalize_direction(direction)
          normalized_side = %w[left right top bottom].include?(side.to_s) ? side.to_s : 'left'
          if pin
            pin[:direction] = 'inout' if pin[:direction] != normalized_direction
            return pin
          end

          order_key = "#{symbol_id}|#{normalized_side}"
          pin_order[order_key] += 1
          pin = {
            id: pin_id,
            symbol_id: symbol_id,
            name: name.to_s,
            direction: normalized_direction,
            side: normalized_side,
            order: pin_order[order_key]
          }
          if signal_ref
            pin[:signal] = signal_ref[:name]
            pin[:live_name] = signal_ref[:live_name] if signal_ref[:live_name]
            pin[:width] = (signal_ref[:width].to_i.positive? ? signal_ref[:width].to_i : 1)
            pin[:bus] = true if pin[:width] > 1
          end
          pin_map[pin_id] = pin
          pins << pin
          pin
        end

        ensure_net = lambda do |signal_ref, declared_kind = nil|
          return nil unless signal_ref.is_a?(Hash)
          signal_name = signal_ref[:name].to_s.strip
          return nil if signal_name.empty?

          net = net_map[signal_name]
          if net
            width = signal_ref[:width].to_i
            if width.positive? && (!net[:width] || net[:width].to_i <= 1)
              net[:width] = width
              net[:bus] = true if width > 1
            end
            if (net[:live_name].to_s.empty?) && !signal_ref[:live_name].to_s.empty?
              net[:live_name] = signal_ref[:live_name]
            end
            return net
          end

          width = signal_ref[:width].to_i
          width = 1 unless width.positive?
          net = {
            id: make_schematic_id('net', path, signal_name),
            name: signal_name,
            width: width,
            live_name: signal_ref[:live_name],
            bus: width > 1,
            group: signal_group_name(signal_name)
          }.compact
          net[:declared_kind] = declared_kind if declared_kind
          nets_out << net
          net_map[signal_name] = net
          net
        end

        add_wire = lambda do |from_pin:, to_pin:, signal_ref:, kind:, direction:|
          return unless from_pin && to_pin && signal_ref

          net = ensure_net.call(signal_ref)
          return unless net

          normalized_direction = normalize_direction(direction)
          key = [from_pin[:id], to_pin[:id], net[:id], kind.to_s, normalized_direction].join('|')
          return if wire_dedupe[key]

          wire_dedupe[key] = true
          wire = {
            id: make_schematic_id('wire', path, kind, wires.length + 1),
            net_id: net[:id],
            from_pin_id: from_pin[:id],
            to_pin_id: to_pin[:id],
            kind: kind.to_s,
            direction: normalized_direction,
            signal: signal_ref[:name],
            live_name: signal_ref[:live_name],
            width: signal_ref[:width].to_i.positive? ? signal_ref[:width].to_i : 1
          }.compact
          wires << wire

          net_endpoint_map[net[:id]].add(from_pin[:id])
          net_endpoint_map[net[:id]].add(to_pin[:id])
          if normalized_direction == 'inout'
            net_driver_map[net[:id]].add(from_pin[:id])
            net_driver_map[net[:id]].add(to_pin[:id])
            net_load_map[net[:id]].add(from_pin[:id])
            net_load_map[net[:id]].add(to_pin[:id])
          else
            net_driver_map[net[:id]].add(from_pin[:id])
            net_load_map[net[:id]].add(to_pin[:id])
          end
        end

        focus_symbol_id = make_schematic_id('sym', path, 'self')
        add_symbol.call(id: focus_symbol_id, type: 'focus', label: component_name, attrs: { component_path: path })

        child_symbol_ids = {}
        child_infos.each do |child|
          child_id = make_schematic_id('sym', path, 'child', child[:name])
          child_symbol_ids[child[:path]] = child_id
          add_symbol.call(
            id: child_id,
            type: 'component',
            label: child[:name],
            attrs: {
              component_path: child[:path],
              instance_name: child[:name]
            }
          )
        end

        ports.each do |port|
          direction = normalize_direction(port[:direction])
          signal = port[:signal] || port[:name]
          signal_ref = {
            name: signal.to_s,
            live_name: port[:live_name],
            width: (port[:width].to_i.positive? ? port[:width].to_i : 1)
          }
          ensure_net.call(signal_ref, :port)

          io_symbol_id = make_schematic_id('sym', path, 'io', port[:name])
          add_symbol.call(
            id: io_symbol_id,
            type: 'io',
            label: port[:name],
            attrs: {
              direction: direction
            }
          )

          io_pin = ensure_pin.call(
            symbol_id: io_symbol_id,
            key: "io_#{port[:name]}",
            name: port[:name],
            direction: (direction == 'in' ? 'out' : direction == 'out' ? 'in' : 'inout'),
            side: (direction == 'in' ? 'right' : direction == 'out' ? 'left' : 'left'),
            signal_ref: signal_ref
          )
          self_pin = ensure_pin.call(
            symbol_id: focus_symbol_id,
            key: "self_#{signal_ref[:name]}",
            name: signal_ref[:name],
            direction: direction,
            side: (direction == 'in' ? 'left' : direction == 'out' ? 'right' : 'top'),
            signal_ref: signal_ref
          )

          if direction == 'in'
            add_wire.call(from_pin: io_pin, to_pin: self_pin, signal_ref: signal_ref, kind: :io_port, direction: :in)
          elsif direction == 'out'
            add_wire.call(from_pin: self_pin, to_pin: io_pin, signal_ref: signal_ref, kind: :io_port, direction: :out)
          else
            add_wire.call(from_pin: io_pin, to_pin: self_pin, signal_ref: signal_ref, kind: :io_port, direction: :inout)
          end
        end

        (nets + regs).each do |entry|
          signal_ref = {
            name: entry[:name].to_s,
            live_name: entry[:live_name],
            width: (entry[:width].to_i.positive? ? entry[:width].to_i : 1)
          }
          declared_kind = regs.include?(entry) ? :reg : :net
          ensure_net.call(signal_ref, declared_kind)
          ensure_pin.call(
            symbol_id: focus_symbol_id,
            key: "self_#{signal_ref[:name]}",
            name: signal_ref[:name],
            direction: 'inout',
            side: (signal_ref[:width].to_i > 1 ? 'bottom' : 'top'),
            signal_ref: signal_ref
          )
        end

        child_port_connections.each do |conn|
          child_symbol_id = child_symbol_ids[conn[:child_path]]
          next unless child_symbol_id

          direction = normalize_direction(conn[:direction])
          signal_ref = {
            name: conn[:signal].to_s,
            live_name: conn[:live_name],
            width: (conn[:width].to_i.positive? ? conn[:width].to_i : 1)
          }
          ensure_net.call(signal_ref, :child_port)

          self_pin = ensure_pin.call(
            symbol_id: focus_symbol_id,
            key: "self_#{signal_ref[:name]}",
            name: signal_ref[:name],
            direction: 'inout',
            side: (direction == 'out' ? 'left' : 'right'),
            signal_ref: signal_ref
          )
          child_pin = ensure_pin.call(
            symbol_id: child_symbol_id,
            key: "child_#{conn[:port_name]}",
            name: conn[:port_name].to_s,
            direction: direction,
            side: (direction == 'in' ? 'left' : direction == 'out' ? 'right' : 'top'),
            signal_ref: signal_ref
          )

          if direction == 'out'
            add_wire.call(from_pin: child_pin, to_pin: self_pin, signal_ref: signal_ref, kind: :child_port, direction: :out)
          elsif direction == 'in'
            add_wire.call(from_pin: self_pin, to_pin: child_pin, signal_ref: signal_ref, kind: :child_port, direction: :in)
          else
            add_wire.call(from_pin: child_pin, to_pin: self_pin, signal_ref: signal_ref, kind: :child_port, direction: :inout)
          end
        end

        assigns.each_with_index do |assign, idx|
          target_name = assign[:target].to_s.strip
          next if target_name.empty?

          op_symbol_id = make_schematic_id('sym', path, 'op', 'assign', idx + 1)
          add_symbol.call(
            id: op_symbol_id,
            type: 'op',
            label: "= #{target_name}",
            attrs: {
              op_kind: 'assign'
            }
          )

          target_ref = {
            name: target_name,
            live_name: assign[:target_live_name],
            width: 1
          }
          ensure_net.call(target_ref, :assign_target)
          op_out_pin = ensure_pin.call(
            symbol_id: op_symbol_id,
            key: 'out',
            name: 'out',
            direction: 'out',
            side: 'right',
            signal_ref: target_ref
          )
          self_target_pin = ensure_pin.call(
            symbol_id: focus_symbol_id,
            key: "self_#{target_ref[:name]}",
            name: target_ref[:name],
            direction: 'inout',
            side: 'right',
            signal_ref: target_ref
          )
          add_wire.call(from_pin: op_out_pin, to_pin: self_target_pin, signal_ref: target_ref, kind: :assign_target, direction: :out)

          Array(assign[:source_signals]).each_with_index do |source_ref, source_idx|
            next unless source_ref.is_a?(Hash)
            source_name = source_ref[:name].to_s.strip
            next if source_name.empty?

            normalized_source = {
              name: source_name,
              live_name: source_ref[:live_name],
              width: source_ref[:width].to_i.positive? ? source_ref[:width].to_i : 1
            }
            ensure_net.call(normalized_source, :assign_source)
            self_source_pin = ensure_pin.call(
              symbol_id: focus_symbol_id,
              key: "self_#{normalized_source[:name]}",
              name: normalized_source[:name],
              direction: 'inout',
              side: 'right',
              signal_ref: normalized_source
            )
            op_in_pin = ensure_pin.call(
              symbol_id: op_symbol_id,
              key: "in_#{source_idx + 1}",
              name: "in#{source_idx + 1}",
              direction: 'in',
              side: 'left',
              signal_ref: normalized_source
            )
            add_wire.call(from_pin: self_source_pin, to_pin: op_in_pin, signal_ref: normalized_source, kind: :assign_source, direction: :in)
          end
        end

        memory_symbol_ids = {}
        ensure_memory_symbol = lambda do |memory_name|
          mem = memory_name.to_s.strip
          return nil if mem.empty?
          return memory_symbol_ids[mem] if memory_symbol_ids.key?(mem)

          mem_id = make_schematic_id('sym', path, 'memory', mem)
          add_symbol.call(
            id: mem_id,
            type: 'memory',
            label: mem,
            attrs: {
              memory_name: mem
            }
          )
          memory_symbol_ids[mem] = mem_id
          mem_id
        end

        append_memory_signal_wires = lambda do |memory_symbol_id:, signal_refs:, pin_prefix:, kind:, direction:, memory_pin_side:, self_pin_side:|
          Array(signal_refs).each_with_index do |sig, idx|
            next unless sig.is_a?(Hash)
            sig_name = sig[:name].to_s.strip
            next if sig_name.empty?

            signal_ref = {
              name: sig_name,
              live_name: sig[:live_name],
              width: sig[:width].to_i.positive? ? sig[:width].to_i : 1
            }
            ensure_net.call(signal_ref, :memory)
            self_pin = ensure_pin.call(
              symbol_id: focus_symbol_id,
              key: "self_#{signal_ref[:name]}",
              name: signal_ref[:name],
              direction: 'inout',
              side: self_pin_side,
              signal_ref: signal_ref
            )
            mem_pin = ensure_pin.call(
              symbol_id: memory_symbol_id,
              key: "#{pin_prefix}_#{idx + 1}",
              name: "#{pin_prefix}#{idx + 1}",
              direction: direction,
              side: memory_pin_side,
              signal_ref: signal_ref
            )
            if direction == 'out'
              add_wire.call(from_pin: mem_pin, to_pin: self_pin, signal_ref: signal_ref, kind: kind, direction: :out)
            else
              add_wire.call(from_pin: self_pin, to_pin: mem_pin, signal_ref: signal_ref, kind: kind, direction: :in)
            end
          end
        end

        write_ports.each_with_index do |port, idx|
          memory_symbol_id = ensure_memory_symbol.call(port[:memory])
          next unless memory_symbol_id

          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:addr_signals],
            pin_prefix: "wr_addr_#{idx + 1}",
            kind: :mem_write_addr,
            direction: 'in',
            memory_pin_side: 'left',
            self_pin_side: 'right'
          )
          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:data_signals],
            pin_prefix: "wr_data_#{idx + 1}",
            kind: :mem_write_data,
            direction: 'in',
            memory_pin_side: 'left',
            self_pin_side: 'right'
          )
          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:enable_signals],
            pin_prefix: "wr_en_#{idx + 1}",
            kind: :mem_write_enable,
            direction: 'in',
            memory_pin_side: 'left',
            self_pin_side: 'right'
          )
          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:clock_signals],
            pin_prefix: "wr_clk_#{idx + 1}",
            kind: :mem_write_clock,
            direction: 'in',
            memory_pin_side: 'left',
            self_pin_side: 'left'
          )
        end

        sync_read_ports.each_with_index do |port, idx|
          memory_symbol_id = ensure_memory_symbol.call(port[:memory])
          next unless memory_symbol_id

          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:addr_signals],
            pin_prefix: "rd_addr_#{idx + 1}",
            kind: :mem_read_addr,
            direction: 'in',
            memory_pin_side: 'left',
            self_pin_side: 'right'
          )
          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:enable_signals],
            pin_prefix: "rd_en_#{idx + 1}",
            kind: :mem_read_enable,
            direction: 'in',
            memory_pin_side: 'left',
            self_pin_side: 'right'
          )
          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:clock_signals],
            pin_prefix: "rd_clk_#{idx + 1}",
            kind: :mem_read_clock,
            direction: 'in',
            memory_pin_side: 'left',
            self_pin_side: 'left'
          )
          append_memory_signal_wires.call(
            memory_symbol_id: memory_symbol_id,
            signal_refs: port[:data_signals],
            pin_prefix: "rd_data_#{idx + 1}",
            kind: :mem_read_data,
            direction: 'out',
            memory_pin_side: 'right',
            self_pin_side: 'right'
          )
        end

        nets_out.each do |net|
          endpoints = net_endpoint_map[net[:id]].to_a.sort
          drivers = net_driver_map[net[:id]].to_a.sort
          loads = net_load_map[net[:id]].to_a.sort
          net[:endpoint_pin_ids] = endpoints unless endpoints.empty?
          net[:driver_pin_ids] = drivers unless drivers.empty?
          net[:load_pin_ids] = loads unless loads.empty?
        end

        symbols.sort_by! { |entry| [entry[:type].to_s, entry[:label].to_s] }
        pins.sort_by! { |entry| [entry[:symbol_id].to_s, entry[:side].to_s, entry[:order].to_i, entry[:name].to_s] }
        nets_out.sort_by! { |entry| entry[:name].to_s }

        {
          symbols: symbols,
          pins: pins,
          nets: nets_out,
          wires: wires
        }
      end

      def collect_expr_signal_names(expr, out = Set.new)
        case expr
        when Hash
          if expr['type'] == 'signal' && expr['name'].is_a?(String) && !expr['name'].strip.empty?
            out.add(expr['name'].strip)
          end
          expr.each_value { |value| collect_expr_signal_names(value, out) }
        when Array
          expr.each { |entry| collect_expr_signal_names(entry, out) }
        end
        out
      end

      def port_signal_refs(port_expr, path_tokens, signal_set)
        names = collect_expr_signal_names(port_expr).to_a
        uniq_signal_refs(names.map { |name| signal_ref(name, path_tokens, signal_set) })
      end

      def uniq_signal_refs(refs)
        seen = {}
        refs.each_with_object([]) do |ref, out|
          next unless ref
          key = ref[:name].to_s
          next if key.empty? || seen[key]
          seen[key] = true
          out << ref
        end
      end

      def signal_ref(name, path_tokens, signal_set, width: nil)
        signal_name = name.to_s.strip
        return nil if signal_name.empty?

        live_name = resolve_live_signal_name(signal_name, path_tokens, signal_set)
        ref = { name: signal_name }
        ref[:live_name] = live_name if live_name
        ref[:width] = width.to_i if width && width.to_i.positive?
        ref
      end

      def resolve_live_signal_name(signal_name, path_tokens, signal_set)
        raw = signal_name.to_s.strip
        return nil if raw.empty?

        normalized = raw.tr('.', '__')
        candidates = [raw, normalized]
        if path_tokens && !path_tokens.empty?
          joined = path_tokens.join('__')
          tail = path_tokens[-1]
          candidates << "#{joined}__#{raw}"
          candidates << "#{joined}__#{normalized}"
          candidates << "#{tail}__#{raw}"
          candidates << "#{tail}__#{normalized}"
        end
        candidates.find { |candidate| signal_set.include?(candidate) }
      end

      def derive_component_name(obj, fallback)
        if obj.is_a?(Hash)
          %w[instance_name inst_name instance name id module component label].each do |key|
            value = obj[key]
            return value.to_s.strip unless value.to_s.strip.empty?
          end
        end
        fallback
      end

      def normalize_direction(value)
        raw = value.to_s.strip.downcase
        return 'in' if %w[in input].include?(raw)
        return 'out' if %w[out output].include?(raw)

        'inout'
      end

      def signal_group_name(signal_name)
        name = signal_name.to_s.strip
        return nil if name.empty?

        if name.include?('__')
          name.split('__', 2).first
        elsif name.include?('_')
          name.split('_', 2).first
        else
          name
        end
      end

      def make_schematic_id(prefix, *parts)
        tokens = parts.flatten.compact.map { |part| normalize_schematic_token(part) }.reject(&:empty?)
        ([normalize_schematic_token(prefix)] + tokens).join(':')
      end

      def normalize_schematic_token(value, fallback = 'x')
        token = value.to_s.strip
        token = fallback if token.empty?
        token = token.gsub(/[^a-zA-Z0-9]+/, '_')
        token = token.gsub(/\A_+|_+\z/, '')
        token.empty? ? fallback : token.downcase
      end

      def ir_to_hash(ir_obj)
        return ir_obj if ir_obj.is_a?(Hash)
        return JSON.parse(ir_obj, max_nesting: false) if ir_obj.is_a?(String)

        JSON.parse(RHDL::Codegen::IR::IRToJson.convert(ir_obj), max_nesting: false)
      end
    end
  end
end
