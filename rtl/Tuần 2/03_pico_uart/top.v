// ============================================================================
// TOP MODULE CHÍNH CHỦ: top.v (Tối ưu cho Kit DE10-Lite trên Intel Quartus)
// Mô tả: Module bọc ngoài giúp giấu toàn bộ các bus cồng kềnh vào bên trong,
//        chỉ thò đúng các chân cắm thực tế của bo mạch DE10-Lite ra ngoài.
// ============================================================================

module top (
    input  wire        MAX10_CLK1_50, // Xung nhịp 50MHz trên kit DE10-Lite (Pin P11)
    input  wire [1:0]  KEY,           // KEY[0] là nút Reset (Active-Low, Pin B8)

    // Giao tiếp UART kết nối với PC / ESP32
    input  wire        UART_RX,       // Chân nhận RX
    output wire        UART_TX,       // Chân phát TX

    // Ngoại vi trên bo mạch DE10-Lite
    input  wire [9:0]  SW,            // 10 Công tắc / Nút bấm ngõ vào SW[9:0]
    output wire [9:0]  LEDR           // 10 Đèn LED đỏ ngõ ra LEDR[9:0]
);

    wire resetn = KEY[0]; // Nút KEY[0] làm nút Reset hệ thống

    // Các tín hiệu bus nội bộ (giấu inside top module, không thò ra ngoài chân FPGA)
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

    // Khởi tạo lõi PicoSoC sạch (không có cổng LED/Switches)
    picosoc soc_core (
        .clk           (MAX10_CLK1_50),
        .resetn        (resetn),

        // UART
        .ser_rx        (UART_RX),
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

    // ---------------------------------------------------------------------
    // GIẢI MÃ ĐỊA CHỈ NGOẠI VI (MẠCH GPIO CỦA BOARD NGOÀI LÕI SOC)
    // ---------------------------------------------------------------------
    reg [7:0] leds_reg;
    reg [7:0] sw_reg;
    
    // Ghi dữ liệu vào LED ở địa chỉ 0x0300_0000
    always @(posedge MAX10_CLK1_50 or negedge resetn) begin
        if (!resetn) begin
            leds_reg <= 8'h00;
        end else if (iomem_valid && iomem_wstrb[0] && (iomem_addr[31:24] == 8'h03)) begin
            leds_reg <= iomem_wdata[7:0];
        end
    end
    
    // Đọc dữ liệu từ Switches ở địa chỉ 0x0300_0000 (đọc 8 công tắc SW[7:0])
    always @(posedge MAX10_CLK1_50) begin
        sw_reg <= SW[7:0];
    end

    // Phản hồi bus iomem khi CPU truy cập địa chỉ 0x03xx_xxxx
    wire gpio_sel = iomem_valid && (iomem_addr[31:24] == 8'h03);
    assign iomem_ready = gpio_sel;
    assign iomem_rdata = gpio_sel ? {24'h000000, sw_reg} : 32'h00000000;

    // Nối ra chân LED thực tế của FPGA
    assign LEDR[7:0] = leds_reg;
    assign LEDR[8] = resetn; // Báo trạng thái nút reset
    assign LEDR[9] = 1'b1;   // Báo nguồn OK

endmodule
