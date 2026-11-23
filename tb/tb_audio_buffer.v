`timescale 1ns / 1ps

module tb_audio_buffer;

    reg src_clk = 0;
    reg clk = 0;
    reg rst_n = 0;
    reg signed [7:0] sample_in = 0;
    reg sample_valid = 0;
    reg [2:0] read_addr = 0;

    wire signed [7:0] read_data;
    wire frame_ready;
    wire [2:0] frame_start;
    wire sample_overflow;

    // 125 MHz system clock (8 ns period)
    always #4 clk = ~clk;

    // Approximate 12.284 MHz audio clock (81.4 ns period)
    always #40.7 src_clk = ~src_clk;

    audio_buffer #(
        .DATA_WIDTH(8),
        .BUFFER_SIZE(8),
        .HOP_SIZE(4)
    ) dut (
        .src_clk(src_clk),
        .clk(clk),
        .rst_n(rst_n),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .sample_overflow(sample_overflow),
        .read_addr(read_addr),
        .read_data(read_data),
        .frame_ready(frame_ready),
        .frame_start(frame_start)
    );

    // Send one sample, with a single src_clk-wide valid pulse.
    task send_sample;
        input [7:0] value;
        begin
            @(negedge src_clk);
            sample_in = value;
            sample_valid = 1;
            @(negedge src_clk);
            sample_valid = 0;
            #20000; // 20 us until next sample (approximately 48 kHz)
        end
    endtask

    integer frame_number = 0;
    integer i;
    reg [2:0] start_addr;

    // Print all 8 samples in chronological order when a frame completes.
    // Expected frames: 1..8, 5..12, 9..16, 13..20, 17..24.
    // The read port is synchronous: set address before clock edge, then
    // inspect read_data after that edge.
    always @(posedge frame_ready) begin
        frame_number = frame_number + 1;
        start_addr = frame_start;
        $display("\nFrame %0d, start address = %0d", frame_number, start_addr);

        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            read_addr = (start_addr + i) % 8;
            @(posedge clk);
            #1;
            $display("  sample[%0d] = %0d", i, read_data);
        end
    end

    integer n;
    initial begin
        #200;
        rst_n = 1;

        for (n = 1; n <= 24; n = n + 1) begin
            send_sample(n);
        end

        #1000;
        $display("\nFrames received: %0d (expected: 5)", frame_number);
        $display("Overflow: %b (expected: 0)", sample_overflow);
        $finish;
    end

endmodule
