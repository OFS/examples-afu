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
   output dma_pkg::t_dma_csr_status rd_src_status, 
   input logic descriptor_fifo_not_empty,
   output logic descriptor_fifo_rdack,
   ofs_plat_axi_mem_if.to_sink src_mem,
   dma_fifo_if.wr_out  wr_fifo_if
);

   localparam AXI_LEN_W = dma_pkg::AXI_LEN_W;
   localparam ADDR_INCR = dma_pkg::AXI_MM_DATA_W_BYTES * (2**AXI_LEN_W);
   localparam [AXI_LEN_W:0] MAX_AXI_LEN = '1;
   localparam AXI_SIZE_W = $bits(src_mem.ar.size);

   `define NUM_RD_STATES 5 

   enum {
      IDLE_BIT,
      ADDR_SETUP_BIT,
      CP_RSP_TO_FIFO_BIT,
      WAIT_FOR_WR_RSP_BIT,
      ERROR_BIT
   } index;

   enum logic [`NUM_RD_STATES-1:0] {
      IDLE            = `NUM_RD_STATES'b1<<IDLE_BIT,
      ADDR_SETUP      = `NUM_RD_STATES'b1<<ADDR_SETUP_BIT,
      CP_RSP_TO_FIFO  = `NUM_RD_STATES'b1<<CP_RSP_TO_FIFO_BIT,
      WAIT_FOR_WR_RSP = `NUM_RD_STATES'b1<<WAIT_FOR_WR_RSP_BIT,
      ERROR           = `NUM_RD_STATES'b1<<ERROR_BIT,
      XXX = 'x
   } state, next;

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

   logic rlast_valid;
   logic [dma_pkg::LENGTH_W-1:0] desc_length_minus_one;
   logic [dma_pkg::PERF_CNTR_W-1:0] rd_src_clk_cnt;
   logic [dma_pkg::PERF_CNTR_W-1:0] rd_src_valid_cnt;
   logic [dma_pkg::LENGTH_W-AXI_LEN_W-1:0] num_rlasts;
   logic [dma_pkg::LENGTH_W-AXI_LEN_W-1:0] rlast_cnt;

   assign rd_src_status.rd_src_perf_cntr.rd_src_clk_cnt   = rd_src_clk_cnt;
   assign rd_src_status.rd_src_perf_cntr.rd_src_valid_cnt =  rd_src_valid_cnt;
   assign src_mem.bready = 1'b0;
   assign rd_src_status.rd_state = state;
   assign rlast_valid = src_mem.rvalid & src_mem.rready & src_mem.r.last;
   assign need_more_rlast = (num_rlasts > (rlast_cnt+rlast_valid));
   assign desc_length_minus_one = descriptor.length-1;

   
   always_ff @(posedge clk) begin
      if (!reset_n) state <= IDLE;
      else          state <= next;
   end

   always_comb begin
      next = XXX;
      unique case (1'b1)
        state[IDLE_BIT]: begin 
          if (descriptor.descriptor_control.go & descriptor_fifo_not_empty) next = ADDR_SETUP;
          else next = IDLE;
        end 

         state[ADDR_SETUP_BIT]:
            if (src_mem.arvalid & src_mem.arready) next = CP_RSP_TO_FIFO;
            else next = ADDR_SETUP;

         state[CP_RSP_TO_FIFO_BIT]:
            if (rlast_valid & (num_rlasts == (rlast_cnt+1))) next = WAIT_FOR_WR_RSP;
            else if (rlast_valid & need_more_rlast) next = ADDR_SETUP;
            else next = CP_RSP_TO_FIFO;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wr_fsm_done) next = IDLE;
            else next = WAIT_FOR_WR_RSP;
      endcase
   end

  always_ff @(posedge clk) begin
     if (!reset_n) begin
        num_rlasts                     <= '0;
        rlast_cnt                      <= '0;
        src_mem.arvalid                <= 1'b0;
        src_mem.wvalid                 <= 1'b0;
        src_mem.awvalid                <= 1'b0;
        src_mem.ar                     <= '0;
        wr_fifo_if.wr_en               <= 1'b0;
     end else begin
        unique case (1'b1)
           next[IDLE_BIT]: begin
              wr_fifo_if.wr_en   <= 1'b0;
              src_mem.arvalid    <= 1'b0;
              rlast_cnt          <= '0;
           end 
           
           next[ADDR_SETUP_BIT]: begin
              num_rlasts         <= state[IDLE_BIT] ? (desc_length_minus_one[(dma_pkg::LENGTH_W)-1:AXI_LEN_W]+1) : num_rlasts;
              rlast_cnt          <= rlast_cnt + rlast_valid;
              src_mem.arvalid    <= 1'b1;
              src_mem.ar.addr    <= state[IDLE_BIT]           ? descriptor.src_addr : 
                                    state[CP_RSP_TO_FIFO_BIT] ? src_mem.ar.addr + ADDR_INCR : 
                                                                src_mem.ar.addr;
              src_mem.ar.len     <= (state[CP_RSP_TO_FIFO_BIT] & need_more_rlast)       ? MAX_AXI_LEN : 
                                    (state[IDLE_BIT] & (descriptor.length>MAX_AXI_LEN)) ? MAX_AXI_LEN : 
                                                                                          descriptor.length[AXI_LEN_W-1:0]-1;
              src_mem.ar.burst   <= get_burst(descriptor.descriptor_control.mode);
              src_mem.ar.size    <= src_mem.ADDR_BYTE_IDX_WIDTH; // 111 indicates 128bytes per spec
              wr_fifo_if.wr_data <= state[CP_RSP_TO_FIFO_BIT] ? src_mem.r.data : '0;
              wr_fifo_if.wr_en   <= state[CP_RSP_TO_FIFO_BIT] & !wr_fifo_if.almost_full & src_mem.rvalid;
           end

           next[CP_RSP_TO_FIFO_BIT]: begin
              src_mem.arvalid    <= 1'b0;
              wr_fifo_if.wr_en   <= !wr_fifo_if.almost_full & src_mem.rvalid;
              wr_fifo_if.wr_data <= src_mem.r.data;
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin
              rlast_cnt                      <= rlast_cnt + rlast_valid;
              wr_fifo_if.wr_data             <= src_mem.r.data;
              wr_fifo_if.wr_en               <= !wr_fifo_if.almost_full & src_mem.rvalid & src_mem.r.last;
           end

           next[ERROR_BIT]: begin end
        endcase
     end
  end


   // Data & Descriptor FIFO control
   always_comb begin
      descriptor_fifo_rdack          = 1'b0;
      src_mem.rready                 = 1'b0;
      rd_src_status.stopped_on_error = 1'b0;
      rd_src_status.rd_rsp_err       = 1'b0;
      unique case (1'b1)
         state[IDLE_BIT]: begin end

         state[ADDR_SETUP_BIT]: begin end

         state[CP_RSP_TO_FIFO_BIT]: begin 
            src_mem.rready = !wr_fifo_if.almost_full;
         end

         state[WAIT_FOR_WR_RSP_BIT]: begin 
            descriptor_fifo_rdack = wr_fsm_done;
         end

         state[ERROR_BIT]: begin
            rd_src_status.stopped_on_error = 1'b1;
            rd_src_status.rd_rsp_err       = 1'b1;
         end

      endcase
   end

  // CSR Status Signals 
  // Bandwidth calculations
  always_ff @(posedge clk) begin
     if (!reset_n) begin
        rd_src_status.busy             <= 1'b0;
        rd_src_clk_cnt                 <= '0;
        rd_src_valid_cnt               <= '0;
        rd_src_status.descriptor_count <= '0;
     end else begin
        rd_src_status.busy <= 1'b1;
        unique case (1'b1)
            next[IDLE_BIT]: begin
               rd_src_status.busy <= 1'b0;
            end 
           
           next[ADDR_SETUP_BIT]: begin
              // Only reset the bandwidth calculations when transitioning from IDLE. This 
              // way we can can read the value after a transfer is complete
              rd_src_clk_cnt   <= state[IDLE_BIT] ? '0 : rd_src_clk_cnt + 1;
              rd_src_valid_cnt <= state[IDLE_BIT] ? '0 : rd_src_valid_cnt + (src_mem.rvalid & src_mem.rready);
           end

           next[CP_RSP_TO_FIFO_BIT]: begin  
              rd_src_clk_cnt     <= rd_src_clk_cnt + 1;
              rd_src_valid_cnt   <= rd_src_valid_cnt + (src_mem.rvalid & src_mem.rready);
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin 
              rd_src_clk_cnt     <= rd_src_clk_cnt + 1;
              rd_src_valid_cnt   <= rd_src_valid_cnt + (src_mem.rvalid & src_mem.rready);
              rd_src_status.descriptor_count <= rd_src_status.descriptor_count + descriptor_fifo_rdack;
           end

           next[ERROR_BIT]: begin end
        endcase
      
     end 
  end

endmodule
