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
//!   - cpu8bit/: examples/8bit CPU standalone simulation
//!   - sparc64/: SPARC64 `s1_top` Wishbone host simulation
//! - ffi.rs: Core C ABI function exports

pub mod apple2_runner;
pub mod core;
#[path = "../../ir_compiler/src/runtime_value.rs"]
pub mod runtime_value;
#[path = "../../common/runtime_frontend.rs"]
pub mod runtime_frontend;
#[path = "../../common/signal_value.rs"]
pub mod signal_value;
mod extensions;
mod ffi;
mod vcd;

pub use apple2_runner::{Apple2DebugState, Apple2RunResult, Apple2Runner};
pub use core::CoreSimulator;
pub use extensions::{
    Apple2Extension, Cpu8BitExtension, GameBoyExtension, Mos6502Extension, Sparc64Extension,
};
pub use vcd::{SignalChange, TraceMode, TraceStats, VcdTracer};

// Re-export FFI functions at crate root for easier linking
pub use ffi::*;
