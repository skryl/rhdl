//! VCD (Value Change Dump) Tracing Module
//!
//! Provides signal tracing functionality with support for:
//! - Buffer mode: Accumulate traces in memory, export at end
//! - Streaming mode: Write changes directly to a file
//! - Selective signal tracing or all signals

use std::collections::HashSet;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::time::Instant;

/// Signal change event
#[derive(Debug, Clone)]
pub struct SignalChange {
    pub time: u64,
    pub signal_idx: usize,
    pub value: u64,
}

/// VCD trace mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TraceMode {
    /// Buffer all changes in memory
    Buffer,
    /// Stream changes to a file
    Streaming,
}

/// VCD Tracer for capturing signal changes
pub struct VcdTracer {
    /// Current simulation time (in time units)
    time: u64,

    /// Tracing enabled
    enabled: bool,

    /// Trace mode
    mode: TraceMode,

    /// Signal indices to trace (empty = all signals)
    traced_signals: HashSet<usize>,

    /// Previous signal values for change detection
    prev_values: Vec<u64>,

    /// Signal names (indexed by signal index)
    signal_names: Vec<String>,

    /// Signal widths (indexed by signal index)
    signal_widths: Vec<usize>,

    /// VCD identifier for each signal (indexed by signal index)
    vcd_ids: Vec<String>,

    /// Buffered changes (for Buffer mode)
    changes: Vec<SignalChange>,

    /// File writer (for Streaming mode)
    file_writer: Option<BufWriter<File>>,

    /// Whether the VCD header has been written
    header_written: bool,

    /// Time scale string
    timescale: String,

    /// Module name for VCD
    module_name: String,

    /// Start time for elapsed tracking
    start_instant: Option<Instant>,

    /// Maximum buffer size before auto-flush (0 = unlimited)
    max_buffer_size: usize,
}

impl VcdTracer {
    /// Create a new VCD tracer
    pub fn new() -> Self {
        Self {
            time: 0,
            enabled: false,
            mode: TraceMode::Buffer,
            traced_signals: HashSet::new(),
            prev_values: Vec::new(),
            signal_names: Vec::new(),
            signal_widths: Vec::new(),
            vcd_ids: Vec::new(),
            changes: Vec::new(),
            file_writer: None,
            header_written: false,
            timescale: "1ns".to_string(),
            module_name: "top".to_string(),
            start_instant: None,
            max_buffer_size: 10_000_000, // 10M changes before auto-flush warning
        }
    }

    /// Initialize the tracer with signal metadata
    pub fn init(&mut self, signal_names: Vec<String>, signal_widths: Vec<usize>) {
        let n = signal_names.len();
        self.signal_names = signal_names;
        self.signal_widths = signal_widths;
        self.prev_values = vec![0; n];

        // Generate VCD identifiers (ASCII characters starting from '!')
        // For more than 93 signals, use multi-character identifiers
        self.vcd_ids = (0..n).map(|i| Self::idx_to_vcd_id(i)).collect();
    }

    /// Convert an index to a VCD identifier (ASCII-safe)
    fn idx_to_vcd_id(idx: usize) -> String {
        // VCD allows printable ASCII 33-126 (94 characters)
        // For larger designs, use multi-character identifiers
        let base = 94;
        let offset = 33u8; // '!'

        if idx < base {
            return ((offset + idx as u8) as char).to_string();
        }

        // Multi-character: base-94 encoding
        let mut result = String::new();
        let mut n = idx;
        loop {
            result.insert(0, (offset + (n % base) as u8) as char);
            n /= base;
            if n == 0 {
                break;
            }
            n -= 1; // Adjust for 0-based first digit
        }
        result
    }

    /// Set the trace mode
    pub fn set_mode(&mut self, mode: TraceMode) {
        self.mode = mode;
    }

    /// Set the timescale string (e.g., "1ns", "1ps", "10ns")
    pub fn set_timescale(&mut self, timescale: &str) {
        self.timescale = timescale.to_string();
    }

    /// Set the module name for VCD output
    pub fn set_module_name(&mut self, name: &str) {
        self.module_name = name.to_string();
    }

    /// Add a specific signal to trace by index
    pub fn add_signal(&mut self, idx: usize) {
        self.traced_signals.insert(idx);
    }

    /// Add a specific signal to trace by name
    pub fn add_signal_by_name(&mut self, name: &str) -> bool {
        for (idx, sig_name) in self.signal_names.iter().enumerate() {
            if sig_name == name {
                self.traced_signals.insert(idx);
                return true;
            }
        }
        false
    }

    /// Add multiple signals by name pattern (simple substring match)
    pub fn add_signals_matching(&mut self, pattern: &str) -> usize {
        let mut count = 0;
        for (idx, name) in self.signal_names.iter().enumerate() {
            if name.contains(pattern) {
                self.traced_signals.insert(idx);
                count += 1;
            }
        }
        count
    }

    /// Clear the traced signals set (will trace no signals)
    pub fn clear_signals(&mut self) {
        self.traced_signals.clear();
    }

