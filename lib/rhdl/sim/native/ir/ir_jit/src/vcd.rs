// Shared VCD implementation lives one level up under sim/native/ir/common.
#[path = "../../common/vcd.rs"]
mod shared_vcd;

pub use shared_vcd::*;
