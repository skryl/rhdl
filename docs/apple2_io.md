# Apple ][-style I/O support

This project includes a minimal Apple ][ / Apple ][+ style I/O bus for the 6502 core
to run unmodified Apple II binaries in tests. The implementation is intentionally
lightweight and focuses on memory-mapped I/O behavior rather than video rendering.

## Supported address ranges

### RAM

* `0x0000-0xBFFF`: read/write RAM (including text page memory at `0x0400-0x07FF`).

### I/O page (`0xC000-0xC0FF`)

#### Keyboard

* `0xC000`: read keyboard data. Returns the last key value with bit 7 set if a key is
  pending, or `0x00` if no key is ready.
* `0xC010`: clear the keyboard strobe (read or write).

#### Speaker

* `0xC030`: toggles the speaker click on any access (read or write). The bus records
  speaker toggles for tests.

#### Video soft switches (state only)

The following soft switches update internal video mode state when accessed (read or write):

* `0xC050`: graphics mode (text off)
* `0xC051`: text mode (text on)
* `0xC052`: mixed off
* `0xC053`: mixed on
* `0xC054`: page2 off (page1)
* `0xC055`: page2 on
* `0xC056`: hires off (lores)
* `0xC057`: hires on

### ROM

* ROM images can be loaded into any address range (e.g., `0xF800-0xFFFF` for the
  Apple ][ Dead Test ROM). Writes to ROM addresses are ignored.

## Known limitations

* No disk controller emulation.
* No video rendering; only memory and soft-switch state are tracked.
* No Apple II ROM calls yet (e.g., `COUT` at `0xFDED` is future work).

## Running the Apple II binary tests

The Apple ][ Dead Test ROM is downloaded on demand to `spec/fixtures/apple2/apple2dead.bin`.

```bash
bundle exec rspec spec/apple2_deadtest_spec.rb
```
