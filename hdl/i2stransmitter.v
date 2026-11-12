`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2026 10:59:02 AM
// Design Name: 
// Module Name: i2stransmitter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: Also based on Yuri Cauwerts tutorial
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module i2stransmitter #(
    parameter DATA_WIDTH = 16
)(
    // System clock
    input  wire mclk,
    input  wire rst_n,

    // I2S interface
    input  wire bclk,
    input  wire lrclk,
    output reg  sdata_out,

    // Parallel audio inputs
    input  wire signed [DATA_WIDTH-1:0] left_in,
    input  wire signed [DATA_WIDTH-1:0] right_in
);

    // ============================================================
    // BCLK delay line
    // ============================================================

    reg bclk_r1;
    reg bclk_r2;

    wire bclk_strobe;

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

    // Detect delayed BCLK rising edge
    assign bclk_strobe = bclk_r1 & ~bclk_r2;


    // ============================================================
    // LRCLK delay line
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
    // Transmit shift register
    // ============================================================

    reg [DATA_WIDTH-1:0] shift_reg;


    // ============================================================
    // Main transmitter logic
    // ============================================================

    always @(posedge mclk or negedge rst_n) begin

        if (!rst_n) begin

            shift_reg  <= {DATA_WIDTH{1'b0}};
            lrclk_prev <= 1'b0;
            sdata_out  <= 1'b0;

        end
        else begin

            // Store previous LRCLK state
            lrclk_prev <= lrclk_r2;

            // ----------------------------------------------------
            // Detect LRCLK transition
            // ----------------------------------------------------

            if (lrclk_changed) begin

                // Load the channel that is starting
                if (lrclk_r2 == 1'b1) begin

                    // Right channel
                    shift_reg <= right_in;

                end
                else begin

                    // Left channel
                    shift_reg <= left_in;

                end

            end

            // ----------------------------------------------------
            // Shift data on delayed BCLK rising edge
            // ----------------------------------------------------

            else if (bclk_strobe) begin

                // Output most significant bit
                sdata_out <= shift_reg[DATA_WIDTH-1];

                // Shift left, inserting zero at LSB
                shift_reg <= {
                    shift_reg[DATA_WIDTH-2:0],
                    1'b0
                };

            end

        end
    end

endmodule
