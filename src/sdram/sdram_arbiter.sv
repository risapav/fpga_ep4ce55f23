// sdram_arbiter.sv - Refaktorovaná verzia 3.1
// - Zjednodušené názvy signálov, odstránený mŕtvy kód.
// - Použité SystemVerilog Assertions (SVA) pre robustnejšiu verifikáciu.
//
// Author: refactor by assistant

`include "sdram_pkg.sv"

(* default_nettype = "none" *)

module SdramCmdArbiter #(
    parameter ADDR_WIDTH = 24,
    parameter DATA_WIDTH = 16,
    parameter BURST_LEN  = 8,

    parameter string PRIORITY_MODE = "ROUND_ROBIN",
    parameter bit REGISTER_OUTPUTS = 0
)(
    input  logic                   clk,
    input  logic                   rstn,

    // Reader interface
    input  logic                   reader_valid,
    output logic                   reader_ready,
    input  logic [ADDR_WIDTH-1:0]  reader_addr,

    // Writer interface
    input  logic                   writer_valid,
    output logic                   writer_ready,
    input  logic [ADDR_WIDTH-1:0]  writer_addr,

    // Command FIFO towards controller
    output logic                   cmd_fifo_valid,
    input  logic                   cmd_fifo_ready,
    output sdram_pkg::sdram_cmd_t  cmd_fifo_data
);

    import sdram_pkg::*;

    // -- Interné signály --
    logic grant_reader, grant_writer; // Zjednodušené názvy pre kombinačné signály
    logic prio_is_reader_reg;
    logic can_transfer_reader, can_transfer_writer;

    // Interné (pred-registrové) verzie výstupov
    logic reader_ready_int, writer_ready_int, cmd_fifo_valid_int;
    sdram_pkg::sdram_cmd_t cmd_fifo_data_int;

    //================================================================
    // Logika pre Round-Robin prioritu (registrovaná)
    //================================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            prio_is_reader_reg <= 1'b1; // Defaultne začína s prioritou pre readera
        end else begin
            // Priorita sa preklopí, len ak došlo k úspešnému prenosu
            if (can_transfer_reader || can_transfer_writer) begin
                // A len ak sme v Round-Robin režime
                if (PRIORITY_MODE == "ROUND_ROBIN") begin
                    prio_is_reader_reg <= ~prio_is_reader_reg;
                end
            end
        end
    end

    //================================================================
    // Kombinačná logika arbitráže
    //================================================================
    always_comb begin
        // -- Defaultné hodnoty --
        grant_reader = 1'b0;
        grant_writer = 1'b0;

        // -- 1. Krok: Arbitráž - Určenie víťaza na základe priority --
        if (PRIORITY_MODE == "FIXED_READER") begin
            grant_reader = reader_valid;
            grant_writer = ~reader_valid && writer_valid;
        end else if (PRIORITY_MODE == "FIXED_WRITER") begin
            grant_writer = writer_valid;
            grant_reader = ~writer_valid && reader_valid;
        end else begin // ROUND_ROBIN
            if (prio_is_reader_reg) begin
                grant_reader = reader_valid;
                grant_writer = ~reader_valid && writer_valid;
            end else begin
                grant_writer = writer_valid;
                grant_reader = ~writer_valid && reader_valid;
            end
        end

        // -- 2. Krok: Handshake - Zistenie, či je možný okamžitý prenos --
        can_transfer_reader = grant_reader && cmd_fifo_ready;
        can_transfer_writer = grant_writer && cmd_fifo_ready;

        // -- 3. Krok: Priradenie `ready` signálov --
        reader_ready_int = can_transfer_reader;
        writer_ready_int = can_transfer_writer;

        // -- 4. Krok: Zostavenie výstupného príkazu --
        cmd_fifo_valid_int = can_transfer_reader || can_transfer_writer;

        if (can_transfer_reader) begin
            cmd_fifo_data_int.rw   = READ_CMD;
            cmd_fifo_data_int.addr = reader_addr;
        end else if (can_transfer_writer) begin
            cmd_fifo_data_int.rw   = WRITE_CMD;
            cmd_fifo_data_int.addr = writer_addr;
        end else begin
            // Pre predvídateľnosť nastavíme defaultné hodnoty
            cmd_fifo_data_int.rw   = READ_CMD; // ľubovoľná hodnota
            cmd_fifo_data_int.addr = '0;
        end

        // Spoločné polia príkazu
        cmd_fifo_data_int.wdata = '0; // Arbiter nerieši dáta
        cmd_fifo_data_int.auto_precharge_en = 1'b1; // Politika: vždy použiť pre výkon
    end

    //================================================================
    // Voliteľné registrovanie výstupov
    //================================================================
    generate
        if (REGISTER_OUTPUTS) begin : gen_reg_outputs
            always_ff @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    cmd_fifo_valid <= 1'b0;
                    cmd_fifo_data  <= '0;
                    reader_ready   <= 1'b0;
                    writer_ready   <= 1'b0;
                end else begin
                    cmd_fifo_valid <= cmd_fifo_valid_int;
                    cmd_fifo_data  <= cmd_fifo_data_int;
                    reader_ready   <= reader_ready_int;
                    writer_ready   <= writer_ready_int;
                end
            end
        end else begin : gen_comb_outputs
            // Priame kombinačné priradenie pre najnižšiu latenciu
            assign cmd_fifo_valid = cmd_fifo_valid_int;
            assign cmd_fifo_data  = cmd_fifo_data_int;
            assign reader_ready   = reader_ready_int;
            assign writer_ready   = writer_ready_int;
        end
    endgenerate

    //================================================================
    // Verifikačné asercie (SVA)
    //================================================================
    // SVA: Zabezpečí, že nikdy nebudú obaja žiadatelia obslúžení naraz.
    CheckBothReady: assert property (@(posedge clk) !(reader_ready && writer_ready)) else
        $error("[%0t] SVA FAIL @ %m: Both reader_ready and writer_ready asserted!", $time);

endmodule
