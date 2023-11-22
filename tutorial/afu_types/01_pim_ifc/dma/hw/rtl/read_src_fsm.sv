// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"


module read_src_fsm #(
   parameter DATA_W = 512
)(
   input logic clk,
   input logic reset_n,
   input logic wr_fsm_done,
   input  dma_pkg::t_dma_descriptor descriptor,
   output logic descriptor_fifo_rdack,
   ofs_plat_axi_mem_if.to_sink src_mem,
   dma_fifo_if.wr_out  wr_fifo_if
);

   `define NUM_STATES 4

   enum {
      IDLE_BIT,
      ADDR_SETUP_BIT,
      CP_RSP_TO_FIFO_BIT,
      WAIT_FOR_WR_RSP_BIT
   } index;

   enum logic [`NUM_STATES-1:0] {
      IDLE                = `NUM_STATES'b1<<IDLE_BIT,
      ADDR_SETUP          = `NUM_STATES'b1<<ADDR_SETUP_BIT,
      CP_RSP_TO_FIFO      = `NUM_STATES'b1<<CP_RSP_TO_FIFO_BIT,
      WAIT_FOR_WR_RSP     = `NUM_STATES'b1<<WAIT_FOR_WR_RSP_BIT,
      XXX = 'x
   } state, next;
   
   //assign src_mem.rready = state[CP_RSP_TO_FIFO_BIT] ? wr_fifo_if.not_full : 0;
   assign src_mem.rready = 1'b1;
   assign src_mem.bready = 1'b0;

   always_ff @(posedge clk) begin
      if (!reset_n) state <= IDLE;
      else          state <= next;
   end

   always_comb begin
      next = XXX;
      unique case (1'b1)
         state[IDLE_BIT]: 
            if (descriptor.descriptor_control.go == 1) next = ADDR_SETUP; 
            else next = IDLE;

         state[ADDR_SETUP_BIT]:
            if (src_mem.arvalid & src_mem.arready) next = CP_RSP_TO_FIFO;
            else next = ADDR_SETUP;

         state[CP_RSP_TO_FIFO_BIT]:
            if (src_mem.rvalid & src_mem.rready & src_mem.r.last) next = WAIT_FOR_WR_RSP;
            else next = CP_RSP_TO_FIFO;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wr_fsm_done) next = IDLE;
            else next = WAIT_FOR_WR_RSP;
      endcase
   end


  always_ff @(posedge clk) begin
     if (!reset_n) begin
        src_mem.arvalid       <= 1'b0;
        src_mem.wvalid        <= 1'b0;
        src_mem.awvalid       <= 1'b0;
        descriptor_fifo_rdack <= 1'b0;
     end else begin
        unique case (1'b1)
           next[IDLE_BIT]: begin
              src_mem.arvalid <= 1'b0;
              descriptor_fifo_rdack <= 1'b0;
           end 
           
           next[ADDR_SETUP_BIT]: begin
               src_mem.arvalid  <= 1'b1;
               src_mem.ar.addr  <= descriptor.src_addr;
               src_mem.ar.len   <= descriptor.length;
               src_mem.ar.burst <= 0;
               src_mem.ar.size  <= 0;
           end
           
           next[CP_RSP_TO_FIFO_BIT]: begin
               src_mem.arvalid <= 1'b0;
               wr_fifo_if.wr_data <= src_mem.r.data;
               wr_fifo_if.wr_en   <= !wr_fifo_if.not_full & src_mem.rvalid;
           end
           
           next[WAIT_FOR_WR_RSP_BIT]:
              if (wr_fsm_done) descriptor_fifo_rdack <= 1'b1;
          
       endcase
     end
  end

endmodule
