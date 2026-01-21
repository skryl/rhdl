# frozen_string_literal: true

# Apple II Audio PWM
# Based on Feng Zhou's neoapple2 implementation
#
# PWM audio output for Apple II
# Converts 8-bit audio samples to 1-bit PWM output
# Sampling frequency: 14 MHz / 256 = ~54.7 kHz

require 'rhdl'

module RHDL
  module Apple2
    class AudioPWM < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      # Clock input (14 MHz)
      input :clk

      # Audio sample input (0-255)
      input :audio, width: 8

      # PWM outputs
      output :aud_pwm                    # PWM output
      output :aud_sd                     # Audio shutdown (active low)

      sequential clock: :clk, reset_values: {
        counter: 0,
        audio_latched: 0
      } do
        # Latch audio sample at start of each PWM period (counter == 0)
        audio_latched <= mux(counter == lit(0, width: 8),
          audio,
          audio_latched
        )

        # Increment counter (wraps at 255)
        counter <= counter + lit(1, width: 8)
      end

      behavior do
        # Audio shutdown is always off (audio enabled)
        aud_sd <= lit(1, width: 1)

        # PWM output: high when counter < audio_latched
        # Special case: always high for first cycle (counter < 1)
        # This ensures at least some pulse width for all non-zero values
        is_first = (counter == lit(0, width: 8))
        is_below = (counter < audio_latched) & (counter < lit(255, width: 8))

        aud_pwm <= is_first | is_below
      end
    end

    # Simple speaker toggle (original Apple II 1-bit audio)
    # The original Apple II just toggled a speaker driver
    class SpeakerToggle < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :toggle                      # Toggle strobe (from $C030 access)

      output :speaker                    # Speaker output

      sequential clock: :clk, reset_values: { speaker_state: 0 } do
        # Toggle speaker state when toggle signal is high
        speaker_state <= mux(toggle,
          ~speaker_state,
          speaker_state
        )
      end

      behavior do
        speaker <= speaker_state
      end
    end

    # Audio mixer for combining multiple audio sources
    class AudioMixer < Component
      include RHDL::DSL::Behavior

      # Audio inputs
      input :speaker                     # 1-bit speaker output
      input :cassette_in                 # Cassette audio input

      # Mixed output
      output :audio_out, width: 8

      behavior do
        # Simple mixing: speaker gets most of the range
        # Speaker: 0 -> 0x40, 1 -> 0xC0
        # This provides a centered audio signal
        speaker_level = mux(speaker,
          lit(0xC0, width: 8),
          lit(0x40, width: 8)
        )

        audio_out <= speaker_level
      end
    end
  end
end
