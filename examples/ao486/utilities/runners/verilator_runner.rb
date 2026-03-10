# frozen_string_literal: true

require_relative 'backend_runner'

module RHDL
  module Examples
    module AO486
      class VerilatorRunner < BackendRunner
        def initialize(**kwargs)
          super(backend: :verilator, **kwargs)
        end
      end
    end
  end
end
