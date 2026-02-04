# Appendix X: Cerebras Implementation

*Network-on-Chip components in RHDL*

---

## Overview

This appendix provides RHDL implementations of key Cerebras/NoC components:

1. **MeshRouter**: 5-port router with XY routing
2. **VirtualChannelBuffer**: Input buffering with VCs
3. **Crossbar5x5**: Non-blocking switch fabric
4. **CreditManager**: Flow control
5. **ProcessingElement**: Simplified compute tile
6. **MeshNetwork**: Assembled 2D mesh
7. **DataflowController**: Execution coordination

---

## Flit and Packet Format

```ruby
module RHDL::NoC
  # Flit types for wormhole routing
  module FlitType
    HEAD = 0b00    # Contains routing info
    BODY = 0b01    # Payload data
    TAIL = 0b10    # Last flit of packet
    SINGLE = 0b11  # Single-flit packet (head + tail)
  end

  # Flit structure
  class Flit < SimComponent
    parameter :data_width, default: 256

    # Flit fields
    output :flit_type, width: 2
    output :vc_id, width: 2           # Virtual channel
    output :dest_x, width: 10         # Destination X coordinate
    output :dest_y, width: 10         # Destination Y coordinate
    output :payload, width: :data_width

    input :raw, width: :data_width + 24

    behavior do
      flit_type <= raw[1:0]
      vc_id <= raw[3:2]
      dest_x <= raw[13:4]
      dest_y <= raw[23:14]
      payload <= raw[data_width+23:24]
    end
  end

  # Packet builder helper
  class PacketBuilder
    def self.head_flit(dest_x:, dest_y:, vc: 0)
      (dest_y << 14) | (dest_x << 4) | (vc << 2) | FlitType::HEAD
    end

    def self.body_flit(data, vc: 0)
      (data << 24) | (vc << 2) | FlitType::BODY
    end

    def self.tail_flit(data, vc: 0)
      (data << 24) | (vc << 2) | FlitType::TAIL
    end
  end
end
```

---

## XY Routing Logic

```ruby
module RHDL::NoC
  # Direction encoding
  module Direction
    LOCAL = 0
    NORTH = 1
    SOUTH = 2
    EAST  = 3
    WEST  = 4
  end

  # XY routing: route X first, then Y
  class XYRouter < SimComponent
    parameter :coord_width, default: 10

    # Current position
    input :my_x, width: :coord_width
    input :my_y, width: :coord_width

    # Destination from flit header
    input :dest_x, width: :coord_width
    input :dest_y, width: :coord_width

    # Routing decision
    output :output_port, width: 3

    behavior do
      if dest_x == my_x && dest_y == my_y
        # Arrived at destination
        output_port <= Direction::LOCAL
      elsif dest_x > my_x
        # Go East first (X dimension)
        output_port <= Direction::EAST
      elsif dest_x < my_x
        # Go West first (X dimension)
        output_port <= Direction::WEST
      elsif dest_y > my_y
        # Then go South (Y dimension)
        output_port <= Direction::SOUTH
      else
        # Then go North (Y dimension)
        output_port <= Direction::NORTH
      end
    end
  end
end
```

---

## Virtual Channel Buffer

