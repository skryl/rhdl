# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for managing test dependencies
      class DepsTask < Task
        def run
          if options[:check]
            check_status
          else
            install
          end
        end

        # Install test dependencies
        def install
          puts_header("RHDL Test Dependencies Installer")

          platform = detect_platform
          puts "Platform: #{platform}"
          puts

          # Check for iverilog
          iverilog_available = command_available?('iverilog')

          if iverilog_available
            version = `iverilog -V 2>&1`.lines.first&.strip
            puts "[OK] iverilog is installed: #{version}"
          else
            puts "[MISSING] iverilog is not installed"
            puts

            install_iverilog(platform)

            puts
            if command_available?('iverilog')
              version = `iverilog -V 2>&1`.lines.first&.strip
              puts "[OK] iverilog installed successfully: #{version}"
            else
              puts "[WARN] iverilog installation may have failed. Check above for errors."
            end
          end

          puts
          puts '=' * 50
          puts "Dependency check complete."
        end

        # Check test dependencies status
        def check_status
          puts_header("RHDL Test Dependencies Status")

          deps = {
            'iverilog' => { cmd: 'iverilog -V', optional: true, desc: 'Icarus Verilog (for gate-level simulation tests)' },
            'dot' => { cmd: 'dot -V', optional: true, desc: 'Graphviz (for diagram rendering)' },
            'ruby' => { cmd: 'ruby --version', optional: false, desc: 'Ruby interpreter' },
            'bundler' => { cmd: 'bundle --version', optional: false, desc: 'Ruby Bundler' }
          }

          deps.each do |name, info|
            available = command_available?(name)
            status = available ? "[OK]" : (info[:optional] ? "[OPTIONAL]" : "[MISSING]")
            version = available ? `#{info[:cmd]} 2>&1`.lines.first&.strip : "not installed"

            puts "#{status.ljust(12)} #{name.ljust(12)} - #{info[:desc]}"
            puts "             #{version}" if available
          end

          puts
          puts "Run 'rake dev:deps:install' to install missing dependencies."
        end

        private

        def detect_platform
          case RUBY_PLATFORM
          when /linux/i then :linux
          when /darwin/i then :macos
          when /mswin|mingw|cygwin/i then :windows
          else :unknown
          end
        end

        def install_iverilog(platform)
          case platform
          when :linux
            install_iverilog_linux
          when :macos
            install_iverilog_macos
          when :windows
            puts "On Windows, please install iverilog manually:"
            puts "  1. Download from: http://bleyer.org/icarus/"
            puts "  2. Or use WSL and install via apt-get"
          else
            puts "Unknown platform. Please install iverilog manually."
          end
        end

        def install_iverilog_linux
          if File.exist?('/etc/debian_version') || command_available?('apt-get')
            puts "Installing iverilog via apt-get..."
            if ENV['USER'] == 'root'
              system('apt-get update && apt-get install -y iverilog')
            else
              system('sudo apt-get update && sudo apt-get install -y iverilog')
            end
          elsif command_available?('dnf')
            puts "Installing iverilog via dnf..."
            system('sudo dnf install -y iverilog')
          elsif command_available?('yum')
            puts "Installing iverilog via yum..."
            system('sudo yum install -y iverilog')
          elsif command_available?('pacman')
            puts "Installing iverilog via pacman..."
            system('sudo pacman -S --noconfirm iverilog')
          else
            puts "Could not detect package manager."
            puts "Please install iverilog manually:"
            puts "  Ubuntu/Debian: sudo apt-get install iverilog"
            puts "  Fedora: sudo dnf install iverilog"
            puts "  Arch: sudo pacman -S iverilog"
          end
        end

        def install_iverilog_macos
          if command_available?('brew')
            puts "Installing iverilog via Homebrew..."
            system('brew install icarus-verilog')
          else
            puts "Homebrew not found. Please install Homebrew first:"
            puts "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            puts "Then run: brew install icarus-verilog"
          end
        end
      end
    end
  end
end
