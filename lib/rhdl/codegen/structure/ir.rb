# Gate-level intermediate representation

require 'json'

module RHDL
  module Codegen
    module Structure
    Gate = Struct.new(:type, :inputs, :output, :value, keyword_init: true)
    DFF = Struct.new(:d, :q, :rst, :en, :async_reset, :reset_value, keyword_init: true)
    SRLatch = Struct.new(:s, :r, :en, :q, :qn, keyword_init: true)

    class IR
      attr_reader :name, :net_count, :gates, :dffs, :sr_latches, :inputs, :outputs, :schedule

      def initialize(name: 'design')
        @name = name
        @net_count = 0
        @gates = []
        @dffs = []
        @sr_latches = []
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

      def add_dff(d:, q:, rst: nil, en: nil, async_reset: false, reset_value: 0)
        @dffs << DFF.new(d: d, q: q, rst: rst, en: en, async_reset: async_reset, reset_value: reset_value)
      end

      def add_sr_latch(s:, r:, en:, q:, qn:)
        @sr_latches << SRLatch.new(s: s, r: r, en: en, q: q, qn: qn)
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
          dffs: @dffs.map { |d| { d: d.d, q: d.q, rst: d.rst, en: d.en, async_reset: d.async_reset, reset_value: d.reset_value } },
          sr_latches: @sr_latches.map { |l| { s: l.s, r: l.r, en: l.en, q: l.q, qn: l.qn } },
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
          ir.add_dff(d: d[:d], q: d[:q], rst: d[:rst], en: d[:en], async_reset: d[:async_reset], reset_value: d[:reset_value] || 0)
        end
        (data[:sr_latches] || []).each do |l|
          ir.add_sr_latch(s: l[:s], r: l[:r], en: l[:en], q: l[:q], qn: l[:qn])
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