```ruby
module RHDL::NoC
  # Input buffer with multiple virtual channels
  class VirtualChannelBuffer < SimComponent
    parameter :num_vcs, default: 4
    parameter :depth_per_vc, default: 4
    parameter :flit_width, default: 280

    input :clk
    input :reset

    # Write interface
    input :write_data, width: :flit_width
    input :write_vc, width: 2
    input :write_en

    # Read interface (per VC)
    input :read_vc, width: 2
    input :read_en
    output :read_data, width: :flit_width
    output :read_valid

    # Status (per VC)
    output :vc_empty, width: :num_vcs
    output :vc_full, width: :num_vcs
    output :vc_credits, width: :num_vcs * 4  # 4 bits per VC

    # Storage: FIFO per VC
    memory :buffers, depth: num_vcs * depth_per_vc, width: flit_width
    memory :head_ptr, depth: num_vcs, width: 4
    memory :tail_ptr, depth: num_vcs, width: 4
    memory :count, depth: num_vcs, width: 4

    behavior do
      # Status computation
      num_vcs.times do |vc|
        vc_empty[vc] <= (count[vc] == 0) ? 1 : 0
        vc_full[vc] <= (count[vc] == depth_per_vc) ? 1 : 0
        vc_credits[vc*4+3:vc*4] <= depth_per_vc - count[vc]
      end

      # Read output
      read_valid <= (count[read_vc] > 0) ? 1 : 0
      if count[read_vc] > 0
        read_data <= buffers[read_vc * depth_per_vc + head_ptr[read_vc]]
      end

      on_rising_edge(:clk) do
        if reset == 1
          num_vcs.times do |vc|
            head_ptr[vc] <= 0
            tail_ptr[vc] <= 0
            count[vc] <= 0
          end
        else
          # Write operation
          if write_en == 1 && vc_full[write_vc] == 0
            addr = write_vc * depth_per_vc + tail_ptr[write_vc]
            buffers[addr] <= write_data
            tail_ptr[write_vc] <= (tail_ptr[write_vc] + 1) % depth_per_vc
            count[write_vc] <= count[write_vc] + 1
          end

          # Read operation
          if read_en == 1 && vc_empty[read_vc] == 0
            head_ptr[read_vc] <= (head_ptr[read_vc] + 1) % depth_per_vc
            count[read_vc] <= count[read_vc] - 1
          end
        end
      end
    end
  end
end
```

---

## Credit Manager

```ruby
module RHDL::NoC
  # Credit-based flow control
  class CreditManager < SimComponent
    parameter :num_vcs, default: 4
    parameter :init_credits, default: 4  # Buffer depth at receiver

    input :clk
    input :reset

    # Credit return from downstream
    input :credit_in
    input :credit_vc, width: 2

    # Credit consumption (when sending flit)
    input :consume_credit
    input :consume_vc, width: 2

    # Available credits per VC
    output :credits, width: :num_vcs * 4
    output :can_send, width: :num_vcs  # At least one credit available

    memory :credit_count, depth: num_vcs, width: 4

    behavior do
      # Output current credits
      num_vcs.times do |vc|
        credits[vc*4+3:vc*4] <= credit_count[vc]
        can_send[vc] <= (credit_count[vc] > 0) ? 1 : 0
      end

      on_rising_edge(:clk) do
        if reset == 1
          num_vcs.times { |vc| credit_count[vc] <= init_credits }
        else
          # Credit return (receiver freed a buffer slot)
          if credit_in == 1
            credit_count[credit_vc] <= credit_count[credit_vc] + 1
          end

          # Credit consumption (we sent a flit)
          if consume_credit == 1 && credit_count[consume_vc] > 0
            credit_count[consume_vc] <= credit_count[consume_vc] - 1
          end
        end
      end
    end
  end
end
```

---

## 5×5 Crossbar

```ruby
module RHDL::NoC
  # Non-blocking 5x5 crossbar switch
  class Crossbar5x5 < SimComponent
    parameter :data_width, default: 280

    input :clk

    # Input ports (N, S, E, W, Local)
    input :in_north, width: :data_width
    input :in_south, width: :data_width
    input :in_east, width: :data_width
    input :in_west, width: :data_width
    input :in_local, width: :data_width

    # Input valid signals
    input :valid_north, :valid_south, :valid_east, :valid_west, :valid_local

    # Output ports
    output :out_north, width: :data_width
    output :out_south, width: :data_width
    output :out_east, width: :data_width
    output :out_west, width: :data_width
    output :out_local, width: :data_width

    # Crossbar configuration (which input to each output)
    # 3 bits per output: 0=none, 1=N, 2=S, 3=E, 4=W, 5=Local
    input :config_north, width: 3
    input :config_south, width: 3
    input :config_east, width: 3
    input :config_west, width: 3
    input :config_local, width: 3

    behavior do
      # North output mux
      out_north <= case config_north
                   when 1 then in_north   # U-turn (unusual)
                   when 2 then in_south
                   when 3 then in_east
                   when 4 then in_west
                   when 5 then in_local
                   else 0
                   end

      # South output mux
      out_south <= case config_south
                   when 1 then in_north
                   when 2 then in_south   # U-turn
                   when 3 then in_east
                   when 4 then in_west
                   when 5 then in_local
                   else 0
                   end

      # East output mux
      out_east <= case config_east
                  when 1 then in_north
                  when 2 then in_south
                  when 3 then in_east    # U-turn
                  when 4 then in_west
                  when 5 then in_local
                  else 0
                  end

      # West output mux
      out_west <= case config_west
                  when 1 then in_north
                  when 2 then in_south
                  when 3 then in_east
                  when 4 then in_west    # U-turn
                  when 5 then in_local
                  else 0
                  end

      # Local output mux
      out_local <= case config_local
                   when 1 then in_north
                   when 2 then in_south
                   when 3 then in_east
                   when 4 then in_west
                   when 5 then in_local  # Loopback
                   else 0
                   end
    end
  end
end
```

