// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"


module write_dest_fsm #(
   parameter DATA_W = 512
)(
   input logic clk,
   input logic reset_n,
   output logic wr_fsm_done,
   output dma_pkg::t_dma_csr_status csr_status,
   input  dma_pkg::t_dma_csr_control csr_control,
   input  dma_pkg::t_dma_descriptor descriptor,
   ofs_plat_axi_mem_if.to_sink dest_mem,
   dma_fifo_if.rd_out  rd_fifo_if
);

   `define NUM_STATES 5

   enum {
      IDLE_BIT,
      ADDR_SETUP_BIT,
      RD_FIFO_WR_DEST_BIT,
      WAIT_FOR_WR_RSP_BIT,
      ERROR_BIT
   } index;

   enum logic [`NUM_STATES-1:0] {
      IDLE            = `NUM_STATES'b1<<IDLE_BIT,
      ADDR_SETUP      = `NUM_STATES'b1<<ADDR_SETUP_BIT,
      RD_FIFO_WR_DEST = `NUM_STATES'b1<<RD_FIFO_WR_DEST_BIT,
      WAIT_FOR_WR_RSP = `NUM_STATES'b1<<WAIT_FOR_WR_RSP_BIT,
      ERROR           = `NUM_STATES'b1<<ERROR_BIT,
      XXX             = 'x
   } state, next;

   logic wr_resp_last;
   assign wr_resp_last = dest_mem.bvalid & dest_mem.bready & dest_mem.w.last;
   
   always_ff @(posedge clk) begin
      if (!reset_n) state <= IDLE;
      else          state <= next;
   end

   always_comb begin
      next = XXX;
      unique case (1'b1)
         state[IDLE_BIT]: 
            if (descriptor.control.go == 1) next = ADDR_SETUP; 

         state[ADDR_SETUP_BIT]:
            if (dest_mem.awvalid & dest_mem.awready) next = RD_FIFO_WR_DEST;

         state[RD_FIFO_WR_DEST_BIT]:
            if (dest_mem.wvalid & dest_mem.wready & dest_mem.w.last) next = WAIT_FOR_WR_RSP;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wr_resp_last & (dest_mem.b.resp==dma_pkg::OKAY)) next = IDLE;
            else if (wr_resp_last & ((dest_mem.b.resp==dma_pkg::SLVERR) | ((dest_mem.b.resp==dma_pkg::SLVERR)))) next = ERROR; 
 
         state[ERROR]:
            if (csr_control.reset_dispatcher) next = IDLE;

      endcase
   end

  always_ff @(posedge clk) begin
     if (!reset_n) begin
        dest_mem.arvalid       <= 1'b0;
        dest_mem.wvalid        <= 1'b0;
        dest_mem.awvalid       <= 1'b0;
     end else begin
        unique case (1'b1)
           state[IDLE_BIT]: begin
              dest_mem.awvalid      <= 1'b0;
           end 
           
           state[ADDR_SETUP_BIT]: begin
               dest_mem.awvalid  <= 1'b1;
               dest_mem.aw.addr  <= descriptor.dest_addr;
               dest_mem.aw.len   <= descriptor.length;
               dest_mem.aw.burst <= 0;
               dest_mem.aw.size  <= 0;
           end
           
           state[RD_FIFO_WR_DEST_BIT]: begin
               dest_mem.awvalid <= 1'b0;
                dest_mem.w.data <= rd_fifo_if.rd_data;
                rd_fifo_if.rd_en <= 1'b1;
           end
           
           state[WAIT_FOR_WR_RSP_BIT]:
              wr_fsm_done <= 1'b1;
          
       endcase
     end
  end




endmodule
