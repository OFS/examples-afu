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

   localparam WLAST_COUNTER_W =  dma_pkg::LENGTH_W;
   localparam AXI_SIZE_W = $bits(dest_mem.aw.size);
   localparam AXI_LEN_W = dma_pkg::AXI_LEN_W;
   localparam ADDR_INCR = dma_pkg::AXI_MM_DATA_W_BYTES * (2**AXI_LEN_W);
   localparam [AXI_LEN_W-1:0] MAX_AXI_LEN = '1;
   localparam ADDR_BYTE_IDX_W = dest_mem.ADDR_BYTE_IDX_WIDTH;

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

   logic wlast_valid;
   logic need_more_wlast;
   logic [AXI_LEN_W:0] num_wlasts;
   logic [AXI_LEN_W:0] wlast_cnt;
   logic [dma_pkg::LENGTH_W-1:0] desc_length_minus_one;
   logic [AXI_SIZE_W-1:0] axi_size;
   logic [AXI_LEN_W:0] wlast_counter;
   logic [dma_pkg::PERF_CNTR_W-1:0] wr_dest_clk_cnt;
   logic [dma_pkg::PERF_CNTR_W-1:0] wr_dest_valid_cnt;

   assign wr_dest_status.wr_dest_perf_cntr.wr_dest_clk_cnt = wr_dest_clk_cnt;
   assign wr_dest_status.wr_dest_perf_cntr.wr_dest_valid_cnt = wr_dest_valid_cnt;
   assign axi_size   = dest_mem.ADDR_BYTE_IDX_WIDTH;
   assign wr_resp    = dest_mem.bvalid & dest_mem.bready;
   assign wr_resp_ok = wr_resp & (dest_mem.b.resp==dma_pkg::OKAY);
   assign dest_mem.rready = 1'b1;
   assign wr_dest_status.wr_state = state; 
   assign wlast_valid = dest_mem.wvalid & dest_mem.wready & dest_mem.w.last;
   assign need_more_wlast = (num_wlasts > (wlast_cnt + wlast_valid));
   assign desc_length_minus_one = descriptor.length-1;
   
   always_ff @(posedge clk) begin
      if (!reset_n) state <= IDLE;
      else          state <= next;
   end
   
   always_comb begin
      next = XXX;
      unique case (1'b1)
         state[IDLE_BIT]: begin 
           if (descriptor.descriptor_control.go & descriptor_fifo_not_empty & dest_mem.awready)next = ADDR_SETUP;
           else next = IDLE;
         end 

         state[ADDR_SETUP_BIT]:
           if (dest_mem.awvalid & dest_mem.awready) next = FIFO_EMPTY;
           else next = ADDR_SETUP;
         
         state[FIFO_EMPTY_BIT]:
            if (rd_fifo_if.not_empty) next = RD_FIFO_WR_DEST;
            else next = FIFO_EMPTY;

         state[RD_FIFO_WR_DEST_BIT]:
            if (wlast_valid & need_more_wlast) next = ADDR_SETUP;
            else if (wlast_valid & !need_more_wlast) next = WAIT_FOR_WR_RSP;
            else next = RD_FIFO_WR_DEST;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wr_resp_ok && (wlast_cnt < num_wlasts)) next = ADDR_SETUP;
            else if (wr_resp_ok && (wlast_cnt >= num_wlasts)) next = IDLE;
            else if (dma_pkg::ENABLE_ERROR & wr_resp & ((dest_mem.b.resp==dma_pkg::SLVERR) | ((dest_mem.b.resp==dma_pkg::SLVERR)))) next = ERROR; 
            else next = WAIT_FOR_WR_RSP;
         
         state[ERROR_BIT]:
            if (csr_control.reset_dispatcher) next = IDLE;
            else next = ERROR;
      
       endcase
   end

   logic [2:0] awaddr_prop_delay;

   always_ff @(posedge clk) begin
      if (!reset_n) begin
         wlast_counter       <= '0; // used for asserting w.last
         num_wlasts          <= '0; // used for transactions that require multiple bursts (ie multiple w.lasts)
         wlast_cnt           <= '0;
         awaddr_prop_delay   <= '0;
         dest_mem.arvalid    <= 1'b0;
         dest_mem.aw         <= '0;
      end else begin
         awaddr_prop_delay <= '0;
         wlast_cnt         <= wlast_cnt + wlast_valid;
         wlast_counter     <= wlast_counter + (dest_mem.wvalid & dest_mem.wready & rd_fifo_if.not_empty);
         unique case (1'b1)
            next[IDLE_BIT]: begin
               num_wlasts    <= state[WAIT_FOR_WR_RSP_BIT] <= '0;
               wlast_counter <= '0;
               wlast_cnt     <= '0;
            end 
            
            next[ADDR_SETUP_BIT]: begin
               awaddr_prop_delay <= awaddr_prop_delay + 1;
               num_wlasts        <= state[IDLE_BIT] ? (desc_length_minus_one[(dma_pkg::LENGTH_W)-1:AXI_LEN_W]+1) : num_wlasts;
               wlast_counter     <= state[IDLE_BIT] ? 0 : wlast_counter + (dest_mem.wvalid & dest_mem.wready & rd_fifo_if.not_empty);
               dest_mem.aw.burst <= get_burst(descriptor.descriptor_control.mode);
               dest_mem.aw.size  <= axi_size;
               dest_mem.aw.addr  <= state[IDLE_BIT]            ? descriptor.dest_addr : 
                                    state[RD_FIFO_WR_DEST_BIT] ? dest_mem.aw.addr + ADDR_INCR :
                                                                 dest_mem.aw.addr;
               dest_mem.aw.len   <= (state[IDLE_BIT] & ((desc_length_minus_one)>MAX_AXI_LEN)) ? MAX_AXI_LEN : 
                                    (state[RD_FIFO_WR_DEST_BIT] & need_more_wlast)          ? MAX_AXI_LEN :
                                                                                             descriptor.length[AXI_LEN_W-1:0]-1; 
            end
            
            next[FIFO_EMPTY_BIT]: begin end
            
            next[RD_FIFO_WR_DEST_BIT]: begin end
            
            next[WAIT_FOR_WR_RSP_BIT]: begin end
            
            next[ERROR_BIT]: begin end
            
         endcase
      end
   end

   // Data & Descriptor FIFO control
   always_comb begin
      rd_fifo_if.rd_en                = 1'b0;
      dest_mem.bready                 = 1'b1;
      wr_fsm_done                     = 1'b0;
      wr_dest_status.stopped_on_error = 1'b0;
      wr_dest_status.wr_rsp_err       = 1'b0;
      dest_mem.w.strb                 = '1;
      dest_mem.wvalid                 = 1'b0;
      dest_mem.w.last                 = 1'b0;
      dest_mem.w.data                 = '0;
      dest_mem.w.user                 = '0;
      dest_mem.awvalid                = 1'b0;
      unique case (1'b1)
         state[IDLE_BIT]: begin end
         state[ADDR_SETUP_BIT]:begin
            dest_mem.awvalid = dest_mem.awready & awaddr_prop_delay[2];
            dest_mem.w.data  = rd_fifo_if.rd_data;
         end
         state[FIFO_EMPTY_BIT]:begin end
         state[RD_FIFO_WR_DEST_BIT]: begin 
            rd_fifo_if.rd_en = rd_fifo_if.not_empty & dest_mem.wready;
            dest_mem.wvalid  = rd_fifo_if.not_empty & dest_mem.wready;
            dest_mem.w.data  = rd_fifo_if.rd_data;
            dest_mem.w.last  = (desc_length_minus_one==wlast_counter) | (wlast_counter[AXI_LEN_W-1:0]==MAX_AXI_LEN); 
         end
         state[WAIT_FOR_WR_RSP_BIT]: begin 
            wr_fsm_done     = wr_resp_ok;
         end
         state[ERROR_BIT]:begin 
            wr_dest_status.stopped_on_error = 1'b1;
            wr_dest_status.wr_rsp_err       = 1'b1;
         end
      endcase
   end

  // CSR Status Signals 
  // Bandwidth calculations
  always_ff @(posedge clk) begin
     if (!reset_n) begin
        wr_dest_status.busy <= 1'b0;
        wr_dest_clk_cnt     <= '0;
        wr_dest_valid_cnt   <= '0;
     end else begin
        unique case (1'b1)
           next[IDLE_BIT]: begin
              wr_dest_status.busy <= 1'b0;
           end 
           
           next[ADDR_SETUP_BIT]: begin
              // Only reset the bandwidth calculations when transitioning from IDLE. This 
              // way we can can read the value after a transfer is complete
              wr_dest_clk_cnt     <= state[IDLE_BIT] ? '0 : wr_dest_clk_cnt + 1;;
              wr_dest_valid_cnt   <= state[IDLE_BIT] ? '0 : wr_dest_valid_cnt + (dest_mem.wvalid & dest_mem.wready);;
           end

           next[FIFO_EMPTY_BIT]: begin end

           next[RD_FIFO_WR_DEST_BIT]: begin
                wr_dest_clk_cnt   <= wr_dest_clk_cnt + 1;
                wr_dest_valid_cnt <= wr_dest_valid_cnt + (dest_mem.wvalid & dest_mem.wready);
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin end

           next[ERROR_BIT]: begin end

       endcase
     end
  end

endmodule
