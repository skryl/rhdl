`timescale 1ns/1ps

module altdpram #(
    parameter indata_aclr = "OFF",
    parameter indata_reg = "INCLOCK",
    parameter intended_device_family = "Cyclone V",
    parameter lpm_type = "altdpram",
    parameter outdata_aclr = "OFF",
    parameter outdata_reg = "UNREGISTERED",
    parameter ram_block_type = "AUTO",
    parameter rdaddress_aclr = "OFF",
    parameter rdaddress_reg = "UNREGISTERED",
    parameter rdcontrol_aclr = "OFF",
    parameter rdcontrol_reg = "UNREGISTERED",
    parameter read_during_write_mode_mixed_ports = "DONT_CARE",
    parameter width = 8,
    parameter widthad = 8,
    parameter width_byteena = 1,
    parameter wraddress_aclr = "OFF",
    parameter wraddress_reg = "INCLOCK",
    parameter wrcontrol_aclr = "OFF",
    parameter wrcontrol_reg = "INCLOCK"
) (
    input                   inclock,
    input                   outclock,
    input      [width-1:0]  data,
    input      [widthad-1:0] rdaddress,
    input      [widthad-1:0] wraddress,
    input                   wren,
    output     [width-1:0]  q,
    input                   aclr,
    input      [width_byteena-1:0] byteena,
    input                   inclocken,
    input                   outclocken,
    input                   rdaddressstall,
    input                   rden,
    input                   sclr,
    input                   wraddressstall
);
    localparam DEPTH = (1 << widthad);
    localparam BYTE_WIDTH = (width_byteena > 0) ? ((width + width_byteena - 1) / width_byteena) : width;

    reg [width-1:0] mem [0:DEPTH-1];
    reg [width-1:0] read_word;
    integer idx;

    function [width-1:0] apply_byteena;
        input [width-1:0] prior_word;
        input [width-1:0] next_word;
        input [width_byteena-1:0] mask;
        integer byte_index;
        begin
            apply_byteena = prior_word;
            if (width_byteena <= 1) begin
                apply_byteena = next_word;
            end else begin
                for (byte_index = 0; byte_index < width_byteena; byte_index = byte_index + 1) begin
                    if (mask[byte_index]) begin
                        apply_byteena[(byte_index * BYTE_WIDTH) +: BYTE_WIDTH] =
                            next_word[(byte_index * BYTE_WIDTH) +: BYTE_WIDTH];
                    end
                end
            end
        end
    endfunction

    always @(posedge inclock or posedge aclr) begin
        if (aclr || sclr) begin
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                mem[idx] <= {width{1'b0}};
            end
        end else if (inclocken && !wraddressstall && wren) begin
            mem[wraddress] <= apply_byteena(mem[wraddress], data, byteena);
        end
    end

    always @* begin
        read_word = {width{1'b0}};
        if (outclocken && !rdaddressstall && rden) begin
            read_word = mem[rdaddress];
            if (inclocken && !wraddressstall && wren && (rdaddress == wraddress)) begin
                read_word = apply_byteena(mem[wraddress], data, byteena);
            end
        end
    end

    assign q = read_word;
endmodule
