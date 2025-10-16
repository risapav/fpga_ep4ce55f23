(* default_nettype = "none" *)
module CountdownTimer #(
    parameter int WIDTH = 8
)(
    input  logic clk,
    input  logic rstn,
    input  logic start,
    input  logic [WIDTH-1:0] preset,
    output logic busy,
    output logic done
);
    logic [WIDTH-1:0] cnt;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn)
            cnt <= '0;
        else if (start)
            cnt <= preset;
        else if (busy)
            cnt <= cnt - 1;
    end

    assign busy = (cnt != 0);
    assign done = (cnt == 1);

endmodule
`default_nettype wire
