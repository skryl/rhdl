//! Extension modules for the JIT simulator
//!
//! Each extension provides example-specific functionality:
//! - apple2: Apple II full system simulation
//! - gameboy: Game Boy full system simulation
//! - mos6502: MOS6502 CPU standalone simulation
//! - cpu8bit: examples/8bit CPU standalone simulation

pub mod apple2;
pub mod cpu8bit;
pub mod gameboy;
pub mod mos6502;

pub use apple2::Apple2Extension;
pub use cpu8bit::Cpu8BitExtension;
pub use gameboy::GameBoyExtension;
pub use mos6502::Mos6502Extension;
