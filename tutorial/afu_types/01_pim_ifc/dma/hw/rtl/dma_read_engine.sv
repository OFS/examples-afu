// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"


module dma_read_engine #(
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
   localparam [AXI_LEN_W-1:0] MAX_AXI_LEN = '1;
   localparam AXI_SIZE_W = $bits(src_mem.ar.size);

   `define NUM_RD_STATES 6 

   enum {
      IDLE_BIT,
      ADDR_PROP_DELAY_BIT,
      ADDR_SETUP_BIT,
      CP_RSP_TO_FIFO_BIT,
      WAIT_FOR_WR_RSP_BIT,
      ERROR_BIT
   } index;

   enum logic [`NUM_RD_STATES-1:0] {
      IDLE            = `NUM_RD_STATES'b1<<IDLE_BIT,
      ADDR_PROP_DELAY = `NUM_RD_STATES'b1<<ADDR_PROP_DELAY_BIT,
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

   logic packet_complete;
   logic rlast_valid;
   logic [dma_pkg::DEST_ADDR_W-1:0] saved_araddr;
   logic [2:0] awaddr_prop_delay;
   logic [dma_pkg::LENGTH_W-1:0] desc_length_minus_one;
   logic [dma_pkg::PERF_CNTR_W-1:0] rd_src_clk_cnt;
   logic [dma_pkg::PERF_CNTR_W-1:0] rd_src_valid_cnt;
   logic [AXI_LEN_W:0] num_rlasts;
   logic [AXI_LEN_W:0] rlast_cnt;
   logic [AXI_LEN_W:0] num_rd_reqs;
   logic [AXI_LEN_W:0] rd_req_cnt;

   assign rd_src_status.rd_src_perf_cntr.rd_src_clk_cnt   = {'0,rd_src_clk_cnt};
   assign rd_src_status.rd_src_perf_cntr.rd_src_valid_cnt = {'0,rd_src_valid_cnt};
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
          if (descriptor.descriptor_control.go & descriptor_fifo_not_empty) next = ADDR_PROP_DELAY;
          else next = IDLE;
        end 

        state[ADDR_PROP_DELAY_BIT]:
            if ((awaddr_prop_delay[2] & src_mem.arready) & ((rd_req_cnt-rlast_cnt)<2)) next = ADDR_SETUP;
            else next = ADDR_PROP_DELAY;

         state[ADDR_SETUP_BIT]:
            if ((rd_req_cnt+1) < num_rd_reqs) next = ADDR_PROP_DELAY; 
            else if ((rd_req_cnt+1) >= num_rd_reqs) next = CP_RSP_TO_FIFO;
            else next = ADDR_SETUP;

         state[CP_RSP_TO_FIFO_BIT]:
            if (rlast_valid & (num_rlasts == (rlast_cnt+1))) next = WAIT_FOR_WR_RSP;
            else next = CP_RSP_TO_FIFO;

         state[WAIT_FOR_WR_RSP_BIT]:
            if (wr_fsm_done) next = IDLE;
            else next = WAIT_FOR_WR_RSP;
      endcase
   end

  always_ff @(posedge clk) begin
     if (!reset_n) begin
        num_rlasts        <= '0;
        rlast_cnt         <= '0;
        src_mem.arvalid   <= 1'b0;
        src_mem.wvalid    <= 1'b0;
        src_mem.awvalid   <= 1'b0;
        src_mem.ar        <= '0;
        wr_fifo_if.wr_en  <= 1'b0;
        awaddr_prop_delay <= '0;
        rd_req_cnt        <= 0;
        num_rd_reqs       <= '0;
     end else begin
        awaddr_prop_delay  <= '0;
        rlast_cnt          <= rlast_cnt + rlast_valid;
        wr_fifo_if.wr_en   <= !wr_fifo_if.almost_full & src_mem.rvalid & src_mem.rready;
        wr_fifo_if.wr_data <= {packet_complete, src_mem.r.last, src_mem.r.data};
 
        unique case (1'b1)
           next[IDLE_BIT]: begin
              rd_req_cnt         <= 0;
              wr_fifo_if.wr_en   <= 1'b0;
              src_mem.arvalid    <= 1'b0;
              rlast_cnt          <= '0;
           end 

           next[ADDR_PROP_DELAY_BIT]: begin
               src_mem.arvalid    <= 1'b0;
               num_rd_reqs        <= desc_length_minus_one[(dma_pkg::LENGTH_W)-1:AXI_LEN_W]+1;
               num_rlasts         <= desc_length_minus_one[(dma_pkg::LENGTH_W)-1:AXI_LEN_W]+1;
               rd_req_cnt         <= state[ADDR_SETUP_BIT] ? (rd_req_cnt+1) : rd_req_cnt;
               awaddr_prop_delay  <= awaddr_prop_delay + 1;
               src_mem.ar.addr    <= state[ADDR_SETUP_BIT] ? src_mem.ar.addr + ADDR_INCR :
                                     state[IDLE_BIT]       ? descriptor.src_addr         : 
                                                             src_mem.ar.addr;
           end
           
           next[ADDR_SETUP_BIT]: begin
              src_mem.arvalid    <= 1'b1;
              src_mem.ar.addr    <= state[IDLE_BIT] ? descriptor.src_addr : src_mem.ar.addr;
              src_mem.ar.len     <= ((rd_req_cnt+1) < num_rd_reqs) ? MAX_AXI_LEN : (descriptor.length[AXI_LEN_W-1:0]-1);
              src_mem.ar.burst   <= get_burst(descriptor.descriptor_control.mode);
              src_mem.ar.size    <= src_mem.ADDR_BYTE_IDX_WIDTH; // 111 indicates 128bytes per spec
           end

           next[CP_RSP_TO_FIFO_BIT]: begin
              src_mem.arvalid    <= 1'b0;
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin
              wr_fifo_if.wr_data <= {packet_complete, src_mem.r.last, src_mem.r.data};
              wr_fifo_if.wr_en   <= !wr_fifo_if.almost_full & src_mem.rvalid & src_mem.r.last;
           end

           next[ERROR_BIT]: begin end
        endcase
     end
  end

   // Data & Descriptor FIFO control
   always_comb begin
      descriptor_fifo_rdack          = 1'b0;
      src_mem.rready = !wr_fifo_if.almost_full;
      rd_src_status.stopped_on_error = 1'b0;
      rd_src_status.rd_rsp_err       = 1'b0;
      packet_complete = 0;
      unique case (1'b1)
         state[IDLE_BIT]: begin end

         state[ADDR_SETUP_BIT]: begin end

         state[ADDR_PROP_DELAY_BIT]: begin end

         state[CP_RSP_TO_FIFO_BIT]: begin 
            packet_complete = rlast_valid & (num_rlasts == (rlast_cnt+1));
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
        rd_src_clk_cnt   <= rd_src_clk_cnt + 1;
        rd_src_valid_cnt <= rd_src_valid_cnt + (src_mem.rvalid & src_mem.rready);
 
        unique case (1'b1)
            next[IDLE_BIT]: begin
               rd_src_status.busy <= 1'b0;
               rd_src_clk_cnt   <= rd_src_clk_cnt;
               rd_src_valid_cnt <= rd_src_valid_cnt;
            end 
           next[ADDR_PROP_DELAY_BIT]: begin 
              // Only reset the bandwidth calculations when transitioning from IDLE. This 
              // way we can can read the value after a transfer is complete
              rd_src_clk_cnt   <= state[IDLE_BIT] ? '0 : rd_src_clk_cnt + 1;
              rd_src_valid_cnt <= state[IDLE_BIT] ? '0 : rd_src_valid_cnt + (src_mem.rvalid & src_mem.rready);
           end
           
           next[ADDR_SETUP_BIT]: begin
           end

           next[CP_RSP_TO_FIFO_BIT]: begin  
           end
           
           next[WAIT_FOR_WR_RSP_BIT]: begin 
              rd_src_status.descriptor_count <= rd_src_status.descriptor_count + descriptor_fifo_rdack;
           end

           next[ERROR_BIT]: begin end
        endcase
      
     end 
  end

  
   // synthesis translate_off
   integer rd_src_axi_file;
   integer rd_src_fifo_file;
   integer debug;
 
   initial begin 
      debug = 0;
      if (debug) begin
      rd_src_axi_file = $fopen("rd_src_axi.txt","a");
      rd_src_fifo_file = $fopen("rd_src_fifo.txt","a");
      end
 
      forever begin
         fork 
            begin
                @(posedge clk);
                if (wr_fifo_if.wr_en & debug) 
                   $fwrite(rd_src_fifo_file, "0x%0h: 0x%0h\n", descriptor.descriptor_control.mode,wr_fifo_if.wr_data[DATA_W-3:0]);
            end
            begin
                @(posedge clk);
                if (src_mem.rvalid & src_mem.rready & debug) 
                   $fwrite(rd_src_axi_file, "0x%0h: 0x%0h\n", descriptor.descriptor_control.mode,src_mem.r.data);
            end
            begin
               // close the debug files
               @(posedge clk);
               if (state[WAIT_FOR_WR_RSP_BIT] & wr_fsm_done & debug) begin
                  $fclose(rd_src_axi_file);
                  $fclose(rd_src_fifo_file);
               end
            end 
         join
      end
   end
   // synthesis translate_on
 
endmodule
