//! IR Compiler - generates specialized Rust code from Behavior IR
//!
//! This is a pure Rust library with C ABI exports. No Ruby dependencies.
//! Ruby bindings are done via Fiddle in the Ruby wrapper class.
//!
//! The module is organized as:
//! - core.rs: Generic IR simulation infrastructure
//! - extensions/: Example-specific extensions
//!   - apple2/: Apple II full system simulation
//!   - gameboy/: Game Boy full system simulation
//!   - mos6502/: MOS6502 CPU standalone simulation
//! - ffi.rs: Core C ABI function exports

mod core;
#[cfg(feature = "aot")]
mod aot_generated;
mod extensions;
mod ffi;
mod vcd;

pub use core::CoreSimulator;
pub use extensions::{Apple2Extension, GameBoyExtension, Mos6502Extension};
pub use vcd::{VcdTracer, TraceMode, SignalChange, TraceStats};

// Re-export FFI functions at crate root for easier linking
pub use ffi::*;