---

## Round-Robin Arbiter

```ruby
module RHDL::NoC
  # Round-robin arbiter for crossbar allocation
  class RoundRobinArbiter < SimComponent
    parameter :num_requesters, default: 5

    input :clk
    input :reset

    input :requests, width: :num_requesters
    output :grant, width: :num_requesters
    output :grant_valid

    wire :priority_ptr, width: 3  # Points to highest priority

    behavior do
      # Find first requester starting from priority_ptr
      granted = 0
      grant_idx = 0

      num_requesters.times do |offset|
        idx = (priority_ptr + offset) % num_requesters
        if requests[idx] == 1 && granted == 0
          grant[idx] <= 1
          granted = 1
          grant_idx = idx
        else
          grant[idx] <= 0
        end
      end

      grant_valid <= granted

      on_rising_edge(:clk) do
        if reset == 1
          priority_ptr <= 0
        elsif granted == 1
          # Move priority to next after granted
          priority_ptr <= (grant_idx + 1) % num_requesters
        end
      end
    end
  end
end
```

---

## Complete Mesh Router

```ruby
module RHDL::NoC
  # Complete 5-port mesh router with VC buffers
  class MeshRouter < SimComponent
    parameter :data_width, default: 256
    parameter :num_vcs, default: 4
    parameter :buffer_depth, default: 4
    parameter :coord_width, default: 10

    input :clk
    input :reset

    # Position in mesh
    input :my_x, width: :coord_width
    input :my_y, width: :coord_width

    # North port
    input :north_in_data, width: :data_width + 24
    input :north_in_valid
    output :north_in_credit
    output :north_out_data, width: :data_width + 24
    output :north_out_valid
    input :north_out_credit

    # South port (similar)
    input :south_in_data, width: :data_width + 24
    input :south_in_valid
    output :south_in_credit
    output :south_out_data, width: :data_width + 24
    output :south_out_valid
    input :south_out_credit

    # East port
    input :east_in_data, width: :data_width + 24
    input :east_in_valid
    output :east_in_credit
    output :east_out_data, width: :data_width + 24
    output :east_out_valid
    input :east_out_credit

    # West port
    input :west_in_data, width: :data_width + 24
    input :west_in_valid
    output :west_in_credit
    output :west_out_data, width: :data_width + 24
    output :west_out_valid
    input :west_out_credit

    # Local port (to/from PE)
    input :local_in_data, width: :data_width + 24
    input :local_in_valid
    output :local_in_credit
    output :local_out_data, width: :data_width + 24
    output :local_out_valid
    input :local_out_credit

    # Sub-components
    instance :vc_buf_north, VirtualChannelBuffer,
             num_vcs: num_vcs, depth_per_vc: buffer_depth
    instance :vc_buf_south, VirtualChannelBuffer,
             num_vcs: num_vcs, depth_per_vc: buffer_depth
    instance :vc_buf_east, VirtualChannelBuffer,
             num_vcs: num_vcs, depth_per_vc: buffer_depth
    instance :vc_buf_west, VirtualChannelBuffer,
             num_vcs: num_vcs, depth_per_vc: buffer_depth
    instance :vc_buf_local, VirtualChannelBuffer,
             num_vcs: num_vcs, depth_per_vc: buffer_depth

    instance :crossbar, Crossbar5x5, data_width: data_width + 24
    instance :arbiter, RoundRobinArbiter, num_requesters: 5
    instance :xy_route, XYRouter, coord_width: coord_width

    # Credit managers for output ports
    instance :credits_north, CreditManager, num_vcs: num_vcs
    instance :credits_south, CreditManager, num_vcs: num_vcs
    instance :credits_east, CreditManager, num_vcs: num_vcs
    instance :credits_west, CreditManager, num_vcs: num_vcs
    instance :credits_local, CreditManager, num_vcs: num_vcs

    # Connect clock/reset
    port :clk => [[:vc_buf_north, :clk], [:vc_buf_south, :clk],
                  [:vc_buf_east, :clk], [:vc_buf_west, :clk],
                  [:vc_buf_local, :clk], [:crossbar, :clk],
                  [:arbiter, :clk], [:credits_north, :clk],
                  [:credits_south, :clk], [:credits_east, :clk],
                  [:credits_west, :clk], [:credits_local, :clk]]

    behavior do
      # Route position
      xy_route.my_x <= my_x
      xy_route.my_y <= my_y

      # Buffer incoming flits
      vc_buf_north.write_data <= north_in_data
      vc_buf_north.write_en <= north_in_valid
      # ... (similar for other ports)

      # Return credits when buffer has space
      north_in_credit <= ~vc_buf_north.vc_full[0]  # Simplified
      # ... (similar for other ports)

      # Route decision for head flits in each buffer
      # (In reality, need state machine per input to track routing)

      # Arbitration for output port contention
      # Crossbar configuration based on arbitration result

      # Output valid and data from crossbar
      north_out_data <= crossbar.out_north
      # ... (similar for other ports)
    end
  end
end
```

