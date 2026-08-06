module cnn_accel_core (
    input  wire        clk,
    input  wire        resetn,

    // Local register interface driven by the AXI4-Lite slave.
    input  wire        reg_write,
    input  wire [3:0]  reg_wstrb,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    output wire        irq_done,
    output wire [3:0]  result_class_o,
    output wire        ready_o,
    output wire        busy_o,
    output wire        done_o,
    output wire        error_o,
    output wire        input_full_o
);

    localparam [31:0] CNN_ID_VERSION = 32'h434E_4E31; // "CNN1"
    localparam [31:0] CNN_CONFIG     = 32'h080A_1C1C; // int8, 10 classes, 28x28
    localparam [31:0] MAX_CYCLES     = 32'd200000;

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_PRIME       = 3'd1;
    localparam [2:0] ST_STREAM      = 3'd2;
    localparam [2:0] ST_WAIT_RESULT = 3'd3;
    localparam [2:0] ST_COOLDOWN    = 3'd4;

    localparam [31:0] ERR_NONE           = 32'd0;
    localparam [31:0] ERR_START_LENGTH   = 32'd1;
    localparam [31:0] ERR_START_BUSY     = 32'd2;
    localparam [31:0] ERR_INPUT_OVERFLOW = 32'd3;
    localparam [31:0] ERR_TIMEOUT        = 32'd4;
    localparam [31:0] ERR_BAD_STROBE     = 32'd5;
    localparam [31:0] ERR_CORE_NOT_READY = 32'd6;

    reg [2:0]  state;
    reg [9:0]  input_count;
    reg [9:0]  feed_index;
    wire [7:0] feed_data;
    reg        stream_valid;
    reg        busy;
    reg        done;
    reg        error;
    reg        irq_enable;
    reg [31:0] error_code;
    reg [31:0] cycle_count;
    reg [31:0] frame_id;
    reg [3:0]  result_class;
    reg        core_resetn;

    wire       core_s_ready;
    wire [7:0] core_m_data;
    wire       core_m_valid;
    wire       core_m_last;

    wire input_full = (input_count == 10'd784);
    wire ready_to_start =
        (state == ST_IDLE) && input_full && core_s_ready && core_resetn;

    wire input_strobe_onehot =
        (reg_wstrb == 4'b0001) ||
        (reg_wstrb == 4'b0010) ||
        (reg_wstrb == 4'b0100) ||
        (reg_wstrb == 4'b1000);

    reg [7:0] selected_input_byte;
    always @* begin
        case (reg_wstrb)
            4'b0001: selected_input_byte = reg_wdata[7:0];
            4'b0010: selected_input_byte = reg_wdata[15:8];
            4'b0100: selected_input_byte = reg_wdata[23:16];
            4'b1000: selected_input_byte = reg_wdata[31:24];
            default: selected_input_byte = 8'h00;
        endcase
    end

    wire input_write_accept =
        reg_write && (reg_addr == 8'h18) && input_strobe_onehot &&
        (state == ST_IDLE) && !busy && !input_full;

    wire input_read_advance =
        (state == ST_STREAM) && stream_valid && core_s_ready &&
        (feed_index < 10'd783);
    wire input_read_enable = (state == ST_PRIME) || input_read_advance;
    wire [9:0] input_read_addr =
        (state == ST_PRIME) ? 10'd0 : (feed_index + 1'b1);

    cnn_input_ram input_ram (
        .clk          (clk),
        .write_enable (input_write_accept),
        .write_addr   (input_count),
        .write_data   (selected_input_byte),
        .read_enable  (input_read_enable),
        .read_addr    (input_read_addr),
        .read_data    (feed_data)
    );

    axis_cnn_mnist cnn_core (
        .aclk          (clk),
        .aresetn       (resetn && core_resetn),
        .s_axis_tready (core_s_ready),
        .s_axis_tdata  (feed_data),
        .s_axis_tvalid (stream_valid),
        .m_axis_tready (1'b1),
        .m_axis_tdata  (core_m_data),
        .m_axis_tvalid (core_m_valid),
        .m_axis_tlast  (core_m_last)
    );

    always @* begin
        case (reg_addr)
            8'h00: reg_rdata = CNN_ID_VERSION;
            8'h04: reg_rdata = {23'd0, irq_enable, 8'd0};
            8'h08: reg_rdata = {
                27'd0,
                input_full,
                error,
                done,
                busy,
                ready_to_start
            };
            8'h0C: reg_rdata = CNN_CONFIG;
            8'h10: reg_rdata = 32'd784;
            8'h14: reg_rdata = {22'd0, input_count};
            8'h18: reg_rdata = 32'd0;
            8'h1C: reg_rdata = {28'd0, result_class};
            8'h20: reg_rdata = cycle_count;
            8'h24: reg_rdata = error_code;
            8'h28: reg_rdata = frame_id;
            default: reg_rdata = 32'd0;
        endcase
    end

    assign irq_done       = irq_enable && done;
    assign result_class_o = result_class;
    assign ready_o        = ready_to_start;
    assign busy_o         = busy;
    assign done_o         = done;
    assign error_o        = error;
    assign input_full_o   = input_full;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state         <= ST_IDLE;
            input_count   <= 10'd0;
            feed_index    <= 10'd0;
            stream_valid  <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
            error         <= 1'b0;
            irq_enable    <= 1'b0;
            error_code    <= ERR_NONE;
            cycle_count   <= 32'd0;
            frame_id      <= 32'd0;
            result_class  <= 4'd0;
            core_resetn   <= 1'b0;
        end else begin
            // Normally released. CONTROL.CLEAR or timeout pulses CNN reset.
            core_resetn <= 1'b1;

            case (state)
                ST_IDLE: begin
                    stream_valid <= 1'b0;
                    busy <= 1'b0;
                end

                ST_PRIME: begin
                    // Synchronous first read: pixel 0 settles before VALID.
                    feed_index <= 10'd0;
                    stream_valid <= 1'b0;
                    state <= ST_STREAM;
                    cycle_count <= cycle_count + 1'b1;
                end

                ST_STREAM: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (!stream_valid) begin
                        stream_valid <= 1'b1;
                    end else if (core_s_ready) begin
                        if (feed_index == 10'd783) begin
                            stream_valid <= 1'b0;
                            state <= ST_WAIT_RESULT;
                        end else begin
                            feed_index <= feed_index + 1'b1;
                        end
                    end
                end

                ST_WAIT_RESULT: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (core_m_valid && core_m_last) begin
                        result_class <= core_m_data[3:0];
                        done <= 1'b1;
                        busy <= 1'b0;
                        frame_id <= frame_id + 1'b1;
                        state <= ST_COOLDOWN;
                    end else if (cycle_count >= MAX_CYCLES) begin
                        error <= 1'b1;
                        error_code <= ERR_TIMEOUT;
                        busy <= 1'b0;
                        input_count <= 10'd0;
                        core_resetn <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                ST_COOLDOWN: begin
                    // Wait for the sample CNN pipeline to become ready again.
                    if (core_s_ready)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase

            if (reg_write && (reg_addr == 8'h18)) begin
                if (!input_strobe_onehot) begin
                    error <= 1'b1;
                    error_code <= ERR_BAD_STROBE;
                end else if ((state != ST_IDLE) || busy || input_full) begin
                    error <= 1'b1;
                    error_code <= ERR_INPUT_OVERFLOW;
                end else begin
                    input_count <= input_count + 1'b1;
                end
            end

            if (reg_write && (reg_addr == 8'h04)) begin
                irq_enable <= reg_wdata[8];

                // bit 1: clear/abort all state and reset the CNN pipeline.
                if (reg_wdata[1]) begin
                    state        <= ST_IDLE;
                    input_count  <= 10'd0;
                    feed_index   <= 10'd0;
                    stream_valid <= 1'b0;
                    busy         <= 1'b0;
                    done         <= 1'b0;
                    error        <= 1'b0;
                    error_code   <= ERR_NONE;
                    cycle_count  <= 32'd0;
                    result_class <= 4'd0;
                    core_resetn  <= 1'b0;
                end else begin
                    // bit 2: acknowledge sticky DONE only.
                    if (reg_wdata[2])
                        done <= 1'b0;

                    // bit 0: start one inference.
                    if (reg_wdata[0]) begin
                        if (busy || (state != ST_IDLE)) begin
                            error <= 1'b1;
                            error_code <= ERR_START_BUSY;
                        end else if (!input_full) begin
                            error <= 1'b1;
                            error_code <= ERR_START_LENGTH;
                        end else if (!core_s_ready || !core_resetn) begin
                            error <= 1'b1;
                            error_code <= ERR_CORE_NOT_READY;
                        end else begin
                            busy         <= 1'b1;
                            done         <= 1'b0;
                            error        <= 1'b0;
                            error_code   <= ERR_NONE;
                            cycle_count  <= 32'd0;
                            feed_index   <= 10'd0;
                            stream_valid <= 1'b0;
                            state        <= ST_PRIME;
                        end
                    end
                end
            end
        end
    end

endmodule
