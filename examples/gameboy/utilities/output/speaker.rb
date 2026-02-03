# frozen_string_literal: true

# Game Boy Speaker Simulation
# Generates audio from the APU outputs in the HDL simulation

module RHDL
  module GameBoy
    # Speaker simulation that converts APU output to audio
    # Uses external audio tools (sox, ffplay, paplay, aplay) for playback
    class Speaker
      # Audio sample rate (Game Boy runs at ~32768 Hz APU)
      SAMPLE_RATE = 44100

      # Buffer size in samples
      BUFFER_SIZE = 1024

      # Maximum amplitude for 16-bit signed audio
      AMPLITUDE = 12000

      attr_reader :enabled, :toggle_count, :audio_backend, :samples_written, :last_error

      def initialize
        @enabled = false
        @speaker_state = false
        @prev_state = false
        @last_toggle_time = nil
        @sample_buffer = []
        @audio_thread = nil
        @mutex = Mutex.new
        @running = false
        @audio_pipe = nil
        @audio_cmd = nil
        @audio_backend = nil
        @toggle_count = 0
        @samples_generated = 0
        @samples_written = 0
        @last_error = nil
        @last_toggle_count = 0
        @last_activity_check = Time.now
      end

      # Update speaker state from audio output
      def update_state(state)
        new_state = state != 0
        if new_state != @prev_state
          @prev_state = new_state
          toggle
        end
      end

      # Toggle the speaker
      def toggle
        @toggle_count += 1
        @speaker_state = !@speaker_state
        return unless @enabled && @running

        now = Time.now
        if @last_toggle_time
          interval = now - @last_toggle_time
          if interval > 0.00001 && interval < 0.1
            generate_samples(interval)
          end
        end
        @last_toggle_time = now
      end

      # Sync batched toggles
      def sync_toggles(count, elapsed_time)
        return unless @enabled && @running
        return if count <= 0 || elapsed_time <= 0

        @toggle_count += count
        avg_interval = elapsed_time / count

        return if avg_interval < 0.00001 || avg_interval > 0.1

        count.times do
          generate_samples(avg_interval)
          @speaker_state = !@speaker_state
        end

        @last_toggle_time = Time.now
      end

      # Generate audio samples
      def generate_samples(interval)
        num_samples = (interval * SAMPLE_RATE).to_i
        return if num_samples <= 0 || num_samples > SAMPLE_RATE

        sample_value = @speaker_state ? AMPLITUDE : -AMPLITUDE

        @mutex.synchronize do
          num_samples.times do
            @sample_buffer << sample_value
          end
          @samples_generated += num_samples

          flush_to_pipe if @sample_buffer.size >= BUFFER_SIZE
        end
      end

      # Start audio playback
      def start
        return if @running

        @audio_cmd, @audio_backend = find_audio_command
        unless @audio_cmd
          @audio_backend = 'none'
          return
        end

        @running = true
        @enabled = true
        @last_toggle_time = nil
        @toggle_count = 0
        @samples_generated = 0
        start_audio_pipe
      end

      # Stop audio playback
      def stop
        return unless @running

        @running = false
        @enabled = false
        stop_audio_pipe
      end

      def enable(state)
        @enabled = state
      end

      def status
        if @running && @audio_backend && @audio_backend != 'none'
          @audio_backend
        elsif @audio_backend == 'none'
          "no backend"
        else
          "OFF"
        end
      end

      def active?
        now = Time.now
        if now - @last_activity_check > 0.1
          @activity = @toggle_count > @last_toggle_count
          @last_toggle_count = @toggle_count
          @last_activity_check = now
        end
        @activity || false
      end

      def debug_info
        {
          backend: @audio_backend,
          enabled: @enabled,
          running: @running,
          toggle_count: @toggle_count,
          samples_generated: @samples_generated,
          samples_written: @samples_written,
          buffer_size: @sample_buffer.size,
          last_error: @last_error,
          pipe_open: !@audio_pipe.nil?
        }
      end

      def self.available?
        find_available_backend != nil
      end

      def self.find_available_backend
        return 'sox' if system('which play > /dev/null 2>&1')
        return 'ffplay' if system('which ffplay > /dev/null 2>&1')
        return 'paplay' if system('which paplay > /dev/null 2>&1')
        return 'aplay' if system('which aplay > /dev/null 2>&1')
        nil
      end

      private

      def find_audio_command
        if system('which play > /dev/null 2>&1')
          cmd = ['play', '-q', '-t', 'raw', '-r', SAMPLE_RATE.to_s,
                 '-b', '16', '-c', '1', '-e', 'signed', '-L', '-']
          return [cmd, 'sox']
        end

        if system('which ffplay > /dev/null 2>&1')
          cmd = ['ffplay', '-f', 's16le', '-ar', SAMPLE_RATE.to_s,
                 '-ac', '1', '-nodisp', '-autoexit', '-loglevel', 'quiet', '-i', '-']
          return [cmd, 'ffplay']
        end

        if system('which paplay > /dev/null 2>&1')
          cmd = ['paplay', '--raw', "--rate=#{SAMPLE_RATE}", '--channels=1', '--format=s16le']
          return [cmd, 'paplay']
        end

        if system('which aplay > /dev/null 2>&1')
          cmd = ['aplay', '-q', '-f', 'S16_LE', '-r', SAMPLE_RATE.to_s, '-c', '1']
          return [cmd, 'aplay']
        end

        [nil, nil]
      end

      def start_audio_pipe
        return unless @audio_cmd

        begin
          @audio_pipe = IO.popen(@audio_cmd, 'wb')
          @audio_thread = Thread.new { audio_writer_thread }
        rescue => e
          warn "Failed to start audio: #{e.message}" if ENV['DEBUG']
          @audio_pipe = nil
          @audio_backend = 'error'
        end
      end

      def stop_audio_pipe
        @audio_thread&.kill
        @audio_thread = nil

        if @audio_pipe
          begin
            @audio_pipe.close
          rescue
            nil
          end
          @audio_pipe = nil
        end
      end

      def audio_writer_thread
        while @running
          samples = nil

          @mutex.synchronize do
            if @sample_buffer.size >= BUFFER_SIZE
              samples = @sample_buffer.shift(BUFFER_SIZE)
            end
          end

          if samples
            write_samples(samples)
          else
            sleep 0.01
          end
        end
      end

      def flush_to_pipe
        return unless @audio_pipe && @sample_buffer.size >= BUFFER_SIZE

        samples = @sample_buffer.shift(BUFFER_SIZE)
        write_samples_unlocked(samples)
      end

      def write_samples(samples)
        return unless @audio_pipe && !samples.empty?

        begin
          raw_data = samples.pack('s<*')
          @audio_pipe.write(raw_data)
          @audio_pipe.flush
          @samples_written += samples.size
        rescue Errno::EPIPE, IOError => e
          @last_error = "Pipe: #{e.message}"
          stop_audio_pipe
          start_audio_pipe
        rescue => e
          @last_error = "Write: #{e.class}"
        end
      end

      def write_samples_unlocked(samples)
        return unless @audio_pipe && !samples.empty?

        begin
          raw_data = samples.pack('s<*')
          @audio_pipe.write(raw_data)
          @samples_written += samples.size
        rescue Errno::EPIPE, IOError => e
          @last_error = "Pipe: #{e.message}"
        rescue => e
          @last_error = "Write: #{e.class}"
        end
      end
    end
  end
end
