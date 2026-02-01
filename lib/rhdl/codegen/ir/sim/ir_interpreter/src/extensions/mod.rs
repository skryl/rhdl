//! Extension modules for the IR Interpreter
//!
//! Each extension provides example-specific functionality:
//! - apple2: Apple II full system simulation
//! - gameboy: Game Boy full system simulation
//! - mos6502: MOS6502 CPU standalone simulation

pub mod apple2;
pub mod gameboy;
pub mod mos6502;

pub use apple2::Apple2Extension;
pub use gameboy::GameBoyExtension;
pub use mos6502::Mos6502Extension;
