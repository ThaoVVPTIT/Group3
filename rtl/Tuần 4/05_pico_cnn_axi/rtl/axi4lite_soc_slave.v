module axi4lite_soc_slave #(
    parameter integer MEM_WORDS = 8192
) (
    input  wire        clk,
    input  wire        resetn,

    // AXI4-Lite slave interface. This is the only memory/peripheral slave
    // seen by picorv32_axi; address decoding is performed inside this block.
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,

    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,

    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    output wire [1:0]  s_axi_bresp,

    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    input  wire [31:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,

    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,

    input  wire        ser_rx,
    output wire        ser_tx,
    input  wire [9:0]  gpio_switches,

    output wire        cnn_irq,
    output wire [3:0]  cnn_result,
    output wire        cnn_ready,
    output wire        cnn_busy,
    output wire        cnn_done,
    output wire        cnn_error,
    output wire        cnn_input_full
);

    localparam [31:0] RAM_LIMIT     = 4 * MEM_WORDS;
    localparam [31:0] UART_DIV_ADDR = 32'h0200_0004;
    localparam [31:0] UART_DAT_ADDR = 32'h0200_0008;
    localparam [23:0] CNN_PAGE      = 24'h0300_00;
    localparam [31:0] GPIO_ADDR     = 32'h0400_0000;

    // Declarations are placed before the AXI read mux for Quartus 18.1.
    reg  [31:0] ram_rdata;
    wire [31:0] uart_div_do;
    wire [31:0] uart_dat_do;
    wire [31:0] cnn_reg_rdata;

    // AXI4-Lite responses are always OKAY. Peripheral-specific failures are
    // reported in CNN_STATUS/CNN_ERROR_CODE, preserving the firmware ABI.
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    // ------------------------------------------------------------------
    // Write channel buffering
    // AXI4-Lite allows AW and W to arrive independently. Capture both, then
    // commit exactly one local write and return BVALID.
    // ------------------------------------------------------------------
    reg        aw_pending;
    reg [31:0] awaddr_q;
    reg        w_pending;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;

    assign s_axi_awready = resetn && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = resetn && !w_pending  && !s_axi_bvalid;

    wire aw_take = s_axi_awvalid && s_axi_awready;
    wire w_take  = s_axi_wvalid  && s_axi_wready;

    wire have_aw = aw_pending || aw_take;
    wire have_w  = w_pending  || w_take;

    wire [31:0] write_addr  = aw_pending ? awaddr_q : s_axi_awaddr;
    wire [31:0] write_data  = w_pending  ? wdata_q  : s_axi_wdata;
    wire [3:0]  write_strb  = w_pending  ? wstrb_q  : s_axi_wstrb;
    wire        write_request = resetn && !s_axi_bvalid && have_aw && have_w;

    wire write_is_uart_data = (write_addr == UART_DAT_ADDR);
    wire uart_data_write_attempt = write_request && write_is_uart_data;
    wire uart_data_wait;
    wire write_commit = write_request && !uart_data_wait;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            aw_pending  <= 1'b0;
            awaddr_q    <= 32'd0;
            w_pending   <= 1'b0;
            wdata_q     <= 32'd0;
            wstrb_q     <= 4'd0;
            s_axi_bvalid <= 1'b0;
        end else begin
            if (aw_take) begin
                aw_pending <= 1'b1;
                awaddr_q <= s_axi_awaddr;
            end

            if (w_take) begin
                w_pending <= 1'b1;
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (write_commit) begin
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Read channel buffering
    // All reads have a fixed one-cycle local access stage. RAM remains a
    // synchronous M9K implementation; peripherals are sampled in that stage.
    // ------------------------------------------------------------------
    reg        read_pending;
    reg [31:0] read_addr_q;

    assign s_axi_arready = resetn && !read_pending && !s_axi_rvalid;
    wire ar_take = s_axi_arvalid && s_axi_arready;

    wire uart_data_read = read_pending && (read_addr_q == UART_DAT_ADDR);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            read_pending <= 1'b0;
            read_addr_q <= 32'd0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 32'd0;
        end else begin
            if (ar_take) begin
                read_pending <= 1'b1;
                read_addr_q <= s_axi_araddr;
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (read_pending) begin
                read_pending <= 1'b0;
                s_axi_rvalid <= 1'b1;

                if (read_addr_q < RAM_LIMIT)
                    s_axi_rdata <= ram_rdata;
                else if (read_addr_q == UART_DIV_ADDR)
                    s_axi_rdata <= uart_div_do;
                else if (read_addr_q == UART_DAT_ADDR)
                    s_axi_rdata <= uart_dat_do;
                else if (read_addr_q[31:8] == CNN_PAGE)
                    s_axi_rdata <= cnn_reg_rdata;
                else if (read_addr_q == GPIO_ADDR)
                    s_axi_rdata <= {22'd0, gpio_switches};
                else
                    s_axi_rdata <= 32'd0;
            end
        end
    end

    // ------------------------------------------------------------------
    // 32 KiB AXI-accessed firmware/data RAM at 0x0000_0000
    // ------------------------------------------------------------------
    (* ramstyle = "M9K" *) reg [7:0] mem0 [0:MEM_WORDS-1];
    (* ramstyle = "M9K" *) reg [7:0] mem1 [0:MEM_WORDS-1];
    (* ramstyle = "M9K" *) reg [7:0] mem2 [0:MEM_WORDS-1];
    (* ramstyle = "M9K" *) reg [7:0] mem3 [0:MEM_WORDS-1];

    reg [31:0] initdata [0:MEM_WORDS-1];
    integer i;

    wire [12:0] ram_read_addr = ar_take ? s_axi_araddr[14:2] : read_addr_q[14:2];
    wire ram_write = write_commit && (write_addr < RAM_LIMIT);

    initial begin
        // Quartus 18.1 limits each constant loop to 5000 iterations.
        for (i = 0; i < MEM_WORDS/2; i = i + 1)
            initdata[i] = 32'h0000_0000;
        for (i = MEM_WORDS/2; i < MEM_WORDS; i = i + 1)
            initdata[i] = 32'h0000_0000;
        $readmemh("firmware.hex", initdata);
        for (i = 0; i < MEM_WORDS/2; i = i + 1) begin
            mem0[i] = initdata[i][7:0];
            mem1[i] = initdata[i][15:8];
            mem2[i] = initdata[i][23:16];
            mem3[i] = initdata[i][31:24];
        end
        for (i = MEM_WORDS/2; i < MEM_WORDS; i = i + 1) begin
            mem0[i] = initdata[i][7:0];
            mem1[i] = initdata[i][15:8];
            mem2[i] = initdata[i][23:16];
            mem3[i] = initdata[i][31:24];
        end
    end

    always @(posedge clk) begin
        ram_rdata <= {
            mem3[ram_read_addr], mem2[ram_read_addr],
            mem1[ram_read_addr], mem0[ram_read_addr]
        };

        if (ram_write && write_strb[0]) mem0[write_addr[14:2]] <= write_data[7:0];
        if (ram_write && write_strb[1]) mem1[write_addr[14:2]] <= write_data[15:8];
        if (ram_write && write_strb[2]) mem2[write_addr[14:2]] <= write_data[23:16];
        if (ram_write && write_strb[3]) mem3[write_addr[14:2]] <= write_data[31:24];
    end

    // ------------------------------------------------------------------
    // AXI-addressed UART at 0x0200_0004 / 0x0200_0008
    // ------------------------------------------------------------------
    wire [3:0] uart_div_we =
        (write_commit && (write_addr == UART_DIV_ADDR)) ? write_strb : 4'b0000;

    simpleuart simpleuart (
        .clk          (clk),
        .resetn       (resetn),
        .ser_tx       (ser_tx),
        .ser_rx       (ser_rx),
        .reg_div_we   (uart_div_we),
        .reg_div_di   (write_data),
        .reg_div_do   (uart_div_do),
        .reg_dat_we   (uart_data_write_attempt && write_strb[0]),
        .reg_dat_re   (uart_data_read),
        .reg_dat_di   (write_data),
        .reg_dat_do   (uart_dat_do),
        .reg_dat_wait (uart_data_wait)
    );

    // ------------------------------------------------------------------
    // CNN register page at 0x0300_0000, now reached through AXI4-Lite.
    // The register offsets remain compatible with the proven MMIO firmware.
    // ------------------------------------------------------------------
    wire cnn_selected_write =
        write_commit && (write_addr[31:8] == CNN_PAGE);
    wire [7:0] cnn_reg_addr =
        read_pending ? read_addr_q[7:0] : write_addr[7:0];

    cnn_accel_core cnn_accel (
        .clk            (clk),
        .resetn         (resetn),
        .reg_write      (cnn_selected_write),
        .reg_wstrb      (write_strb),
        .reg_addr       (cnn_reg_addr),
        .reg_wdata      (write_data),
        .reg_rdata      (cnn_reg_rdata),
        .irq_done       (cnn_irq),
        .result_class_o (cnn_result),
        .ready_o        (cnn_ready),
        .busy_o         (cnn_busy),
        .done_o         (cnn_done),
        .error_o        (cnn_error),
        .input_full_o   (cnn_input_full)
    );

    // Protection attributes are accepted for protocol completeness. This
    // small SoC does not implement privilege/security filtering.
    wire unused_prot = ^{s_axi_awprot, s_axi_arprot};

endmodule
