//! IR Compiler - generates specialized Rust code from Behavior IR
//!
//! This is a pure Rust library with C ABI exports. No Ruby dependencies.
//! Ruby bindings are done via Fiddle in the Ruby wrapper class.
//!
//! The module is organized as:
//! - core.rs: Generic IR simulation infrastructure
//! - examples/: Example-specific extensions (Apple II, MOS6502)
//! - ffi.rs: C ABI function exports

mod core;
mod examples;
mod ffi;

pub use core::CoreSimulator;
pub use examples::{Apple2Extension, Mos6502Extension};

// Re-export FFI functions at crate root for easier linking
pub use ffi::*;
