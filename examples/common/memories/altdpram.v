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
    input tri0              aclr,
    input      [width_byteena-1:0] byteena,
    input tri1              inclocken,
    input tri1              outclocken,
    input tri0              rdaddressstall,
    input tri1              rden,
    input tri0              sclr,
    input tri0              wraddressstall
);
    // Quartus primitives treat omitted optional controls as enabled/bypassed.
    // Use tri0/tri1 port defaults instead of pullup/pulldown primitives so
    // the module stays importable by circt-verilog.

    localparam DEPTH = (1 << widthad);
    localparam BYTE_WIDTH = (width_byteena > 0) ? ((width + width_byteena - 1) / width_byteena) : width;

    reg [width-1:0] mem [0:DEPTH-1];
    reg [width-1:0] read_word;
    reg [width-1:0] write_data_reg;
    reg [widthad-1:0] write_address_reg;
    reg write_enable_reg;
    reg [width_byteena-1:0] write_byteena_reg;
    integer idx;

    wire effective_aclr = (aclr === 1'b1);
    wire effective_sclr = (sclr === 1'b1);
    wire effective_inclocken = (inclocken === 1'b0) ? 1'b0 : 1'b1;
    wire effective_outclocken = (outclocken === 1'b0) ? 1'b0 : 1'b1;
    wire effective_rdaddressstall = (rdaddressstall === 1'b1);
    wire effective_wraddressstall = (wraddressstall === 1'b1);
    wire effective_rden = (rden === 1'b0) ? 1'b0 : 1'b1;
    wire [width_byteena-1:0] effective_byteena;
    wire [widthad-1:0] effective_write_address = write_address_reg;

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

    function [width_byteena-1:0] sanitize_byteena;
        input [width_byteena-1:0] raw_mask;
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < width_byteena; byte_index = byte_index + 1) begin
                sanitize_byteena[byte_index] = (raw_mask[byte_index] === 1'b0) ? 1'b0 : 1'b1;
            end
        end
    endfunction

    assign effective_byteena = sanitize_byteena(byteena);

    always @(posedge inclock or posedge aclr) begin
        if (effective_aclr || effective_sclr) begin
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                mem[idx] <= {width{1'b0}};
            end
            write_data_reg <= {width{1'b0}};
            if (widthad > 0) begin
                write_address_reg <= {widthad{1'b0}};
            end
            write_enable_reg <= 1'b0;
            write_byteena_reg <= {width_byteena{1'b1}};
        end else begin
            if (effective_inclocken && !effective_wraddressstall && write_enable_reg) begin
                mem[effective_write_address] <= apply_byteena(
                    mem[effective_write_address],
                    write_data_reg,
                    write_byteena_reg
                );
            end

            if (effective_inclocken && !effective_wraddressstall) begin
                write_data_reg <= data;
                if (widthad > 0) begin
                    write_address_reg <= wraddress;
                end
                write_enable_reg <= wren;
                write_byteena_reg <= effective_byteena;
            end
        end
    end

    always @* begin
        read_word = {width{1'b0}};
        if (effective_outclocken && !effective_rdaddressstall && effective_rden) begin
            read_word = mem[rdaddress];
            if (effective_inclocken && !effective_wraddressstall && write_enable_reg &&
                (rdaddress == effective_write_address)) begin
                read_word = apply_byteena(
                    mem[effective_write_address],
                    write_data_reg,
                    write_byteena_reg
                );
            end
        end
    end

    assign q = read_word;
endmodule
