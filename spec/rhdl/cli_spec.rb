# frozen_string_literal: true

RSpec.describe "RHDL CLI" do
  let(:exe_path) { File.expand_path("../../exe/rhdl", __dir__) }

  def run_cli(*args)
    output = `bundle exec #{exe_path} #{args.join(' ')} 2>&1`
    [output, $?.exitstatus]
  end

  describe "help commands" do
    it "shows help with no arguments" do
      output, status = run_cli
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl <command>")
      expect(output).to include("tui")
      expect(output).to include("diagram")
      expect(output).to include("export")
      expect(output).to include("gates")
    end

    it "shows help with --help" do
      output, status = run_cli("--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl <command>")
    end

    it "shows help with -h" do
      output, status = run_cli("-h")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl <command>")
    end

    it "shows help with 'help' command" do
      output, status = run_cli("help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl <command>")
    end

    it "fails with unknown command" do
      output, status = run_cli("unknown_command")
      expect(status).to eq(1)
      expect(output).to include("Unknown command: unknown_command")
    end
  end

  describe "tui command" do
    it "shows tui help with --help" do
      output, status = run_cli("tui", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl tui")
      expect(output).to include("ComponentRef")
    end

    it "lists available components with --list" do
      output, status = run_cli("tui", "--list")
      expect(status).to eq(0)
      expect(output).to include("Available Components:")
      expect(output).to include("sequential/counter")
    end

    it "fails gracefully with unknown component" do
      output, status = run_cli("tui", "NonExistent::Component")
      expect(status).to eq(1)
      expect(output).to include("Component not found")
    end

    it "loads RHDL::HDL::Counter component without namespace errors" do
      # Use timeout to kill TUI before it blocks on curses input
      # This test verifies the component loads without NameError
      output = `timeout 0.5 bundle exec #{exe_path} tui RHDL::HDL::Counter 2>&1 || true`
      # Should NOT have "uninitialized constant" error
      expect(output).not_to include("uninitialized constant")
      expect(output).not_to include("NameError")
    end

    it "loads component by short name without errors" do
      output = `timeout 0.5 bundle exec #{exe_path} tui sequential/counter 2>&1 || true`
      expect(output).not_to include("uninitialized constant")
      expect(output).not_to include("NameError")
    end
  end

  describe "diagram command" do
    it "shows diagram help with --help" do
      output, status = run_cli("diagram", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl diagram")
      expect(output).to include("--level")
      expect(output).to include("--format")
    end
  end

  describe "export command" do
    it "shows export help with --help" do
      output, status = run_cli("export", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl export")
    end
  end

  describe "gates command" do
    it "shows gates help with --help" do
      output, status = run_cli("gates", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl gates")
    end
  end

  describe "apple2 command" do
    it "shows apple2 help with --help" do
      output, status = run_cli("apple2", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl apple2")
    end
  end

  describe "generate command" do
    it "shows generate help with --help" do
      output, status = run_cli("generate", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl generate")
    end
  end

  describe "clean command" do
    it "shows clean help with --help" do
      output, status = run_cli("clean", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl clean")
    end
  end

  describe "regenerate command" do
    it "shows regenerate help with --help" do
      output, status = run_cli("regenerate", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl regenerate")
    end
  end

  describe "command aliases" do
    it "accepts 'diagrams' as alias for 'diagram'" do
      output, status = run_cli("diagrams", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl diagram")
    end

    it "accepts 'exports' as alias for 'export'" do
      output, status = run_cli("exports", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl export")
    end

    it "accepts 'gate' as alias for 'gates'" do
      output, status = run_cli("gate", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl gates")
    end

    it "accepts 'generate_all' as alias for 'generate'" do
      output, status = run_cli("generate_all", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl generate")
    end

    it "accepts 'clean_all' as alias for 'clean'" do
      output, status = run_cli("clean_all", "--help")
      expect(status).to eq(0)
      expect(output).to include("Usage: rhdl clean")
    end
  end
end
