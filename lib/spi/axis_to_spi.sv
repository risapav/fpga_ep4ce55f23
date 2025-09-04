//axis_to_spi.sv

module axis_to_spi #(
    parameter int CLK_DIV    = 4,
    parameter int DATA_WIDTH = 8  // Musí zodpovedať SPI dátovej šírke
)(
    input logic clk,
    input logic rst,

    // AXI4-Stream slave interface (dáta do SPI)
    axi4s_if.slave s_axis,

    // AXI4-Stream master interface (dáta zo SPI)
    axi4s_if.master m_axis,

    // SPI rozhranie
    output logic sclk,
    output logic mosi,
    input  logic miso,
    output logic ss
);

    // SPI interné prepojenie
    logic start, done;
    logic [DATA_WIDTH-1:0] spi_data_in, spi_data_out;

    // Stavový automat
    typedef enum logic [1:0] {
        IDLE, SEND, WAIT_DONE, OUTPUT
    } state_t;

    state_t state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            s_axis.tready <= 1;
            m_axis.tvalid <= 0;
            start <= 0;
            spi_data_in <= 0;
            m_axis.tdata <= 0;
            m_axis.tlast <= 0;
            m_axis.tuser <= 0;
            m_axis.tkeep <= {DATA_WIDTH/8{1'b1}};
        end else begin
            case (state)
                IDLE: begin
                    m_axis.tvalid <= 0;
                    if (s_axis.tvalid) begin
                        spi_data_in <= s_axis.tdata;
                        start <= 1;
                        s_axis.tready <= 0;
                        state <= SEND;
                    end else begin
                        s_axis.tready <= 1;
                    end
                end

                SEND: begin
                    start <= 0;
                    state <= WAIT_DONE;
                end

                WAIT_DONE: begin
                    if (done) begin
                        m_axis.tdata <= spi_data_out;
                        m_axis.tvalid <= 1;
                        m_axis.tlast <= 1; // Voliteľné
                        m_axis.tuser <= 0;
                        m_axis.tkeep <= {DATA_WIDTH/8{1'b1}};
                        state <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    if (m_axis.tready) begin
                        m_axis.tvalid <= 0;
                        s_axis.tready <= 1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // SPI master inštancia
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

