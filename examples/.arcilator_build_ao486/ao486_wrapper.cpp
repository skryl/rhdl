#include <cstdint>
#include <cstring>
#include <cstddef>
#include <cstdlib>
#include <cstdio>
#include <unordered_map>
#include <unordered_set>

extern "C" void ao486_eval(void* state);

struct SignalInfo {
  const char* name;
  uint32_t offset;
  uint32_t bits;
  uint8_t is_input;
};

static const SignalInfo SIGNALS[] = {
  {"clk", 0, 1, 1},
  {"rst_n", 1, 1, 1},
  {"a20_enable", 2, 1, 1},
  {"cache_disable", 3, 1, 1},
  {"interrupt_do", 4, 1, 1},
  {"interrupt_vector", 5, 8, 1},
  {"avm_waitrequest", 6, 1, 1},
  {"avm_readdatavalid", 7, 1, 1},
  {"avm_readdata", 8, 32, 1},
  {"dma_address", 12, 24, 1},
  {"dma_16bit", 15, 1, 1},
  {"dma_write", 16, 1, 1},
  {"dma_writedata", 18, 16, 1},
  {"dma_read", 20, 1, 1},
  {"io_read_data", 24, 32, 1},
  {"io_read_done", 28, 1, 1},
  {"io_write_done", 29, 1, 1},
  {"interrupt_done", 3577, 1, 0},
  {"avm_address", 3580, 30, 0},
  {"avm_writedata", 3584, 32, 0},
  {"avm_byteenable", 3588, 4, 0},
  {"avm_burstcount", 3589, 4, 0},
  {"avm_write", 3590, 1, 0},
  {"avm_read", 3591, 1, 0},
  {"dma_readdata", 3592, 16, 0},
  {"dma_readdatavalid", 3594, 1, 0},
  {"dma_waitrequest", 3595, 1, 0},
  {"io_read_do", 3596, 1, 0},
  {"io_read_address", 3598, 16, 0},
  {"io_read_length", 3600, 3, 0},
  {"io_write_do", 3601, 1, 0},
  {"io_write_address", 3602, 16, 0},
  {"io_write_length", 3604, 3, 0},
  {"io_write_data", 3608, 32, 0}
};
static const size_t SIGNAL_COUNT = sizeof(SIGNALS) / sizeof(SIGNALS[0]);
static const uint32_t STATE_SIZE = 3612;

struct SimContext {
  uint8_t state[STATE_SIZE];
  std::unordered_map<uint32_t, uint32_t> memory;
};

static uint32_t bit_mask(uint32_t bits) {
  if(bits == 0) return 0u;
  if(bits >= 32) return 0xFFFFFFFFu;
  return ((1u << bits) - 1u);
}

static const SignalInfo* find_signal(const char* name) {
  for(size_t i = 0; i < SIGNAL_COUNT; i++) {
    if(std::strcmp(SIGNALS[i].name, name) == 0) {
      return &SIGNALS[i];
    }
  }
  return nullptr;
}

static void write_signal(SimContext* ctx, const SignalInfo* signal, uint32_t value) {
  uint32_t masked = value & bit_mask(signal->bits);
  uint8_t* base = &ctx->state[signal->offset];

  if(signal->bits <= 8) {
    base[0] = static_cast<uint8_t>(masked & 0xFFu);
    return;
  }
  if(signal->bits <= 16) {
    uint16_t v16 = static_cast<uint16_t>(masked & 0xFFFFu);
    std::memcpy(base, &v16, sizeof(uint16_t));
    return;
  }
  uint32_t v32 = masked;
  std::memcpy(base, &v32, sizeof(uint32_t));
}

static uint32_t read_signal(SimContext* ctx, const SignalInfo* signal) {
  uint8_t* base = &ctx->state[signal->offset];

  if(signal->bits <= 8) {
    return static_cast<uint32_t>(base[0]) & bit_mask(signal->bits);
  }
  if(signal->bits <= 16) {
    uint16_t value = 0;
    std::memcpy(&value, base, sizeof(uint16_t));
    return static_cast<uint32_t>(value) & bit_mask(signal->bits);
  }
  uint32_t value = 0;
  std::memcpy(&value, base, sizeof(uint32_t));
  return value & bit_mask(signal->bits);
}

