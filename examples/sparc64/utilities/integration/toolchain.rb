# frozen_string_literal: true

module RHDL
  module Examples
    module SPARC64
      module Integration
        module Toolchain
          module_function

          def which(cmd)
            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |path|
              executable = File.join(path, cmd)
              return executable if File.executable?(executable) && !File.directory?(executable)
            end
            nil
          end

          def require_tool!(cmd)
            which(cmd) || raise("required tool not found on PATH: #{cmd}")
          end

          def llvm_mc
            require_tool!('llvm-mc')
          end

          def llvm_objcopy
            require_tool!('llvm-objcopy')
          end

          def ld_lld
            require_tool!('ld.lld')
          end

          def verilator
            require_tool!('verilator')
          end

          def firtool
            require_tool!('firtool')
          end
        end
      end
    end
  end
end
