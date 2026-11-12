`timescale 1ns / 1ps

module i2stransmittertb;

    // ============================================================
    // Parameters
    // ============================================================

    parameter DATA_WIDTH = 16;

    localparam integer SLOT_BITS = 32;
    localparam real MCLK_HALF_PERIOD = 40.690104;

    // ============================================================
    // DUT signals
    // ============================================================

    reg mclk = 1'b0;
    reg rst_n = 1'b0;

    reg bclk  = 1'b0;
    reg lrclk = 1'b0;

    reg signed [DATA_WIDTH-1:0] left_in  = 0;
    reg signed [DATA_WIDTH-1:0] right_in = 0;

    wire sdata_out;

    // ============================================================
    // Testbench variables
    // ============================================================

    integer errors = 0;
    integer tests_passed = 0;

    integer bclk_div = 0;
    integer slot_count = 0;

    integer bit_count = 0;

    reg [DATA_WIDTH-1:0] received_left  = 0;
    reg [DATA_WIDTH-1:0] received_right = 0;

    reg [DATA_WIDTH-1:0] expected_left  = 0;
    reg [DATA_WIDTH-1:0] expected_right = 0;

    reg previous_lrclk = 0;

    // ============================================================
    // DUT
    // ============================================================

    i2stransmitter #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .mclk(mclk),
        .rst_n(rst_n),

        .bclk(bclk),
        .lrclk(lrclk),
        .sdata_out(sdata_out),

        .left_in(left_in),
        .right_in(right_in)
    );

    // ============================================================
    // MCLK generation: 12.288 MHz
    // ============================================================

    always #(MCLK_HALF_PERIOD)
        mclk = ~mclk;

    // ============================================================
    // BCLK generation: MCLK / 4
    //
    // BCLK changes every 2 MCLK cycles.
    // ============================================================

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_div <= 0;
            bclk     <= 0;
        end
        else begin
            if (bclk_div == 1) begin
                bclk     <= ~bclk;
                bclk_div <= 0;
            end
            else begin
                bclk_div <= bclk_div + 1;
            end
        end
    end

    // ============================================================
    // LRCLK generation
    //
    // 32 BCLK cycles per channel.
    // LRCLK changes on falling BCLK edges.
    // ============================================================

    always @(negedge bclk or negedge rst_n) begin
        if (!rst_n) begin
            slot_count <= 0;
            lrclk      <= 0;
        end
        else begin
            if (slot_count == SLOT_BITS-1) begin
                slot_count <= 0;
                lrclk      <= ~lrclk;
            end
            else begin
                slot_count <= slot_count + 1;
            end
        end
    end

    // ============================================================
    // I2S output reconstruction
    //
    // Standard I2S:
    // - LRCLK changes on BCLK falling edge.
    // - First BCLK rising edge after transition captures MSB.
    // - DATA_WIDTH bits are received.
    //
    // The checker operates on BCLK rising edges, like the codec.
    // ============================================================

    always @(posedge bclk or negedge rst_n) begin
        if (!rst_n) begin
            previous_lrclk <= 0;
            bit_count      <= 0;

            received_left  <= 0;
            received_right <= 0;
        end
        else begin
            previous_lrclk <= lrclk;

            if (lrclk != previous_lrclk) begin
                bit_count <= 0;
            end
            else if (bit_count < DATA_WIDTH) begin

                if (lrclk == 0) begin
                    received_left <= {
                        received_left[DATA_WIDTH-2:0],
                        sdata_out
                    };
                end
                else begin
                    received_right <= {
                        received_right[DATA_WIDTH-2:0],
                        sdata_out
                    };
                end

                bit_count <= bit_count + 1;
            end
        end
    end

    // ============================================================
    // Test task
    //
    // Each test:
    // 1. Waits for a stereo frame boundary.
    // 2. Updates the samples after the previous frame is complete.
    // 3. Waits for the transmitter to send the new frame.
    // 4. Compares received values.
    //
    // This avoids the previous one-frame expectation mismatch.
    // ============================================================

    task run_test;

        input [DATA_WIDTH-1:0] test_left;
        input [DATA_WIDTH-1:0] test_right;
        input [8*40-1:0] test_name;

        begin

            // Wait for a complete stereo frame boundary
            @(negedge lrclk);
            #10;

            // Apply new input samples
            left_in  = test_left;
            right_in = test_right;

            expected_left  = test_left;
            expected_right = test_right;

            // Wait for the next complete stereo frame.
            // The first new left-channel load occurs at the next
            // LRCLK falling edge, followed by the right channel.
            @(negedge lrclk);
            @(negedge lrclk);

            // Allow simulation signals to settle
            #10;

            $display(
                "[%0t] %0s | LEFT=%h RIGHT=%h | Expected L=%h R=%h",
                $time,
                test_name,
                received_left,
                received_right,
                expected_left,
                expected_right
            );

            if ((received_left !== expected_left) ||
                (received_right !== expected_right)) begin

                $display("ERROR: Sample mismatch");
                errors = errors + 1;

            end
            else begin

                $display("PASS");
                tests_passed = tests_passed + 1;

            end

        end

    endtask

    // ============================================================
    // Main test sequence
    // ============================================================

    initial begin

        $display("======================================");
        $display("       I2S TRANSMITTER TESTBENCH");
        $display("======================================");

        // Reset
        rst_n = 0;

        left_in  = 0;
        right_in = 0;

        repeat (10) @(posedge mclk);

        @(negedge mclk);
        rst_n = 1;

        // Allow startup synchronization
        repeat (2) @(negedge lrclk);

        // --------------------------------------------------------
        // Test 1: Positive samples
        // --------------------------------------------------------

        run_test(
            16'h1234,
            16'h5678,
            "Positive samples"
        );

        // --------------------------------------------------------
        // Test 2: Negative samples
        // --------------------------------------------------------

        run_test(
            16'h8000,
            16'hFFFF,
            "Negative samples"
        );

        // --------------------------------------------------------
        // Test 3: Maximum positive amplitude
        // --------------------------------------------------------

        run_test(
            16'h7FFF,
            16'h7FFF,
            "Maximum positive amplitude"
        );

        // --------------------------------------------------------
        // Test 4: Zero samples
        // --------------------------------------------------------

        run_test(
            16'h0000,
            16'h0000,
            "Zero samples"
        );

        // --------------------------------------------------------
        // Test 5: Alternating bits
        // --------------------------------------------------------

        run_test(
            16'hAAAA,
            16'h5555,
            "Alternating bits"
        );

        // ========================================================
        // Results
        // ========================================================

        $display("\n======================================");
        $display("              RESULTS");
        $display("======================================");

        $display("Tests passed: %0d / 5", tests_passed);
        $display("Errors: %0d", errors);

        if ((errors == 0) && (tests_passed == 5))
            $display("TEST PASSED");
        else
            $display("TEST FAILED");

        $finish;

    end

    // ============================================================
    // Timeout protection
    // ============================================================

    initial begin
        #1000000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule