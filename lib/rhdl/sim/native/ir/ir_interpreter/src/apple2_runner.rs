//! High-level Apple II runner API for IR interpreter users.
//!
//! This is a native Rust convenience layer over `IrSimContext` and the Apple II
//! extension, similar to the Ruby wrapper API.

use crate::ffi::IrSimContext;
use crate::vcd::TraceMode;

/// Result from running batched Apple II CPU cycles.
#[derive(Debug, Clone, Copy)]
pub struct Apple2RunResult {
    pub text_dirty: bool,
    pub key_cleared: bool,
    pub cycles_run: usize,
    pub speaker_toggles: u32,
}

/// Apple II debug snapshot.
#[derive(Debug, Clone, Copy)]
pub struct Apple2DebugState {
    pub pc: u16,
    pub opcode: u8,
    pub a: u8,
    pub x: u8,
    pub y: u8,
    pub s: u8,
    pub p: u8,
    pub speaker: u8,
    pub cycles: u64,
}

/// Native Rust runner for Apple II IR simulations.
pub struct Apple2Runner {
    ctx: IrSimContext,
    queued_key: Option<u8>,
    cycles: u64,
}

impl Apple2Runner {
    /// Create a runner from flattened IR JSON.
    pub fn new(ir_json: &str, sub_cycles: usize) -> Result<Self, String> {
        let ctx = IrSimContext::new(ir_json, sub_cycles)?;
        if ctx.apple2.is_none() {
            return Err("IR does not contain Apple II extension signals".to_string());
        }
        Ok(Self {
            ctx,
            queued_key: None,
            cycles: 0,
        })
    }

    /// Returns true when the loaded IR is Apple II compatible.
    pub fn is_apple2_mode(&self) -> bool {
        self.ctx.apple2.is_some()
    }

    /// Reset simulation state.
    pub fn reset(&mut self) {
        self.ctx.core.reset();
        self.queued_key = None;
        self.cycles = 0;
    }

    /// Queue a single ASCII key to inject into the Apple II keyboard input.
    pub fn queue_key(&mut self, ascii: u8) {
        self.queued_key = Some(ascii);
    }

    /// Clear pending keyboard input.
    pub fn clear_key(&mut self) {
        self.queued_key = None;
    }

    /// Returns true when there is a pending key waiting to be consumed.
    pub fn key_pending(&self) -> bool {
        self.queued_key.is_some()
    }

    /// Total CPU cycles run through this runner.
    pub fn cycle_count(&self) -> u64 {
        self.cycles
    }

    /// Load ROM bytes (mapped at `$D000..$FFFF` by the extension).
    pub fn load_rom(&mut self, data: &[u8]) -> Result<(), String> {
        let apple2 = self
            .ctx
            .apple2
            .as_mut()
            .ok_or_else(|| "Apple II extension not available".to_string())?;
        apple2.load_rom(data);
        Ok(())
    }

    /// Load RAM bytes at an offset in the 48K RAM space.
    pub fn load_ram(&mut self, offset: usize, data: &[u8]) -> Result<(), String> {
        let apple2 = self
            .ctx
            .apple2
            .as_mut()
            .ok_or_else(|| "Apple II extension not available".to_string())?;
        apple2.load_ram(data, offset);
        Ok(())
    }

    /// Read RAM bytes.
    pub fn read_ram(&self, offset: usize, len: usize) -> Result<Vec<u8>, String> {
        let apple2 = self
            .ctx
            .apple2
            .as_ref()
            .ok_or_else(|| "Apple II extension not available".to_string())?;
        Ok(apple2.read_ram(offset, len).to_vec())
    }

    /// Write RAM bytes.
    pub fn write_ram(&mut self, offset: usize, data: &[u8]) -> Result<(), String> {
        let apple2 = self
            .ctx
            .apple2
            .as_mut()
            .ok_or_else(|| "Apple II extension not available".to_string())?;
        apple2.write_ram(offset, data);
        Ok(())
    }

    /// Run batched CPU cycles using extension-level memory bridging.
    pub fn run_cpu_cycles(&mut self, n: usize) -> Result<Apple2RunResult, String> {
        let key_data = self.queued_key.unwrap_or(0);
        let key_ready = self.queued_key.is_some();

        let result = {
            let apple2 = self
                .ctx
                .apple2
                .as_mut()
                .ok_or_else(|| "Apple II extension not available".to_string())?;
            apple2.run_cpu_cycles(&mut self.ctx.core, n, key_data, key_ready)
        };

        if result.key_cleared {
            self.queued_key = None;
        }

        self.cycles = self.cycles.saturating_add(result.cycles_run as u64);

        if self.ctx.tracer.is_enabled() {
            self.ctx.tracer.capture(&self.ctx.core.signals);
        }

        Ok(Apple2RunResult {
            text_dirty: result.text_dirty,
            key_cleared: result.key_cleared,
            cycles_run: result.cycles_run,
            speaker_toggles: result.speaker_toggles,
        })
    }