---

## Processing Element (Simplified)

```ruby
module RHDL::NoC
  # Simplified Processing Element (tensor core + SRAM)
  class ProcessingElement < SimComponent
    parameter :sram_size, default: 48 * 1024  # 48KB
    parameter :data_width, default: 256

    input :clk
    input :reset

    # Network interface
    input :net_in_data, width: :data_width + 24
    input :net_in_valid
    output :net_out_data, width: :data_width + 24
    output :net_out_valid

    # Coordinates (for routing)
    input :my_x, width: 10
    input :my_y, width: 10

    # Local SRAM
    memory :sram, depth: sram_size / 4, width: 32

    # Tensor computation state
    wire :state, width: 4
    wire :accumulator, width: 32

    # States
    IDLE = 0
    LOAD_WEIGHTS = 1
    COMPUTE = 2
    STORE_OUTPUT = 3
    SEND_OUTPUT = 4

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          state <= IDLE
          accumulator <= 0
        else
          case state
          when IDLE
            if net_in_valid == 1
              # Decode incoming flit
              # Could be: weights, activations, control
              state <= LOAD_WEIGHTS
            end

          when LOAD_WEIGHTS
            # Store incoming weights to SRAM
            # Transition to COMPUTE when ready

          when COMPUTE
            # Perform MAC operations
            # accumulator += weight * activation
            state <= STORE_OUTPUT

          when STORE_OUTPUT
            # Write result to SRAM
            state <= SEND_OUTPUT

          when SEND_OUTPUT
            # Send result to next layer via network
            net_out_valid <= 1
            # Pack output into flit with destination
            state <= IDLE
          end
        end
      end
    end
  end
end
```

---

## Mesh Network Assembly