    /// Trace all signals
    pub fn trace_all_signals(&mut self) {
        self.traced_signals.clear();
        for i in 0..self.signal_names.len() {
            self.traced_signals.insert(i);
        }
    }

    /// Start tracing
    pub fn start(&mut self) {
        self.enabled = true;
        self.time = 0;
        self.start_instant = Some(Instant::now());
        self.header_written = false;

        // If no signals specified, trace all
        if self.traced_signals.is_empty() {
            self.trace_all_signals();
        }
    }

    /// Stop tracing
    pub fn stop(&mut self) {
        self.enabled = false;

        // Flush any remaining streaming data
        if let Some(ref mut writer) = self.file_writer {
            let _ = writer.flush();
        }
    }

    /// Open a file for streaming mode
    pub fn open_file(&mut self, path: &str) -> Result<(), String> {
        let file = File::create(path).map_err(|e| format!("Failed to create VCD file: {}", e))?;
        self.file_writer = Some(BufWriter::with_capacity(1024 * 1024, file)); // 1MB buffer
        self.mode = TraceMode::Streaming;
        Ok(())
    }

    /// Close the streaming file
    pub fn close_file(&mut self) {
        if let Some(ref mut writer) = self.file_writer {
            let _ = writer.flush();
        }
        self.file_writer = None;
    }

    /// Check if tracing is enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Check if a signal should be traced
    #[inline(always)]
    fn should_trace(&self, idx: usize) -> bool {
        self.traced_signals.is_empty() || self.traced_signals.contains(&idx)
    }

    /// Record the current state of all traced signals (called at each time step)
    pub fn capture(&mut self, signals: &[u64]) {
        if !self.enabled {
            return;
        }

        // Write header if not done yet
        if !self.header_written {
            self.write_header();
        }

        // Check for changes - collect first to avoid borrow issues
        let time = self.time;
        let traced_signals = &self.traced_signals;
        let prev_values = &self.prev_values;

        let indices_to_update: Vec<(usize, u64)> = signals.iter().enumerate()
            .filter(|&(idx, &val)| {
                (traced_signals.is_empty() || traced_signals.contains(&idx)) &&
                idx < prev_values.len() &&
                val != prev_values[idx]
            })
            .map(|(idx, &val)| (idx, val))
            .collect();

        // Now update prev_values and build changes
        let changes: Vec<SignalChange> = indices_to_update.iter()
            .map(|&(idx, val)| {
                self.prev_values[idx] = val;
                SignalChange { time, signal_idx: idx, value: val }
            })
            .collect();

        if !changes.is_empty() {
            match self.mode {
                TraceMode::Buffer => {
                    self.changes.extend(changes);
                }
                TraceMode::Streaming => {
                    self.write_changes(&changes);
                }
            }
        }

        self.time += 1;
    }

    /// Advance time without capturing (for batched simulation)
    pub fn advance_time(&mut self, cycles: u64) {
        self.time += cycles;
    }

    /// Set the current time explicitly
    pub fn set_time(&mut self, time: u64) {
        self.time = time;
    }

    /// Get current time
    pub fn get_time(&self) -> u64 {
        self.time
    }

    /// Get number of recorded changes
    pub fn change_count(&self) -> usize {
        self.changes.len()
    }

    /// Write VCD header
    fn write_header(&mut self) {
        if self.header_written {
            return;
        }

        let mut header = String::new();

        // Header
        header.push_str(&format!("$timescale {} $end\n", self.timescale));
        header.push_str(&format!("$scope module {} $end\n", self.module_name));

        // Variable declarations (only traced signals)
        for (idx, name) in self.signal_names.iter().enumerate() {
            if self.should_trace(idx) {
                let width = self.signal_widths.get(idx).copied().unwrap_or(1);
                let vcd_id = &self.vcd_ids[idx];
                // Sanitize name for VCD (replace problematic chars)
                let safe_name = name.replace(".", "_").replace("[", "_").replace("]", "");
                header.push_str(&format!("$var wire {} {} {} $end\n", width, vcd_id, safe_name));
            }
        }

        header.push_str("$upscope $end\n");
        header.push_str("$enddefinitions $end\n");

        // Initial values
        header.push_str("$dumpvars\n");
        for (idx, &val) in self.prev_values.iter().enumerate() {
            if self.should_trace(idx) {
                let width = self.signal_widths.get(idx).copied().unwrap_or(1);
                let vcd_id = &self.vcd_ids[idx];
                header.push_str(&Self::format_value(val, width, vcd_id));
                header.push('\n');
            }
        }
        header.push_str("$end\n");

        // Write to file or store
        match self.mode {
            TraceMode::Streaming => {
                if let Some(ref mut writer) = self.file_writer {
                    let _ = writer.write_all(header.as_bytes());
                }
            }
            TraceMode::Buffer => {
                // For buffer mode, we'll include the header in the final output
            }
        }

        self.header_written = true;
    }

