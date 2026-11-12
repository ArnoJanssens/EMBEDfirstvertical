`timescale 1ns / 1ps

module i2sreceivertb;

    parameter DATA_WIDTH = 16;

    // Clock frequencies
    // MCLK = 12.288 MHz
    // BCLK = MCLK / 4 = 3.072 MHz

    localparam integer MCLK_HALF_PERIOD = 40.690;
    localparam integer SLOT_BITS = 32;

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------

    reg mclk;
    reg rst_n;

    reg bclk;
    reg lrclk;
    reg sdata_in;

    wire signed [DATA_WIDTH-1:0] left_out;
    wire signed [DATA_WIDTH-1:0] right_out;
    wire data_valid;

    // ------------------------------------------------------------
    // Test variables
    // ------------------------------------------------------------

    integer errors;
    integer valid_count;

    reg [DATA_WIDTH-1:0] expected_left;
    reg [DATA_WIDTH-1:0] expected_right;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    i2sparallelreceiver #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .mclk(mclk),
        .rst_n(rst_n),

        .bclk(bclk),
        .lrclk(lrclk),
        .sdata_in(sdata_in),

        .left_out(left_out),
        .right_out(right_out),
        .data_valid(data_valid)
    );

    // ------------------------------------------------------------
    // MCLK generation
    // ------------------------------------------------------------

    initial begin
        mclk = 0;
        forever #40.690 mclk = ~mclk;
    end

    // ------------------------------------------------------------
    // BCLK generation
    // ------------------------------------------------------------

    initial begin
        bclk = 0;

        forever begin
            repeat (2) @(posedge mclk);
            #1 bclk = ~bclk;
        end
    end

    // ------------------------------------------------------------
    // I2S channel transmission
    //
    // LRCLK changes on BCLK falling edge.
    // Data is updated on BCLK falling edges.
    // Receiver samples on BCLK rising edges.
    // ------------------------------------------------------------

    task send_channel;

        input channel;
        input [DATA_WIDTH-1:0] sample;

        integer i;

        begin

            // Start of channel
            @(negedge bclk);
            lrclk = channel;

            // Standard I2S one-bit delay
            sdata_in = 0;

            // First BCLK rising edge after LRCLK transition
            @(negedge bclk);

            // Send MSB first
            for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin

                sdata_in = sample[i];

                @(negedge bclk);

            end

            // Pad remaining channel slot with zeros
            for (i = DATA_WIDTH+1; i < SLOT_BITS; i = i+1) begin

                sdata_in = 0;

                @(negedge bclk);

            end

        end

    endtask

    // ------------------------------------------------------------
    // Send stereo frame
    // ------------------------------------------------------------

    task send_stereo;

        input [DATA_WIDTH-1:0] left_sample;
        input [DATA_WIDTH-1:0] right_sample;

        begin

            expected_left  = left_sample;
            expected_right = right_sample;

            send_channel(0, left_sample);
            send_channel(1, right_sample);

        end

    endtask

    // ------------------------------------------------------------
    // Output monitor
    // ------------------------------------------------------------

    always @(posedge mclk) begin

        if (rst_n && data_valid) begin

            valid_count = valid_count + 1;

            $display(
                "[%0t] VALID | LEFT = %h | RIGHT = %h",
                $time,
                left_out,
                right_out
            );

            if (left_out !== expected_left) begin

                $display(
                    "ERROR: LEFT expected %h, got %h",
                    expected_left,
                    left_out
                );

                errors = errors + 1;

            end

            if (right_out !== expected_right) begin

                $display(
                    "ERROR: RIGHT expected %h, got %h",
                    expected_right,
                    right_out
                );

                errors = errors + 1;

            end

        end

    end

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------

    initial begin

        mclk = 0;
        rst_n = 0;

        lrclk = 1;
        sdata_in = 0;

        errors = 0;
        valid_count = 0;

        expected_left = 0;
        expected_right = 0;

        $display("======================================");
        $display("       I2S RECEIVER TESTBENCH");
        $display("======================================");

        // Reset
        repeat (10) @(posedge mclk);

        rst_n = 1;

        // Allow clocks to stabilize
        repeat (10) @(posedge mclk);

        // --------------------------------------------------------
        // Test 1: Positive samples
        // --------------------------------------------------------

        $display("\nTEST 1: Positive samples");

        send_stereo(16'h1234, 16'h5678);

        // --------------------------------------------------------
        // Test 2: Negative samples
        // --------------------------------------------------------

        $display("\nTEST 2: Negative samples");

        send_stereo(16'h8000, 16'hFFFF);

        // --------------------------------------------------------
        // Test 3: Maximum positive amplitude
        // --------------------------------------------------------

        $display("\nTEST 3: Maximum positive amplitude");

        send_stereo(16'h7FFF, 16'h7FFF);

        // --------------------------------------------------------
        // Test 4: Zero samples
        // --------------------------------------------------------

        $display("\nTEST 4: Zero samples");

        send_stereo(16'h0000, 16'h0000);

        // --------------------------------------------------------
        // Test 5: Alternating bits
        // --------------------------------------------------------

        $display("\nTEST 5: Alternating bits");

        send_stereo(16'hAAAA, 16'h5555);

        // --------------------------------------------------------
        // Results
        // --------------------------------------------------------

        repeat (20) @(posedge mclk);

        $display("\n======================================");
        $display("              RESULTS");
        $display("======================================");

        $display("Valid samples received: %0d", valid_count);
        $display("Errors: %0d", errors);

        if (errors == 0 && valid_count == 5)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");

        $finish;

    end

    // ------------------------------------------------------------
    // Timeout protection
    // ------------------------------------------------------------

    initial begin
        #1000000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule