# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../../examples/apple2/hdl/audio_pwm'
require_relative '../../../support/vhdl_reference_helper'
require_relative '../../../support/hdl_toolchain'

RSpec.describe RHDL::Apple2::AudioPWM do
  extend VhdlReferenceHelper
  let(:pwm) { described_class.new('pwm') }

  before do
    pwm
    pwm.set_input(:clk, 0)
    pwm.set_input(:audio, 0)
  end

  def clock_cycle
    pwm.set_input(:clk, 0)
    pwm.propagate
    pwm.set_input(:clk, 1)
    pwm.propagate
  end

  def run_pwm_period
    # Run for one complete PWM period (256 cycles)
    high_count = 0
    256.times do
      clock_cycle
      high_count += 1 if pwm.get_output(:aud_pwm) == 1
    end
    high_count
  end

  describe 'PWM generation' do
    # Reference: PWM output is high when counter < audio_latched
    # Period is 256 cycles (8-bit counter)

    it 'generates PWM based on audio input value' do
      pwm.set_input(:audio, 128)  # 50% duty cycle

      high_count = run_pwm_period

      # Should be approximately 50% (128/256)
      expect(high_count).to be_within(10).of(128)
    end

    it 'generates 0% duty cycle for audio=0' do
      pwm.set_input(:audio, 0)

      high_count = run_pwm_period

      # Should be very low (only first cycle is high)
      expect(high_count).to be <= 2
    end

    it 'generates 100% duty cycle for audio=255' do
      pwm.set_input(:audio, 255)

      high_count = run_pwm_period

      # Should be nearly 100%
      expect(high_count).to be >= 254
    end

    it 'generates proportional duty cycle' do
      duty_cycles = {}

      [0, 64, 128, 192, 255].each do |level|
        pwm.set_input(:audio, level)
        high_count = run_pwm_period
        duty_cycles[level] = high_count
      end

      # Duty cycle should increase with audio level
      expect(duty_cycles[64]).to be > duty_cycles[0]
      expect(duty_cycles[128]).to be > duty_cycles[64]
      expect(duty_cycles[192]).to be > duty_cycles[128]
      expect(duty_cycles[255]).to be > duty_cycles[192]
    end
  end

  describe 'audio sample latching' do
    # Reference: Audio is latched at start of each PWM period (counter == 0)

    it 'latches audio at start of period' do
      # Set initial audio value
      pwm.set_input(:audio, 100)

      # Run part of a period to latch it
      clock_cycle

      # Change audio value mid-period
      pwm.set_input(:audio, 200)

      # Complete the period
      255.times { clock_cycle }

      # Start new period - should latch new value
      pwm.set_input(:audio, 50)
      clock_cycle

      # Change again mid-period
      pwm.set_input(:audio, 250)

      # The latched value should be 50, not 250
      # Complete period and measure
      high_count = 0
      255.times do
        clock_cycle
        high_count += 1 if pwm.get_output(:aud_pwm) == 1
      end

      # Should be approximately 50/256 duty cycle (plus initial 1)
      expect(high_count).to be_within(10).of(50)
    end
  end

  describe 'PWM output signal' do
    it 'outputs valid 1-bit signal' do
      pwm.set_input(:audio, 128)

      100.times do
        clock_cycle
        aud_pwm = pwm.get_output(:aud_pwm)
        expect([0, 1]).to include(aud_pwm)
      end
    end

    it 'starts high at beginning of period' do
      # Counter starts at 0, so first cycle should be high
      pwm.set_input(:audio, 100)
      clock_cycle

      aud_pwm = pwm.get_output(:aud_pwm)
      expect(aud_pwm).to eq(1)
    end
  end

  describe 'audio shutdown signal' do
    # Reference: aud_sd is always 1 (audio enabled)

    it 'keeps audio enabled (aud_sd = 1)' do
      pwm.set_input(:audio, 0)
      clock_cycle

      aud_sd = pwm.get_output(:aud_sd)
      expect(aud_sd).to eq(1)
    end

    it 'maintains aud_sd regardless of audio level' do
      [0, 128, 255].each do |level|
        pwm.set_input(:audio, level)
        clock_cycle

        aud_sd = pwm.get_output(:aud_sd)
        expect(aud_sd).to eq(1)
      end
    end
  end

  describe '8-bit counter' do
    # Reference: Counter increments each cycle, wraps at 255

    it 'completes period in 256 cycles' do
      pwm.set_input(:audio, 1)

      # Count cycles until we see the pattern repeat
      pattern = []
      512.times do
        clock_cycle
        pattern << pwm.get_output(:aud_pwm)
      end

      # Pattern should repeat every 256 cycles
      first_period = pattern[0...256]
      second_period = pattern[256...512]
      expect(first_period).to eq(second_period)
    end
  end

  describe 'Verilog reference comparison', if: HdlToolchain.iverilog_available? do
    include VhdlReferenceHelper

    let(:reference_verilog) { VhdlReferenceHelper.reference_file('audio_pwm.v') }
    let(:work_dir) { Dir.mktmpdir('audio_pwm_test_') }

    before do
      skip 'Reference Verilog not found' unless VhdlReferenceHelper.reference_exists?('audio_pwm.v')
    end

    after do
      FileUtils.rm_rf(work_dir) if work_dir && Dir.exist?(work_dir)
    end

    it 'matches reference Verilog PWM behavior' do
      ports = {
        clk: { direction: 'in', width: 1 },
        audio: { direction: 'in', width: 8 },
        aud_pwm: { direction: 'out', width: 1 },
        aud_sd: { direction: 'out', width: 1 }
      }

      # Test PWM generation for different audio levels
      test_vectors = []
      # First 20 cycles with audio=128 (50% duty cycle)
      20.times { test_vectors << { inputs: { audio: 128 } } }
      # Next 20 cycles with audio=64 (25% duty cycle)
      20.times { test_vectors << { inputs: { audio: 64 } } }
      # Next 20 cycles with audio=255 (100% duty cycle)
      20.times { test_vectors << { inputs: { audio: 255 } } }

      result = run_verilog_comparison_test(
        pwm,
        verilog_files: [reference_verilog],
        ports: ports,
        test_vectors: test_vectors,
        base_dir: work_dir,
        clock_name: 'clk'
      )

      if result[:success] == false && result[:error]
        skip "iverilog simulation failed: #{result[:error]}"
      end

      expect(result[:success]).to be(true),
        "Mismatches: #{result[:comparison][:mismatches].first(5).inspect}"
    end

    it 'matches reference aud_sd output (always 1)' do
      ports = {
        clk: { direction: 'in', width: 1 },
        audio: { direction: 'in', width: 8 },
        aud_pwm: { direction: 'out', width: 1 },
        aud_sd: { direction: 'out', width: 1 }
      }

      test_vectors = [0, 128, 255].map { |level| { inputs: { audio: level } } }

      result = run_verilog_comparison_test(
        pwm,
        verilog_files: [reference_verilog],
        ports: ports,
        test_vectors: test_vectors,
        base_dir: work_dir,
        clock_name: 'clk'
      )

      if result[:success] == false && result[:error]
        skip "iverilog simulation failed: #{result[:error]}"
      end

      # Check aud_sd is always 1
      result[:rhdl_results].each do |cycle_result|
        expect(cycle_result[:aud_sd]).to eq(1)
      end
    end
  end
