# frozen_string_literal: true

require_relative 'backend_runner'

module RHDL
  module Examples
    module AO486
      class ArcilatorRunner < BackendRunner
        def initialize(**kwargs)
          super(backend: :arcilator, **kwargs)
        end
      end
    end
  end
end
