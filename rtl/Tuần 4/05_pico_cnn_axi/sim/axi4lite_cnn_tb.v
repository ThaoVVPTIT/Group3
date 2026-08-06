`timescale 1ns / 1ps

module axi4lite_cnn_tb;
    reg clk;
    reg resetn;

    reg         awvalid;
    wire        awready;
    reg  [31:0] awaddr;
    reg  [2:0]  awprot;
    reg         wvalid;
    wire        wready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    wire        bvalid;
    reg         bready;
    wire [1:0]  bresp;
    reg         arvalid;
    wire        arready;
    reg  [31:0] araddr;
    reg  [2:0]  arprot;
    wire        rvalid;
    reg         rready;
    wire [31:0] rdata;
    wire [1:0]  rresp;

    reg         ser_rx;
    wire        ser_tx;
    reg  [9:0]  gpio_switches;
    wire        cnn_irq;
    wire [3:0]  cnn_result;
    wire        cnn_ready;
    wire        cnn_busy;
    wire        cnn_done;
    wire        cnn_error;
    wire        cnn_input_full;

    reg [7:0] pixels [0:783];
    reg [31:0] rd;
    integer i;
    integer run;
    integer polls;

    axi4lite_soc_slave #(
        .MEM_WORDS(8192)
    ) dut (
        .clk            (clk),
        .resetn         (resetn),
        .s_axi_awvalid  (awvalid),
        .s_axi_awready  (awready),
        .s_axi_awaddr   (awaddr),
        .s_axi_awprot   (awprot),
        .s_axi_wvalid   (wvalid),
        .s_axi_wready   (wready),
        .s_axi_wdata    (wdata),
        .s_axi_wstrb    (wstrb),
        .s_axi_bvalid   (bvalid),
        .s_axi_bready   (bready),
        .s_axi_bresp    (bresp),
        .s_axi_arvalid  (arvalid),
        .s_axi_arready  (arready),
        .s_axi_araddr   (araddr),
        .s_axi_arprot   (arprot),
        .s_axi_rvalid   (rvalid),
        .s_axi_rready   (rready),
        .s_axi_rdata    (rdata),
        .s_axi_rresp    (rresp),
        .ser_rx         (ser_rx),
        .ser_tx         (ser_tx),
        .gpio_switches  (gpio_switches),
        .cnn_irq        (cnn_irq),
        .cnn_result     (cnn_result),
        .cnn_ready      (cnn_ready),
        .cnn_busy       (cnn_busy),
        .cnn_done       (cnn_done),
        .cnn_error      (cnn_error),
        .cnn_input_full (cnn_input_full)
    );

    always #10 clk = ~clk;

    task axi_write;
        input [31:0] address;
        input [31:0] value;
        input [3:0] strobe;
        input integer split_channels;
        integer aw_done;
        integer w_done;
        begin
            aw_done = 0;
            w_done = 0;

            @(negedge clk);
            awaddr = address;
            awvalid = 1'b1;

            if (split_channels != 0) begin
                while (!aw_done) begin
                    @(posedge clk);
                    if (awvalid && awready)
                        aw_done = 1;
                end
                @(negedge clk);
                awvalid = 1'b0;
                repeat (2) @(posedge clk);
                @(negedge clk);
            end

            wdata = value;
            wstrb = strobe;
            wvalid = 1'b1;

            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (awvalid && awready)
                    aw_done = 1;
                if (wvalid && wready)
                    w_done = 1;
                @(negedge clk);
                if (aw_done)
                    awvalid = 1'b0;
                if (w_done)
                    wvalid = 1'b0;
            end

            while (!bvalid)
                @(negedge clk);
            if (bresp != 2'b00) begin
                $display("FAIL: AXI write response %0d at %08x", bresp, address);
                $finish;
            end
            @(posedge clk);
        end
    endtask

    task axi_read;
        input [31:0] address;
        output [31:0] value;
        begin
            @(negedge clk);
            araddr = address;
            arvalid = 1'b1;
            while (!(arvalid && arready))
                @(posedge clk);
            @(negedge clk);
            arvalid = 1'b0;

            while (!rvalid)
                @(negedge clk);
            value = rdata;
            if (rresp != 2'b00) begin
                $display("FAIL: AXI read response %0d at %08x", rresp, address);
                $finish;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("data/mnist_vector0.mem", pixels);
        clk = 1'b0;
        resetn = 1'b0;
        awvalid = 1'b0;
        awaddr = 32'd0;
        awprot = 3'd0;
        wvalid = 1'b0;
        wdata = 32'd0;
        wstrb = 4'd0;
        bready = 1'b1;
        arvalid = 1'b0;
        araddr = 32'd0;
        arprot = 3'd0;
        rready = 1'b1;
        ser_rx = 1'b1;
        gpio_switches = 10'h155;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (4) @(posedge clk);

        // AXI RAM smoke test.
        axi_write(32'h0000_7FFC, 32'hA5A5_5A5A, 4'b1111, 1);
        axi_read(32'h0000_7FFC, rd);
        if (rd !== 32'hA5A5_5A5A) begin
            $display("FAIL: AXI RAM readback %08x", rd);
            $finish;
        end

        // Read-only GPIO page smoke test.
        axi_read(32'h0400_0000, rd);
        if (rd[9:0] !== 10'h155) begin
            $display("FAIL: AXI GPIO readback %08x", rd);
            $finish;
        end

        axi_read(32'h0300_0000, rd);
        if (rd !== 32'h434E_4E31) begin
            $display("FAIL: wrong AXI CNN ID %08x", rd);
            $finish;
        end

        for (run = 1; run <= 3; run = run + 1) begin
            // AW-before-W verifies that the slave handles independent AXI
            // write channels instead of assuming simultaneous valid pulses.
            axi_write(32'h0300_0004, 32'h0000_0002, 4'b1111, 1);

            for (i = 0; i < 784; i = i + 1)
                axi_write(32'h0300_0018, {24'd0, pixels[i]}, 4'b0001, 0);

            axi_read(32'h0300_0014, rd);
            if (rd !== 32'd784 || !cnn_input_full || !cnn_ready) begin
                $display("FAIL: input buffer count=%0d status full=%0d ready=%0d",
                         rd, cnn_input_full, cnn_ready);
                $finish;
            end

            axi_write(32'h0300_0004, 32'h0000_0001, 4'b1111, 0);

            polls = 0;
            rd = 32'd0;
            while (!(rd[2] || rd[3]) && polls < 2000) begin
                axi_read(32'h0300_0008, rd);
                polls = polls + 1;
            end

            if (rd[3] || cnn_error) begin
                axi_read(32'h0300_0024, rd);
                $display("FAIL: CNN AXI error code=%0d", rd);
                $finish;
            end
            if (!rd[2]) begin
                $display("FAIL: AXI START-to-DONE timeout");
                $finish;
            end

            axi_read(32'h0300_001C, rd);
            if (rd[3:0] !== 4'd3) begin
                $display("FAIL: class=%0d expected=3", rd[3:0]);
                $finish;
            end

            axi_read(32'h0300_0020, rd);
            if (rd !== 32'd1282) begin
                $display("FAIL: cycles=%0d expected=1282", rd);
                $finish;
            end

            axi_read(32'h0300_0028, rd);
            if (rd !== run) begin
                $display("FAIL: frame=%0d expected=%0d", rd, run);
                $finish;
            end

            $display("AXI RUN %0d PASS: class=3 cycles=1282 frame=%0d", run, rd);
        end

        $display("ALL AXI4-LITE START->BUSY->DONE TESTS PASS");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: global simulation timeout");
        $finish;
    end

endmodule
