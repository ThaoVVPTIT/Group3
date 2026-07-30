module top (
    input  wire        MAX10_CLK1_50,
    input  wire [1:0]  KEY,
    input  wire        UART_RX,
    output wire        UART_TX,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR
);

    // KEY[0] is active-low. Assertion is asynchronous, release is
    // synchronized to avoid a partial reset across the SoC and CNN.
    reg [1:0] reset_sync;
    always @(posedge MAX10_CLK1_50 or negedge KEY[0]) begin
        if (!KEY[0])
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    wire resetn = reset_sync[1];

    wire        iomem_valid;
    wire        iomem_ready;
    wire [3:0]  iomem_wstrb;
    wire [31:0] iomem_addr;
    wire [31:0] iomem_wdata;
    wire [31:0] iomem_rdata;

    wire flash_csb;
    wire flash_clk;
    wire flash_io0_oe, flash_io1_oe, flash_io2_oe, flash_io3_oe;
    wire flash_io0_do, flash_io1_do, flash_io2_do, flash_io3_do;

    wire        cnn_ready;
    wire [31:0] cnn_rdata;
    wire        cnn_irq;
    wire [3:0]  cnn_result;
    wire        cnn_busy;
    wire        cnn_done;
    wire        cnn_error;
    wire        cnn_input_full;

    picosoc #(
        .BARREL_SHIFTER(1'b0),
        .ENABLE_MUL(1'b0),
        .ENABLE_DIV(1'b0),
        .ENABLE_COMPRESSED(1'b0),
        .ENABLE_COUNTERS(1'b0),
        .MEM_WORDS(8192)
    ) soc_core (
        .clk           (MAX10_CLK1_50),
        .resetn        (resetn),
        .ser_rx        (UART_RX),
        .ser_tx        (UART_TX),
        .iomem_valid   (iomem_valid),
        .iomem_ready   (iomem_ready),
        .iomem_wstrb   (iomem_wstrb),
        .iomem_addr    (iomem_addr),
        .iomem_wdata   (iomem_wdata),
        .iomem_rdata   (iomem_rdata),
        .irq_5         (cnn_irq),
        .irq_6         (1'b0),
        .irq_7         (1'b0),
        .flash_csb     (flash_csb),
        .flash_clk     (flash_clk),
        .flash_io0_oe  (flash_io0_oe),
        .flash_io1_oe  (flash_io1_oe),
        .flash_io2_oe  (flash_io2_oe),
        .flash_io3_oe  (flash_io3_oe),
        .flash_io0_do  (flash_io0_do),
        .flash_io1_do  (flash_io1_do),
        .flash_io2_do  (flash_io2_do),
        .flash_io3_do  (flash_io3_do),
        .flash_io0_di  (1'b0),
        .flash_io1_di  (1'b0),
        .flash_io2_di  (1'b0),
        .flash_io3_di  (1'b0)
    );

    cnn_mmio_controller cnn_mmio (
        .clk            (MAX10_CLK1_50),
        .resetn         (resetn),
        .iomem_valid    (iomem_valid),
        .iomem_wstrb    (iomem_wstrb),
        .iomem_addr     (iomem_addr),
        .iomem_wdata    (iomem_wdata),
        .iomem_ready    (cnn_ready),
        .iomem_rdata    (cnn_rdata),
        .irq_done       (cnn_irq),
        .result_class_o (cnn_result),
        .busy_o         (cnn_busy),
        .done_o         (cnn_done),
        .error_o        (cnn_error),
        .input_full_o   (cnn_input_full)
    );

    // Small read-only debug page at 0x0400_0000.
    wire gpio_selected =
        iomem_valid && (iomem_addr[31:24] == 8'h04);

    assign iomem_ready = cnn_ready || gpio_selected;
    assign iomem_rdata = cnn_ready ? cnn_rdata :
                         gpio_selected ? {22'd0, SW} :
                         32'd0;

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
    assign LEDR[6]   = cnn_error;
    assign LEDR[7]   = cnn_input_full;
    assign LEDR[8]   = resetn;
    assign LEDR[9]   = heartbeat[24];

endmodule
