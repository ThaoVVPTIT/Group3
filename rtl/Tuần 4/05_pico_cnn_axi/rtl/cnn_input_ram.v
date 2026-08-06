module cnn_input_ram (
    input  wire       clk,
    input  wire       write_enable,
    input  wire [9:0] write_addr,
    input  wire [7:0] write_data,
    input  wire       read_enable,
    input  wire [9:0] read_addr,
    output reg  [7:0] read_data
);

    // Dedicated, synchronous simple-dual-port wrapper. Keeping this RAM
    // separate from the control FSM lets Quartus infer one M9K instead of
    // implementing all 784 bytes as flip-flops.
    (* ramstyle = "M9K, no_rw_check" *) reg [7:0] mem [0:783];

    always @(posedge clk) begin
        if (write_enable)
            mem[write_addr] <= write_data;

        if (read_enable)
            read_data <= mem[read_addr];
    end

endmodule
