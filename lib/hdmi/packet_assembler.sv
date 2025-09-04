// packet_assembler.sv
// Assembler pre rozloženie paketových dát do bitových sekvencií pre TMDS kódovanie
module packet_assembler (
    input  logic             clk_pixel,
    input  logic             data_island_period,
    input  logic [23:0]      header,
    input  logic [55:0]      sub [3:0],
    output logic [8:0]       packet_data,
    input  logic [4:0]       counter
);

    // Počet bitov v pakete (napr. 32 bajtov = 256 bitov, ale tu zjednodušené na 9-bitové slová)
    // Pre ilustráciu postupne vyskladáme 9-bitové slová z headeru + sub dát
    // Reálne by sa mal dekódovať správny formát podľa HDMI špecifikácie.

    always_ff @(posedge clk_pixel) begin
        if (!data_island_period) begin
            packet_data <= 9'd0;
        end else begin
            case (counter)
                5'd0: packet_data <= {1'b0, header[23:15]};       // prvých 9 bitov hlavičky
                5'd1: packet_data <= {1'b0, header[14:6]};
                5'd2: packet_data <= {1'b0, header[5:0], 3'b000};
                default: packet_data <= 9'd0; // neskôr dátové časti (sub), tu len nula
            endcase
        end
    end

endmodule
