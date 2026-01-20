# Gate-level intermediate representation

require 'json'

module RHDL
  module Codegen
    module Structure
    Gate = Struct.new(:type, :inputs, :output, :value, keyword_init: true)
    DFF = Struct.new(:d, :q, :rst, :en, :async_reset, keyword_init: true)

    class IR
      attr_reader :name, :net_count, :gates, :dffs, :inputs, :outputs, :schedule

      def initialize(name: 'design')
        @name = name
        @net_count = 0
        @gates = []
        @dffs = []
        @inputs = {}
        @outputs = {}
        @schedule = []
      end

      def new_net
        idx = @net_count
        @net_count += 1
        idx
      end

      def add_gate(type:, inputs:, output:, value: nil)
        @gates << Gate.new(type: type, inputs: inputs, output: output, value: value)
      end

      def add_dff(d:, q:, rst: nil, en: nil, async_reset: false)
        @dffs << DFF.new(d: d, q: q, rst: rst, en: en, async_reset: async_reset)
      end

      def add_input(name, nets)
        @inputs[name] = nets
      end

      def add_output(name, nets)
        @outputs[name] = nets
      end

      def set_schedule(order)
        @schedule = order
      end

      def to_h
        {
          name: @name,
          net_count: @net_count,
          gates: @gates.map { |g| { type: g.type, inputs: g.inputs, output: g.output, value: g.value } },
          dffs: @dffs.map { |d| { d: d.d, q: d.q, rst: d.rst, en: d.en, async_reset: d.async_reset } },
          inputs: @inputs,
          outputs: @outputs,
          schedule: @schedule
        }
      end

      def to_json(*_args)
        JSON.pretty_generate(to_h)
      end

      def self.from_json(json)
        data = JSON.parse(json, symbolize_names: true)
        ir = new(name: data[:name])
        ir.instance_variable_set(:@net_count, data[:net_count])
        data[:gates].each do |g|
          ir.add_gate(type: g[:type].to_sym, inputs: g[:inputs], output: g[:output], value: g[:value])
        end
        data[:dffs].each do |d|
          ir.add_dff(d: d[:d], q: d[:q], rst: d[:rst], en: d[:en], async_reset: d[:async_reset])
        end
        data[:inputs].each { |name, nets| ir.add_input(name, nets) }
        data[:outputs].each { |name, nets| ir.add_output(name, nets) }
        ir.set_schedule(data[:schedule])
        ir
      end
    end
    end
  end
end
