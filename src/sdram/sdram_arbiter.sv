// sdram_arbiter.sv - Verzia 3.2 - Vylepšená "Sticky" Round-Robin Arbitráž
//
// Kľúčové zmeny v tejto verzii:
// 1. VYLEPŠENIE (Výkon): Logika pre Round-Robin bola upravená na "sticky" prioritu.
//    Priorita sa teraz mení len v prípade reálnej kolízie (keď obaja masteri
//    žiadajú o prístup naraz), čím sa maximalizuje priepustnosť zbernice,
//    ak je aktívny len jeden master.
//
// Author: refactor by assistant & user feedback

`ifndef SDRAM_ARBITER_SV
`define SDRAM_ARBITER_SV

//`include "sdram_pkg.sv"

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

    logic grant_reader, grant_writer;
    logic prio_is_reader_reg;
    logic can_transfer_reader, can_transfer_writer;

    logic reader_ready_int, writer_ready_int, cmd_fifo_valid_int;
    sdram_pkg::sdram_cmd_t cmd_fifo_data_int;

    //================================================================
    // Logika pre prioritu (registrovaná)
    //================================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            prio_is_reader_reg <= 1'b1;
        end else begin
            // Vylepšená "Sticky" Round-Robin logika
            if (PRIORITY_MODE == "ROUND_ROBIN") begin
                if (can_transfer_reader && writer_valid) begin
                    // Reader vyhral, ale writer tiež čakal -> prioritu dostane writer.
                    prio_is_reader_reg <= 1'b0;
                end else if (can_transfer_writer && reader_valid) begin
                    // Writer vyhral, ale reader tiež čakal -> prioritu dostane reader.
                    prio_is_reader_reg <= 1'b1;
                end
                // Ak nie je kolízia, priorita sa nemení.
            end
        end
    end

    //================================================================
    // Kombinačná logika arbitráže
    //================================================================
    always_comb begin
        grant_reader = 1'b0;
        grant_writer = 1'b0;

        if (PRIORITY_MODE == "FIXED_READER") begin
            grant_reader = reader_valid;
            grant_writer = !reader_valid && writer_valid;
        end else if (PRIORITY_MODE == "FIXED_WRITER") begin
            grant_writer = writer_valid;
            grant_reader = !writer_valid && reader_valid;
        end else begin // ROUND_ROBIN
            if (prio_is_reader_reg) begin
                grant_reader = reader_valid;
                grant_writer = !reader_valid && writer_valid;
            end else begin
                grant_writer = writer_valid;
                grant_reader = !writer_valid && reader_valid;
            end
        end

        can_transfer_reader = grant_reader && cmd_fifo_ready;
        can_transfer_writer = grant_writer && cmd_fifo_ready;

        reader_ready_int = can_transfer_reader;
        writer_ready_int = can_transfer_writer;

        cmd_fifo_valid_int = can_transfer_reader || can_transfer_writer;

        if (can_transfer_reader) begin
            cmd_fifo_data_int.rw   = READ_CMD;
            cmd_fifo_data_int.addr = reader_addr;
        end else if (can_transfer_writer) begin
            cmd_fifo_data_int.rw   = WRITE_CMD;
            cmd_fifo_data_int.addr = writer_addr;
        end else begin
            cmd_fifo_data_int.rw   = READ_CMD;
            cmd_fifo_data_int.addr = '0;
        end

        cmd_fifo_data_int.wdata = '0;
        cmd_fifo_data_int.auto_precharge_en = 1'b1;
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
            assign cmd_fifo_valid = cmd_fifo_valid_int;
            assign cmd_fifo_data  = cmd_fifo_data_int;
            assign reader_ready   = reader_ready_int;
            assign writer_ready   = writer_ready_int;
        end
    endgenerate

    //================================================================
    // Verifikačné asercie (SVA)
    //================================================================
    CheckBothReady: assert property (@(posedge clk) !(reader_ready && writer_ready)) else
        $error("[%0t] SVA FAIL @ %m: Both reader_ready and writer_ready asserted!", $time);

endmodule


`endif