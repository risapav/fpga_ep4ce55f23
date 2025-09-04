module spi_to_axis #(
    parameter int CLK_DIV    = 4,
    parameter int DATA_WIDTH = 8
)(
    input  logic clk,
    input  logic rst,

    // SPI interface
    output logic sclk,
    output logic mosi,
    input  logic miso,
    output logic ss,

    // AXI4-Stream master interface (výstup zo SPI do systému)
    axi4s_if.master m_axis
);

    logic start, done;
    logic [DATA_WIDTH-1:0] spi_data_in = {DATA_WIDTH{1'b1}}; // často 0xFF
    logic [DATA_WIDTH-1:0] spi_data_out;

    typedef enum logic [1:0] {
        IDLE, SEND, WAIT_DONE, OUTPUT
    } state_t;

    state_t state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= IDLE;
            start           <= 0;
            m_axis.tvalid   <= 0;
            m_axis.tdata    <= 0;
            m_axis.tlast    <= 0;
            m_axis.tkeep    <= {DATA_WIDTH/8{1'b1}};
            m_axis.tuser    <= 0;
            m_axis.tid      <= '0;
            m_axis.tdest    <= '0;
        end else begin
            case (state)
                IDLE: begin
                    start <= 1;
                    state <= SEND;
                end

                SEND: begin
                    start <= 0;
                    state <= WAIT_DONE;
                end

                WAIT_DONE: begin
                    if (done) begin
                        m_axis.tdata  <= spi_data_out;
                        m_axis.tvalid <= 1;
                        m_axis.tlast  <= 1;
                        m_axis.tkeep  <= {DATA_WIDTH/8{1'b1}};
                        state <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    if (m_axis.tready) begin
                        m_axis.tvalid <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // SPI Master instance
    spi_master #(
        .CLK_DIV(CLK_DIV)
    ) spi_inst (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in(spi_data_in),
        .data_out(spi_data_out),
        .done(done),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .ss(ss)
    );

endmodule
