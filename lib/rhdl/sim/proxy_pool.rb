# frozen_string_literal: true

module RHDL
  module Sim
    # Object pool for ValueProxy instances to reduce GC pressure
    # Proxies are recycled after each propagation cycle
    class ProxyPool
      # Maximum pool size per width to prevent memory bloat
      MAX_POOL_SIZE = 100

      def initialize
        @pools = Hash.new { |h, k| h[k] = [] }
        @in_use = []
      end

      # Acquire a ValueProxy from the pool or create a new one
      def acquire(value, width, context)
        pool = @pools[width]
        proxy = if pool.empty?
                  ValueProxy.allocate
                else
                  pool.pop
                end
        proxy.send(:reinitialize, value, width, context)
        @in_use << proxy
        proxy
      end

      # Release all proxies back to the pool
      # Called at the end of each propagation cycle
      def release_all
        @in_use.each do |proxy|
          width = proxy.width
          pool = @pools[width]
          pool << proxy if pool.size < MAX_POOL_SIZE
        end
        @in_use.clear
      end

      # Clear all pools (for testing or reset)
      def clear
        @pools.clear
        @in_use.clear
      end

      # Stats for debugging
      def stats
        {
          pools: @pools.transform_values(&:size),
          in_use: @in_use.size
        }
      end
    end

    # Thread-local pool accessor
    module ProxyPoolAccessor
      class << self
        def pool
          Thread.current[:rhdl_proxy_pool] ||= ProxyPool.new
        end

        def release_all
          pool.release_all
        end

        def clear
          pool.clear
        end
      end
    end
  end
end
