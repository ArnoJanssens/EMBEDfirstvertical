// =============================================================================
// File    : audio_clock_divider.v
// Purpose : Generates BCLK and LRCLK from MCLK
//
// MCLK  = 12.288 MHz
// BCLK  = MCLK / 4  = 3.072 MHz
// LRCLK = BCLK / 64 = 48 kHz
//
// 32 BCLK cycles per channel
// 64 BCLK cycles per stereo frame
//
// Standard I2S:
// - MSB delayed by 1 BCLK after LRCLK transition
// - 16-bit audio samples
// - 32-bit channel slots
// =============================================================================

module audio_clock_divider (
    input  wire mclk,
    input  wire rst_n,

    output wire bclk,
    output wire lrclk
);

    // ============================================================
    // Internal registers
    // ============================================================

    // Divide MCLK by 4
    reg [1:0] bclk_cnt;
    reg       bclk_int;

    // Divide BCLK by 64
    reg [5:0] lrclk_cnt;
    reg       lrclk_int;


    // ============================================================
    // Clock divider
    // ============================================================

    always @(posedge mclk or negedge rst_n) begin

        if (!rst_n) begin

            bclk_cnt  <= 2'd0;
            bclk_int  <= 1'b0;

            lrclk_cnt <= 6'd0;
            lrclk_int <= 1'b0;

        end
        else begin

            // ----------------------------------------------------
            // BCLK generation
            // Toggle every 2 MCLK cycles
            // ----------------------------------------------------

            if (bclk_cnt == 2'd1) begin

                bclk_cnt <= 2'd0;
                bclk_int <= ~bclk_int;

                // ------------------------------------------------
                // LRCLK generation
                // Count BCLK half-periods
                //
                // 64 half-periods = 32 full BCLK cycles
                // ------------------------------------------------

                if (lrclk_cnt == 6'd63) begin

                    lrclk_cnt <= 6'd0;
                    lrclk_int <= ~lrclk_int;

                end
                else begin

                    lrclk_cnt <= lrclk_cnt + 1'b1;

                end

            end
            else begin

                bclk_cnt <= bclk_cnt + 1'b1;

            end

        end

    end


    // ============================================================
    // Output assignments
    // ============================================================

    assign bclk  = bclk_int;
    assign lrclk = lrclk_int;

endmodule