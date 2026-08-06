`timescale 1ns/1ps

// End-to-end smoke test: the real picorv32_axi fetches firmware from the
// AXI4-Lite RAM, programs the UART and reaches the READY 784 protocol state.
module top_axi_boot_tb;
    localparam integer UART_BIT_NS = 8720;
    localparam integer TIMEOUT_NS  = 20_000_000;

    reg         clk = 1'b0;
    reg  [1:0]  key = 2'b00;
    reg         uart_rx = 1'b1;
    reg  [9:0]  sw = 10'd0;
    wire        uart_tx;
    wire [9:0]  ledr;

    integer byte_count = 0;
    integer token_index = 0;
    reg [7:0] rx_byte;
    reg ready_seen = 1'b0;

    top_axi dut (
        .MAX10_CLK1_50(clk),
        .KEY(key),
        .UART_RX(uart_rx),
        .UART_TX(uart_tx),
        .SW(sw),
        .LEDR(ledr)
    );

    always #10 clk = ~clk;

    task receive_uart_byte;
        output [7:0] value;
        integer bit_index;
        begin
            @(negedge uart_tx);
            #(UART_BIT_NS + UART_BIT_NS/2);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx;
                #UART_BIT_NS;
            end
            if (uart_tx !== 1'b1) begin
                $display("ERROR: UART stop bit is not high at byte %0d", byte_count);
                $finish;
            end
            #(UART_BIT_NS/2);
        end
    endtask

    // Match the byte sequence "READY 784" without relying on simulator-only
    // string methods, keeping this test compatible with ModelSim 10.5b.
    task update_ready_match;
        input [7:0] value;
        begin
            case (token_index)
                0: token_index = (value == "R") ? 1 : 0;
                1: token_index = (value == "E") ? 2 : ((value == "R") ? 1 : 0);
                2: token_index = (value == "A") ? 3 : ((value == "R") ? 1 : 0);
                3: token_index = (value == "D") ? 4 : ((value == "R") ? 1 : 0);
                4: token_index = (value == "Y") ? 5 : ((value == "R") ? 1 : 0);
                5: token_index = (value == " ") ? 6 : ((value == "R") ? 1 : 0);
                6: token_index = (value == "7") ? 7 : ((value == "R") ? 1 : 0);
                7: token_index = (value == "8") ? 8 : ((value == "R") ? 1 : 0);
                8: begin
                    if (value == "4") begin
                        ready_seen = 1'b1;
                        token_index = 9;
                    end else begin
                        token_index = (value == "R") ? 1 : 0;
                    end
                end
                default: token_index = token_index;
            endcase
        end
    endtask

    initial begin
        // Assert KEY[0] reset, then release it as on the DE10-Lite board.
        repeat (20) @(posedge clk);
        key = 2'b11;

        wait (dut.resetn === 1'b1);
        while (!ready_seen) begin
            receive_uart_byte(rx_byte);
            byte_count = byte_count + 1;
            $write("%c", rx_byte);
            update_ready_match(rx_byte);
            if (dut.cpu_trap) begin
                $display("\nERROR: PicoRV32 entered trap before READY 784");
                $finish;
            end
        end

        $display("\nAXI CPU BOOT PASS: firmware reached READY 784 after %0d UART bytes", byte_count);
        $display("LEDR=%b resetn=%b cpu_trap=%b", ledr, dut.resetn, dut.cpu_trap);
        $finish;
    end

    initial begin
        #TIMEOUT_NS;
        $display("\nERROR: timeout waiting for firmware READY 784");
        $display("LEDR=%b resetn=%b cpu_trap=%b bytes=%0d", ledr, dut.resetn, dut.cpu_trap, byte_count);
        $finish;
    end
endmodule
