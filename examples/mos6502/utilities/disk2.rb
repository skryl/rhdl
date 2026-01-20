# Apple II Disk II Controller Emulation
# Emulates the Disk II controller card for slot 6 (addresses $C0E0-$C0EF)

module MOS6502
  class Disk2
    # Disk geometry constants
    TRACKS = 35
    SECTORS_PER_TRACK = 16
    BYTES_PER_SECTOR = 256
    TRACK_SIZE = SECTORS_PER_TRACK * BYTES_PER_SECTOR  # 4096 bytes
    DISK_SIZE = TRACKS * TRACK_SIZE                      # 143360 bytes

    # Slot 6 I/O addresses (offset from $C080)
    # Actual addresses are $C0E0-$C0EF
    SLOT = 6
    BASE_ADDR = 0xC080 + (SLOT * 0x10)  # = 0xC0E0

    # Address offsets within slot
    PHASE0_OFF  = 0x00  # $C0E0 - Phase 0 off
    PHASE0_ON   = 0x01  # $C0E1 - Phase 0 on
    PHASE1_OFF  = 0x02  # $C0E2 - Phase 1 off
    PHASE1_ON   = 0x03  # $C0E3 - Phase 1 on
    PHASE2_OFF  = 0x04  # $C0E4 - Phase 2 off
    PHASE2_ON   = 0x05  # $C0E5 - Phase 2 on
    PHASE3_OFF  = 0x06  # $C0E6 - Phase 3 off
    PHASE3_ON   = 0x07  # $C0E7 - Phase 3 on
    MOTOR_OFF   = 0x08  # $C0E8 - Motor off
    MOTOR_ON    = 0x09  # $C0E9 - Motor on
    DRIVE1      = 0x0A  # $C0EA - Select drive 1
    DRIVE2      = 0x0B  # $C0EB - Select drive 2
    Q6L         = 0x0C  # $C0EC - Read data (Q6 low)
    Q6H         = 0x0D  # $C0ED - Shift register (Q6 high)
    Q7L         = 0x0E  # $C0EE - Read mode (Q7 low)
    Q7H         = 0x0F  # $C0EF - Write mode (Q7 high)

    # DOS 3.3 sector interleaving table
    # Physical to logical sector mapping
    DOS33_INTERLEAVE = [
      0x00, 0x0D, 0x0B, 0x09, 0x07, 0x05, 0x03, 0x01,
      0x0E, 0x0C, 0x0A, 0x08, 0x06, 0x04, 0x02, 0x0F
    ].freeze

    attr_reader :track, :motor_on, :write_mode, :current_drive

    def initialize
      @drives = [nil, nil]  # Two drives supported
      @current_drive = 0
      @track = 0            # Current track (0-34)
      @phase = [false, false, false, false]  # Phase magnet states
      @motor_on = false
      @write_mode = false   # false = read, true = write
      @q6 = false           # Q6 latch
      @q7 = false           # Q7 latch
      @data_latch = 0       # Data register
      @bit_position = 0     # Current bit position in nibble stream
      @byte_position = 0    # Current byte position in track
      @spin_counter = 0     # For timing simulation
    end

    # Load a .dsk disk image into drive (0 or 1)
    def load_disk(path_or_bytes, drive: 0)
      bytes = if path_or_bytes.is_a?(String)
                File.binread(path_or_bytes).bytes
              else
                path_or_bytes.is_a?(Array) ? path_or_bytes : path_or_bytes.bytes
              end

      if bytes.length != DISK_SIZE
        raise ArgumentError, "Invalid disk image size: #{bytes.length} (expected #{DISK_SIZE})"
      end

      # Convert from DOS 3.3 sector order to physical order and encode to nibbles
      @drives[drive] = encode_disk(bytes)
      @current_drive = drive
    end

    # Check if a disk is loaded in a drive
    def disk_loaded?(drive: 0)
      !@drives[drive].nil?
    end

    # Eject disk from drive
    def eject_disk(drive: 0)
      @drives[drive] = nil
    end

    # Handle Disk II controller I/O access
    # Returns nil if address not handled, otherwise returns read value
    def access(addr, value = nil, write: false)
      return nil unless handles_address?(addr)

      offset = (addr - BASE_ADDR) & 0x0F

      case offset
      when PHASE0_OFF
        set_phase(0, false)
      when PHASE0_ON
        set_phase(0, true)
      when PHASE1_OFF
        set_phase(1, false)
      when PHASE1_ON
        set_phase(1, true)
      when PHASE2_OFF
        set_phase(2, false)
      when PHASE2_ON
        set_phase(2, true)
      when PHASE3_OFF
        set_phase(3, false)
      when PHASE3_ON
        set_phase(3, true)
      when MOTOR_OFF
        @motor_on = false
      when MOTOR_ON
        @motor_on = true
      when DRIVE1
        @current_drive = 0
      when DRIVE2
        @current_drive = 1
      when Q6L
        @q6 = false
        return read_data if !@q7  # Read data byte
      when Q6H
        @q6 = true
        if write && @q7
          write_data(value)
        end
      when Q7L
        @q7 = false
        @write_mode = false
        return read_status if @q6  # Read write-protect status
      when Q7H
        @q7 = true
        @write_mode = true
      end

      0x00
    end

    # Check if this controller handles the given address
    def handles_address?(addr)
      addr >= BASE_ADDR && addr < BASE_ADDR + 0x10
    end

    private

    # Set phase magnet state and move head if appropriate
    def set_phase(phase_num, on)
      @phase[phase_num] = on
      update_track_position if @motor_on
    end

    # Update track position based on phase magnets
    # The Disk II uses a 4-phase stepper motor
    def update_track_position
      # Find which phases are on
      phases_on = @phase.each_with_index.select { |on, _| on }.map { |_, i| i }
      return if phases_on.empty?

      # Calculate desired half-track from phase pattern
      # Each phase corresponds to a half-track position
      current_half_track = @track * 2

      # Simple stepper logic: move toward the active phase
      phases_on.each do |phase|
        target_half_track = phase

        # Find closest half-track position matching this phase
        while target_half_track < current_half_track - 2
          target_half_track += 4
        end
        while target_half_track > current_half_track + 2
          target_half_track -= 4
        end

        if target_half_track > current_half_track && current_half_track < (TRACKS - 1) * 2
          current_half_track += 1
        elsif target_half_track < current_half_track && current_half_track > 0
          current_half_track -= 1
        end
      end

      @track = current_half_track / 2
      @track = 0 if @track < 0
      @track = TRACKS - 1 if @track >= TRACKS
    end

    # Read next data byte from current track
    def read_data
      disk = @drives[@current_drive]
      return 0x00 unless disk && @motor_on

      track_data = disk[@track]
      return 0x00 unless track_data

      # Get next nibble byte
      byte = track_data[@byte_position] || 0x00
      @byte_position = (@byte_position + 1) % track_data.length

      # Simulate disk spinning time
      @spin_counter += 1

      byte
    end

    # Read write-protect status
    def read_status
      # Return $80 if write-protected (high bit set)
      # For now, all disks are write-protected
      0x80
    end

    # Write data byte (not implemented - read-only for now)
    def write_data(value)
      # Write support would go here
      # For now, disks are read-only
    end

    # Encode a .dsk image to nibblized format for each track
    # .dsk files store sectors in DOS 3.3 logical order
    def encode_disk(bytes)
      tracks = []

      TRACKS.times do |track_num|
        track_data = []

        SECTORS_PER_TRACK.times do |phys_sector|
          # Map physical sector to logical sector (DOS 3.3 interleaving)
          log_sector = DOS33_INTERLEAVE[phys_sector]

          # Calculate offset in disk image
          offset = (track_num * TRACK_SIZE) + (log_sector * BYTES_PER_SECTOR)
          sector_data = bytes[offset, BYTES_PER_SECTOR]

          # Encode sector with address and data fields
          track_data.concat(encode_sector(track_num, phys_sector, sector_data))
        end

        tracks << track_data
      end

      tracks
    end

    # Encode a single sector with address field, gaps, and data field
    def encode_sector(track, sector, data)
      encoded = []

      # Gap 1 - self-sync bytes (typically 40-95 $FF bytes)
      16.times { encoded << 0xFF }

      # Address field
      # Prologue: D5 AA 96
      encoded << 0xD5 << 0xAA << 0x96

      # Volume, track, sector, checksum (4-and-4 encoded)
      volume = 254  # Standard DOS 3.3 volume
      checksum = volume ^ track ^ sector

      encoded.concat(encode_4and4(volume))
      encoded.concat(encode_4and4(track))
      encoded.concat(encode_4and4(sector))
      encoded.concat(encode_4and4(checksum))

      # Epilogue: DE AA EB
      encoded << 0xDE << 0xAA << 0xEB

      # Gap 2
      8.times { encoded << 0xFF }

      # Data field
      # Prologue: D5 AA AD
      encoded << 0xD5 << 0xAA << 0xAD

      # Encode 256 bytes of data using 6-and-2 encoding
      encoded.concat(encode_6and2(data || Array.new(256, 0)))

      # Epilogue: DE AA EB
      encoded << 0xDE << 0xAA << 0xEB

      # Gap 3
      16.times { encoded << 0xFF }

      encoded
    end

    # 4-and-4 encoding for address field
    def encode_4and4(byte)
      [
        ((byte >> 1) & 0x55) | 0xAA,
        (byte & 0x55) | 0xAA
      ]
    end

    # 6-and-2 encoding for data field
    # This encodes 256 bytes into 342 disk bytes plus checksum
    def encode_6and2(data)
      # Disk byte translation table
      translate = [
        0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
        0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
        0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
        0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
        0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
        0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
        0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
        0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
      ]

      # Buffer for encoded data
      # First 86 bytes hold the 2-bit remainders
      # Next 256 bytes hold the 6-bit values
      buffer = Array.new(342, 0)

      # Extract 2-bit values (bottom 2 bits of each byte, packed)
      86.times do |i|
        val = 0
        val |= ((data[i] || 0) & 0x01) << 1
        val |= ((data[i] || 0) & 0x02) >> 1
        val |= ((data[i + 86] || 0) & 0x01) << 3 if i + 86 < 256
        val |= ((data[i + 86] || 0) & 0x02) << 1 if i + 86 < 256
        val |= ((data[i + 172] || 0) & 0x01) << 5 if i + 172 < 256
        val |= ((data[i + 172] || 0) & 0x02) << 3 if i + 172 < 256
        buffer[85 - i] = val
      end

      # Store 6-bit values (top 6 bits of each byte)
      256.times do |i|
        buffer[86 + i] = (data[i] || 0) >> 2
      end

      # XOR encode and translate
      encoded = []
      checksum = 0

      342.times do |i|
        val = buffer[i] ^ checksum
        checksum = buffer[i]
        encoded << translate[val & 0x3F]
      end

      # Append checksum
      encoded << translate[checksum & 0x3F]

      encoded
    end
  end
end
