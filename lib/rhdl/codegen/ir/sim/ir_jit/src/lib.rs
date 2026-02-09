//! Cranelift-based JIT compiler for IR simulation
//!
//! This is a pure Rust library with C ABI exports. No Ruby dependencies.
//! Ruby bindings are done via Fiddle in the Ruby wrapper class.
//!
//! The module is organized as:
//! - core.rs: Generic JIT compiler and simulator infrastructure
//! - extensions/: Example-specific extensions
//!   - apple2/: Apple II full system simulation
//!   - mos6502/: MOS6502 CPU standalone simulation
//! - ffi.rs: Core C ABI function exports

mod core;
mod extensions;
mod ffi;
mod vcd;

pub use core::CoreSimulator;
pub use extensions::{Apple2Extension, GameBoyExtension, Mos6502Extension};
pub use vcd::{SignalChange, TraceMode, TraceStats, VcdTracer};

// Re-export FFI functions at crate root for easier linking
pub use ffi::*;
