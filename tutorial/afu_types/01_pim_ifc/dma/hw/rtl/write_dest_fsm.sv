// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"


module write_dest_fsm #(
   parameter DATA_W = 512
)(
   input logic clk,
   input logic reset_n,
   output logic wr_fsm_done,
   input  dma_pkg::t_dma_descriptor descriptor,
   ofs_plat_axi_mem_if.to_src dest_mem,
   dma_fifo_if.wr_out  rd_fifo_if
);



endmodule