static void write_signal_if_input(SimContext* ctx, const SignalInfo* signal, uint32_t value) {
  if(signal == nullptr) return;
  if(!signal->is_input) return;
  write_signal(ctx, signal, value);
}

static uint32_t read_memory_word(const std::unordered_map<uint32_t, uint32_t>& memory, uint32_t address) {
  auto it = memory.find(address);
  return it == memory.end() ? 0u : it->second;
}

static void write_memory_word(std::unordered_map<uint32_t, uint32_t>& memory, uint32_t address, uint32_t data, uint32_t byteenable) {
  uint32_t current = read_memory_word(memory, address);
  uint32_t merged = current;
  if((byteenable & 0x1u) != 0u) {
    merged = (merged & ~0x000000FFu) | (data & 0x000000FFu);
  }
  if((byteenable & 0x2u) != 0u) {
    merged = (merged & ~0x0000FF00u) | (data & 0x0000FF00u);
  }
  if((byteenable & 0x4u) != 0u) {
    merged = (merged & ~0x00FF0000u) | (data & 0x00FF0000u);
  }
  if((byteenable & 0x8u) != 0u) {
    merged = (merged & ~0xFF000000u) | (data & 0xFF000000u);
  }
  memory[address] = merged & 0xFFFFFFFFu;
}

static void init_inputs(SimContext* ctx) {
  for(size_t i = 0; i < SIGNAL_COUNT; i++) {
    if(SIGNALS[i].is_input) {
      write_signal(ctx, &SIGNALS[i], 0u);
    }
  }
}

static uint32_t read_signal_value(const SimContext* ctx, const SignalInfo* signal) {
  if(signal == nullptr) return 0u;
  return read_signal(const_cast<SimContext*>(ctx), signal);
}

static void write_trace_fetch(
  FILE* trace,
  uint32_t cycle,
  uint32_t address,
  uint32_t data
) {
  std::fprintf(trace, "EV IF %u %08x %08x\n", cycle, address, data);
}

static void write_trace_write(
  FILE* trace,
  uint32_t cycle,
  uint32_t address,
  uint32_t data,
  uint32_t byteenable
) {
  std::fprintf(trace, "EV WR %u %08x %08x %x\n", cycle, address, data, byteenable);
}

