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
   localparam ADDR_INCR_W = $clog2(ADDR_INCR);
   localparam [AXI_LEN_W-1:0] MAX_AXI_LEN = '1;
   localparam ADDR_BYTE_IDX_W = dest_mem.ADDR_BYTE_IDX_WIDTH;

   `define NUM_WR_STATES 8

   enum {
      IDLE_BIT,
      ADDR_PROP_DELAY_BIT,
      ADDR_SETUP_BIT,
      FIFO_EMPTY_BIT,
      NOT_READY_BIT,
      RD_FIFO_WR_DEST_BIT,
      WAIT_FOR_WR_RSP_BIT,
      ERROR_BIT
   } index;

   enum logic [`NUM_WR_STATES-1:0] {
      IDLE            = `NUM_WR_STATES'b1<<IDLE_BIT,
      ADDR_PROP_DELAY = `NUM_WR_STATES'b1<<ADDR_PROP_DELAY_BIT,
      ADDR_SETUP      = `NUM_WR_STATES'b1<<ADDR_SETUP_BIT,
      FIFO_EMPTY      = `NUM_WR_STATES'b1<<FIFO_EMPTY_BIT,
      NOT_READY       = `NUM_WR_STATES'b1<<NOT_READY_BIT,
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
   logic [2:0] awaddr_prop_delay;
   logic [dma_pkg::DEST_ADDR_W-ADDR_INCR_W-1:0] saved_awaddr;
   logic [AXI_LEN_W:0] num_wlasts;
   logic [AXI_LEN_W:0] wlast_cnt;
   logic [dma_pkg::LENGTH_W-1:0] desc_length_minus_one;
   logic [AXI_SIZE_W-1:0] axi_size;
   logic [dma_pkg::LENGTH_W-1:0] wlast_counter;
   logic [dma_pkg::LENGTH_W-1:0] wlast_counter_next;
   logic [dma_pkg::LENGTH_W-1:0] wr_dest_clk_cnt;
   logic [dma_pkg::LENGTH_W-1:0] wr_dest_valid_cnt;

   assign wr_dest_status.wr_dest_perf_cntr.wr_dest_clk_cnt = {12'b0, wr_dest_clk_cnt};
   assign wr_dest_status.wr_dest_perf_cntr.wr_dest_valid_cnt = {12'b0, wr_dest_valid_cnt};
   assign axi_size   = dest_mem.ADDR_BYTE_IDX_WIDTH;
   assign wr_resp    = dest_mem.bvalid & dest_mem.bready;
   assign wr_resp_ok = wr_resp & (dest_mem.b.resp==dma_pkg::OKAY);
   assign dest_mem.rready = 1'b1;
   assign wr_dest_status.wr_state = state; 
   assign wlast_valid = dest_mem.wvalid & dest_mem.wready & dest_mem.w.last;
   assign need_more_wlast = (num_wlasts > (wlast_cnt + wlast_valid));
   assign desc_length_minus_one = descriptor.length-1;
   assign wlast_counter_next = wlast_counter + (dest_mem.wvalid & dest_mem.wready);
   
   always_ff @(posedge clk) begin
      if (!reset_n) state <= IDLE;
      else          state <= next;
   end
   
   always_comb begin
      next = XXX;
      unique case (1'b1)
         state[IDLE_BIT]: begin 
           if (descriptor.descriptor_control.go & descriptor_fifo_not_empty & dest_mem.awready & rd_fifo_if.not_empty)next = ADDR_SETUP;
           else next = IDLE;
         end 

        state[ADDR_PROP_DELAY_BIT]:
            if (awaddr_prop_delay[2]) next = ADDR_SETUP;
            else if (wlast_valid & !need_more_wlast) next = WAIT_FOR_WR_RSP;
            else next = ADDR_PROP_DELAY;

         state[ADDR_SETUP_BIT]:
           if (dest_mem.awvalid & dest_mem.awready) next = FIFO_EMPTY;
           else next = ADDR_SETUP;
         
         state[FIFO_EMPTY_BIT]:
            if (wlast_valid & need_more_wlast) next = ADDR_PROP_DELAY;
            else if (wlast_valid & !need_more_wlast) next = WAIT_FOR_WR_RSP;
            else if (!rd_fifo_if.not_empty) next = FIFO_EMPTY;
            else next = NOT_READY;

         state[NOT_READY_BIT]:
            if (wlast_valid & need_more_wlast) next = ADDR_PROP_DELAY;
            else if (wlast_valid & !need_more_wlast) next = WAIT_FOR_WR_RSP;
            else if (!dest_mem.wready) next = NOT_READY;
            else next = RD_FIFO_WR_DEST;


         state[RD_FIFO_WR_DEST_BIT]:
            if (wlast_valid & need_more_wlast) next = ADDR_PROP_DELAY;
            else if (wlast_valid & !need_more_wlast) next = WAIT_FOR_WR_RSP;
            else if ((!rd_fifo_if.not_empty) | (!dest_mem.wready)) next = FIFO_EMPTY;
            else next = RD_FIFO_WR_DEST;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wlast_cnt >= num_wlasts) next = IDLE;
            else if (dma_pkg::ENABLE_ERROR & wr_resp & ((dest_mem.b.resp==dma_pkg::SLVERR) | ((dest_mem.b.resp==dma_pkg::SLVERR)))) next = ERROR; 
            else next = WAIT_FOR_WR_RSP;
         
         state[ERROR_BIT]:
            if (csr_control.reset_dispatcher) next = IDLE;
            else next = ERROR;
      
       endcase
   end


   always_ff @(posedge clk) begin
      if (!reset_n) begin
         num_wlasts        <= '0; // used for transactions that require multiple bursts (ie multiple w.lasts)
         wlast_cnt         <= '0;
         awaddr_prop_delay <= '0;
         dest_mem.aw       <= '0;
         dest_mem.aw.addr  <= '0;
         saved_awaddr      <= '0;
      end else begin
         awaddr_prop_delay <= '0;
         wlast_cnt         <= wlast_cnt + wlast_valid;
         unique case (1'b1)
            next[IDLE_BIT]: begin
               num_wlasts       <= state[WAIT_FOR_WR_RSP_BIT] <= '0;
               wlast_cnt        <= '0;
               dest_mem.aw.addr <= '0;
               saved_awaddr     <= '0;
            end 

            next[ADDR_PROP_DELAY_BIT]: begin
               awaddr_prop_delay <= awaddr_prop_delay + 1;
               dest_mem.aw.addr[(dma_pkg::DEST_ADDR_W)-1:ADDR_INCR_W]  <= saved_awaddr + 1;
            end
            
            next[ADDR_SETUP_BIT]: begin
               num_wlasts        <= state[IDLE_BIT] ? (desc_length_minus_one[(dma_pkg::LENGTH_W)-1:AXI_LEN_W]+1) : num_wlasts;
               dest_mem.aw.burst <= get_burst(descriptor.descriptor_control.mode);
               dest_mem.aw.size  <= axi_size;
               dest_mem.aw.addr  <= state[IDLE_BIT] ? descriptor.dest_addr :dest_mem.aw.addr;
               dest_mem.aw.len   <= (state[IDLE_BIT] & ((desc_length_minus_one)>MAX_AXI_LEN)) ? MAX_AXI_LEN : 
                                    (state[RD_FIFO_WR_DEST_BIT] & need_more_wlast)            ? MAX_AXI_LEN :
                                    (state[FIFO_EMPTY_BIT] & need_more_wlast)                 ? MAX_AXI_LEN :
                                                                                                descriptor.length[AXI_LEN_W-1:0]-1; 
            end

            next[NOT_READY_BIT]: begin end
            
            next[FIFO_EMPTY_BIT]: begin 
               saved_awaddr  <= dest_mem.aw.addr[(dma_pkg::DEST_ADDR_W)-1:ADDR_INCR_W];
            end
            
            next[RD_FIFO_WR_DEST_BIT]: begin 
               saved_awaddr  <= dest_mem.aw.addr[(dma_pkg::DEST_ADDR_W)-1:ADDR_INCR_W];
            end
            
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
      dest_mem.awvalid                = 1'b0;
      dest_mem.arvalid                = 1'b0;
      unique case (1'b1)
         state[IDLE_BIT]: begin end
         state[ADDR_PROP_DELAY_BIT]: begin end
         state[ADDR_SETUP_BIT]:begin
            dest_mem.awvalid = dest_mem.awready;
         end
         state[FIFO_EMPTY_BIT]:begin end
         state[NOT_READY_BIT]:begin end
         state[RD_FIFO_WR_DEST_BIT]: begin 
            rd_fifo_if.rd_en = rd_fifo_if.not_empty & dest_mem.wready;
         end
         state[WAIT_FOR_WR_RSP_BIT]: begin 
            //wr_fsm_done     = wr_resp_ok;
            wr_fsm_done     = 1'b1;
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
        dest_mem.w.strb     <= '1;
        dest_mem.wvalid     <= 1'b0;
        dest_mem.w.last     <= 1'b0;
        dest_mem.w.data     <= '0;
        dest_mem.w.user     <= '0;
        wlast_counter       <= '0; // used for asserting w.last
   
     end else begin
        wr_dest_clk_cnt     <= wr_dest_clk_cnt + 1;
        wr_dest_valid_cnt   <= wr_dest_valid_cnt + (dest_mem.wvalid & dest_mem.wready);
        wlast_counter       <= wlast_counter_next;
        dest_mem.wvalid     <= 1'b0;
        dest_mem.w.data     <= rd_fifo_if.rd_data;
        dest_mem.w.last     <= dest_mem.wready & (desc_length_minus_one==wlast_counter_next) | (wlast_counter_next[AXI_LEN_W-1:0]==MAX_AXI_LEN); 
        unique case (1'b1)
           next[IDLE_BIT]: begin
              wr_dest_status.busy <= 1'b0;
              wr_dest_clk_cnt     <= wr_dest_clk_cnt;
              wr_dest_valid_cnt   <= wr_dest_valid_cnt;
              wlast_counter       <= '0;
           end 
           next[ADDR_PROP_DELAY_BIT]: begin 
              dest_mem.w.data   <= rd_fifo_if.rd_data;
              dest_mem.wvalid   <= rd_fifo_if.rd_en | (dest_mem.wvalid & (!dest_mem.wready)); 
           end
           
           next[ADDR_SETUP_BIT]: begin
              // Only reset the bandwidth calculations when transitioning from IDLE. This 
              // way we can can read the value after a transfer is complete
              //wlast_counter       <= state[ADDR_PROP_DELAY_BIT] ? '0 : wlast_counter_next;
              wr_dest_clk_cnt   <= state[IDLE_BIT] ? '0 : wr_dest_clk_cnt + 1;;
              wr_dest_valid_cnt <= state[IDLE_BIT] ? '0 : wr_dest_valid_cnt + (dest_mem.wvalid & dest_mem.wready);;
              dest_mem.w.data   <= (dest_mem.wready & dest_mem.wvalid) ? rd_fifo_if.rd_data : dest_mem.w.data;
              dest_mem.wvalid   <= (dest_mem.wready & dest_mem.wvalid) ? 1'b0 : dest_mem.wvalid; 
           end

           next[FIFO_EMPTY_BIT]: begin 
              dest_mem.w.data <= (state[RD_FIFO_WR_DEST_BIT] & rd_fifo_if.not_empty)   ? dest_mem.w.data    : 
                                 (dest_mem.wvalid & dest_mem.wready)                   ? rd_fifo_if.rd_data : 
                                                                                         dest_mem.w.data;

              dest_mem.wvalid <= (state[RD_FIFO_WR_DEST_BIT] & rd_fifo_if.not_empty) ? 1'b1 : 
                                 (dest_mem.wvalid & dest_mem.wready)                 ? 1'b0 : 
                                                                                       dest_mem.wvalid; 
           end
          
           next[NOT_READY_BIT]: begin
              dest_mem.w.data <= (dest_mem.wready & dest_mem.wvalid) ? rd_fifo_if.rd_data : dest_mem.w.data;
              dest_mem.wvalid <= (dest_mem.wready & dest_mem.wvalid) ? 1'b0 : dest_mem.wvalid; 
           end

           next[RD_FIFO_WR_DEST_BIT]: begin
             dest_mem.w.data <= rd_fifo_if.rd_data;
             dest_mem.wvalid <= rd_fifo_if.rd_en;
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin end

           next[ERROR_BIT]: begin end

       endcase
     end
  end
  
  // synthesis translate_off
  integer wr_dest_fifo_file;
  integer wr_dest_axi_file;

  initial begin 
     wr_dest_axi_file = $fopen("wr_dest_axi.txt","a");
     wr_dest_fifo_file = $fopen("wr_dest_fifo.txt","a");
     forever begin
        begin
           fork 
              begin
                 @(posedge clk);
                 if (dest_mem.wvalid & dest_mem.wready) 
                    $fwrite(wr_dest_axi_file, "0x%0h: 0x%0h\n",descriptor.descriptor_control.mode, dest_mem.w.data);
              end
              begin
                 @(posedge clk);
                 if (rd_fifo_if.rd_en) 
                    $fwrite(wr_dest_fifo_file, "0x%0h: 0x%0h\n",descriptor.descriptor_control.mode, rd_fifo_if.rd_data);
              end
           join
        end
     end 
  end
  // synthesis translate_on
 
endmodule
