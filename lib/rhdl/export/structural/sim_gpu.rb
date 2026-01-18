# GPU backend stub for gate-level simulation

module RHDL
  module Export
    module Structural
      class SimGPU
        def self.available?
          false
        end

        def initialize(_ir, **_opts)
          raise LoadError, 'GPU backend not built. Build the GPU extension to enable this backend.'
        end
      end
    end
  end
end