extern "C" {
  void* sim_create(void) {
    SimContext* ctx = new SimContext();
    std::memset(ctx->state, 0, sizeof(ctx->state));
    ctx->memory = {};
    return ctx;
  }

  void sim_destroy(void* sim) {
    delete static_cast<SimContext*>(sim);
  }

  void sim_eval(void* sim) {
    SimContext* ctx = static_cast<SimContext*>(sim);
    ao486_eval(ctx->state);
  }

  int sim_has_signal(void* sim, const char* name) {
    (void)sim;
    return find_signal(name) == nullptr ? 0 : 1;
  }

  void sim_poke(void* sim, const char* name, uint32_t value) {
    SimContext* ctx = static_cast<SimContext*>(sim);
    const SignalInfo* signal = find_signal(name);
    if(signal == nullptr) return;
    write_signal(ctx, signal, value);
  }

  uint32_t sim_peek(void* sim, const char* name) {
    SimContext* ctx = static_cast<SimContext*>(sim);
    const SignalInfo* signal = find_signal(name);
    if(signal == nullptr) return 0u;
    return read_signal(ctx, signal);
  }

  int sim_run_program(
    void* sim,
    const uint32_t* program_addresses,
    const uint32_t* program_words,
    uint32_t program_count,
    const uint32_t* fetch_addresses,
    uint32_t fetch_count,
    uint32_t cycles,
    const char* trace_path
  ) {
    if(sim == nullptr) return 1;
    if((program_count > 0u && (program_addresses == nullptr || program_words == nullptr))) return 2;
    if((fetch_count > 0u && fetch_addresses == nullptr)) return 3;
    if(trace_path == nullptr) return 4;

    SimContext* ctx = static_cast<SimContext*>(sim);
    ctx->memory.clear();

    for(uint32_t i = 0; i < program_count; i++) {
      ctx->memory[program_addresses[i]] = program_words[i];
    }

    std::unordered_set<uint32_t> fetch_set;
    for(uint32_t i = 0; i < fetch_count; i++) {
      fetch_set.insert(fetch_addresses[i]);
    }

    FILE* trace = std::fopen(trace_path, "w");
    if(trace == nullptr) return 5;

    init_inputs(ctx);

    const SignalInfo* sig_a20_enable = find_signal("a20_enable");
    const SignalInfo* sig_cache_disable = find_signal("cache_disable");
    const SignalInfo* sig_interrupt_do = find_signal("interrupt_do");
    const SignalInfo* sig_interrupt_vector = find_signal("interrupt_vector");
    const SignalInfo* sig_rst_n = find_signal("rst_n");
    const SignalInfo* sig_avm_waitrequest = find_signal("avm_waitrequest");
    const SignalInfo* sig_avm_readdatavalid = find_signal("avm_readdatavalid");
    const SignalInfo* sig_avm_readdata = find_signal("avm_readdata");
    const SignalInfo* sig_dma_address = find_signal("dma_address");
    const SignalInfo* sig_dma_16bit = find_signal("dma_16bit");
    const SignalInfo* sig_dma_write = find_signal("dma_write");
    const SignalInfo* sig_dma_writedata = find_signal("dma_writedata");
    const SignalInfo* sig_dma_read = find_signal("dma_read");
    const SignalInfo* sig_io_read_data = find_signal("io_read_data");
    const SignalInfo* sig_io_read_done = find_signal("io_read_done");
    const SignalInfo* sig_io_write_done = find_signal("io_write_done");
    const SignalInfo* sig_clk = find_signal("clk");

    const SignalInfo* sig_avm_read = find_signal("avm_read");
    const SignalInfo* sig_avm_write = find_signal("avm_write");
    const SignalInfo* sig_avm_address = find_signal("avm_address");
    const SignalInfo* sig_avm_writedata = find_signal("avm_writedata");
    const SignalInfo* sig_avm_byteenable = find_signal("avm_byteenable");
    const SignalInfo* sig_avm_burstcount = find_signal("avm_burstcount");
    const SignalInfo* sig_io_read_do = find_signal("io_read_do");
    const SignalInfo* sig_io_write_do = find_signal("io_write_do");

    write_signal_if_input(ctx, sig_a20_enable, 1u);
    write_signal_if_input(ctx, sig_cache_disable, 0u);
    write_signal_if_input(ctx, sig_interrupt_do, 0u);
    write_signal_if_input(ctx, sig_interrupt_vector, 0u);
    write_signal_if_input(ctx, sig_avm_waitrequest, 0u);
    write_signal_if_input(ctx, sig_avm_readdatavalid, 0u);
    write_signal_if_input(ctx, sig_avm_readdata, 0u);
    write_signal_if_input(ctx, sig_dma_address, 0u);
    write_signal_if_input(ctx, sig_dma_16bit, 0u);
    write_signal_if_input(ctx, sig_dma_write, 0u);
    write_signal_if_input(ctx, sig_dma_writedata, 0u);
    write_signal_if_input(ctx, sig_dma_read, 0u);
    write_signal_if_input(ctx, sig_io_read_data, 0u);
    write_signal_if_input(ctx, sig_io_read_done, 0u);
    write_signal_if_input(ctx, sig_io_write_done, 0u);
    write_signal_if_input(ctx, sig_rst_n, 0u);
    write_signal_if_input(ctx, sig_clk, 0u);

    uint32_t state_avm_waitrequest = read_signal_value(ctx, sig_avm_waitrequest);
    uint32_t state_avm_readdata = read_signal_value(ctx, sig_avm_readdata);
    uint32_t state_avm_readdatavalid = 0u;
    uint32_t state_io_read_done = 0u;
    uint32_t state_io_write_done = 0u;
    uint32_t state_io_read_data = read_signal_value(ctx, sig_io_read_data);
    uint32_t state_rst_n = 0u;

    if(sig_rst_n != nullptr) {
      state_rst_n = read_signal_value(ctx, sig_rst_n);
    }

    ao486_eval(ctx->state);

    uint32_t cycle = 0u;
    uint32_t pending_read_words = 0u;
    uint32_t pending_read_address = 0u;

    while(cycle <= cycles) {
      if(sig_rst_n != nullptr && cycle == 4u) {
        state_rst_n = 1u;
      }

      state_avm_readdatavalid = 0u;
      state_io_read_done = 0u;
      state_io_write_done = 0u;

      write_signal_if_input(ctx, sig_rst_n, state_rst_n);
      write_signal_if_input(ctx, sig_avm_readdatavalid, state_avm_readdatavalid);
      write_signal_if_input(ctx, sig_avm_readdata, state_avm_readdata);
      write_signal_if_input(ctx, sig_io_read_done, state_io_read_done);
      write_signal_if_input(ctx, sig_io_write_done, state_io_write_done);

      write_signal_if_input(ctx, sig_io_read_data, state_io_read_data);

      if(pending_read_words > 0u) {
        uint32_t read_value = read_memory_word(ctx->memory, pending_read_address);
        write_signal_if_input(ctx, sig_avm_readdata, read_value);
        write_signal_if_input(ctx, sig_avm_readdatavalid, 1u);
        state_avm_readdatavalid = 1u;
        state_avm_readdata = read_value;
        if(fetch_set.find(pending_read_address) != fetch_set.end()) {
          write_trace_fetch(trace, cycle, pending_read_address, read_value);
        }
        pending_read_address = (pending_read_address + 4u) & 0xFFFFFFFFu;
        pending_read_words -= 1u;
      }

      if(state_avm_readdatavalid == 0u && sig_avm_readdatavalid != nullptr) {
        write_signal(ctx, sig_avm_readdatavalid, 0u);
      }

      write_signal_if_input(ctx, sig_clk, 1u);
      ao486_eval(ctx->state);

      uint32_t output_avm_read = read_signal_value(ctx, sig_avm_read) & 1u;
      uint32_t output_avm_write = read_signal_value(ctx, sig_avm_write) & 1u;
      uint32_t output_avm_address = read_signal_value(ctx, sig_avm_address);
      uint32_t output_avm_writedata = read_signal_value(ctx, sig_avm_writedata);
      uint32_t output_avm_burstcount = read_signal_value(ctx, sig_avm_burstcount);
      uint32_t output_avm_byteenable = read_signal_value(ctx, sig_avm_byteenable);
      uint32_t output_io_read_do = read_signal_value(ctx, sig_io_read_do);
      uint32_t output_io_write_do = read_signal_value(ctx, sig_io_write_do);

      if(pending_read_words == 0u && output_avm_read != 0u && state_avm_waitrequest == 0u) {
        pending_read_address = (output_avm_address & 0x3FFFFFFFu) << 4u;
        uint32_t burst_words = output_avm_burstcount & bit_mask(4);
        pending_read_words = burst_words == 0u ? 1u : burst_words;
      }

      if(output_avm_write != 0u && state_avm_waitrequest == 0u) {
        uint32_t address = (output_avm_address & 0x3FFFFFFFu) << 4u;
        write_memory_word(ctx->memory, address, output_avm_writedata, output_avm_byteenable);
        write_trace_write(
          trace,
          cycle,
          address,
          output_avm_writedata,
          output_avm_byteenable
        );
      }

      if(output_io_read_do != 0u) {
        if(sig_io_read_data != nullptr) {
          state_io_read_data = 0u;
        }
        if(sig_io_read_done != nullptr) {
          state_io_read_done = 1u;
        }
      }

      state_io_write_done = output_io_write_do != 0u ? 1u : 0u;
      if(pending_read_words > 0u) {
        state_avm_readdatavalid = 1u;
      }

      write_signal_if_input(ctx, sig_rst_n, state_rst_n);
      write_signal_if_input(ctx, sig_avm_readdatavalid, state_avm_readdatavalid);
      write_signal_if_input(ctx, sig_io_read_done, state_io_read_done);
      write_signal_if_input(ctx, sig_io_write_done, state_io_write_done);
      write_signal_if_input(ctx, sig_io_read_data, state_io_read_data);
      write_signal_if_input(ctx, sig_clk, 0u);
      ao486_eval(ctx->state);

      cycle += 1u;
    }

    std::fclose(trace);
    return 0;
  }
}
