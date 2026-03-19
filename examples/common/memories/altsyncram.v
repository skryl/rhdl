`timescale 1ns/1ps

module altsyncram #(
    parameter address_aclr_a = "NONE",
    parameter address_aclr_b = "NONE",
    parameter address_reg_b = "CLOCK1",
    parameter byte_size = 8,
    parameter clock_enable_input_a = "NORMAL",
    parameter clock_enable_input_b = "NORMAL",
    parameter clock_enable_output_a = "BYPASS",
    parameter clock_enable_output_b = "BYPASS",
    parameter intended_device_family = "Cyclone V",
    parameter lpm_hint = "ENABLE_RUNTIME_MOD=NO",
    parameter lpm_type = "altsyncram",
    parameter numwords_a = 256,
    parameter numwords_b = 256,
    parameter operation_mode = "DUAL_PORT",
    parameter outdata_aclr_a = "NONE",
    parameter outdata_aclr_b = "NONE",
    parameter outdata_reg_a = "UNREGISTERED",
    parameter outdata_reg_b = "UNREGISTERED",
    parameter power_up_uninitialized = "FALSE",
    parameter read_during_write_mode_mixed_ports = "DONT_CARE",
    parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    parameter read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
    parameter widthad_a = 8,
    parameter widthad_b = 8,
    parameter width_a = 8,
    parameter width_b = 8,
    parameter width_byteena_a = 1,
    parameter width_byteena_b = 1,
    parameter wrcontrol_wraddress_reg_b = "CLOCK1"
) (
    input      [widthad_a-1:0] address_a,
    input      [widthad_b-1:0] address_b,
    input                      clock0,
    input                      clock1,
    input                      clocken0,
    input                      clocken1,
    input                      clocken2,
    input                      clocken3,
    input      [width_a-1:0]   data_a,
    input      [width_b-1:0]   data_b,
    input      [width_byteena_a-1:0] byteena_a,
    input      [width_byteena_b-1:0] byteena_b,
    input                      wren_a,
    input                      wren_b,
    input                      aclr0,
    input                      aclr1,
    input                      addressstall_a,
    input                      addressstall_b,
    input                      rden_a,
    input                      rden_b,
    output     [width_a-1:0]   q_a,
    output     [width_b-1:0]   q_b,
    output                     eccstatus
);
    localparam MEM_WIDTH = (width_a > width_b) ? width_a : width_b;
    localparam MEM_DEPTH = (numwords_a > numwords_b) ? numwords_a : numwords_b;
    localparam BYTE_WIDTH_A = (width_byteena_a > 0) ? ((width_a + width_byteena_a - 1) / width_byteena_a) : width_a;
    localparam BYTE_WIDTH_B = (width_byteena_b > 0) ? ((width_b + width_byteena_b - 1) / width_byteena_b) : width_b;

    reg [MEM_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    reg [width_a-1:0] q_a_word;
    reg [width_b-1:0] q_b_word;
    integer idx;

    function [MEM_WIDTH-1:0] apply_byteena_a;
        input [MEM_WIDTH-1:0] prior_word;
        input [width_a-1:0] next_word;
        input [width_byteena_a-1:0] mask;
        integer byte_index;
        begin
            apply_byteena_a = prior_word;
            if (width_byteena_a <= 1) begin
                apply_byteena_a[width_a-1:0] = next_word;
            end else begin
                for (byte_index = 0; byte_index < width_byteena_a; byte_index = byte_index + 1) begin
                    if (mask[byte_index]) begin
                        apply_byteena_a[(byte_index * BYTE_WIDTH_A) +: BYTE_WIDTH_A] =
                            next_word[(byte_index * BYTE_WIDTH_A) +: BYTE_WIDTH_A];
                    end
                end
            end
        end
    endfunction

    function [MEM_WIDTH-1:0] apply_byteena_b;
        input [MEM_WIDTH-1:0] prior_word;
        input [width_b-1:0] next_word;
        input [width_byteena_b-1:0] mask;
        integer byte_index;
        begin
            apply_byteena_b = prior_word;
            if (width_byteena_b <= 1) begin
                apply_byteena_b[width_b-1:0] = next_word;
            end else begin
                for (byte_index = 0; byte_index < width_byteena_b; byte_index = byte_index + 1) begin
                    if (mask[byte_index]) begin
                        apply_byteena_b[(byte_index * BYTE_WIDTH_B) +: BYTE_WIDTH_B] =
                            next_word[(byte_index * BYTE_WIDTH_B) +: BYTE_WIDTH_B];
                    end
                end
            end
        end
    endfunction

    always @(posedge clock0 or posedge aclr0) begin
        if (aclr0) begin
            for (idx = 0; idx < MEM_DEPTH; idx = idx + 1) begin
                mem[idx] <= {MEM_WIDTH{1'b0}};
            end
        end else if (clocken0 && !addressstall_a && wren_a) begin
            mem[address_a] <= apply_byteena_a(mem[address_a], data_a, byteena_a);
        end
    end

    always @* begin
        q_a_word = {width_a{1'b0}};
        if (clocken2 && !addressstall_a && rden_a) begin
            q_a_word = mem[address_a][width_a-1:0];
            if (clocken0 && !addressstall_a && wren_a) begin
                q_a_word = apply_byteena_a(mem[address_a], data_a, byteena_a)[width_a-1:0];
            end
        end
    end

    always @* begin
        q_b_word = {width_b{1'b0}};
        if (clocken3 && !addressstall_b && rden_b) begin
            q_b_word = mem[address_b][width_b-1:0];
            if (clocken0 && !addressstall_a && wren_a && (address_a == address_b)) begin
                q_b_word = apply_byteena_a(mem[address_a], data_a, byteena_a)[width_b-1:0];
            end
        end
    end

    assign q_a = q_a_word;
    assign q_b = q_b_word;
    assign eccstatus = 1'b0;
endmodule
