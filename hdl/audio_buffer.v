`timescale 1ns / 1ps

// Parameterizable circular audio buffer with a bundled-data CDC handshake.
// Source: I2S receiver clock domain. Destination: FFT/base-clock domain.
// BUFFER_SIZE must be a power of two; 1 <= HOP_SIZE <= BUFFER_SIZE.
// Both clock domains must use the same reset assertion (rst_n).
module audio_buffer #(
    parameter integer DATA_WIDTH  = 16,
    parameter integer BUFFER_SIZE = 1024,
    parameter integer HOP_SIZE    = 512,
    parameter integer ADDR_WIDTH  = $clog2(BUFFER_SIZE)
)(
    input  wire                     src_clk,    //I2S clock
    input  wire                     clk,       // 125 MHz destination clock
    input  wire                     rst_n,     // active-low asynchronous assertion

    input  wire signed [DATA_WIDTH-1:0] sample_in,
    input  wire                     sample_valid, // one src_clk cycle per sample
    output reg                      sample_overflow,

    input  wire [ADDR_WIDTH-1:0]    read_addr,
    output reg signed [DATA_WIDTH-1:0] read_data,
    output reg                      frame_ready, // one destination-clock pulse
    output reg [ADDR_WIDTH-1:0]     frame_start
);

    // Source captures and holds a complete data word until acknowledged.
    reg signed [DATA_WIDTH-1:0] sample_hold;
    reg request_toggle;
    (* ASYNC_REG = "TRUE" *) reg ack_sync1, ack_sync2;

    wire src_ready;

    assign src_ready = (request_toggle == ack_sync2);

    always @(posedge src_clk or negedge rst_n) begin //I2S clock domain
        if (!rst_n) begin// on reset
            sample_hold     <= {DATA_WIDTH{1'b0}};
            request_toggle  <= 1'b0;
            ack_sync1       <= 1'b0;
            ack_sync2       <= 1'b0;
            sample_overflow <= 1'b0;
        end else begin
            ack_sync1 <= ack_toggle;
            ack_sync2 <= ack_sync1;

            if (sample_valid) begin
                if (src_ready) begin
                    sample_hold    <= sample_in; //copy sample to internal buffer
                    request_toggle <= ~request_toggle; //sample toggle, easier to detect in other clock domain
                end else begin
                    // Sticky flag: source produced a sample before prior ack.
                    sample_overflow <= 1'b1;
                end
            end
        end
    end

    // Synchronize only the request toggle; sample_hold remains stable
    // throughout the synchronization delay (bundled-data CDC).
    (* ASYNC_REG = "TRUE" *) reg req_sync1, req_sync2;
    reg ack_toggle;

    reg signed [DATA_WIDTH-1:0] audio_ram [0:BUFFER_SIZE-1];
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] initial_count;
    reg initial_filled;
    localparam integer HOP_WIDTH = (HOP_SIZE > 1) ? $clog2(HOP_SIZE) : 1;
    reg [HOP_WIDTH-1:0] hop_counter;

    // A separate synchronous read port supports BRAM inference.
    always @(posedge clk) begin
        read_data <= audio_ram[read_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_sync1    <= 1'b0;
            req_sync2    <= 1'b0;
            ack_toggle   <= 1'b0;
            write_ptr    <= {ADDR_WIDTH{1'b0}};
            initial_count <= {ADDR_WIDTH{1'b0}};
            initial_filled <= 1'b0;
            hop_counter  <= {HOP_WIDTH{1'b0}};
            frame_ready  <= 1'b0;
            frame_start  <= {ADDR_WIDTH{1'b0}};
        end else begin
            req_sync1   <= request_toggle; //Two FF toggle buffer -> I2S clk domain certainly out of metastable state
            req_sync2   <= req_sync1;
            frame_ready <= 1'b0;

            if (req_sync2 != ack_toggle) begin
                // Request has propagated through two destination flops;
                // the source data register has been held stable throughout.
                audio_ram[write_ptr] <= sample_hold;
                write_ptr <= write_ptr + 1'b1;
                ack_toggle <= req_sync2; //check toggle -> will only retoggle on next sample

                if (!initial_filled) begin
                    if (initial_count == BUFFER_SIZE - 1) begin
                        initial_filled <= 1'b1;
                        frame_ready <= 1'b1;
                        frame_start <= write_ptr + 1'b1;
                        hop_counter <= {HOP_WIDTH{1'b0}};
                    end else begin
                        initial_count <= initial_count + 1'b1;
                    end
                end else begin
                    if (hop_counter == HOP_SIZE - 1) begin
                        hop_counter <= {HOP_WIDTH{1'b0}};
                        frame_ready <= 1'b1;
                        frame_start <= write_ptr + 1'b1;
                    end else begin
                        hop_counter <= hop_counter + 1'b1;
                    end
                end
            end
        end
    end
endmodule