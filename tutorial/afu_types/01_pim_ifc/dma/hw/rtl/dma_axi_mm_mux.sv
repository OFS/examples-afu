
`include "ofs_plat_if.vh"

module dma_axi_mm_mux (
   input logic clk,
   input logic reset_n,
   input dma_pkg::e_dma_mode mode,
   ofs_plat_axi_mem_if.to_source src_mem,
   ofs_plat_axi_mem_if.to_source dest_mem,
   ofs_plat_axi_mem_if.to_sink host_mem,
   ofs_plat_axi_mem_if.to_sink ddr_mem
);
	localparam SKID_BUFFER = 0;
	localparam SIMPLE_BUFFER = 1;
	localparam BYPASS = 2;

   `define AXI_MEM_IF_COPY_READY(dma_mem_src, pim_mem_src, dma_mem_dest, pim_mem_dest) \
      ``pim_mem_src``.arvalid    = ``dma_mem_src``.arvalid; \
      ``dma_mem_src``.arready    = ``pim_mem_src``.arready; \
      ``pim_mem_src``.ar         = {'0, ``dma_mem_src``.ar}; \
      ``pim_mem_src``.rready  = ``dma_mem_src``.rready; \
      ``dma_mem_src``.rvalid  = ``pim_mem_src``.rvalid; \
      ``dma_mem_src``.awready    = ``pim_mem_src``.awready; \
      ``pim_mem_src``.awvalid    = ``dma_mem_src``.awvalid; \
      ``dma_mem_src``.wready  = ``pim_mem_src``.wready; \
      ``pim_mem_src``.wvalid  = ``dma_mem_src``.wvalid; \
      ``pim_mem_src``.bready  = ``dma_mem_src``.bready; \
      ``dma_mem_src``.bvalid  = ``pim_mem_src``.bvalid; \
      ``dma_mem_dest``.arready   = ``pim_mem_dest``.arready; \
      ``pim_mem_dest``.arvalid   = ``dma_mem_dest``.arvalid; \
      ``pim_mem_dest``.rready  = ``dma_mem_dest``.rready; \
      ``dma_mem_dest``.rvalid  = ``pim_mem_dest``.rvalid; \
      ``dma_mem_dest``.awready   = ``pim_mem_dest``.awready; \
      ``pim_mem_dest``.awvalid   = ``dma_mem_dest``.awvalid; \
      ``dma_mem_dest``.wready  = ``pim_mem_dest``.wready; \
      ``pim_mem_dest``.wvalid  = ``dma_mem_dest``.wvalid; \
      ``pim_mem_dest``.bready  = ``dma_mem_dest``.bready; \
      ``dma_mem_dest``.bvalid  = ``pim_mem_dest``.bvalid; \


   `define AXI_MM_ASSIGN(dma_mem_src, pim_mem_src, dma_mem_dest, pim_mem_dest) \
      `AXI_MEM_IF_COPY_READY(dma_mem_src, pim_mem_src, dma_mem_dest, pim_mem_dest) \
      \
      `OFS_PLAT_AXI_MEM_IF_COPY_AR(pim_mem_src.ar, =, dma_mem_src.ar); \
      `OFS_PLAT_AXI_MEM_IF_COPY_R(dma_mem_src.r, =, pim_mem_src.r); \
      `OFS_PLAT_AXI_MEM_IF_COPY_AW(pim_mem_src.aw, =, dma_mem_src.aw); \
      `OFS_PLAT_AXI_MEM_IF_COPY_W(pim_mem_src.w, =, dma_mem_src.w); \
      `OFS_PLAT_AXI_MEM_IF_COPY_B(dma_mem_src.b, =, pim_mem_src.b); \
      \
      `OFS_PLAT_AXI_MEM_IF_COPY_AR(pim_mem_dest.ar, =, dma_mem_dest.ar); \
      `OFS_PLAT_AXI_MEM_IF_COPY_R(dma_mem_dest.r, =, pim_mem_dest.r); \
      `OFS_PLAT_AXI_MEM_IF_COPY_AW(pim_mem_dest.aw, =, dma_mem_dest.aw); \
      `OFS_PLAT_AXI_MEM_IF_COPY_W(pim_mem_dest.w, =, dma_mem_dest.w); \
      `OFS_PLAT_AXI_MEM_IF_COPY_B(dma_mem_dest.b, =, pim_mem_dest.b);

   ofs_plat_axi_mem_if #(
      `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(src_mem)
   ) src_mem_q();

   ofs_plat_axi_mem_if #(
      `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(dest_mem)
   ) dest_mem_q();

   assign src_mem_q.clk = host_mem.clk;
   assign src_mem_q.reset_n = host_mem.reset_n;
   assign dest_mem_q.clk = host_mem.clk;
   assign dest_mem_q.reset_n = host_mem.reset_n;

   ofs_plat_axi_mem_if_reg_impl #(
     `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(src_mem),
     .T_AW_WIDTH      ($bits(src_mem_q.aw    )), 
     .T_W_WIDTH       ($bits(src_mem_q.w     )), 
     .T_B_WIDTH       ($bits(src_mem_q.b     )), 
     .T_AR_WIDTH      ($bits(src_mem_q.ar    )), 
     .T_R_WIDTH       ($bits(src_mem_q.r     ))  
   ) src_mem_reg_inst ( 
     .mem_sink   (src_mem_q.to_sink), 
     .mem_source (src_mem)  
   );

   ofs_plat_axi_mem_if_reg_impl #(
      `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(dest_mem),
      .T_AW_WIDTH      ($bits(dest_mem_q.aw    )), 
      .T_W_WIDTH       ($bits(dest_mem_q.w     )), 
      .T_B_WIDTH       ($bits(dest_mem_q.b     )), 
      .T_AR_WIDTH      ($bits(dest_mem_q.ar    )), 
      .T_R_WIDTH       ($bits(dest_mem_q.r     ))  
   ) dest_mem_reg_inst ( 
      .mem_sink   (dest_mem_q.to_sink), 
      .mem_source (dest_mem)  
   );

   always_comb begin
      case (mode) 
         dma_pkg::DDR_TO_HOST: begin 
            `AXI_MM_ASSIGN(src_mem_q, ddr_mem, dest_mem_q, host_mem)
         end

         dma_pkg::HOST_TO_DDR: begin 
            `AXI_MM_ASSIGN(src_mem_q, host_mem, dest_mem_q, ddr_mem)
         end
 
         default: begin 
            `AXI_MM_ASSIGN(src_mem_q, ddr_mem, dest_mem_q, host_mem)
         end

      endcase
      host_mem.aw.atop = 0;
      ddr_mem.aw.atop = 0;
  end

endmodule : dma_axi_mm_mux
