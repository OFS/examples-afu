// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"


module read_src_fsm #(
   parameter DATA_W = 512,
   parameter MAX_TRANSFER_SIZE_BITS = 14
)(
   input logic clk,
   input logic reset_n,
   input logic wr_fsm_done,
   input  dma_pkg::t_dma_descriptor descriptor,
   output dma_pkg::t_dma_csr_status rd_src_status, 
   input logic descriptor_fifo_not_empty,
   output logic descriptor_fifo_rdack,
   ofs_plat_axi_mem_if.to_sink src_mem,
   dma_fifo_if.wr_out  wr_fifo_if
);

   localparam AXI_SIZE_W = $bits(src_mem.ar.size);

   localparam MAX_TRANSFER_IDX = MAX_TRANSFER_SIZE_BITS-1-3;
   localparam MAX_TRANSFER_BYTES = 'b1 << (MAX_TRANSFER_SIZE_BITS - 3); 

   `define NUM_RD_STATES 7 

   enum {
      IDLE_BIT,
      LONG_ADDR_SETUP_BIT,
      LAST_ADDR_SETUP_BIT,
      CP_RSP_TO_FIFO_BIT,
      WAIT_FOR_WR_RSP_BIT,
      ERROR_BIT
   } index;

   enum logic [`NUM_RD_STATES-1:0] {
      IDLE            = `NUM_RD_STATES'b1<<IDLE_BIT,
      LONG_ADDR_SETUP = `NUM_WR_STATES'b1<<LONG_ADDR_SETUP_BIT,
      LAST_ADDR_SETUP = `NUM_RD_STATES'b1<<LAST_ADDR_SETUP_BIT,
      CP_RSP_TO_FIFO  = `NUM_RD_STATES'b1<<CP_RSP_TO_FIFO_BIT,
      WAIT_FOR_WR_RSP = `NUM_RD_STATES'b1<<WAIT_FOR_WR_RSP_BIT,
      ERROR           = `NUM_RD_STATES'b1<<ERROR_BIT,
      XXX = 'x
   } prev, state, next;

   function automatic logic [AXI_SIZE_W-1:0] get_burst;
      input [1:0] burst_mode;
      begin
         case (burst_mode)
            dma_pkg::STAND_BY:    return XXX;
            dma_pkg::HOST_TO_DDR: return dma_pkg::BURST_WRAP;
            dma_pkg::DDR_TO_HOST: return dma_pkg::BURST_INCR;
            dma_pkg::DDR_TO_DDR:  return dma_pkg::BURST_INCR;
            default:              return XXX;
         endcase
      end
    endfunction

   logic [dma_pkg::PERF_CNTR_W-1:0] rd_src_clk_cnt;
   logic [dma_pkg::PERF_CNTR_W-1:0] rd_src_valid_cnt;
   logic [dma_pkg::SRC_ADDR_W-1:0]  rd_src_addr;
   logic [dma_pkg::LENGTH_W-1:0]    rd_length;
   logic                            rd_prev_incr;

   assign rd_src_status.rd_src_perf_cntr.rd_src_clk_cnt   = rd_src_clk_cnt;
   assign rd_src_status.rd_src_perf_cntr.rd_src_valid_cnt =  rd_src_valid_cnt;
   assign src_mem.bready = 1'b0;
   assign rd_src_status.rd_state = state;
   
   always_ff @(posedge clk) begin
      if (!reset_n) state <= IDLE;
      else          state <= next;
   end

   always_ff @(posedge clk) begin
      if (!reset_n) prev <= IDLE;
      else          prev <= state;
   end

   always_comb begin
      next = XXX;
      unique case (1'b1)
        state[IDLE_BIT]: begin 
          if (descriptor.descriptor_control.go & descriptor_fifo_not_empty) begin 
            if(descriptor.length > MAX_TRANSFER_BYTES) next = LONG_ADDR_SETUP;
            else next = LAST_ADDR_SETUP;
          end else next = IDLE;
        end 

         state[LONG_ADDR_SETUP_BIT]:
            if (src_mem.arvalid & src_mem.arready) next = CP_RSP_TO_FIFO;
            else next = LONG_ADDR_SETUP;

         state[LAST_ADDR_SETUP_BIT]:
            if (src_mem.arvalid & src_mem.arready) next = CP_RSP_TO_FIFO;
            else next = LAST_ADDR_SETUP;

         state[CP_RSP_TO_FIFO_BIT]:
            if (src_mem.rvalid & src_mem.rready & src_mem.r.last) next = WAIT_FOR_WR_RSP;
            else next = CP_RSP_TO_FIFO;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wr_fsm_done) begin 
              if(rd_length > MAX_TRANSFER_BYTES) next = LONG_ADDR_SETUP;
              else if (rd_length == '0) next = IDLE;
              else next = LAST_ADDR_SETUP;
            end else next = WAIT_FOR_WR_RSP;
      endcase
   end


  always_ff @(posedge clk) begin
     if (!reset_n) begin
        rd_src_clk_cnt                 <= '0;
        rd_src_valid_cnt               <= '0;
        rd_src_status.busy             <= 1'b0;
        rd_src_addr                    <= '0;
        rd_length                      <= '0;
        rd_prev_incr                   <= 1'b0;
        src_mem.arvalid                <= 1'b0;
        src_mem.wvalid                 <= 1'b0;
        src_mem.awvalid                <= 1'b0;
        src_mem.ar                     <= '0;
        wr_fifo_if.wr_en               <= 1'b0;
        rd_src_status.descriptor_count <= '0;
     end else begin
        unique case (1'b1)
           next[IDLE_BIT]: begin
              wr_fifo_if.wr_en      <= 1'b0;
              rd_src_status.busy    <= 0;
              src_mem.arvalid       <= 1'b0;
              rd_prev_incr          <= 1'b0;
           end 
           
           next[LONG_ADDR_SETUP_BIT]: begin
             rd_src_clk_cnt     <= '0;
             rd_src_valid_cnt   <= '0;
             rd_prev_incr       <= 1'b1;
             rd_src_status.busy <= 1;
             src_mem.arvalid    <= 1'b1;
             src_mem.ar.burst   <= get_burst(descriptor.descriptor_control.mode);;
             src_mem.ar.size    <= src_mem.ADDR_BYTE_IDX_WIDTH; // 111 indicates 128bytes per spec
             unique case (1'b1)
               prev[IDLE_BIT]: begin  
                 rd_src_addr     <= descriptor.src_addr + MAX_TRANSFER_BYTES;
                 src_mem.ar.addr <= descriptor.src_addr;
                 //src_mem.ar.addr <= rd_src_addr;
                 rd_length       <= descriptor.length - MAX_TRANSFER_BYTES;
                 src_mem.ar.len  <= MAX_TRANSFER_BYTES - 1;
               end
               prev[LONG_ADDR_SETUP_BIT]:begin end

               default: begin
                 src_mem.ar.addr <= rd_src_addr;
                 src_mem.ar.len  <= MAX_TRANSFER_BYTES - 1;
                 rd_src_addr     <= rd_src_addr + MAX_TRANSFER_BYTES;
                 rd_length       <= rd_length - MAX_TRANSFER_BYTES;
               end
             endcase

           end

           next[LAST_ADDR_SETUP_BIT]: begin
             rd_src_clk_cnt     <= '0;
             rd_src_valid_cnt   <= '0;
             rd_prev_incr       <= 1'b1;
             rd_src_status.busy <= 1;
             src_mem.arvalid    <= 1'b1;
             src_mem.ar.burst   <= get_burst(descriptor.descriptor_control.mode);;
             src_mem.ar.size    <= src_mem.ADDR_BYTE_IDX_WIDTH; // 111 indicates 128bytes per spec
             unique case (1'b1)
               prev[IDLE_BIT]: begin  
                 src_mem.ar.addr    <= descriptor.src_addr;
                 src_mem.ar.len     <= descriptor.length-1;
               end
               
               prev[LAST_ADDR_SETUP_BIT]: begin end

               default: begin
                 src_mem.ar.addr    <= rd_src_addr;
                 src_mem.ar.len     <= rd_length - 1;
               end
             endcase

           end
           
           next[CP_RSP_TO_FIFO_BIT]: begin
               rd_src_clk_cnt     <= rd_src_clk_cnt + 1;
               rd_src_valid_cnt   <= rd_src_valid_cnt + (src_mem.rvalid & src_mem.rready);
               src_mem.arvalid    <= 1'b0;
               wr_fifo_if.wr_data <= src_mem.r.data;
               wr_fifo_if.wr_en   <= !wr_fifo_if.almost_full & src_mem.rvalid;
               rd_prev_incr       <= 1'b0;
               if(prev[LAST_ADDR_SETUP]) rd_length <= '0;
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin
              wr_fifo_if.wr_data             <= src_mem.r.data;
              wr_fifo_if.wr_en               <= !wr_fifo_if.almost_full & src_mem.rvalid & src_mem.r.last;
              rd_src_status.descriptor_count <= rd_src_status.descriptor_count + descriptor_fifo_rdack;
              rd_prev_incr                   <= 1'b0;
           end

           next[ERROR_BIT]: begin end

           default: begin end
       endcase
     end
  end


   always_comb begin
      descriptor_fifo_rdack          = 1'b0;
      src_mem.rready                 = 1'b0;
      rd_src_status.stopped_on_error = 1'b0;
      rd_src_status.rd_rsp_err       = 1'b0;
      unique case (1'b1)
         state[IDLE_BIT]: begin end

         state[LONG_ADDR_SETUP_BIT]: begin end

         state[LAST_ADDR_SETUP_BIT]: begin end

         state[CP_RSP_TO_FIFO_BIT]: begin 
            src_mem.rready = !wr_fifo_if.almost_full;
         end

         state[WAIT_FOR_WR_RSP_BIT]: begin 
              if (wr_fsm_done && rd_length == '0) descriptor_fifo_rdack = 1'b1;
         end

         state[ERROR_BIT]: begin
            rd_src_status.stopped_on_error = 1'b1;
            rd_src_status.rd_rsp_err       = 1'b1;
         end

         default: begin end

      endcase
   end


endmodule