end

RSpec.describe RHDL::Apple2::SpeakerToggle do
  let(:speaker) { described_class.new('speaker') }

  before do
    speaker
    speaker.set_input(:clk, 0)
    speaker.set_input(:toggle, 0)
  end

  def clock_cycle
    speaker.set_input(:clk, 0)
    speaker.propagate
    speaker.set_input(:clk, 1)
    speaker.propagate
  end

  describe 'speaker toggle' do
    # Reference: Original Apple II just toggled speaker on $C030 access

    it 'starts with speaker off' do
      clock_cycle

      state = speaker.get_output(:speaker)
      expect(state).to eq(0)
    end

    it 'toggles speaker on toggle strobe' do
      # Initial state
      clock_cycle
      initial = speaker.get_output(:speaker)

      # Toggle
      speaker.set_input(:toggle, 1)
      clock_cycle
      speaker.set_input(:toggle, 0)

      toggled = speaker.get_output(:speaker)
      expect(toggled).not_to eq(initial)
    end

    it 'toggles back on second strobe' do
      clock_cycle
      initial = speaker.get_output(:speaker)

      # First toggle
      speaker.set_input(:toggle, 1)
      clock_cycle
      speaker.set_input(:toggle, 0)

      # Second toggle
      speaker.set_input(:toggle, 1)
      clock_cycle
      speaker.set_input(:toggle, 0)

      final = speaker.get_output(:speaker)
      expect(final).to eq(initial)
    end

    it 'holds state between toggles' do
      speaker.set_input(:toggle, 1)
      clock_cycle
      speaker.set_input(:toggle, 0)

      state_after_toggle = speaker.get_output(:speaker)

      # Run multiple cycles without toggle
      10.times do
        clock_cycle
        expect(speaker.get_output(:speaker)).to eq(state_after_toggle)
      end
    end
  end

  describe 'square wave generation' do
    it 'generates square wave with alternating toggles' do
      samples = []

      # Generate square wave by toggling every N cycles
      20.times do |i|
        if i.even?
          speaker.set_input(:toggle, 1)
          clock_cycle
          speaker.set_input(:toggle, 0)
        else
          clock_cycle
        end
        samples << speaker.get_output(:speaker)
      end

      # Should see alternating pattern
      transitions = samples.each_cons(2).count { |a, b| a != b }
      expect(transitions).to be > 0
    end
  end
