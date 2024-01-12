// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"


module write_dest_fsm #(
   parameter DATA_W = 512
)(
   input logic clk,
   input logic reset_n,
   output logic wr_fsm_done,
   input logic descriptor_fifo_not_empty,
   input  dma_pkg::t_dma_descriptor descriptor,
   output dma_pkg::t_dma_csr_status wr_dest_status,
   input  dma_pkg::t_dma_csr_control csr_control,
   ofs_plat_axi_mem_if.to_sink dest_mem,
   dma_fifo_if.rd_out  rd_fifo_if
);

   localparam TLAST_COUNTER_W = dest_mem.ADDR_BYTE_IDX_WIDTH + dma_pkg::LENGTH_W;
   localparam AXI_SIZE_W = $bits(dest_mem.aw.size);

   `define NUM_WR_STATES 6

   enum {
      IDLE_BIT,
      ADDR_SETUP_BIT,
      FIFO_EMPTY_BIT,
      RD_FIFO_WR_DEST_BIT,
      WAIT_FOR_WR_RSP_BIT,
      ERROR_BIT
   } index;

   enum logic [`NUM_WR_STATES-1:0] {
      IDLE            = `NUM_WR_STATES'b1<<IDLE_BIT,
      ADDR_SETUP      = `NUM_WR_STATES'b1<<ADDR_SETUP_BIT,
      FIFO_EMPTY      = `NUM_WR_STATES'b1<<FIFO_EMPTY_BIT,
      RD_FIFO_WR_DEST = `NUM_WR_STATES'b1<<RD_FIFO_WR_DEST_BIT,
      WAIT_FOR_WR_RSP = `NUM_WR_STATES'b1<<WAIT_FOR_WR_RSP_BIT,
      ERROR           = `NUM_WR_STATES'b1<<ERROR_BIT,
      XXX             = 'x
   } state, next;

   function automatic logic [TLAST_COUNTER_W-1:0] get_size;
      input [AXI_SIZE_W-1:0] size;
      begin
         case (size)
            0: return 1; 
            1: return 2; 
            2: return 4; 
            3: return 8; 
            4: return 16; 
            5: return 32; 
            6: return 64; 
            7: return 128; 
         endcase
      end
   endfunction

   function automatic logic [AXI_SIZE_W-1:0] get_burst;
      input [1:0] burst_mode;
      begin
         case (burst_mode)
            dma_pkg::STAND_BY:    return XXX;
            dma_pkg::HOST_TO_DDR: return dma_pkg::BURST_INCR;
            dma_pkg::DDR_TO_HOST: return dma_pkg::BURST_WRAP;
            dma_pkg::DDR_TO_DDR:  return dma_pkg::BURST_INCR;
            default:              return XXX;
         endcase
      end
    endfunction

   logic wr_resp_last;
   logic [AXI_SIZE_W-1:0] axi_size;
   logic [TLAST_COUNTER_W-1:0] tlast_counter;
   logic [TLAST_COUNTER_W-1:0] tlast_counter_upper;
   logic [TLAST_COUNTER_W-1:0] tlast_counter_next;
   logic [dma_pkg::PERF_CNTR_W-1:0] wr_dest_clk_cnt;
   logic [dma_pkg::PERF_CNTR_W-1:0] wr_dest_valid_cnt;

   assign wr_dest_status.wr_dest_perf_cntr.wr_dest_clk_cnt = wr_dest_clk_cnt;
   assign wr_dest_status.wr_dest_perf_cntr.wr_dest_valid_cnt = wr_dest_valid_cnt;
   assign axi_size   = dest_mem.ADDR_BYTE_IDX_WIDTH;
   assign wr_resp    = dest_mem.bvalid & dest_mem.bready;
   assign wr_resp_ok = wr_resp & (dest_mem.b.resp==dma_pkg::OKAY);
   assign tlast_counter_next = tlast_counter + get_size(axi_size);
   assign dest_mem.rready = 1'b1;
   assign tlast_counter_upper = {'0, tlast_counter[TLAST_COUNTER_W-1:dest_mem.ADDR_BYTE_IDX_WIDTH]};
   assign wr_dest_status.wr_state = state; 
   
   always_ff @(posedge clk) begin
      if (!reset_n) state <= IDLE;
      else          state <= next;
   end

   always_comb begin
      next = XXX;
      unique case (1'b1)
         state[IDLE_BIT]: 
            if (descriptor.descriptor_control.go & descriptor_fifo_not_empty) next = ADDR_SETUP; 
            else next = IDLE;

         state[ADDR_SETUP_BIT]:
            if (dest_mem.awvalid & dest_mem.awready) next = FIFO_EMPTY;
            else next = ADDR_SETUP;

         state[FIFO_EMPTY_BIT]:
            if (rd_fifo_if.not_empty) next = RD_FIFO_WR_DEST;
            else next = FIFO_EMPTY;

         state[RD_FIFO_WR_DEST_BIT]:
            if (dest_mem.wvalid & dest_mem.wready & dest_mem.w.last) next = WAIT_FOR_WR_RSP;
            else next = RD_FIFO_WR_DEST;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wr_resp_ok) next = IDLE;
            else if (ENABLE_ERROR & wr_resp & ((dest_mem.b.resp==dma_pkg::SLVERR) | ((dest_mem.b.resp==dma_pkg::SLVERR)))) next = ERROR; 
            else next = WAIT_FOR_WR_RSP;
 
         state[ERROR_BIT]:
            if (csr_control.reset_dispatcher) next = IDLE;
            else next = ERROR;
      endcase
   end

  always_ff @(posedge clk) begin
     if (!reset_n) begin
        tlast_counter       <= '0;
        wr_dest_status.busy <= 1'b0;
        wr_dest_clk_cnt     <= '0;
        wr_dest_valid_cnt   <= '0;
        dest_mem.arvalid    <= 1'b0;
        dest_mem.awvalid    <= 1'b0;
        dest_mem.aw         <= '0;
     end else begin
        unique case (1'b1)
           next[IDLE_BIT]: begin
              tlast_counter       <= '0;
              wr_dest_status.busy <= 1'b0;
              dest_mem.awvalid    <= 1'b0;
           end 
           
           next[ADDR_SETUP_BIT]: begin
               wr_dest_clk_cnt     <= '0;
               wr_dest_valid_cnt   <= '0;
               wr_dest_status.busy <= 1'b1;
               dest_mem.awvalid    <= 1'b1;
               dest_mem.aw.addr    <= descriptor.dest_addr;
               dest_mem.aw.len     <= descriptor.length-1;
               dest_mem.aw.burst   <= get_burst(descriptor.descriptor_control.mode);
               dest_mem.aw.size    <= axi_size;
           end

           next[FIFO_EMPTY_BIT]: begin end
           
           next[RD_FIFO_WR_DEST_BIT]: begin
                tlast_counter     <= rd_fifo_if.rd_en ? tlast_counter_next : tlast_counter;
                wr_dest_clk_cnt   <= wr_dest_clk_cnt + 1;
                wr_dest_valid_cnt <= wr_dest_valid_cnt + (dest_mem.wvalid & dest_mem.wready);
                dest_mem.awvalid  <= 1'b0;
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin
              tlast_counter    <= tlast_counter;
           end

           next[ERROR_BIT]: begin end

           default: begin end
          
       endcase
     end
  end

   always_comb begin
      rd_fifo_if.rd_en                = 1'b0;
      dest_mem.bready                 = 1'b0;
      wr_fsm_done                     = 1'b0;
      wr_dest_status.stopped_on_error = 1'b0;
      wr_dest_status.wr_rsp_err       = 1'b0;
      dest_mem.w.strb                 = '1;
      dest_mem.wvalid                 = 1'b0;
      dest_mem.w.last                 = 1'b0;
      dest_mem.w.data                 = '0;
      dest_mem.w.user                 = '0;
      unique case (1'b1)
         state[IDLE_BIT]: begin end
         state[ADDR_SETUP_BIT]:begin end
         state[FIFO_EMPTY_BIT]:begin end
         state[RD_FIFO_WR_DEST_BIT]: begin 
            rd_fifo_if.rd_en = rd_fifo_if.not_empty & dest_mem.wready;
            dest_mem.wvalid  = rd_fifo_if.not_empty & dest_mem.wready;
            dest_mem.w.data  = rd_fifo_if.rd_data;
          //dest_mem.w.last  = tlast_counter >= ((descriptor.length-1)*get_size(axi_size)); 
            dest_mem.w.last  = tlast_counter_upper == (descriptor.length-1); 
         end
         state[WAIT_FOR_WR_RSP_BIT]: begin 
            dest_mem.bready = 1'b1;
            wr_fsm_done     = wr_resp_ok;
         end
         state[ERROR_BIT]:begin 
            wr_dest_status.stopped_on_error = 1'b1;
            wr_dest_status.wr_rsp_err       = 1'b1;
         end
         default: begin end
      endcase
   end


endmodule
