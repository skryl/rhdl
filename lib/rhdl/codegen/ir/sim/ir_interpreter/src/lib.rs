//! IR Interpreter - bytecode-based IR simulation
//!
//! This is a pure Rust library with C ABI exports. No Ruby dependencies.
//! Ruby bindings are done via Fiddle in the Ruby wrapper class.
//!
//! The module is organized as:
//! - core.rs: Generic IR simulation infrastructure
//! - extensions/: Example-specific extensions
//!   - apple2/: Apple II full system simulation
//!   - mos6502/: MOS6502 CPU standalone simulation
//! - ffi.rs: Core C ABI function exports

pub mod core;
mod extensions;
mod ffi;

pub use core::CoreSimulator;
pub use extensions::{Apple2Extension, Mos6502Extension};

// Re-export FFI functions at crate root for easier linking
pub use ffi::*;
