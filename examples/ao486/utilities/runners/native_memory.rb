# frozen_string_literal: true

module RHDL
  module Examples
    module AO486
      class NativeMemory
        class WordHash < Hash
          def initialize(*args)
            super
          end

          def fetch(key, default = nil)
            super(Integer(key) & 0xFFFF_FFFF, default)
          end
        end

        DEFAULT_MASK = 0xFFFF_FFFF
        BYTE_ENABLE_MASK = 0x0000_000F

        def initialize(initial_words: {})
          @words = WordHash.new
          add_words(initial_words)
        end

        def self.from_words(words)
          new(initial_words: words || {})
        end

        def read_word(address)
          @words.fetch(normalize_address(address), 0) & DEFAULT_MASK
        end

        def read_byte(address)
          addr = normalize_address(address)
          word_address = addr & ~0x3
          shift = (addr & 0x3) * 8
          (read_word(word_address) >> shift) & 0xFF
        end

        def write_word(address:, data:, byteenable: BYTE_ENABLE_MASK)
          addr = normalize_address(address)
          current = read_word(addr)
          enables = Integer(byteenable) & BYTE_ENABLE_MASK
          merged = current
          value = Integer(data) & DEFAULT_MASK
          merged = (merged & ~0x0000_00FF) | (value & 0x0000_00FF) if (enables & 0x1) != 0
          merged = (merged & ~0x0000_FF00) | (value & 0x0000_FF00) if (enables & 0x2) != 0
          merged = (merged & ~0x00FF_0000) | (value & 0x00FF_0000) if (enables & 0x4) != 0
          merged = (merged & ~0xFF00_0000) | (value & 0xFF00_0000) if (enables & 0x8) != 0
          @words[addr] = merged & DEFAULT_MASK
          merged & DEFAULT_MASK
        end

        def write_words(words)
          words.each do |address, value|
            @words[normalize_address(address)] = Integer(value) & DEFAULT_MASK
          end
        end

        def snapshot(addresses)
          Array(addresses).each_with_object({}) do |address, memo|
            normalized = normalize_address(address)
            memo[format("%08x", normalized)] = read_word(normalized)
          end
        end

        def to_h
          @words.dup
        end

        def inspect
          "#<NativeMemory words=#{@words.size}>"
        end

        private

        def add_words(initial_words)
          return if initial_words.nil?

          Array(initial_words).each do |entry|
            @words[normalize_address(entry[0])] = Integer(entry[1]) & DEFAULT_MASK
          end
        end

        def normalize_address(value)
          Integer(value).to_i & 0xFFFF_FFFF
        end
      end
    end
  end
end
