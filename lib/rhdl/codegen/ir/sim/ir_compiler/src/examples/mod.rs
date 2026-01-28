//! Example-specific extensions for the IR Compiler
//!
//! This module contains extensions for specific hardware examples:
//! - Apple II full system simulation
//! - MOS6502 CPU standalone simulation

pub mod apple2;
pub mod mos6502;

pub use apple2::Apple2Extension;
pub use mos6502::Mos6502Extension;
