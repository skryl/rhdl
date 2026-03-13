//! Extension modules for the IR Interpreter
//!
//! Each extension provides example-specific functionality:
//! - apple2: Apple II full system simulation
//! - gameboy: Game Boy full system simulation
//! - mos6502: MOS6502 CPU standalone simulation
//! - cpu8bit: examples/8bit CPU standalone simulation
//! - riscv: RISC-V CPU + MMIO system simulation
//! - ao486: AO486 CPU-top host simulation
//! - sparc64: SPARC64 `s1_top` Wishbone host simulation

pub mod ao486;
pub mod apple2;
pub mod cpu8bit;
pub mod gameboy;
pub mod mos6502;
pub mod riscv;
pub mod sparc64;

pub use ao486::Ao486Extension;
pub use apple2::Apple2Extension;
pub use cpu8bit::Cpu8BitExtension;
pub use gameboy::GameBoyExtension;
pub use mos6502::Mos6502Extension;
pub use riscv::RiscvExtension;
pub use sparc64::Sparc64Extension;
