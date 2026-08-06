module top_axi (
    input  wire        MAX10_CLK1_50,
    input  wire [1:0]  KEY,
    input  wire        UART_RX,
    output wire        UART_TX,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR
);

    // KEY[0] is active-low. Assertion is asynchronous and release is
    // synchronized so the CPU, AXI fabric and CNN leave reset together.
    reg [1:0] reset_sync;
    always @(posedge MAX10_CLK1_50 or negedge KEY[0]) begin
        if (!KEY[0])
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    wire resetn = reset_sync[1];

    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_awaddr;
    wire [2:0]  axi_awprot;
    wire        axi_wvalid;
    wire        axi_wready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_bvalid;
    wire        axi_bready;
    wire [1:0]  axi_bresp;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_araddr;
    wire [2:0]  axi_arprot;
    wire        axi_rvalid;
    wire        axi_rready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;

    wire        cpu_trap;
    wire        cnn_irq;
    wire [3:0]  cnn_result;
    wire        cnn_ready;
    wire        cnn_busy;
    wire        cnn_done;
    wire        cnn_error;
    wire        cnn_input_full;

    wire [31:0] cpu_irq = {26'd0, cnn_irq, 5'd0};
    wire [31:0] cpu_eoi;
    wire        trace_valid;
    wire [35:0] trace_data;
    wire        pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;

    picorv32_axi #(
        .BARREL_SHIFTER       (1'b0),
        .COMPRESSED_ISA       (1'b0),
        .ENABLE_COUNTERS      (1'b0),
        .ENABLE_COUNTERS64    (1'b0),
        .ENABLE_MUL           (1'b0),
        .ENABLE_FAST_MUL      (1'b0),
        .ENABLE_DIV           (1'b0),
        .ENABLE_IRQ           (1'b1),
        .ENABLE_IRQ_QREGS     (1'b0),
        .ENABLE_IRQ_TIMER     (1'b0),
        .PROGADDR_RESET       (32'h0000_0000),
        .PROGADDR_IRQ         (32'h0000_0010),
        .STACKADDR            (32'h0000_8000)
    ) cpu (
        .clk                  (MAX10_CLK1_50),
        .resetn               (resetn),
        .trap                 (cpu_trap),
        .mem_axi_awvalid      (axi_awvalid),
        .mem_axi_awready      (axi_awready),
        .mem_axi_awaddr       (axi_awaddr),
        .mem_axi_awprot       (axi_awprot),
        .mem_axi_wvalid       (axi_wvalid),
        .mem_axi_wready       (axi_wready),
        .mem_axi_wdata        (axi_wdata),
        .mem_axi_wstrb        (axi_wstrb),
        .mem_axi_bvalid       (axi_bvalid),
        .mem_axi_bready       (axi_bready),
        .mem_axi_arvalid      (axi_arvalid),
        .mem_axi_arready      (axi_arready),
        .mem_axi_araddr       (axi_araddr),
        .mem_axi_arprot       (axi_arprot),
        .mem_axi_rvalid       (axi_rvalid),
        .mem_axi_rready       (axi_rready),
        .mem_axi_rdata        (axi_rdata),
        .pcpi_valid           (pcpi_valid),
        .pcpi_insn            (pcpi_insn),
        .pcpi_rs1             (pcpi_rs1),
        .pcpi_rs2             (pcpi_rs2),
        .pcpi_wr              (1'b0),
        .pcpi_rd              (32'd0),
        .pcpi_wait            (1'b0),
        .pcpi_ready           (1'b0),
        .irq                  (cpu_irq),
        .eoi                  (cpu_eoi),
        .trace_valid          (trace_valid),
        .trace_data           (trace_data)
    );

    axi4lite_soc_slave #(
        .MEM_WORDS            (8192)
    ) axi_soc (
        .clk                  (MAX10_CLK1_50),
        .resetn               (resetn),
        .s_axi_awvalid        (axi_awvalid),
        .s_axi_awready        (axi_awready),
        .s_axi_awaddr         (axi_awaddr),
        .s_axi_awprot         (axi_awprot),
        .s_axi_wvalid         (axi_wvalid),
        .s_axi_wready         (axi_wready),
        .s_axi_wdata          (axi_wdata),
        .s_axi_wstrb          (axi_wstrb),
        .s_axi_bvalid         (axi_bvalid),
        .s_axi_bready         (axi_bready),
        .s_axi_bresp          (axi_bresp),
        .s_axi_arvalid        (axi_arvalid),
        .s_axi_arready        (axi_arready),
        .s_axi_araddr         (axi_araddr),
        .s_axi_arprot         (axi_arprot),
        .s_axi_rvalid         (axi_rvalid),
        .s_axi_rready         (axi_rready),
        .s_axi_rdata          (axi_rdata),
        .s_axi_rresp          (axi_rresp),
        .ser_rx               (UART_RX),
        .ser_tx               (UART_TX),
        .gpio_switches        (SW),
        .cnn_irq              (cnn_irq),
        .cnn_result           (cnn_result),
        .cnn_ready            (cnn_ready),
        .cnn_busy             (cnn_busy),
        .cnn_done             (cnn_done),
        .cnn_error            (cnn_error),
        .cnn_input_full       (cnn_input_full)
    );

    reg [24:0] heartbeat;
    always @(posedge MAX10_CLK1_50 or negedge resetn) begin
        if (!resetn)
            heartbeat <= 25'd0;
        else
            heartbeat <= heartbeat + 1'b1;
    end

    assign LEDR[3:0] = cnn_result;
    assign LEDR[4]   = cnn_done;
    assign LEDR[5]   = cnn_busy;
    assign LEDR[6]   = cnn_error | cpu_trap;
    assign LEDR[7]   = cnn_input_full;
    assign LEDR[8]   = resetn;
    assign LEDR[9]   = heartbeat[24];

endmodule