    /// Read current debug signals from the Apple II design.
    pub fn debug_state(&self) -> Apple2DebugState {
        let get = |name: &str| self.ctx.core.peek(name).unwrap_or(0);
        Apple2DebugState {
            pc: (get("pc_debug") & 0xFFFF) as u16,
            opcode: (get("opcode_debug") & 0xFF) as u8,
            a: (get("a_debug") & 0xFF) as u8,
            x: (get("x_debug") & 0xFF) as u8,
            y: (get("y_debug") & 0xFF) as u8,
            s: (get("s_debug") & 0xFF) as u8,
            p: (get("p_debug") & 0xFF) as u8,
            speaker: (get("speaker") & 0x1) as u8,
            cycles: self.cycles,
        }
    }

    /// Read the Apple II text screen as 24 lines.
    pub fn read_screen_lines(&self) -> Result<Vec<String>, String> {
        let text_page = self.read_ram(0x0400, 0x0400)?;
        let mut lines = Vec::with_capacity(24);

        for row in 0..24usize {
            let base = text_line_address(row) - 0x0400;
            let mut line = String::with_capacity(40);
            for col in 0..40usize {
                let ch = *text_page.get(base + col).unwrap_or(&0) & 0x7F;
                if (0x20..=0x7E).contains(&ch) {
                    line.push(ch as char);
                } else {
                    line.push(' ');
                }
            }
            lines.push(line);
        }

        Ok(lines)
    }

    /// Poke an arbitrary signal by name.
    pub fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        self.ctx.core.poke(name, value)
    }

    /// Peek an arbitrary signal by name.
    pub fn peek(&self, name: &str) -> Result<u64, String> {
        self.ctx.core.peek(name)
    }

    /// Evaluate combinational logic.
    pub fn evaluate(&mut self) {
        self.ctx.core.evaluate();
        if self.ctx.tracer.is_enabled() {
            self.ctx.tracer.capture(&self.ctx.core.signals);
        }
    }

    /// Run a generic clock tick (non-Apple II extension path).
    pub fn tick(&mut self) {
        self.ctx.core.tick();
        if self.ctx.tracer.is_enabled() {
            self.ctx.tracer.capture(&self.ctx.core.signals);
        }
    }

    /// Start VCD tracing in buffer mode.
    pub fn trace_start(&mut self) {
        self.ctx.tracer.set_mode(TraceMode::Buffer);
        self.ctx.tracer.start();
        self.ctx.tracer.capture(&self.ctx.core.signals);
    }

    /// Start VCD tracing in streaming mode.
    pub fn trace_start_streaming(&mut self, path: &str) -> Result<(), String> {
        self.ctx.tracer.open_file(path)?;
        self.ctx.tracer.start();
        self.ctx.tracer.capture(&self.ctx.core.signals);
        Ok(())
    }

    /// Stop VCD tracing.
    pub fn trace_stop(&mut self) {
        self.ctx.tracer.stop();
        self.ctx.tracer.close_file();
    }

    /// Trace all available signals.
    pub fn trace_all_signals(&mut self) {
        self.ctx.tracer.trace_all_signals();
    }

    /// Add a signal by name to the trace set.
    pub fn trace_add_signal(&mut self, name: &str) -> bool {
        self.ctx.tracer.add_signal_by_name(name)
    }

    /// Get the full buffered VCD output.
    pub fn trace_to_vcd(&self) -> String {
        self.ctx.tracer.to_vcd()
    }

    /// Get incremental live VCD output since the previous call.
    pub fn trace_take_live_vcd(&mut self) -> String {
        self.ctx.tracer.take_live_chunk()
    }

    /// Save full buffered VCD to disk.
    pub fn trace_save_vcd(&self, path: &str) -> Result<(), String> {
        self.ctx.tracer.save_vcd(path)
    }
}

fn text_line_address(row: usize) -> usize {
    let group = row / 8;
    let line_in_group = row % 8;
    0x0400 + (line_in_group * 0x80) + (group * 0x28)
}