```ruby
module RHDL::NoC
  # NxM mesh network
  class MeshNetwork < SimComponent
    parameter :width, default: 4     # X dimension
    parameter :height, default: 4    # Y dimension
    parameter :data_width, default: 256

    input :clk
    input :reset

    # Create routers and PEs
    # (In real RHDL, would use generate-like constructs)

    def initialize(name, params = {})
      super
      @routers = []
      @pes = []

      # Create grid of routers and PEs
      height.times do |y|
        row_routers = []
        row_pes = []
        width.times do |x|
          router = MeshRouter.new("router_#{x}_#{y}",
                                   data_width: data_width)
          pe = ProcessingElement.new("pe_#{x}_#{y}",
                                      data_width: data_width)

          # Set coordinates
          router.my_x = x
          router.my_y = y
          pe.my_x = x
          pe.my_y = y

          row_routers << router
          row_pes << pe
        end
        @routers << row_routers
        @pes << row_pes
      end

      # Connect routers to neighbors
      connect_mesh
    end

    def connect_mesh
      height.times do |y|
        width.times do |x|
          router = @routers[y][x]

          # Connect to PE
          pe = @pes[y][x]
          connect(router, :local_out_data, pe, :net_in_data)
          connect(router, :local_out_valid, pe, :net_in_valid)
          connect(pe, :net_out_data, router, :local_in_data)
          connect(pe, :net_out_valid, router, :local_in_valid)

          # Connect to East neighbor
          if x < width - 1
            east_router = @routers[y][x + 1]
            connect(router, :east_out_data, east_router, :west_in_data)
            connect(router, :east_out_valid, east_router, :west_in_valid)
            connect(east_router, :west_out_data, router, :east_in_data)
            connect(east_router, :west_out_valid, router, :east_in_valid)
          end

          # Connect to South neighbor
          if y < height - 1
            south_router = @routers[y + 1][x]
            connect(router, :south_out_data, south_router, :north_in_data)
            connect(router, :south_out_valid, south_router, :north_in_valid)
            connect(south_router, :north_out_data, router, :south_in_data)
            connect(south_router, :north_out_valid, router, :south_in_valid)
          end
        end
      end
    end
  end
end
```

---

## Dataflow Controller

```ruby
module RHDL::NoC
  # Coordinates dataflow execution across the mesh
  class DataflowController < SimComponent
    parameter :num_layers, default: 8
    parameter :width, default: 32

    input :clk
    input :reset

    # Layer configuration
    input :layer_start_x, width: 10 * :num_layers
    input :layer_start_y, width: 10 * :num_layers
    input :layer_width, width: 10 * :num_layers
    input :layer_height, width: 10 * :num_layers

    # Control
    input :start
    output :done
    output :layer_active, width: :num_layers

    # Injection ports (to edge routers)
    output :inject_data, width: 280
    output :inject_valid
    output :inject_dest_x, width: 10
    output :inject_dest_y, width: 10

    wire :state, width: 4
    wire :current_batch, width: 16
    wire :inject_count, width: 32

    IDLE = 0
    INJECT = 1
    WAIT_PIPELINE = 2
    DONE = 3

    behavior do
      done <= (state == DONE) ? 1 : 0

      on_rising_edge(:clk) do
        if reset == 1
          state <= IDLE
          current_batch <= 0
          inject_count <= 0
        else
          case state
          when IDLE
            if start == 1
              state <= INJECT
              inject_count <= 0
            end

          when INJECT
            # Inject input data to first layer
            inject_valid <= 1
            inject_dest_x <= layer_start_x[9:0]  # Layer 0
            inject_dest_y <= layer_start_y[9:0]
            inject_count <= inject_count + 1

            # When all inputs injected, wait for pipeline
            if inject_count == 1024  # Example
              state <= WAIT_PIPELINE
            end

          when WAIT_PIPELINE
            inject_valid <= 0
            # Wait for outputs to emerge
            # (Simplified - real implementation tracks completion)
            state <= DONE

          when DONE
            # Signal completion
          end
        end
      end
    end
  end
end
```

---

## Traffic Generator (Test)

```ruby
module RHDL::NoC
  # Generate test traffic for mesh validation
  class TrafficGenerator < SimComponent
    parameter :pattern, default: :uniform  # :uniform, :hotspot, :neighbor
    parameter :injection_rate, default: 0.1
    parameter :mesh_width, default: 4
    parameter :mesh_height, default: 4

    input :clk
    input :reset
    input :my_x, width: 10
    input :my_y, width: 10

    output :flit_out, width: 280
    output :flit_valid
    output :dest_x, width: 10
    output :dest_y, width: 10

    input :flit_in, width: 280
    input :flit_in_valid

    # Statistics
    output :packets_sent, width: 32
    output :packets_received, width: 32

    wire :lfsr, width: 16  # For random generation

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          packets_sent <= 0
          packets_received <= 0
          lfsr <= 0xACE1  # Seed
        else
          # LFSR update
          lfsr <= (lfsr >> 1) ^ ((lfsr[0] == 1) ? 0xB400 : 0)

          # Injection decision based on rate
          if (lfsr[7:0] / 256.0) < injection_rate
            flit_valid <= 1

            # Destination based on pattern
            case pattern
            when :uniform
              # Random destination
              dest_x <= lfsr[3:0] % mesh_width
              dest_y <= lfsr[7:4] % mesh_height
            when :hotspot
              # 50% to center, 50% uniform
              if lfsr[0] == 1
                dest_x <= mesh_width / 2
                dest_y <= mesh_height / 2
              else
                dest_x <= lfsr[3:0] % mesh_width
                dest_y <= lfsr[7:4] % mesh_height
              end
            when :neighbor
              # Only to immediate neighbors
              dest_x <= my_x + (lfsr[1:0] == 0 ? 1 : (lfsr[1:0] == 1 ? -1 : 0))
              dest_y <= my_y + (lfsr[3:2] == 0 ? 1 : (lfsr[3:2] == 1 ? -1 : 0))
            end

            packets_sent <= packets_sent + 1
          else
            flit_valid <= 0
          end

          # Count received packets
          if flit_in_valid == 1
            packets_received <= packets_received + 1
          end
        end
      end
    end
  end
end
```

