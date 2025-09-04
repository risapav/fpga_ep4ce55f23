SDRAM Controller for W9825G6KH-6

Overview

This module implements an SDRAM controller tailored for the Winbond W9825G6KH-6 device. It manages initialization, read/write operations, and periodic refresh in compliance with the JEDEC standard. The controller uses a simple FSM and FIFO-based command interface.

Features

Compatible with W9825G6KH-6 SDRAM

Fully synchronous interface

Configurable burst length, CAS latency, and timing parameters

Supports:

Initialization sequence

Read/Write with burst

Auto refresh

Parameters

Name

Description

Default

ADDR_WIDTH

Full address width (row + column + bank)

24

DATA_WIDTH

Data width of SDRAM

16

BURST_LEN

SDRAM burst length

8

tRP

Precharge command period (in cycles)

3

tRCD

Activate to Read/Write delay

3

tWR

Write recovery time

3

tRC

Row cycle time

9

CAS_LATENCY

CAS latency (read delay)

3

tRFC

Refresh cycle time

7

Ports

Clock and Reset

clk : Clock input

rstn: Active-low asynchronous reset

Command FIFO Interface

cmd_fifo_valid : Command valid

cmd_fifo_ready : Controller ready to accept command

cmd_fifo_data  : Contains command (from sdram_pkg::sdram_cmd_t)

Read Response Interface

resp_valid : Indicates valid read data

resp_last  : Last beat of burst

resp_data  : Output read data

resp_ready : Read data accepted

SDRAM Physical Interface

sdram_addr  : Address bus

sdram_ba    : Bank address

sdram_cs_n  : Chip select

sdram_ras_n : Row address strobe

sdram_cas_n : Column address strobe

sdram_we_n  : Write enable

sdram_dq    : Bidirectional data bus

sdram_dqm   : Data mask

sdram_cke   : Clock enable

Debug

fsm_state : Current state of FSM

Command Format (from sdram_pkg)

typedef struct packed {
  logic rw;                  // 1 = Read, 0 = Write
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] wdata; // Only for write
} sdram_cmd_t;

FSM States

State

Description

RESET

Wait for reset deassertion and start init

INIT_*

Initialization sequence (precharge, refresh, mode register)

IDLE

Wait for command or refresh

ACTIVE

Activate a row (RAS phase)

WAIT_TRCD

Wait tRCD before issuing command

READ, WRITE

Issue read/write command

WAIT_CL

Wait for CAS latency before data read

READ_DATA

Output data from read burst

WAIT_TWR

Wait after write before precharge

PRECHARGE

Close open row

AUTO_REFRESH

Issue auto-refresh command

WAIT_TRFC

Wait for refresh completion

Timing Diagrams (Conceptual)

Read Operation

ACTIVE -> WAIT_TRCD -> READ -> WAIT_CL -> READ_DATA -> PRECHARGE

Write Operation

ACTIVE -> WAIT_TRCD -> WRITE -> WAIT_TWR -> PRECHARGE

Refresh Cycle

IDLE -> AUTO_REFRESH -> WAIT_TRFC -> IDLE

Notes

The controller supports fixed burst length defined by parameter BURST_LEN

sdram_dqm is set to 00 (no masking)

sdram_cs_n is always driven low (active)

Refresh counter ensures periodic refresh every ~7.8us (for 100 MHz clock)

Future Improvements

Implement write/read FIFOs with backpressure

Add error detection/logging

Support partial writes with sdram_dqm

Support dynamic burst lengths

License

Open hardware, provided as-is under MIT or similar license.

Author

Generated with ❤️ by ChatGPT for optimized SDRAM control

risapav
