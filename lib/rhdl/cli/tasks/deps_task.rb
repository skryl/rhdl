# frozen_string_literal: true

require_relative '../task'
require_relative '../config'
require 'json'
require 'open3'
require 'timeout'
require 'tmpdir'

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

          # Check for verilator
          puts
          verilator_available = command_available?('verilator')

          if verilator_available
            version = `verilator --version 2>&1`.lines.first&.strip
            puts "[OK] verilator is installed: #{version}"
          else
            puts "[MISSING] verilator is not installed"
            puts

            install_verilator(platform)

            puts
            if command_available?('verilator')
              version = `verilator --version 2>&1`.lines.first&.strip
              puts "[OK] verilator installed successfully: #{version}"
            else
              puts "[WARN] verilator installation may have failed. Check above for errors."
            end
          end

          # Check for arcilator (CIRCT tools)
          puts
          arcilator_health_checks = arcilator_tool_health_checks
          missing_arcilator_tools = arcilator_health_checks.keys.reject do |tool|
            command_healthy?(tool, arcilator_health_checks.fetch(tool))
          end

          if missing_arcilator_tools.empty?
            version = command_output_first_line(arcilator_health_checks.fetch('firtool'))
            puts "[OK] arcilator tools are installed (firtool: #{version})"
          else
            puts "[MISSING] arcilator tools not fully installed (missing or broken: #{missing_arcilator_tools.join(', ')})"
            puts

            install_arcilator(platform, missing_tools: missing_arcilator_tools)

            puts
            remaining = arcilator_health_checks.keys.reject do |tool|
              command_healthy?(tool, arcilator_health_checks.fetch(tool))
            end
            if remaining.empty?
              version = command_output_first_line(arcilator_health_checks.fetch('firtool'))
              puts "[OK] arcilator tools installed successfully (firtool: #{version})"
            else
              puts "[WARN] arcilator tool installation may have failed (still missing or broken: #{remaining.join(', ')})"
              remaining.each do |tool|
                diagnostic = command_output_first_line(arcilator_health_checks.fetch(tool))
                puts "  #{tool}: #{diagnostic}" if diagnostic && !diagnostic.empty?
              end
              puts "  Install CIRCT tools (firtool, arcilator, llc) from https://github.com/llvm/circt"
            end
          end

          # Check for graphviz (dot)
          puts
          dot_available = command_available?('dot')

          if dot_available
            version = `dot -V 2>&1`.lines.first&.strip
            puts "[OK] graphviz is installed: #{version}"
          else
            puts "[MISSING] graphviz is not installed"
            puts

            install_graphviz(platform)

            puts
            if command_available?('dot')
              version = `dot -V 2>&1`.lines.first&.strip
              puts "[OK] graphviz installed successfully: #{version}"
            else
              puts "[WARN] graphviz installation may have failed. Check above for errors."
            end
          end

          # Check for bun (for web/desktop tooling)
          puts
          bun_available = command_available?('bun')

          if bun_available
            version = `bun --version 2>&1`.lines.first&.strip
            puts "[OK] bun is installed: #{version}"
          else
            puts "[MISSING] bun is not installed"
            puts

            install_bun(platform)

            puts
            if command_available?('bun')
              version = `bun --version 2>&1`.lines.first&.strip
              puts "[OK] bun installed successfully: #{version}"
            else
              bun_bin = File.join(Dir.home, '.bun', 'bin', 'bun')
              if File.exist?(bun_bin)
                version = run_command_with_timeout("#{bun_bin} --version").first.lines.first&.strip
                puts "[OK] bun installed successfully: #{version} (use #{bun_bin} on this machine)"
                ENV['PATH'] = "#{File.join(Dir.home, '.bun', 'bin')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}"
              else
                puts "[WARN] bun installation may have failed. Check above for errors."
              end
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
            'verilator' => { cmd: 'verilator --version', optional: true, desc: 'Verilator (for high-performance Verilog simulation)' },
            'firtool' => { cmd: 'firtool --version', optional: true, desc: 'CIRCT firtool (for Arcilator HDL simulation)' },
            'arcilator' => { cmd: 'arcilator --version', optional: true, desc: 'CIRCT Arcilator (cycle-based HDL simulator)' },
            'dot' => { cmd: 'dot -V', optional: true, desc: 'Graphviz (for diagram rendering)' },
            'bun' => { cmd: 'bun --version', optional: true, desc: 'Bun (for web and desktop tooling)' },
            'ruby' => { cmd: 'ruby --version', optional: false, desc: 'Ruby interpreter' },
            'bundler' => { cmd: 'bundle --version', optional: false, desc: 'Ruby Bundler' }
          }

          deps.each do |name, info|
            available = command_available?(name)
            status = available ? "[OK]" : (info[:optional] ? "[OPTIONAL]" : "[MISSING]")
            version = available ? command_output_first_line(info[:cmd]) : "not installed"

            puts "#{status.ljust(12)} #{name.ljust(12)} - #{info[:desc]}"
            puts "             #{version}" if available
          end

          puts
          puts "Run 'bundle exec rake deps' to install missing dependencies."
        end

        private

        def arcilator_tool_health_checks
          {
            'firtool' => 'firtool --version',
            'arcilator' => 'arcilator --version',
            'llc' => 'llc --version'
          }
        end

        def command_healthy?(tool, version_cmd)
          return false unless command_available?(tool)

          _, status = run_command_with_timeout(version_cmd)
          status&.success? || false
        end

        def command_output_first_line(command)
          output, _status = run_command_with_timeout(command)
          output.lines.first&.strip
        end

        def run_command_with_timeout(command, timeout_seconds: 2)
          output = +""
          status = nil

          Open3.popen2e(command) do |_stdin, stdout_stderr, wait_thr|
            begin
              Timeout.timeout(timeout_seconds) do
                output = stdout_stderr.read
                status = wait_thr.value
              end
            rescue Timeout::Error
              begin
                Process.kill('TERM', wait_thr.pid)
              rescue Errno::ESRCH
                # already exited
              end

              sleep(0.05)

              begin
                Process.kill('KILL', wait_thr.pid)
              rescue Errno::ESRCH
                # already exited
              end

              output = "command timed out after #{timeout_seconds}s"
              status = nil
            end
          end

          [output, status]
        rescue StandardError => e
          ["command failed: #{e.message}", nil]
        end

        def missing_commands(commands)
          commands.reject { |cmd| command_available?(cmd) }
        end

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
          if command_available?('apt-get')
            puts "Installing iverilog via apt-get..."
            if ENV['USER'] == 'root'
              system('apt-get update && apt-get install -y iverilog')
            else
              system('sudo apt-get update && sudo apt-get install -y iverilog')
            end
          else
            puts "apt-get not found. Please install iverilog manually:"
            puts "  sudo apt-get update && sudo apt-get install -y iverilog"
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

        def install_verilator(platform)
          case platform
          when :linux
            install_verilator_linux
          when :macos
            install_verilator_macos
          when :windows
            puts "On Windows, please install verilator manually:"
            puts "  1. Use WSL and install via apt-get"
            puts "  2. Or build from source: https://verilator.org/guide/latest/install.html"
          else
            puts "Unknown platform. Please install verilator manually."
          end
        end

        def install_verilator_linux
          if command_available?('apt-get')
            puts "Installing verilator via apt-get..."
            if ENV['USER'] == 'root'
              system('apt-get update && apt-get install -y verilator')
            else
              system('sudo apt-get update && sudo apt-get install -y verilator')
            end
          else
            puts "apt-get not found. Please install verilator manually:"
            puts "  sudo apt-get update && sudo apt-get install -y verilator"
          end
        end

        def install_verilator_macos
          if command_available?('brew')
            puts "Installing verilator via Homebrew..."
            system('brew install verilator')
          else
            puts "Homebrew not found. Please install Homebrew first:"
            puts "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            puts "Then run: brew install verilator"
          end
        end

        def install_arcilator(platform, missing_tools:)
          case platform
          when :linux
            install_arcilator_linux(missing_tools: missing_tools)
          when :macos
            install_arcilator_macos(missing_tools: missing_tools)
          when :windows
            puts "On Windows, please install CIRCT tools manually:"
            puts "  1. Download prebuilt CIRCT release from: https://github.com/llvm/circt/releases"
            puts "  2. Add firtool/arcilator/llc to PATH"
          else
            puts "Unknown platform. Attempting GitHub prebuilt CIRCT install..."
            install_arcilator_from_release(platform: platform, missing_tools: missing_tools)
          end
        end

        def install_arcilator_linux(missing_tools:)
          if command_available?('apt-get')
            puts "Installing LLVM tools via apt-get..."
            if ENV['USER'] == 'root'
              system('apt-get update && apt-get install -y llvm')
            else
              system('sudo apt-get update && sudo apt-get install -y llvm')
            end

            puts "Installing CIRCT tools via apt-get..."
            if ENV['USER'] == 'root'
              system('apt-get update && apt-get install -y circt')
            else
              system('sudo apt-get update && sudo apt-get install -y circt')
            end
          else
            puts "apt-get not found. Please install CIRCT tools manually:"
            puts "  sudo apt-get update && sudo apt-get install -y circt llvm"
          end

          # Ubuntu repos may not provide circt on all releases (e.g. noble);
          # fall back to prebuilt CIRCT release for missing tools.
          remaining = missing_commands(missing_tools)
          install_arcilator_from_release(platform: :linux, missing_tools: remaining) unless remaining.empty?
        end

        def install_graphviz(platform)
          case platform
          when :linux
            install_graphviz_linux
          when :macos
            install_graphviz_macos
          when :windows
            puts "On Windows, please install Graphviz manually:"
            puts "  https://graphviz.org/download/"
          else
            puts "Unknown platform. Please install graphviz manually."
          end
        end

        def install_graphviz_linux
          if command_available?('apt-get')
            puts "Installing graphviz via apt-get..."
            if ENV['USER'] == 'root'
              system('apt-get update && apt-get install -y graphviz')
            else
              system('sudo apt-get update && sudo apt-get install -y graphviz')
            end
          else
            puts "apt-get not found. Please install graphviz manually:"
            puts "  sudo apt-get update && sudo apt-get install -y graphviz"
          end
        end

        def install_graphviz_macos
          if command_available?('brew')
            puts "Installing graphviz via Homebrew..."
            system('brew install graphviz')
          else
            puts "Homebrew not found. Please install Homebrew first:"
            puts "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            puts "Then run: brew install graphviz"
          end
        end

        def install_bun(platform)
          case platform
          when :linux
            install_bun_linux
          when :macos
            install_bun_macos
          when :windows
            puts "On Windows, please install Bun manually:"
            puts "  https://bun.sh/#installation"
          else
            puts "Unknown platform. Please install bun manually:"
            puts "  https://bun.sh/#installation"
          end
        end

        def install_bun_linux
          if command_available?('curl')
            puts "Installing bun via official install script..."
            system("curl -fsSL https://bun.sh/install | bash")
            export_bun_path
          else
            puts "curl not found. Please install bun manually:"
            puts "  https://bun.sh/#installation"
          end
        end

        def install_bun_macos
          if command_available?('brew')
            puts "Installing bun via Homebrew..."
            system('brew install oven-sh/bun/bun')
            return
          end

          if command_available?('curl')
            puts "Homebrew not found. Installing bun via official script..."
            system("curl -fsSL https://bun.sh/install | bash")
            export_bun_path
          else
            puts "curl not found. Please install bun manually:"
            puts "  https://bun.sh/#installation"
          end
        end

        def export_bun_path
          bun_bin = File.join(Dir.home, '.bun', 'bin', 'bun')
          return unless File.exist?(bun_bin)

          ENV['PATH'] = "#{File.join(Dir.home, '.bun', 'bin')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}"
          puts "Added #{File.join(Dir.home, '.bun', 'bin')} to PATH for current process."
          puts "If bun is still not found, run:"
          puts "  source ~/.bashrc   # or your shell profile"
        end

        def install_arcilator_macos(missing_tools:)
          # CIRCT formula is not consistently available on Homebrew; use GitHub release fallback.
          install_arcilator_from_release(platform: :macos, missing_tools: missing_tools)
        end

        def install_arcilator_from_release(platform:, missing_tools:)
          tools_to_install = missing_tools.dup
          tools_to_install << 'circt-opt' unless tools_to_install.include?('circt-opt')
          release_api = 'https://api.github.com/repos/llvm/circt/releases/latest'
          install_dir = File.expand_path('~/.local/bin')
          lib_install_dir = File.expand_path('~/.local/lib')
          ensure_dir(install_dir)

          puts "Installing CIRCT tools from GitHub prebuilt release..."
          puts "  Target tools: #{tools_to_install.join(', ')}"

          asset_name, fallback_note = circt_release_asset_name_for(platform)
          unless asset_name
            puts "Could not determine a supported CIRCT prebuilt asset for this platform."
            return
          end

          puts "  Using asset: #{asset_name}"
          puts "  Note: #{fallback_note}" if fallback_note

          begin
            metadata_json = `curl -fsSL #{release_api} 2>/dev/null`
            if metadata_json.nil? || metadata_json.strip.empty?
              puts "Failed to download CIRCT release metadata."
              return
            end

            metadata = JSON.parse(metadata_json)
            asset = metadata.fetch('assets', []).find { |item| item['name'] == asset_name }
            unless asset
              puts "CIRCT release asset not found: #{asset_name}"
              return
            end

            Dir.mktmpdir('rhdl-circt-') do |tmp|
              archive_path = File.join(tmp, asset_name)
              extract_dir = File.join(tmp, 'extract')
              ensure_dir(extract_dir)

              puts "  Downloading CIRCT archive..."
              unless system("curl -fL '#{asset['browser_download_url']}' -o '#{archive_path}'")
                puts "Failed to download CIRCT archive."
                return
              end

              puts "  Extracting CIRCT archive..."
              unless system("tar -xzf '#{archive_path}' -C '#{extract_dir}'")
                puts "Failed to extract CIRCT archive."
                return
              end

              source_root = Dir.children(extract_dir)
                               .map { |entry| File.join(extract_dir, entry) }
                               .find { |path| File.directory?(path) }
              unless source_root
                puts "Failed to locate extracted CIRCT directory."
                return
              end

              source_bin_dir = File.join(source_root, 'bin')
              source_lib_dir = File.join(source_root, 'lib')

              tools_to_install.each do |tool|
                source = File.join(source_bin_dir, tool)
                unless File.exist?(source)
                  puts "  Missing tool in archive: #{tool}"
                  next
                end

                target = File.join(install_dir, tool)
                FileUtils.cp(source, target)
                FileUtils.chmod(0o755, target)
              end

              if File.directory?(source_lib_dir)
                ensure_dir(lib_install_dir)
                FileUtils.cp_r(File.join(source_lib_dir, '.'), lib_install_dir)
                puts "  Installed CIRCT shared libraries into #{lib_install_dir}"
              else
                puts "  Could not find CIRCT library directory in archive."
              end
            end
          rescue JSON::ParserError
            puts "Failed to parse CIRCT release metadata."
            return
          end

          puts "Installed CIRCT tools into #{install_dir}"

          path_entries = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)
          unless path_entries.include?(install_dir)
            ENV['PATH'] = "#{install_dir}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}"
            puts
            puts "Updated PATH for current process: #{install_dir}"
            puts "Add it permanently with:"
            puts "  export PATH=\"#{install_dir}:$PATH\""
          end

          if File.directory?(lib_install_dir)
            ld_path = ENV.fetch('LD_LIBRARY_PATH', '')
            ld_entries = ld_path.split(File::PATH_SEPARATOR).reject(&:empty?)
            unless ld_entries.include?(lib_install_dir)
              ENV['LD_LIBRARY_PATH'] = ([lib_install_dir] + ld_entries).join(File::PATH_SEPARATOR)
              puts "Updated LD_LIBRARY_PATH for current process: #{lib_install_dir}"
            end
          end
        end

        def circt_release_asset_name_for(platform)
          arch = host_arch

          case platform
          when :linux
            return ['circt-full-shared-linux-x64.tar.gz', nil] if %i[x64 amd64].include?(arch)
            [nil, nil]
          when :macos
            if %i[x64 amd64].include?(arch)
              ['circt-full-shared-macos-x64.tar.gz', nil]
            elsif %i[arm64 aarch64].include?(arch)
              [
                'circt-full-shared-macos-x64.tar.gz',
                'No native arm64 CIRCT prebuilt found; using x64 build (requires Rosetta on Apple Silicon).'
              ]
            else
              [nil, nil]
            end
          else
            [nil, nil]
          end
        end

        def host_arch
          arch = `uname -m 2>/dev/null`.strip.downcase
          case arch
          when 'x86_64', 'amd64' then :x64
          when 'arm64', 'aarch64' then :arm64
          else
            arch.to_sym
          end
        end
      end
    end
  end
end