end

RSpec.describe RHDL::Apple2::AudioMixer do
  let(:mixer) { described_class.new('mixer') }

  before do
    mixer
    mixer.set_input(:speaker, 0)
    mixer.set_input(:cassette_in, 0)
  end

  describe 'speaker mixing' do
    # Reference: Speaker 0 -> 0x40, Speaker 1 -> 0xC0

    it 'outputs 0x40 when speaker is off' do
      mixer.set_input(:speaker, 0)
      mixer.propagate

      audio_out = mixer.get_output(:audio_out)
      expect(audio_out).to eq(0x40)
    end

    it 'outputs 0xC0 when speaker is on' do
      mixer.set_input(:speaker, 1)
      mixer.propagate

      audio_out = mixer.get_output(:audio_out)
      expect(audio_out).to eq(0xC0)
    end

    it 'centers audio around 0x80' do
      # 0x40 and 0xC0 are equidistant from center (0x80)
      mixer.set_input(:speaker, 0)
      mixer.propagate
      low = mixer.get_output(:audio_out)

      mixer.set_input(:speaker, 1)
      mixer.propagate
      high = mixer.get_output(:audio_out)

      # Both should be same distance from center
      expect(0x80 - low).to eq(high - 0x80)
    end
  end

  describe 'combinational output' do
    it 'updates immediately with speaker change' do
      mixer.set_input(:speaker, 0)
      mixer.propagate
      expect(mixer.get_output(:audio_out)).to eq(0x40)

      mixer.set_input(:speaker, 1)
      mixer.propagate
      expect(mixer.get_output(:audio_out)).to eq(0xC0)
    end
  end

  describe '8-bit output range' do
    it 'outputs valid 8-bit values' do
      mixer.set_input(:speaker, 0)
      mixer.propagate
      expect(mixer.get_output(:audio_out)).to be_between(0, 255)

      mixer.set_input(:speaker, 1)
      mixer.propagate
      expect(mixer.get_output(:audio_out)).to be_between(0, 255)
    end
  end
end
