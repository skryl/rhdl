//! Extension modules for the IR Interpreter
//!
//! Extensions provide specialized functionality for specific simulation scenarios.

pub mod apple2;
pub mod mos6502;

pub use apple2::Apple2Extension;
pub use mos6502::Mos6502Extension;
