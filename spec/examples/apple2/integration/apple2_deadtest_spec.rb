# frozen_string_literal: true

require 'fileutils'
require 'open-uri'
require_relative '../../../../examples/mos6502/utilities/apple2/harness'

RSpec.describe 'Apple ][ dead test ROM', skip: 'Requires network access to download ROM' do
  DEADTEST_URL = 'https://github.com/misterblack1/appleII_deadtest/releases/download/v1.0.1/apple2dead.bin'
  FIXTURE_DIR = File.join(__dir__, 'fixtures', 'apple2')
  FIXTURE_PATH = File.join(FIXTURE_DIR, 'apple2dead.bin')

  def load_deadtest_rom
    FileUtils.mkdir_p(FIXTURE_DIR)
    unless File.exist?(FIXTURE_PATH)
      URI.open(DEADTEST_URL) do |remote|
        File.open(FIXTURE_PATH, 'wb') { |file| file.write(remote.read) }
      end
    end
    File.binread(FIXTURE_PATH)
  end

  def boot_deadtest
    runner = Apple2Harness::Runner.new
    runner.load_rom(load_deadtest_rom, base_addr: 0xF800)
    runner.reset
    runner
  end

  it 'beeps the speaker after reset' do
    runner = boot_deadtest
    runner.run_until(max_cycles: 50_000) { runner.bus.speaker_toggles.positive? }
    expect(runner.bus.speaker_toggles).to be > 0
  end

  it 'enters text mode via soft switches' do
    runner = boot_deadtest
    runner.run_until(max_cycles: 80_000) { runner.bus.soft_switch_accessed?(0xC051) }
    expect(runner.bus.soft_switch_accessed?(0xC051)).to be(true)
    expect(runner.bus.video[:text]).to be(true)
  end

  it 'writes to text page memory' do
    runner = boot_deadtest
    runner.run_steps(120_000)
    expect(runner.bus.text_page_written?).to be(true)
  end
end
