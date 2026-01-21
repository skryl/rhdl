# Apple II Speaker Emulation
# Generates audio from speaker toggle events at $C030

module MOS6502
  class Apple2Speaker
    # Audio sample rate (standard)
    SAMPLE_RATE = 22050

    # Buffer size in samples (smaller = lower latency, larger = more stable)
    BUFFER_SIZE = 512

    # Maximum amplitude for 16-bit signed audio
    AMPLITUDE = 12000

    # Minimum time between toggles to count as audio (filter noise)
    MIN_TOGGLE_INTERVAL = 0.00001  # 10 microseconds (100kHz max)

    # Maximum time between toggles before we consider it silence
    MAX_TOGGLE_INTERVAL = 0.1  # 100ms

    attr_reader :enabled, :toggle_count, :audio_backend

    def initialize
      @enabled = false  # Start disabled, enable explicitly
      @speaker_state = false  # false = low, true = high
      @last_toggle_time = nil
      @sample_buffer = []
      @sample_position = 0.0
      @audio_thread = nil
      @mutex = Mutex.new
      @running = false
      @audio_pipe = nil
      @audio_cmd = nil
      @audio_backend = nil
      @toggle_count = 0
      @samples_generated = 0
    end

    # Toggle the speaker (called when $C030 is accessed)
    def toggle(_cycle = 0)
      @toggle_count += 1
      return unless @enabled && @running

      now = Time.now
      if @last_toggle_time
        interval = now - @last_toggle_time

        # Only generate audio for reasonable toggle frequencies
        if interval > MIN_TOGGLE_INTERVAL && interval < MAX_TOGGLE_INTERVAL
          generate_samples(interval)
        end
      end

      @last_toggle_time = now
      @speaker_state = !@speaker_state
    end

    # Update cycle (compatibility method - uses time internally)
    def update_cycle(_cycle)
      # No-op - we use wall-clock time
    end

    # Generate audio samples for a time interval
    def generate_samples(interval)
      num_samples = (interval * SAMPLE_RATE).to_i
      return if num_samples <= 0 || num_samples > SAMPLE_RATE  # Sanity check

      sample_value = @speaker_state ? AMPLITUDE : -AMPLITUDE

      @mutex.synchronize do
        num_samples.times do
          @sample_buffer << sample_value
        end
        @samples_generated += num_samples

        # Write to audio pipe if we have enough samples
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

    # Enable/disable audio
    def enable(state)
      @enabled = state
    end

    # Get status info for debug display
    def status
      if @running && @audio_backend && @audio_backend != 'none'
        "#{@audio_backend}"
      elsif @audio_backend == 'none'
        "no backend"
      else
        "off"
      end
    end

    # Check if audio system is available
    def self.available?
      find_available_backend != nil
    end

    # Find available audio backend (class method for checking availability)
    def self.find_available_backend
      # Check for sox play (works on macOS and Linux)
      if system('which play > /dev/null 2>&1')
        return 'sox'
      end

      # Check for ffplay (ffmpeg - works on macOS and Linux)
      if system('which ffplay > /dev/null 2>&1')
        return 'ffplay'
      end

      # Check for paplay (PulseAudio - Linux)
      if system('which paplay > /dev/null 2>&1')
        return 'paplay'
      end

      # Check for aplay (ALSA - Linux)
      if system('which aplay > /dev/null 2>&1')
        return 'aplay'
      end

      nil
    end

    private

    def find_audio_command
      # Try sox play first (cross-platform, install with: brew install sox)
      if system('which play > /dev/null 2>&1')
        cmd = ['play', '-q', '-t', 'raw', '-r', SAMPLE_RATE.to_s,
               '-e', 'signed-integer', '-b', '16', '-c', '1',
               '--endian', 'little', '-']
        return [cmd, 'sox']
      end

      # Try ffplay (ffmpeg - cross-platform, install with: brew install ffmpeg)
      if system('which ffplay > /dev/null 2>&1')
        cmd = ['ffplay', '-f', 's16le', '-ar', SAMPLE_RATE.to_s,
               '-ac', '1', '-nodisp', '-autoexit', '-loglevel', 'quiet', '-']
        return [cmd, 'ffplay']
      end

      # Try paplay (PulseAudio - Linux)
      if system('which paplay > /dev/null 2>&1')
        cmd = ['paplay', '--raw', "--rate=#{SAMPLE_RATE}", '--channels=1', '--format=s16le']
        return [cmd, 'paplay']
      end

      # Try aplay (ALSA - Linux)
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
          # No samples - generate a tiny bit of silence to keep pipe alive
          sleep 0.01
        end
      end
    end

    def flush_to_pipe
      # Called within mutex - extract samples and write
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
      rescue Errno::EPIPE, IOError => e
        warn "Audio pipe error: #{e.message}" if ENV['DEBUG']
        # Restart the pipe
        stop_audio_pipe
        start_audio_pipe
      end
    end

    def write_samples_unlocked(samples)
      return unless @audio_pipe && !samples.empty?

      begin
        raw_data = samples.pack('s<*')
        @audio_pipe.write(raw_data)
      rescue Errno::EPIPE, IOError
        # Will be handled by audio thread
      end
    end
  end

  # Simple beep-based audio fallback for systems without audio utilities
  class Apple2SpeakerBeep
    attr_reader :enabled, :toggle_count, :audio_backend

    def initialize
      @enabled = true
      @toggle_count = 0
      @last_beep_time = Time.now
      @audio_backend = 'beep'
    end

    def toggle(_cycle = 0)
      @toggle_count += 1

      # Beep occasionally to indicate audio activity
      if @toggle_count % 5000 == 0 && (Time.now - @last_beep_time) > 0.5
        print "\a" if @enabled  # Terminal bell
        @last_beep_time = Time.now
      end
    end

    def update_cycle(_cycle)
      # No-op
    end

    def start
      # No-op
    end

    def stop
      # No-op
    end

    def enable(state)
      @enabled = state
    end

    def status
      @enabled ? 'beep' : 'off'
    end

    def self.available?
      true
    end
  end
end