---

## Performance Metrics

```ruby
module RHDL::NoC
  # Collect mesh performance statistics
  class MeshMetrics < SimComponent
    parameter :mesh_width, default: 4
    parameter :mesh_height, default: 4

    input :clk
    input :reset

    # Per-router statistics (aggregated)
    input :total_flits_sent, width: 32
    input :total_flits_received, width: 32
    input :total_hops, width: 48
    input :total_latency, width: 48

    output :throughput, width: 32      # Flits per cycle
    output :avg_latency, width: 16     # Cycles per packet
    output :avg_hops, width: 8         # Hops per packet
    output :utilization, width: 8      # Link utilization %

    wire :cycle_count, width: 32

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          cycle_count <= 0
        else
          cycle_count <= cycle_count + 1

          # Compute metrics
          if cycle_count > 0
            throughput <= total_flits_received / cycle_count
          end

          if total_flits_received > 0
            avg_latency <= total_latency / total_flits_received
            avg_hops <= total_hops / total_flits_received
          end

          # Utilization: actual / theoretical max
          max_flits = cycle_count * mesh_width * mesh_height * 4  # 4 links per router
          if max_flits > 0
            utilization <= (total_flits_sent * 100) / max_flits
          end
        end
      end
    end
  end
end
```

---

## Test Bench

```ruby
describe "Mesh Network" do
  it "routes packets correctly with XY routing" do
    mesh = RHDL::NoC::MeshNetwork.new("test_mesh",
                                       width: 4, height: 4)
    sim = Simulator.new(mesh)

    # Inject packet from (0,0) to (3,3)
    mesh.inject_packet(src: [0, 0], dest: [3, 3], data: 0xDEADBEEF)

    # Run simulation
    sim.run(100)  # Should arrive in ~6 hops

    # Check packet arrived
    expect(mesh.pe_at(3, 3).received_data).to include(0xDEADBEEF)
  end

  it "handles contention with fair arbitration" do
    mesh = RHDL::NoC::MeshNetwork.new("test_mesh",
                                       width: 4, height: 4)

    # Multiple sources to same destination
    mesh.inject_packet(src: [0, 0], dest: [2, 2], data: 0x1111)
    mesh.inject_packet(src: [0, 1], dest: [2, 2], data: 0x2222)
    mesh.inject_packet(src: [1, 0], dest: [2, 2], data: 0x3333)

    sim = Simulator.new(mesh)
    sim.run(200)

    # All packets should arrive (arbitration, no drops)
    received = mesh.pe_at(2, 2).all_received
    expect(received).to include(0x1111, 0x2222, 0x3333)
  end
end
```

---

## Scaling Considerations

```
WSE-2 at scale:
  - 850,000 routers
  - 3.4 million router ports
  - ~13.6 million virtual channel buffers
  - Clock: ~1 GHz (estimated)

Per-cycle operations:
  - Each router: 5 arbitrations, 5 crossbar transfers
  - Total: 4.25 million arbitrations/cycle
  - Aggregate bandwidth: 850K × 256 bits × 4 ports = 870 Tb/cycle

RHDL simulation:
  - Full WSE: not practical (memory, time)
  - 64×64 mesh: feasible for validation
  - Behavioral model: for large-scale analysis
```

---

*Back to [Chapter 24 - Cerebras](24-cerebras.md)*
