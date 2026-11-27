`timescale 1ns / 1ps

module fft #(
    parameter DATA_WIDTH = 16,
    parameter N_POINT = 1024,
    parameter LED_LEVELS = 2048,
    parameter LED_WIDTH = $clog2(LED_LEVELS),
    parameter STAGES = $clog2(N_POINT),
    parameter ADDR_WIDTH = $clog2(N_POINT),
    parameter BUFFER_ADDR_WIDTH = ADDR_WIDTH,
    parameter COEFF_WIDTH = 16,
    parameter FRAC = 15
)(
    input wire iClk, // 125 MHz
    input wire iNRst,

    // Audio buffer interface
    input wire iFrameReady,
    input wire signed [DATA_WIDTH-1:0] iBufferReadData,
    input wire [BUFFER_ADDR_WIDTH-1:0] iFrameStart,
    output wire [BUFFER_ADDR_WIDTH-1:0] oReadAddress,

    // LED outputs
    output reg [LED_WIDTH-1:0] oLed [0:7],
    output reg oLedReady
);

    // ========================================================
    // FSM STATES
    // ========================================================

    localparam s_idle           = 2'b00;
    localparam s_datacollwindow = 2'b01;
    localparam s_fftstages      = 2'b10;
    localparam s_done           = 2'b11;

    reg [1:0] s_FSM_current;
    reg [1:0] s_FSM_next;

    // ========================================================
    // DATA COLLECTION SIGNALS
    // ========================================================

    reg [BUFFER_ADDR_WIDTH-1:0] frame_start;

    reg [ADDR_WIDTH-1:0] sample_index; //starts from zero

    reg all_requested;

    wire read_valid;

    assign read_valid = (s_FSM_current == s_datacollwindow)
                        && !all_requested;

    assign oReadAddress = frame_start + sample_index; 

    // ========================================================
    // WINDOW ROM
    // ========================================================

    wire [COEFF_WIDTH-1:0] window_coeff;

    window_rom #(
        .N(N_POINT),
        .COEFF_WIDTH(COEFF_WIDTH)
    ) window_rom_src (
        .clk(iClk),
        .i_addr(sample_index),
        .o_coeff(window_coeff)
    );

    // ========================================================
    // FFT WORKING MEMORY
    // ========================================================

    (* ram_style = "block" *)
    reg signed [DATA_WIDTH-1:0] fft_real [0:N_POINT-1];

    (* ram_style = "block" *)
    reg signed [DATA_WIDTH-1:0] fft_imag [0:N_POINT-1];

    // ========================================================
    // WINDOWING PIPELINE SIGNALS
    // ========================================================

    // Stage 1: memory read
    reg valid_d1;
    reg [ADDR_WIDTH-1:0] index_d1;

    // Stage 2: multiplication
    reg valid_d2;
    reg [ADDR_WIDTH-1:0] index_d2;

    reg signed [DATA_WIDTH+COEFF_WIDTH:0] product;

    wire signed [DATA_WIDTH-1:0] windowed_sample;

    // Round and convert back to Q1.15
    assign windowed_sample =
        (product + (33'sd1 <<< (FRAC-1))) >>> FRAC;

    wire collection_done;

    assign collection_done = valid_d2 &&
                             (index_d2 == N_POINT-1);

    // ========================================================
    // BIT REVERSAL FUNCTION
    // ========================================================

    function [ADDR_WIDTH-1:0] bit_reverse;

        input [ADDR_WIDTH-1:0] index;

        integer i;

        begin
            for (i = 0; i < ADDR_WIDTH; i = i + 1)
                begin
                    bit_reverse[i] = index[ADDR_WIDTH-1-i];
                end
        end

    endfunction

    // ========================================================
    // FSM STATE REGISTER
    // ========================================================

    always @(posedge iClk or negedge iNRst)
        begin
            if (!iNRst)
                begin
                    s_FSM_current <= s_idle;
                end
            else
                begin
                    s_FSM_current <= s_FSM_next;
                end
        end

    // ========================================================
    // FSM NEXT STATE LOGIC
    // ========================================================

    always @(*)
        begin

            s_FSM_next = s_FSM_current;

            case (s_FSM_current)

                s_idle:
                    begin
                        if (iFrameReady)
                            s_FSM_next = s_datacollwindow;
                    end

                s_datacollwindow:
                    begin
                        if (collection_done)
                            s_FSM_next = s_fftstages;
                    end

                s_fftstages:
                    begin
                        //TODO change this!!
                        s_FSM_next = s_idle
                    end

                s_done:
                    begin
                        s_FSM_next = s_idle;
                    end

                default:
                    begin
                        s_FSM_next = s_idle;
                    end

            endcase

        end

    // ========================================================
    // DATA COLLECTION COUNTER
    // ========================================================

    always @(posedge iClk or negedge iNRst)
        begin

            if (!iNRst)
                begin
                    frame_start <= 0;
                    sample_index <= 0;
                    all_requested <= 0;
                end

            else
                begin

                    case (s_FSM_current)

                        s_idle:
                            begin
                                sample_index <= 0;
                                all_requested <= 0;

                                if (iFrameReady)
                                    frame_start <= iFrameStart;
                            end

                        s_datacollwindow:
                            begin

                                if (!all_requested)
                                    begin

                                        if (sample_index == N_POINT-1)
                                            all_requested <= 1;

                                        else
                                            sample_index <= sample_index + 1;

                                    end

                            end

                    endcase

                end

        end

    // ========================================================
    // PIPELINE STAGE 1: MEMORY READ
    // ========================================================

    always @(posedge iClk or negedge iNRst)
        begin

            if (!iNRst)
                begin
                    valid_d1 <= 0;
                    index_d1 <= 0;
                end

            else
                begin
                    valid_d1 <= read_valid;
                    index_d1 <= sample_index;
                end

        end

    // ========================================================
    // PIPELINE STAGE 2: WINDOW MULTIPLICATION
    // ========================================================

    always @(posedge iClk or negedge iNRst)
        begin

            if (!iNRst)
                begin
                    valid_d2 <= 0;
                    index_d2 <= 0;
                    product <= 0;
                end

            else
                begin

                    valid_d2 <= valid_d1;
                    index_d2 <= index_d1;

                    if (valid_d1)
                        begin

                            product <= iBufferReadData *
                                       $signed({1'b0, window_coeff});

                        end

                end

        end

    // ========================================================
    // PIPELINE STAGE 3: FFT MEMORY WRITE
    // ========================================================

    always @(posedge iClk)
        begin

            if (iNRst && valid_d2)
                begin

                    fft_real[bit_reverse(index_d2)]
                        <= windowed_sample;

                    fft_imag[bit_reverse(index_d2)]
                        <= 0;

                end

        end

    // ========================================================
    // LED OUTPUT CONTROL
    // ========================================================

    integer led_index;

    always @(posedge iClk or negedge iNRst)
        begin

            if (!iNRst)
                begin

                    oLedReady <= 0;

                    for (led_index = 0;
                         led_index < 8;
                         led_index = led_index + 1)
                        begin
                            oLed[led_index] <= 0;
                        end

                end

            else
                begin
                    oLedReady <= (s_FSM_current == s_done);

                    // TODO: calculate frequency band levels
                end

        end

endmodule