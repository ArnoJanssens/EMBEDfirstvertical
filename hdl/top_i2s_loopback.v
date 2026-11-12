`timescale 1ns / 1ps
// Top-level I2S loopback, translated from top_i2s_loopback.vhd.
// Requires: clk_wiz_0, adau1761_hd_init, audio_clock_divider,
//           i2s_receiver, i2s_transmitter, and Xilinx UNISIM ODDR.
module top_i2s_loopback (
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire sw_src,
    output wire audio_scl,
    inout  wire audio_sda,
    output wire cfg_ok,
    output wire led_pllen,
    output wire led_lock,
    output wire mclk_out,
    output wire bclk_out,
    output wire lrclk_out,
    input  wire sdata_in,
    output wire sdata_out,
    output wire dbg_scl,
    output wire dbg_sda,
    output wire dbg_mclk,
    output wire dbg_bclk,
    output wire dbg_lrclk,
    output wire dbg_sdata_in,
    output wire dbg_sdata_out,
    output wire dbg_pmod_sdout,
    output wire pmod_tx_mclk,
    output wire pmod_tx_lrck,
    output wire pmod_tx_sclk,
    output wire pmod_tx_sdin,
    output wire pmod_rx_mclk,
    output wire pmod_rx_lrck,
    output wire pmod_rx_sclk,
    input  wire pmod_rx_sdout
);
    wire mclk, mclk_codec, mmcm_locked, rst_n, rst_n_btn;
    wire bclk, lrclk;
    wire signed [15:0] left_sample, right_sample;
    wire signed [15:0] pmod_left_sample, pmod_right_sample;
    wire signed [15:0] tx_left, tx_right;
    wire data_valid, pmod_data_valid;
    wire scl_i, sdo_i, init_sda_i, init_sda_o, init_sda_t;
    wire [1:0] dbg_read_bits;

    // Temporary diagnostic tone (generated but not connected to the DAC).
    reg [15:0] tone_phase;
    wire signed [15:0] tone_sample = $signed(tone_phase);

    // Board BTN0 is active-high; sys_rst_n is its raw input.
    assign rst_n_btn = ~sys_rst_n;
    assign rst_n = mmcm_locked & rst_n_btn;

    adau1761_hd_init u_codec_init (
        .clk(sys_clk),
        .reset_n(rst_n_btn),
        .scl(scl_i),
        .sda_i(init_sda_i),
        .sda_o(init_sda_o),
        .sda_t(init_sda_t),
        .cfg_ok(cfg_ok),
        .dbg_read(dbg_read_bits)
    );
    assign led_pllen = dbg_read_bits[0];
    assign led_lock  = dbg_read_bits[1];

    clk_wiz_0 u_clk_wiz (
        .reset(1'b0), //reset kon ik niet wegkrijgen zoals de tutorial ze
        .clk_in1(sys_clk),
        .clk_out1(mclk),
        .clk_out2(mclk_codec),
        .locked(mmcm_locked)
    );

    audio_clock_divider u_clk_div (
        .mclk(mclk), .rst_n(rst_n), .bclk(bclk), .lrclk(lrclk)
    );

    i2sparallelreceiver #(.DATA_WIDTH(16)) u_rx (
        .mclk(mclk), .rst_n(rst_n),
        .bclk(bclk), .lrclk(lrclk), .sdata_in(sdata_in),
        .left_out(left_sample), .right_out(right_sample),
        .data_valid(data_valid)
    );

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n)
            tone_phase <= 16'd0;
        else if (data_valid)
            tone_phase <= tone_phase + 16'd1365;
    end

    assign tx_left  = sw_src ? pmod_left_sample  : left_sample;
    assign tx_right = sw_src ? pmod_right_sample : right_sample;

    i2stransmitter #(.DATA_WIDTH(16)) u_tx (
        .mclk(mclk), .rst_n(rst_n),
        .bclk(bclk), .lrclk(lrclk), .sdata_out(sdo_i),
        .left_in(tx_left), .right_in(tx_right)
    );
    assign sdata_out = sdo_i;

    // Forward codec MCLK through an output DDR flip-flop.
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("SYNC"))
    u_mclk_oddr (
        .Q(mclk_out), .C(mclk_codec), .CE(1'b1),
        .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0)
    );
    assign bclk_out  = bclk;
    assign lrclk_out = lrclk;

    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("SYNC"))
    u_pmod_tx_mclk_oddr (
        .Q(pmod_tx_mclk), .C(mclk), .CE(1'b1),
        .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0)
    );
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("SYNC"))
    u_pmod_rx_mclk_oddr (
        .Q(pmod_rx_mclk), .C(mclk), .CE(1'b1),
        .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0)
    );

    assign pmod_tx_sclk = bclk;
    assign pmod_tx_lrck = lrclk;
    assign pmod_tx_sdin = sdo_i;
    assign pmod_rx_sclk = bclk;
    assign pmod_rx_lrck = lrclk;

    i2sparallelreceiver #(.DATA_WIDTH(16)) u_rx_pmod (
        .mclk(mclk), .rst_n(rst_n),
        .bclk(bclk), .lrclk(lrclk), .sdata_in(pmod_rx_sdout),
        .left_out(pmod_left_sample), .right_out(pmod_right_sample),
        .data_valid(pmod_data_valid)
    );

    assign dbg_scl        = scl_i;
    assign dbg_sda        = audio_sda;
    assign dbg_mclk       = mclk;
    assign dbg_bclk       = bclk;
    assign dbg_lrclk      = lrclk;
    assign dbg_sdata_in   = sdata_in;
    assign dbg_sdata_out  = sdo_i;
    assign dbg_pmod_sdout = pmod_rx_sdout;

    // Open-drain I2C: never actively drive a high level.
    assign audio_sda = (init_sda_t == 1'b0) ? init_sda_o : 1'bz;
    assign init_sda_i = audio_sda;
    assign audio_scl = (scl_i == 1'b0) ? 1'b0 : 1'bz;
endmodule