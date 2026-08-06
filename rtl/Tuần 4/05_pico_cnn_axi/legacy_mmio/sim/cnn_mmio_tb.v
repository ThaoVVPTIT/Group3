`timescale 1ns / 1ps

module cnn_mmio_tb;
    reg clk;
    reg resetn;
    reg iomem_valid;
    reg [3:0] iomem_wstrb;
    reg [31:0] iomem_addr;
    reg [31:0] iomem_wdata;
    wire iomem_ready;
    wire [31:0] iomem_rdata;
    wire irq_done;
    wire [3:0] result_class;
    wire busy;
    wire done;
    wire error;
    wire input_full;

    reg [7:0] pixels [0:783];
    integer i;
    integer run;
    integer wait_cycles;

    cnn_mmio_controller dut (
        .clk            (clk),
        .resetn         (resetn),
        .iomem_valid    (iomem_valid),
        .iomem_wstrb    (iomem_wstrb),
        .iomem_addr     (iomem_addr),
        .iomem_wdata    (iomem_wdata),
        .iomem_ready    (iomem_ready),
        .iomem_rdata    (iomem_rdata),
        .irq_done       (irq_done),
        .result_class_o (result_class),
        .busy_o         (busy),
        .done_o         (done),
        .error_o        (error),
        .input_full_o   (input_full)
    );

    always #10 clk = ~clk;

    task mmio_write_word;
        input [31:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            iomem_valid = 1'b1;
            iomem_wstrb = 4'b1111;
            iomem_addr = address;
            iomem_wdata = value;
            @(posedge clk);
            if (!iomem_ready) begin
                $display("FAIL: no MMIO ready at %08x", address);
                $finish;
            end
            @(negedge clk);
            iomem_valid = 1'b0;
            iomem_wstrb = 4'b0000;
        end
    endtask

    task mmio_write_byte;
        input [31:0] address;
        input [7:0] value;
        begin
            @(negedge clk);
            iomem_valid = 1'b1;
            iomem_wstrb = 4'b0001;
            iomem_addr = address;
            iomem_wdata = {24'd0, value};
            @(posedge clk);
            if (!iomem_ready) begin
                $display("FAIL: no MMIO ready at %08x", address);
                $finish;
            end
            @(negedge clk);
            iomem_valid = 1'b0;
            iomem_wstrb = 4'b0000;
        end
    endtask

    initial begin
        $readmemh("data/mnist_vector0.mem", pixels);
        clk = 1'b0;
        resetn = 1'b0;
        iomem_valid = 1'b0;
        iomem_wstrb = 4'b0000;
        iomem_addr = 32'd0;
        iomem_wdata = 32'd0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (4) @(posedge clk);

        if (dut.CNN_ID_VERSION !== 32'h434E4E31) begin
            $display("FAIL: wrong MMIO ID");
            $finish;
        end

        for (run = 1; run <= 3; run = run + 1) begin
            mmio_write_word(32'h0300_0004, 32'h0000_0002);

            for (i = 0; i < 784; i = i + 1)
                mmio_write_byte(32'h0300_0018, pixels[i]);

            if (!input_full || dut.input_count != 10'd784) begin
                $display("FAIL: input_count=%0d", dut.input_count);
                $finish;
            end

            mmio_write_word(32'h0300_0004, 32'h0000_0001);

            wait_cycles = 0;
            while (!done && !error && wait_cycles < 5000) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (error) begin
                $display("FAIL: hardware error code=%0d", dut.error_code);
                $finish;
            end
            if (!done) begin
                $display("FAIL: timeout");
                $finish;
            end
            if (result_class != 4'd3) begin
                $display("FAIL: class=%0d expected=3", result_class);
                $finish;
            end

            $display(
                "RUN %0d PASS: class=%0d cycles=%0d frame=%0d",
                run, result_class, dut.cycle_count, dut.frame_id
            );
        end

        $display("ALL MMIO START->DONE TESTS PASS");
        $finish;
    end

endmodule
