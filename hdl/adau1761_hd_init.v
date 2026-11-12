// =============================================================================
// ADAU1761 autonomous I2C initializer (Verilog-2001)
// Direct 49.1728 MHz codec MCLK; PLL bypassed.
// 125 MHz clk drives approximately 100 kHz I2C.
// Translation of the supplied VHDL state machine and register sequence.
// =============================================================================
module adau1761_hd_init (
    input  wire       clk,
    input  wire       reset_n,
    output wire       scl,
    input  wire       sda_i,
    output wire       sda_o,
    output wire       sda_t,
    output wire       cfg_ok,
    output wire [1:0] dbg_read
);
    localparam [6:0] I2C_SLAVE_ADDR = 7'h3B;
    localparam [7:0] ADDR_HI = 8'h40;
    localparam [7:0] RD_REG_LO = 8'h23;
    localparam [7:0] RD_EXPECT = 8'hE7;
    localparam integer LAST_STEP = 30;
    localparam integer DELAY_MAX = 20000;

    localparam [3:0]
        IDLE = 4'd0, START = 4'd1, SEND_BYTE = 4'd2,
        ACK_WAIT = 4'd3, STOP = 4'd4, WAIT_LOCK = 4'd5,
        R_START = 4'd6, R_SEND = 4'd7, R_ACK = 4'd8,
        R_DATA = 4'd9, R_NAK = 4'd10, R_STOP = 4'd11,
        DONE = 4'd12;

    reg [3:0] state;
    reg [1:0] quadrant;
    reg [5:0] step_index;       // 0 through LAST_STEP+2
    reg [3:0] byte_index;       // 0=dev, 1=addr_hi, 2=addr_lo, 3+=data
    reg [2:0] bit_index;
    reg [7:0] current_byte;
    reg [14:0] delay_cnt;
    reg [8:0] tick_counter;
    reg i2c_tick;
    reg scl_reg, sda_reg, sda_dir;
    reg [1:0] read_phase;
    reg [7:0] read_data;
    reg cfg_ok_reg;

    reg [7:0] cur_addr_lo;
    reg [7:0] cur_data [0:5];
    reg [2:0] cur_count;
    reg cur_delay;
    integer i;

    assign scl = scl_reg;
    assign sda_o = sda_reg;
    assign sda_t = ~sda_dir;  // 0=drive, 1=release
    assign cfg_ok = cfg_ok_reg;
    assign dbg_read = read_data[1:0];

    // Register configuration ROM (same 31 steps as the VHDL)
    always @* begin
        cur_addr_lo = 8'h00;
        for (i = 0; i < 6; i = i + 1)
            cur_data[i] = 8'h00;
        cur_count = 3'd1;
        cur_delay = 1'b0;
        case (step_index)
            6'd0: begin cur_addr_lo = 8'h00; cur_data[0] = 8'h06; end
            6'd1: cur_delay = 1'b1;
            6'd2: begin cur_addr_lo = 8'h00; cur_data[0] = 8'h07; end
            6'd3: begin cur_addr_lo = 8'h15; cur_data[0] = 8'h00; end
            6'd4: begin cur_addr_lo = 8'h16; cur_data[0] = 8'h00; end
            6'd5: begin cur_addr_lo = 8'h0A; cur_data[0] = 8'h01; end
            6'd6: begin cur_addr_lo = 8'h0B; cur_data[0] = 8'h07; end
            6'd7: begin cur_addr_lo = 8'h0C; cur_data[0] = 8'h01; end
            6'd8: begin cur_addr_lo = 8'h0D; cur_data[0] = 8'h07; end
            6'd9: begin cur_addr_lo = 8'h0E; cur_data[0] = 8'hB3; end
            6'd10: begin cur_addr_lo = 8'h0F; cur_data[0] = 8'hB3; end
            6'd11: begin cur_addr_lo = 8'h10; cur_data[0] = 8'h01; end
            6'd12: begin cur_addr_lo = 8'h14; cur_data[0] = 8'h20; end
            6'd13: begin cur_addr_lo = 8'h19; cur_data[0] = 8'h33; end
            6'd14: begin cur_addr_lo = 8'h1C; cur_data[0] = 8'h21; end
            6'd15: begin cur_addr_lo = 8'h1D; cur_data[0] = 8'h00; end
            6'd16: begin cur_addr_lo = 8'h1E; cur_data[0] = 8'h41; end
            6'd17: begin cur_addr_lo = 8'h1F; cur_data[0] = 8'h00; end
            6'd18: begin cur_addr_lo = 8'h23; cur_data[0] = 8'hE7; end
            6'd19: begin cur_addr_lo = 8'h24; cur_data[0] = 8'hE7; end
            6'd20: begin cur_addr_lo = 8'h25; cur_data[0] = 8'h00; end
            6'd21: begin cur_addr_lo = 8'h26; cur_data[0] = 8'h00; end
            6'd22: begin cur_addr_lo = 8'h28; cur_data[0] = 8'h00; end
            6'd23: begin cur_addr_lo = 8'h29; cur_data[0] = 8'h03; end
            6'd24: begin cur_addr_lo = 8'h2A; cur_data[0] = 8'h03; end
            6'd25: begin cur_addr_lo = 8'hF2; cur_data[0] = 8'h01; end
            6'd26: begin cur_addr_lo = 8'hF3; cur_data[0] = 8'h01; end
            6'd27: begin cur_addr_lo = 8'hF5; cur_data[0] = 8'h01; end
            6'd28: begin cur_addr_lo = 8'hF6; cur_data[0] = 8'h01; end
            6'd29: begin cur_addr_lo = 8'hF9; cur_data[0] = 8'h7F; end
            6'd30: begin cur_addr_lo = 8'hFA; cur_data[0] = 8'h03; end
            default: ;
        endcase
    end

    // One tick every 312 system clocks (~400.64 kHz); four ticks/bit.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tick_counter <= 9'd0;
            i2c_tick <= 1'b0;
        end else if (tick_counter == 9'd311) begin
            tick_counter <= 9'd0;
            i2c_tick <= 1'b1;
        end else begin
            tick_counter <= tick_counter + 1'b1;
            i2c_tick <= 1'b0;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            quadrant <= 2'd0;
            step_index <= 6'd0;
            byte_index <= 4'd0;
            bit_index <= 3'd0;
            delay_cnt <= 15'd0;
            scl_reg <= 1'b1;
            sda_reg <= 1'b1;
            sda_dir <= 1'b1;
            current_byte <= 8'h00;
            read_phase <= 2'd0;
            read_data <= 8'h00;
            cfg_ok_reg <= 1'b0;
        end else if (i2c_tick) begin
            case (state)
                IDLE: begin
                    scl_reg <= 1'b1;
                    sda_reg <= 1'b1;
                    sda_dir <= 1'b1;
                    if (step_index <= LAST_STEP) begin
                        if (cur_delay) begin
                            delay_cnt <= 15'd0;
                            state <= WAIT_LOCK;
                        end else begin
                            state <= START;
                            quadrant <= 2'd0;
                        end
                    end else if (step_index == LAST_STEP + 1) begin
                        delay_cnt <= 15'd0;
                        state <= WAIT_LOCK;
                    end else begin
                        state <= R_START;
                        quadrant <= 2'd0;
                        read_phase <= 2'd0;
                    end
                end
                WAIT_LOCK: begin
                    scl_reg <= 1'b1;
                    sda_reg <= 1'b1;
                    sda_dir <= 1'b1;
                    if (delay_cnt == DELAY_MAX) begin
                        step_index <= step_index + 1'b1;
                        state <= IDLE;
                    end else
                        delay_cnt <= delay_cnt + 1'b1;
                end
                START: begin
                    case (quadrant)
                        2'd0: begin sda_reg <= 1'b1; scl_reg <= 1'b1; end
                        2'd1: sda_reg <= 1'b0;
                        2'd2: scl_reg <= 1'b0;
                        2'd3: begin
                            current_byte <= {I2C_SLAVE_ADDR, 1'b0};
                            byte_index <= 4'd0;
                            bit_index <= 3'd7;
                            state <= SEND_BYTE;
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                SEND_BYTE: begin
                    case (quadrant)
                        2'd0: begin
                            scl_reg <= 1'b0;
                            sda_reg <= current_byte[bit_index];
                        end
                        2'd1, 2'd2: scl_reg <= 1'b1;
                        2'd3: begin
                            scl_reg <= 1'b0;
                            if (bit_index == 0)
                                state <= ACK_WAIT;
                            else
                                bit_index <= bit_index - 1'b1;
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                ACK_WAIT: begin
                    case (quadrant)
                        2'd0: begin scl_reg <= 1'b0; sda_dir <= 1'b0; end
                        2'd1, 2'd2: scl_reg <= 1'b1;
                        2'd3: begin
                            scl_reg <= 1'b0;
                            sda_dir <= 1'b1;
                            if (byte_index == 0) begin
                                current_byte <= ADDR_HI;
                                byte_index <= 4'd1;
                                bit_index <= 3'd7;
                                state <= SEND_BYTE;
                            end else if (byte_index == 1) begin
                                current_byte <= cur_addr_lo;
                                byte_index <= 4'd2;
                                bit_index <= 3'd7;
                                state <= SEND_BYTE;
                            end else if (byte_index == 2) begin
                                current_byte <= cur_data[0];
                                byte_index <= 4'd3;
                                bit_index <= 3'd7;
                                state <= SEND_BYTE;
                            end else if ((byte_index - 2) < cur_count) begin
                                current_byte <= cur_data[byte_index - 2];
                                byte_index <= byte_index + 1'b1;
                                bit_index <= 3'd7;
                                state <= SEND_BYTE;
                            end else
                                state <= STOP;
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                STOP: begin
                    case (quadrant)
                        2'd0: begin scl_reg <= 1'b0; sda_reg <= 1'b0; end
                        2'd1: scl_reg <= 1'b1;
                        2'd2: sda_reg <= 1'b1;
                        2'd3: begin
                            step_index <= step_index + 1'b1;
                            state <= IDLE;
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                R_START: begin
                    case (quadrant)
                        2'd0: begin
                            sda_reg <= 1'b1;
                            scl_reg <= 1'b1;
                            sda_dir <= 1'b1;
                        end
                        2'd1: sda_reg <= 1'b0;
                        2'd2: scl_reg <= 1'b0;
                        2'd3: begin
                            current_byte <= {I2C_SLAVE_ADDR, (read_phase == 3)};
                            bit_index <= 3'd7;
                            state <= R_SEND;
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                R_SEND: begin
                    case (quadrant)
                        2'd0: begin
                            scl_reg <= 1'b0;
                            sda_reg <= current_byte[bit_index];
                        end
                        2'd1, 2'd2: scl_reg <= 1'b1;
                        2'd3: begin
                            scl_reg <= 1'b0;
                            if (bit_index == 0)
                                state <= R_ACK;
                            else
                                bit_index <= bit_index - 1'b1;
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                R_ACK: begin
                    case (quadrant)
                        2'd0: begin scl_reg <= 1'b0; sda_dir <= 1'b0; end
                        2'd1, 2'd2: scl_reg <= 1'b1;
                        2'd3: begin
                            scl_reg <= 1'b0;
                            if (read_phase == 0) begin
                                sda_dir <= 1'b1;
                                current_byte <= ADDR_HI;
                                read_phase <= 2'd1;
                                bit_index <= 3'd7;
                                state <= R_SEND;
                            end else if (read_phase == 1) begin
                                sda_dir <= 1'b1;
                                current_byte <= RD_REG_LO;
                                read_phase <= 2'd2;
                                bit_index <= 3'd7;
                                state <= R_SEND;
                            end else if (read_phase == 2) begin
                                sda_dir <= 1'b1;
                                state <= R_STOP;
                            end else begin
                                bit_index <= 3'd7;
                                state <= R_DATA;
                            end
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                R_DATA: begin
                    case (quadrant)
                        2'd0: begin scl_reg <= 1'b0; sda_dir <= 1'b0; end
                        2'd1, 2'd2: scl_reg <= 1'b1;
                        2'd3: begin
                            scl_reg <= 1'b0;
                            read_data <= {read_data[6:0], sda_i};
                            if (bit_index == 0)
                                state <= R_NAK;
                            else
                                bit_index <= bit_index - 1'b1;
                        end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                R_NAK: begin
                    case (quadrant)
                        2'd0: begin
                            scl_reg <= 1'b0;
                            sda_dir <= 1'b1;
                            sda_reg <= 1'b1;
                        end
                        2'd1, 2'd2: scl_reg <= 1'b1;
                        2'd3: begin scl_reg <= 1'b0; state <= R_STOP; end
                    endcase
                    quadrant <= quadrant + 1'b1;
                end
                R_STOP: begin
                    case (quadrant)
                        2'd0: begin
                            scl_reg <= 1'b0;
                            sda_reg <= 1'b0;
                            sda_dir <= 1'b1;
                        end
                        2'd1: scl_reg <= 1'b1;
                        2'd2: sda_reg <= 1'b1;
                        2'd3: begin
                            if (read_phase == 3) begin
                                cfg_ok_reg <= (read_data == RD_EXPECT);
                                state <= DONE;
                            end else begin
                                read_phase <= 2'd3;
                                state <= R_START;
                                quadrant <= 2'd0;
                            end
                        end
                    endcase
                    // VHDL assigns quadrant=0 on phase 3 even after R_START
                    quadrant <= quadrant + 1'b1;
                end
                DONE: begin
                    scl_reg <= 1'b1;
                    sda_reg <= 1'b1;
                    sda_dir <= 1'b0;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule