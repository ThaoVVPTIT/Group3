

module top (
    input  wire        MAX10_CLK1_50, 
    input  wire [1:0]  KEY,           

    
    input  wire        UART_RX,      
    output wire        UART_TX,       

    
    input  wire [9:0]  SW,            
    output wire [9:0]  LEDR           
);

    // KEY[0] is active-low: assert reset asynchronously, release it
    // synchronously to avoid a metastable/partial CPU start.
    reg [1:0] reset_sync;
    always @(posedge MAX10_CLK1_50 or negedge KEY[0]) begin
        if (!KEY[0])
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    wire resetn = reset_sync[1];

    // UART_RX is asynchronous to the 50 MHz system clock.
    reg [1:0] uart_rx_sync;
    always @(posedge MAX10_CLK1_50 or negedge resetn) begin
        if (!resetn)
            uart_rx_sync <= 2'b11;
        else
            uart_rx_sync <= {uart_rx_sync[0], UART_RX};
    end

    
    wire        iomem_valid;
    wire [3:0]  iomem_wstrb;
    wire [31:0] iomem_addr;
    wire [31:0] iomem_wdata;
    wire [31:0] iomem_rdata;
    wire        iomem_ready;

    wire flash_csb;
    wire flash_clk;
    wire flash_io0_oe, flash_io1_oe, flash_io2_oe, flash_io3_oe;
    wire flash_io0_do, flash_io1_do, flash_io2_do, flash_io3_do;

   
    picosoc soc_core (
        .clk           (MAX10_CLK1_50),
        .resetn        (resetn),

        // UART
        .ser_rx        (uart_rx_sync[1]),
        .ser_tx        (UART_TX),

        // Bus iomem nối ra ngoài
        .iomem_valid   (iomem_valid),
        .iomem_ready   (iomem_ready),
        .iomem_wstrb   (iomem_wstrb),
        .iomem_addr    (iomem_addr),
        .iomem_wdata   (iomem_wdata),
        .iomem_rdata   (iomem_rdata),

        // IRQ tie-off
        .irq_5         (1'b0),
        .irq_6         (1'b0),
        .irq_7         (1'b0),

        // Flash pins tie-off nội bộ
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

 
    reg [7:0] leds_reg;
    reg [7:0] sw_reg;
    
  
    always @(posedge MAX10_CLK1_50 or negedge resetn) begin
        if (!resetn) begin
            leds_reg <= 8'h00;
        end else if (iomem_valid && iomem_wstrb[0] && (iomem_addr[31:24] == 8'h03)) begin
            leds_reg <= iomem_wdata[7:0];
        end
    end
    
   
    always @(posedge MAX10_CLK1_50) begin
        sw_reg <= SW[7:0];
    end

    // Phản hồi bus iomem khi CPU truy cập địa chỉ 0x03xxxxxx
    wire gpio_sel = iomem_valid && (iomem_addr[31:24] == 8'h03);
    assign iomem_ready = gpio_sel;
    assign iomem_rdata = gpio_sel ? {24'h000000, sw_reg} : 32'h00000000;

  
    assign LEDR[7:0] = leds_reg;
    assign LEDR[8] = resetn;
    assign LEDR[9] = 1'b1;   

endmodule