    /// Write changes to the streaming file
    fn write_changes(&mut self, changes: &[SignalChange]) {
        if let Some(ref mut writer) = self.file_writer {
            let mut output = String::new();
            let mut last_time: Option<u64> = None;

            for change in changes {
                if last_time != Some(change.time) {
                    output.push_str(&format!("#{}\n", change.time));
                    last_time = Some(change.time);
                }

                let width = self.signal_widths.get(change.signal_idx).copied().unwrap_or(1);
                let vcd_id = &self.vcd_ids[change.signal_idx];
                output.push_str(&Self::format_value(change.value, width, vcd_id));
                output.push('\n');
            }

            let _ = writer.write_all(output.as_bytes());
        }
    }

    /// Format a signal value for VCD output
    fn format_value(value: u64, width: usize, vcd_id: &str) -> String {
        if width == 1 {
            format!("{}{}", value & 1, vcd_id)
        } else {
            // Format as binary with leading zeros
            let binary = format!("{:0width$b}", value, width = width);
            format!("b{} {}", binary, vcd_id)
        }
    }

    /// Export buffered traces to VCD format string
    pub fn to_vcd(&self) -> String {
        let mut vcd = String::new();

        // Header
        vcd.push_str(&format!("$timescale {} $end\n", self.timescale));
        vcd.push_str(&format!("$scope module {} $end\n", self.module_name));

        // Variable declarations
        for (idx, name) in self.signal_names.iter().enumerate() {
            if self.should_trace(idx) {
                let width = self.signal_widths.get(idx).copied().unwrap_or(1);
                let vcd_id = &self.vcd_ids[idx];
                let safe_name = name.replace(".", "_").replace("[", "_").replace("]", "");
                vcd.push_str(&format!("$var wire {} {} {} $end\n", width, vcd_id, safe_name));
            }
        }

        vcd.push_str("$upscope $end\n");
        vcd.push_str("$enddefinitions $end\n");

        // Initial values (all zeros or from first recorded values)
        vcd.push_str("$dumpvars\n");
        for (idx, _) in self.signal_names.iter().enumerate() {
            if self.should_trace(idx) {
                let width = self.signal_widths.get(idx).copied().unwrap_or(1);
                let vcd_id = &self.vcd_ids[idx];
                vcd.push_str(&Self::format_value(0, width, vcd_id));
                vcd.push('\n');
            }
        }
        vcd.push_str("$end\n");

        // Value changes (sorted by time)
        let mut sorted_changes = self.changes.clone();
        sorted_changes.sort_by_key(|c| c.time);

        let mut last_time: Option<u64> = None;
        for change in &sorted_changes {
            if last_time != Some(change.time) {
                vcd.push_str(&format!("#{}\n", change.time));
                last_time = Some(change.time);
            }

            let width = self.signal_widths.get(change.signal_idx).copied().unwrap_or(1);
            let vcd_id = &self.vcd_ids[change.signal_idx];
            vcd.push_str(&Self::format_value(change.value, width, vcd_id));
            vcd.push('\n');
        }

        vcd
    }

    /// Save buffered traces to a VCD file
    pub fn save_vcd(&self, path: &str) -> Result<(), String> {
        let vcd = self.to_vcd();
        std::fs::write(path, vcd).map_err(|e| format!("Failed to write VCD file: {}", e))
    }

    /// Clear all buffered traces
    pub fn clear(&mut self) {
        self.changes.clear();
        self.time = 0;
        self.header_written = false;
    }

    /// Get statistics about the trace
    pub fn stats(&self) -> TraceStats {
        TraceStats {
            total_changes: self.changes.len(),
            traced_signals: self.traced_signals.len(),
            total_signals: self.signal_names.len(),
            time_range: if self.changes.is_empty() {
                (0, 0)
            } else {
                let min_time = self.changes.iter().map(|c| c.time).min().unwrap_or(0);
                let max_time = self.changes.iter().map(|c| c.time).max().unwrap_or(0);
                (min_time, max_time)
            },
            elapsed: self.start_instant.map(|t| t.elapsed()),
        }
    }
}

impl Default for VcdTracer {
    fn default() -> Self {
        Self::new()
    }
}

/// Statistics about a VCD trace
#[derive(Debug, Clone)]
pub struct TraceStats {
    pub total_changes: usize,
    pub traced_signals: usize,
    pub total_signals: usize,
    pub time_range: (u64, u64),
    pub elapsed: Option<std::time::Duration>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vcd_id_generation() {
        assert_eq!(VcdTracer::idx_to_vcd_id(0), "!");
        assert_eq!(VcdTracer::idx_to_vcd_id(1), "\"");
        assert_eq!(VcdTracer::idx_to_vcd_id(93), "~");
        // Multi-character IDs for larger indices
        assert_eq!(VcdTracer::idx_to_vcd_id(94).len(), 2);
    }

    #[test]
    fn test_format_value() {
        assert_eq!(VcdTracer::format_value(1, 1, "!"), "1!");
        assert_eq!(VcdTracer::format_value(0, 1, "!"), "0!");
        assert_eq!(VcdTracer::format_value(255, 8, "\""), "b11111111 \"");
        assert_eq!(VcdTracer::format_value(0, 8, "\""), "b00000000 \"");
    }
}
