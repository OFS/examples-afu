// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// This is not the main write engine. It is a wrapper around the main engine,
// which is named copy_write_engine_core().
//
// The module here is responsible for injecting completions (interrupts or
// status line writes) into the write stream as copy operations complete in
// order to signal the host. Putting just the completion logic here makes
// the code easier to read.
//

module dma_engine #(
    parameter MODE = dma_pkg::STAND_BY,
    parameter MAX_REQS_IN_FLIGHT = 16
   )(
      input  logic  clk,
      input  logic  reset_n,
      input  logic descriptor_fifo_not_empty,
      output logic descriptor_fifo_rdack,
      input  dma_pkg::t_dma_descriptor descriptor,
      ofs_plat_axi_mem_if.to_sink src_mem,
      ofs_plat_axi_mem_if.to_sink dest_mem,

      input  dma_pkg::t_dma_csr_control csr_control,
      output dma_pkg::t_dma_csr_status  wr_dest_status,
      output dma_pkg::t_dma_csr_status  rd_src_status
   );

   localparam SRC_ADDR_W  = (MODE == dma_pkg::DDR_TO_HOST) ? dma_pkg::DDR_ADDR_W : dma_pkg::HOST_ADDR_W;
   localparam DEST_ADDR_W = (MODE == dma_pkg::HOST_TO_DDR) ? dma_pkg::DDR_ADDR_W : dma_pkg::HOST_ADDR_W;
   localparam SRC_DATA_W  = (MODE == dma_pkg::DDR_TO_HOST) ? dma_pkg::HOST_DATA_W : dma_pkg::DDR_DATA_W;
   localparam DEST_DATA_W = (MODE == dma_pkg::HOST_TO_DDR) ? dma_pkg::HOST_DATA_W : dma_pkg::DDR_DATA_W;
   localparam FIFO_DATA_W = dma_pkg::AXI_MM_DATA_W;

   logic wr_fsm_done;
   dma_fifo_if #(.DATA_W (DEST_DATA_W)) wr_fifo_if();
   dma_fifo_if #(.DATA_W (SRC_DATA_W))  rd_fifo_if();

     write_dest_fsm #(
      .DATA_W (DEST_DATA_W)
   ) write_dest_fsm_inst (
      .*
   );
   
   ofs_plat_prim_fifo_bram #(
      .N_DATA_BITS (FIFO_DATA_W),
      .N_ENTRIES   (MAX_REQS_IN_FLIGHT)
   ) dma_fifo (
      .clk,
      .reset_n,

      .enq_data   (wr_fifo_if.wr_data),
      .enq_en     (wr_fifo_if.wr_en),
      .notFull    (wr_fifo_if.not_full),
      .almostFull (wr_fifo_if.almost_full),

      // Pop the next command if the read request was sent to the host
      .deq_en   (rd_fifo_if.rd_en),
      .notEmpty (rd_fifo_if.not_empty),
      .first    (rd_fifo_if.rd_data) 
   ); 

   read_src_fsm #(
      .DATA_W (SRC_DATA_W)
   ) read_src_fsm_inst (
      .*
   );

endmodule // copy_write_engine
