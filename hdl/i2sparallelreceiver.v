`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Defensie
// Engineer: Arno Janssens
// 
// Create Date: 11/10/2026 09:42:12 PM
// Design Name: 
// Module Name: i2sparallelreceiver
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: based on tutorial by Yuri Cauwerts
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module i2sparallelreceiver #(
    parameter DATA_WIDTH = 16
)(
    // System clock
    input  wire mclk,
    input  wire rst_n,       // Active-low reset

    // I2S interface
    input  wire bclk,
    input  wire lrclk,
    input  wire sdata_in,

    // Parallel audio output
    output wire signed [DATA_WIDTH-1:0] left_out,
    output wire signed [DATA_WIDTH-1:0] right_out,
    output wire data_valid
);

    // ============================================================
    // BCLK synchronizer
    // ============================================================

    reg bclk_r1;
    reg bclk_r2;

    wire bclk_rise;

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_r1 <= 1'b0;
            bclk_r2 <= 1'b0;
        end
        else begin
            bclk_r1 <= bclk;
            bclk_r2 <= bclk_r1;
        end
    end

    assign bclk_rise = bclk_r1 & ~bclk_r2;


    // ============================================================
    // LRCLK synchronizer
    // ============================================================

    reg lrclk_r1;
    reg lrclk_r2;
    reg lrclk_prev;

    wire lrclk_changed;

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            lrclk_r1 <= 1'b0;
            lrclk_r2 <= 1'b0;
        end
        else begin
            lrclk_r1 <= lrclk;
            lrclk_r2 <= lrclk_r1;
        end
    end

    assign lrclk_changed = (lrclk_r2 != lrclk_prev);


    // ============================================================
    // Receiver registers
    // ============================================================

    localparam COUNT_WIDTH = $clog2(DATA_WIDTH + 1);

    reg [DATA_WIDTH-1:0] shift_reg;
    reg [COUNT_WIDTH-1:0] bit_count;

    reg rcv_channel;   // 0 = Left, 1 = Right
    reg shifting;

    reg signed [DATA_WIDTH-1:0] left_reg;
    reg signed [DATA_WIDTH-1:0] right_reg;

    reg valid_reg;


    // ============================================================
    // Main receiver logic
    // ============================================================

    always @(posedge mclk or negedge rst_n) begin

        if (!rst_n) begin

            shift_reg   <= {DATA_WIDTH{1'b0}};
            bit_count   <= 0;

            rcv_channel <= 1'b0;
            shifting    <= 1'b0;

            left_reg    <= 0;
            right_reg   <= 0;

            valid_reg   <= 1'b0;
            lrclk_prev  <= 1'b0;

        end
        else begin

            // Default: valid is a single MCLK-cycle pulse
            valid_reg <= 1'b0;

            // Store previous LRCLK state
            lrclk_prev <= lrclk_r2;

            // ----------------------------------------------------
            // Detect LRCLK transition
            // ----------------------------------------------------

            if (lrclk_changed) begin

                bit_count   <= 0;
                shifting    <= 1'b0;

                // LRCLK = 0 -> Left
                // LRCLK = 1 -> Right
                rcv_channel <= lrclk_r2;

            end

            // ----------------------------------------------------
            // Detect BCLK rising edge
            // ----------------------------------------------------

            else if (bclk_rise) begin

                // Skip first BCLK after LRCLK transition
                if (!shifting) begin

                    shifting  <= 1'b1;
                    bit_count <= 0;

                end

                // Receive sample bits
                else if (bit_count < DATA_WIDTH) begin

                    shift_reg <= {
                        shift_reg[DATA_WIDTH-2:0],
                        sdata_in
                    };

                    bit_count <= bit_count + 1'b1;

                    // --------------------------------------------
                    // Complete sample received
                    // --------------------------------------------

                    if (bit_count == DATA_WIDTH - 1) begin

                        if (rcv_channel == 1'b0) begin

                            // Left channel
                            left_reg <= {
                                shift_reg[DATA_WIDTH-2:0],
                                sdata_in
                            };

                        end
                        else begin

                            // Right channel
                            right_reg <= {
                                shift_reg[DATA_WIDTH-2:0],
                                sdata_in
                            };

                            // Both channels received
                            valid_reg <= 1'b1;

                        end

                    end
                end
            end
        end
    end


    // ============================================================
    // Output assignments
    // ============================================================

    assign left_out   = left_reg;
    assign right_out  = right_reg;
    assign data_valid = valid_reg;

endmodule