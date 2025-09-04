/*
                 AXI4-Full (125 MHz)
                 +------------------+
                 |                  |
                 |   AXI4-Full      |
                 |     Reader       |
                 |                  |
                 +--------+---------+
                          |
                          | write interface
                          v
                   +--------------+
                   |  Async FIFO  |   (prepája domény)
                   +--------------+
                          |
                          | read interface
                          v
                 +------------------+
                 | AXI4-Stream      |
                 |     Sender       |
                 +------------------+
                     AXI4S (75 MHz)
*/

