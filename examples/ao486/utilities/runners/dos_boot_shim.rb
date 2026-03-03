# frozen_string_literal: true

module RHDL
  module Examples
    module AO486
      # Builds a real-mode bootstrap program that installs a minimal BIOS-like
      # interrupt surface and transfers control to the DOS boot sector at 0000:7C00.
      #
      # INT 13h disk reads are serviced through AO486 extension-specific I/O ports.
      class DosBootShim
        LOAD_ADDRESS = 0x000F_0000
        BOOT_FAIL_MESSAGE = "BOOT FAIL\r\n".freeze

        DISK_IO_PORT_CH = 0x00E0
        DISK_IO_PORT_CL = 0x00E1
        DISK_IO_PORT_DH = 0x00E2
        DISK_IO_PORT_DL = 0x00E3
        DISK_IO_PORT_COUNT = 0x00E4
        DISK_IO_PORT_COMMAND_STATUS = 0x00E5
        DISK_IO_PORT_DATA = 0x00E6
        DISK_IO_COMMAND_READ = 0x01
        DISK_IO_STATUS_ERROR = 0x80

        attr_reader :disk_image_path

        def initialize(disk_image_path:)
          @disk_image_path = File.expand_path(disk_image_path.to_s)
          raise ArgumentError, "DOS disk image not found: #{@disk_image_path}" unless File.file?(@disk_image_path)
        end

        def binary
          builder = BinaryBuilder.new
          build_program(builder: builder)
          builder.to_binary
        end

        private

        def build_program(builder:)
          builder.label(:start)
          builder.emit(0xFA) # cli
          builder.emit(0x31, 0xC0) # xor ax, ax
          builder.emit(0x8E, 0xD8) # mov ds, ax
          builder.emit(0x8E, 0xC0) # mov es, ax
          builder.emit(0x8E, 0xD0) # mov ss, ax
          builder.emit(0xBC, 0x00, 0x7C) # mov sp, 0x7c00

          # Cursor/key state.
          builder.emit_mov_word_ptr_imm(address: 0x0200, value: 0x0000) # cursor_pos
          builder.emit(0xC6, 0x06, 0x02, 0x02, 0x00) # mov byte [0x0202], 0 ; kbd_pending_flag
          builder.emit(0xC6, 0x06, 0x03, 0x02, 0x00) # mov byte [0x0203], 0 ; kbd_pending_value
          builder.emit(0xC6, 0x06, 0x04, 0x02, 0x00) # mov byte [0x0204], 0 ; int13_sector_count

          # Install interrupt vectors.
          builder.emit_mov_word_ptr_label(address: 0x0040, label: :int10_handler) # int 10h offset
          builder.emit_mov_word_ptr_imm(address: 0x0042, value: 0x0000) # int 10h segment
          builder.emit_mov_word_ptr_label(address: 0x004C, label: :int13_handler) # int 13h offset
          builder.emit_mov_word_ptr_imm(address: 0x004E, value: 0x0000) # int 13h segment
          builder.emit_mov_word_ptr_label(address: 0x0058, label: :int16_handler) # int 16h offset
          builder.emit_mov_word_ptr_imm(address: 0x005A, value: 0x0000) # int 16h segment
          builder.emit_mov_word_ptr_label(address: 0x0064, label: :start) # int 19h offset
          builder.emit_mov_word_ptr_imm(address: 0x0066, value: 0x0000) # int 19h segment

          # Clear text mode framebuffer once.
          builder.emit(0xB4, 0x00) # mov ah, 0x00
          builder.emit(0xCD, 0x10) # int 0x10

          # Load boot sector from floppy drive 0 to 0000:7C00 and transfer control.
          builder.emit(0x31, 0xD2) # xor dx, dx (dl=0, dh=0)
          builder.emit(0xB8, 0x01, 0x02) # mov ax, 0x0201 (int13 read 1 sector)
          builder.emit(0xBB, 0x00, 0x7C) # mov bx, 0x7c00
          builder.emit(0xB9, 0x01, 0x00) # mov cx, 0x0001 (cyl=0, sec=1)
          builder.emit(0xCD, 0x13) # int 0x13
          builder.emit_jc_near(:boot_fail)
          builder.emit(0x81, 0x3E, 0xFE, 0x7D, 0x55, 0xAA) # cmp word [0x7dfe], 0xaa55
          builder.emit_jne_near(:boot_fail)
          builder.emit(0xEA, 0x00, 0x7C, 0x00, 0x00) # jmp far 0000:7c00

          builder.label(:boot_fail)
          builder.emit(0xBE) # mov si, imm16
          builder.emit_abs16(:boot_fail_message)
          builder.label(:boot_fail_print_loop)
          builder.emit(0xAC) # lodsb
          builder.emit(0x84, 0xC0) # test al, al
          builder.emit_je_near(:boot_halt)
          builder.emit(0xB4, 0x0E) # mov ah, 0x0e
          builder.emit(0xCD, 0x10) # int 0x10
          builder.emit_jmp_near(:boot_fail_print_loop)
          builder.label(:boot_halt)
          builder.emit_jmp_near(:boot_halt)

          build_int10_handler(builder: builder)
          build_int16_handler(builder: builder)
          build_int13_handler(builder: builder)

          builder.label(:boot_fail_message)
          builder.emit(*BOOT_FAIL_MESSAGE.bytes, 0x00)
        end

        def build_int10_handler(builder:)
          builder.label(:int10_handler)
          builder.emit(0x80, 0xFC, 0x00) # cmp ah, 0x00
          builder.emit_je_near(:int10_set_mode)
          builder.emit(0x80, 0xFC, 0x02) # cmp ah, 0x02
          builder.emit_je_near(:int10_set_cursor)
          builder.emit(0x80, 0xFC, 0x03) # cmp ah, 0x03
          builder.emit_je_near(:int10_get_cursor)
          builder.emit(0x80, 0xFC, 0x0E) # cmp ah, 0x0e
          builder.emit_je_near(:int10_teletype)
          builder.emit(0xCF) # iret

          builder.label(:int10_set_mode)
          builder.emit(0x50, 0x53, 0x51, 0x06) # push ax,bx,cx,es
          builder.emit(0xB8, 0x00, 0xB8) # mov ax, 0xb800
          builder.emit(0x8E, 0xC0) # mov es, ax
          builder.emit(0x31, 0xDB) # xor bx, bx
          builder.emit(0xB8, 0x20, 0x07) # mov ax, 0x0720
          builder.emit(0xB9, 0xD0, 0x07) # mov cx, 2000
          builder.label(:int10_clear_loop)
          builder.emit(0x26, 0x89, 0x07) # mov [es:bx], ax
          builder.emit(0x83, 0xC3, 0x02) # add bx, 2
          builder.emit(0x49) # dec cx
          builder.emit_jne(:int10_clear_loop)
          builder.emit_mov_word_ptr_imm(address: 0x0200, value: 0x0000) # cursor_pos = 0
          builder.emit(0x07, 0x59, 0x5B, 0x58) # pop es,cx,bx,ax
          builder.emit(0xCF) # iret

          builder.label(:int10_set_cursor)
          builder.emit(0x50, 0x53) # push ax,bx
          builder.emit(0x31, 0xC0) # xor ax, ax
          builder.emit(0x8A, 0xC6) # mov al, dh
          builder.emit(0xB3, 0x50) # mov bl, 80
          builder.emit(0xF6, 0xE3) # mul bl
          builder.emit(0x31, 0xDB) # xor bx, bx
          builder.emit(0x8A, 0xDA) # mov bl, dl
          builder.emit(0x01, 0xD8) # add ax, bx
          builder.emit(0xD1, 0xE0) # shl ax, 1
          builder.emit(0xA3) # mov [moffs16], ax
          builder.emit_abs16(:cursor_pos)
          builder.emit(0x5B, 0x58) # pop bx,ax
          builder.emit(0xCF) # iret

          builder.label(:int10_get_cursor)
          builder.emit(0x53, 0x51) # push bx,cx
          builder.emit(0xA1) # mov ax, [moffs16]
          builder.emit_abs16(:cursor_pos)
          builder.emit(0xD1, 0xE8) # shr ax, 1
          builder.emit(0x31, 0xD2) # xor dx, dx
          builder.emit(0xB9, 0x50, 0x00) # mov cx, 80
          builder.emit(0xF7, 0xF1) # div cx
          builder.emit(0x88, 0xC6) # mov dh, al
          builder.emit(0xB7, 0x00) # mov bh, 0
          builder.emit(0x59, 0x5B) # pop cx,bx
          builder.emit(0xCF) # iret

          builder.label(:int10_teletype)
          builder.emit(0x50, 0x53, 0x51, 0x52, 0x06) # push ax,bx,cx,dx,es
          builder.emit(0x8B, 0x1E) # mov bx, [moffs16]
          builder.emit_abs16(:cursor_pos)
          builder.emit(0x3C, 0x08) # cmp al, 0x08
          builder.emit_je(:int10_backspace)
          builder.emit(0x3C, 0x0D) # cmp al, 0x0d
          builder.emit_je(:int10_carriage_return)
          builder.emit(0x3C, 0x0A) # cmp al, 0x0a
          builder.emit_je(:int10_linefeed)
          builder.emit(0xBA, 0xF8, 0x03) # mov dx, 0x03f8
          builder.emit(0xEE) # out dx, al
          builder.emit(0xB8, 0x00, 0xB8) # mov ax, 0xb800
          builder.emit(0x8E, 0xC0) # mov es, ax
          builder.emit(0xB4, 0x07) # mov ah, 0x07
          builder.emit(0x26, 0x89, 0x07) # mov [es:bx], ax
          builder.emit(0x83, 0xC3, 0x02) # add bx, 2
          builder.emit(0x81, 0xFB, 0xA0, 0x0F) # cmp bx, 4000
          builder.emit_jc(:int10_store_cursor)
          builder.emit(0x31, 0xDB) # xor bx, bx
          builder.emit_jmp_short(:int10_store_cursor)

          builder.label(:int10_carriage_return)
          builder.emit(0x89, 0xD8) # mov ax, bx
          builder.emit(0x31, 0xD2) # xor dx, dx
          builder.emit(0xB9, 0xA0, 0x00) # mov cx, 160
          builder.emit(0xF7, 0xF1) # div cx
          builder.emit(0xF7, 0xE1) # mul cx
          builder.emit(0x89, 0xC3) # mov bx, ax
          builder.emit_jmp_short(:int10_store_cursor)

          builder.label(:int10_linefeed)
          builder.emit(0x81, 0xC3, 0xA0, 0x00) # add bx, 160
          builder.emit(0x81, 0xFB, 0xA0, 0x0F) # cmp bx, 4000
          builder.emit_jc(:int10_store_cursor)
          builder.emit(0x31, 0xDB) # xor bx, bx
          builder.emit_jmp_short(:int10_store_cursor)

          builder.label(:int10_backspace)
          builder.emit(0x83, 0xFB, 0x00) # cmp bx, 0
          builder.emit_je(:int10_store_cursor)
          builder.emit(0x83, 0xEB, 0x02) # sub bx, 2
          builder.emit(0xB8, 0x00, 0xB8) # mov ax, 0xb800
          builder.emit(0x8E, 0xC0) # mov es, ax
          builder.emit(0xB8, 0x20, 0x07) # mov ax, 0x0720
          builder.emit(0x26, 0x89, 0x07) # mov [es:bx], ax

          builder.label(:int10_store_cursor)
          builder.emit(0x89, 0x1E) # mov [moffs16], bx
          builder.emit_abs16(:cursor_pos)
          builder.emit(0x07, 0x5A, 0x59, 0x5B, 0x58) # pop es,dx,cx,bx,ax
          builder.emit(0xCF) # iret
        end

        def build_int16_handler(builder:)
          builder.label(:int16_handler)
          builder.emit(0x80, 0xFC, 0x00) # cmp ah, 0
          builder.emit_je(:int16_read_key)
          builder.emit(0x80, 0xFC, 0x01) # cmp ah, 1
          builder.emit_je(:int16_check_key)
          builder.emit(0x80, 0xFC, 0x10) # cmp ah, 0x10
          builder.emit_je(:int16_read_key)
          builder.emit(0xCF) # iret

          builder.label(:int16_read_key)
          builder.emit(0xA0) # mov al, [moffs8]
          builder.emit_abs16(:kbd_pending_flag)
          builder.emit(0x3C, 0x00) # cmp al, 0
          builder.emit_je(:int16_wait_for_key)
          builder.emit(0xA0) # mov al, [moffs8]
          builder.emit_abs16(:kbd_pending_value)
          builder.emit(0xC6, 0x06) # mov byte [moffs16], imm8
          builder.emit_abs16(:kbd_pending_flag)
          builder.emit(0x00)
          builder.emit(0xB4, 0x00) # mov ah, 0
          builder.emit(0xCF) # iret

          builder.label(:int16_wait_for_key)
          builder.emit(0xBA, 0x64, 0x00) # mov dx, 0x0064
          builder.label(:int16_wait_loop)
          builder.emit(0xEC) # in al, dx
          builder.emit(0xA8, 0x01) # test al, 1
          builder.emit_je(:int16_wait_loop)
          builder.emit(0xBA, 0x60, 0x00) # mov dx, 0x0060
          builder.emit(0xEC) # in al, dx
          builder.emit(0xB4, 0x00) # mov ah, 0
          builder.emit(0xCF) # iret

          builder.label(:int16_check_key)
          builder.emit(0xA0) # mov al, [moffs8]
          builder.emit_abs16(:kbd_pending_flag)
          builder.emit(0x3C, 0x00) # cmp al, 0
          builder.emit_jne(:int16_check_have_key)
          builder.emit(0xBA, 0x64, 0x00) # mov dx, 0x0064
          builder.emit(0xEC) # in al, dx
          builder.emit(0xA8, 0x01) # test al, 1
          builder.emit_je(:int16_check_none)
          builder.emit(0xBA, 0x60, 0x00) # mov dx, 0x0060
          builder.emit(0xEC) # in al, dx
          builder.emit(0xA2) # mov [moffs8], al
          builder.emit_abs16(:kbd_pending_value)
          builder.emit(0xC6, 0x06) # mov byte [moffs16], imm8
          builder.emit_abs16(:kbd_pending_flag)
          builder.emit(0x01)

          builder.label(:int16_check_have_key)
          builder.emit(0xA0) # mov al, [moffs8]
          builder.emit_abs16(:kbd_pending_value)
          builder.emit(0xB4, 0x00) # mov ah, 0
          builder.emit(0x80, 0x3E) # cmp byte [moffs16], imm8
          builder.emit_abs16(:kbd_pending_flag)
          builder.emit(0x00) # sets ZF=0 when key is present
          builder.emit(0xCF) # iret

          builder.label(:int16_check_none)
          builder.emit(0x31, 0xC0) # xor ax, ax
          builder.emit(0x3C, 0x00) # cmp al, 0 ; set ZF=1
          builder.emit(0xCF) # iret
        end

        def build_int13_handler(builder:)
          builder.label(:int13_handler)
          builder.emit(0x80, 0xFC, 0x00) # cmp ah, 0x00
          builder.emit_je(:int13_reset)
          builder.emit(0x80, 0xFC, 0x02) # cmp ah, 0x02
          builder.emit_je(:int13_read)
          builder.emit(0x80, 0xFC, 0x08) # cmp ah, 0x08
          builder.emit_je(:int13_params)
          builder.emit(0xB4, 0x01) # mov ah, 1
          builder.emit(0xF9) # stc
          builder.emit(0xCF) # iret

          builder.label(:int13_reset)
          builder.emit(0x30, 0xE4) # xor ah, ah
          builder.emit(0xF8) # clc
          builder.emit(0xCF) # iret

          builder.label(:int13_params)
          builder.emit(0x30, 0xE4) # xor ah, ah
          builder.emit(0xB5, 0x4F) # mov ch, 79
          builder.emit(0xB1, 0x12) # mov cl, 18
          builder.emit(0xB6, 0x01) # mov dh, 1
          builder.emit(0xB2, 0x01) # mov dl, 1
          builder.emit(0xF8) # clc
          builder.emit(0xCF) # iret

          builder.label(:int13_read)
          builder.emit(0x80, 0xFA, 0x00) # cmp dl, 0
          builder.emit_jne(:int13_error)
          builder.emit(0x3C, 0x00) # cmp al, 0
          builder.emit_je(:int13_error)
          builder.emit(0xA2) # mov [moffs8], al
          builder.emit_abs16(:int13_sector_count)

          builder.emit(0x53, 0x51, 0x52, 0x56, 0x57, 0x1E) # push bx,cx,dx,si,di,ds

          builder.emit(0xBA, DISK_IO_PORT_CH & 0xFF, (DISK_IO_PORT_CH >> 8) & 0xFF) # mov dx, port
          builder.emit(0x8A, 0xC5) # mov al, ch
          builder.emit(0xEE) # out dx, al
          builder.emit(0xBA, DISK_IO_PORT_CL & 0xFF, (DISK_IO_PORT_CL >> 8) & 0xFF)
          builder.emit(0x8A, 0xC1) # mov al, cl
          builder.emit(0xEE)
          builder.emit(0xBA, DISK_IO_PORT_DH & 0xFF, (DISK_IO_PORT_DH >> 8) & 0xFF)
          builder.emit(0x8A, 0xC6) # mov al, dh
          builder.emit(0xEE)
          builder.emit(0xBA, DISK_IO_PORT_DL & 0xFF, (DISK_IO_PORT_DL >> 8) & 0xFF)
          builder.emit(0x8A, 0xC2) # mov al, dl
          builder.emit(0xEE)
          builder.emit(0xBA, DISK_IO_PORT_COUNT & 0xFF, (DISK_IO_PORT_COUNT >> 8) & 0xFF)
          builder.emit(0xA0) # mov al, [moffs8]
          builder.emit_abs16(:int13_sector_count)
          builder.emit(0xEE)

          builder.emit(0xBA, DISK_IO_PORT_COMMAND_STATUS & 0xFF, (DISK_IO_PORT_COMMAND_STATUS >> 8) & 0xFF)
          builder.emit(0xB0, DISK_IO_COMMAND_READ) # mov al, 1
          builder.emit(0xEE) # out dx, al
          builder.emit(0xEC) # in al, dx
          builder.emit(0xA8, DISK_IO_STATUS_ERROR) # test al, 0x80
          builder.emit_jne(:int13_error_pop)

          builder.emit(0x89, 0xDF) # mov di, bx
          builder.emit(0xA0) # mov al, [moffs8]
          builder.emit_abs16(:int13_sector_count)
          builder.emit(0x30, 0xE4) # xor ah, ah
          builder.emit(0x89, 0xC6) # mov si, ax

          builder.label(:int13_sector_loop)
          builder.emit(0xB9, 0x00, 0x02) # mov cx, 512
          builder.label(:int13_byte_loop)
          builder.emit(0xBA, DISK_IO_PORT_DATA & 0xFF, (DISK_IO_PORT_DATA >> 8) & 0xFF) # mov dx, data port
          builder.emit(0xEC) # in al, dx
          builder.emit(0x26, 0x88, 0x05) # mov [es:di], al
          builder.emit(0x47) # inc di
          builder.emit(0x49) # dec cx
          builder.emit_jne(:int13_byte_loop)
          builder.emit(0x4E) # dec si
          builder.emit_jne(:int13_sector_loop)

          builder.emit(0x1F, 0x5F, 0x5E, 0x5A, 0x59, 0x5B) # pop ds,di,si,dx,cx,bx
          builder.emit(0x30, 0xE4) # xor ah, ah
          builder.emit(0xA0) # mov al, [moffs8]
          builder.emit_abs16(:int13_sector_count)
          builder.emit(0xF8) # clc
          builder.emit(0xCF) # iret

          builder.label(:int13_error_pop)
          builder.emit(0x1F, 0x5F, 0x5E, 0x5A, 0x59, 0x5B) # pop ds,di,si,dx,cx,bx

          builder.label(:int13_error)
          builder.emit(0xB4, 0x01) # mov ah, 1
          builder.emit(0xF9) # stc
          builder.emit(0xCF) # iret

          builder.label(:cursor_pos)
          builder.emit(0x00, 0x00)
          builder.label(:kbd_pending_flag)
          builder.emit(0x00)
          builder.label(:kbd_pending_value)
          builder.emit(0x00)
          builder.label(:int13_sector_count)
          builder.emit(0x00)
        end

        class BinaryBuilder
          def initialize
            @bytes = []
            @labels = {}
            @fixups = []
          end

          def label(name)
            key = name.to_sym
            raise ArgumentError, "duplicate label #{key}" if @labels.key?(key)

            @labels[key] = @bytes.length
          end

          def emit(*values)
            values.flatten.each { |entry| @bytes << (Integer(entry) & 0xFF) }
          end

          def emit_mov_word_ptr_label(address:, label:)
            emit(0xC7, 0x06)
            emit_u16(Integer(address))
            emit_abs16(label)
          end

          def emit_mov_word_ptr_imm(address:, value:)
            emit(0xC7, 0x06)
            emit_u16(Integer(address))
            emit_u16(Integer(value))
          end

          def emit_jc(label)
            emit(0x72)
            emit_rel8(label)
          end

          def emit_jc_near(label)
            emit(0x0F, 0x82)
            emit_rel16(label)
          end

          def emit_jne(label)
            emit(0x75)
            emit_rel8(label)
          end

          def emit_jne_near(label)
            emit(0x0F, 0x85)
            emit_rel16(label)
          end

          def emit_je(label)
            emit(0x74)
            emit_rel8(label)
          end

          def emit_je_near(label)
            emit(0x0F, 0x84)
            emit_rel16(label)
          end

          def emit_jmp_short(label)
            emit(0xEB)
            emit_rel8(label)
          end

          def emit_jmp_near(label)
            emit(0xE9)
            emit_rel16(label)
          end

          def emit_abs16(label)
            @fixups << { type: :abs16, offset: @bytes.length, label: label.to_sym }
            emit_u16(0)
          end

          def to_binary
            patch_fixups!
            @bytes.pack("C*")
          end

          private

          def emit_rel8(label)
            @fixups << { type: :rel8, offset: @bytes.length, label: label.to_sym }
            emit(0)
          end

          def emit_rel16(label)
            @fixups << { type: :rel16, offset: @bytes.length, label: label.to_sym }
            emit_u16(0)
          end

          def emit_u16(value)
            masked = Integer(value) & 0xFFFF
            emit(masked & 0xFF, (masked >> 8) & 0xFF)
          end

          def patch_fixups!
            @fixups.each do |fixup|
              target = @labels.fetch(fixup.fetch(:label)) do
                raise ArgumentError, "undefined label #{fixup.fetch(:label)}"
              end
              case fixup.fetch(:type)
              when :abs16
                raise ArgumentError, "label offset out of 16-bit range: #{target}" if target.negative? || target > 0xFFFF

                @bytes[fixup.fetch(:offset)] = target & 0xFF
                @bytes[fixup.fetch(:offset) + 1] = (target >> 8) & 0xFF
              when :rel8
                displacement = target - (fixup.fetch(:offset) + 1)
                if displacement < -128 || displacement > 127
                  raise ArgumentError, "short jump out of range (#{displacement}) for #{fixup.fetch(:label)}"
                end

                @bytes[fixup.fetch(:offset)] = displacement & 0xFF
              when :rel16
                displacement = target - (fixup.fetch(:offset) + 2)
                if displacement < -32_768 || displacement > 32_767
                  raise ArgumentError, "near jump out of range (#{displacement}) for #{fixup.fetch(:label)}"
                end

                encoded = displacement & 0xFFFF
                @bytes[fixup.fetch(:offset)] = encoded & 0xFF
                @bytes[fixup.fetch(:offset) + 1] = (encoded >> 8) & 0xFF
              else
                raise ArgumentError, "unsupported fixup type #{fixup.fetch(:type)}"
              end
            end
          end
        end
      end
    end
  end
end
