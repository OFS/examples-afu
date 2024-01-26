`include "ofs_plat_if.vh"

module dma_axi_mm_mux (
   input dma_pkg::e_dma_mode mode,
   ofs_plat_axi_mem_if.to_source src_mem,
   ofs_plat_axi_mem_if.to_source dest_mem,
   ofs_plat_axi_mem_if.to_sink host_mem,
   ofs_plat_axi_mem_if.to_sink ddr_mem
);

   // Use field-level copy macro in case src and dst have different parameters
   `define AXI_MM_ASSIGN(dma_mem_src, pim_mem_src, dma_mem_dest, pim_mem_dest) \
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
      `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem)
   ) host_mem_reg();

   ofs_plat_axi_mem_if_reg_sink_clk host_reg (
      .mem_sink(host_mem),
      .mem_source(host_mem_reg)
   );

   ofs_plat_axi_mem_if #(
      `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(ddr_mem)
   ) ddr_mem_reg();

   ofs_plat_axi_mem_if_reg_sink_clk  ddr_reg (
      .mem_sink(ddr_mem),
      .mem_source(ddr_mem_reg)
   );

  always_comb begin
     case (mode) 
         dma_pkg::DDR_TO_HOST: begin 
            `AXI_MM_ASSIGN(src_mem, ddr_mem_reg, dest_mem, host_mem_reg)
         end

         dma_pkg::HOST_TO_DDR: begin 
            `AXI_MM_ASSIGN(src_mem, host_mem_reg, dest_mem, ddr_mem_reg)
         end

         default: begin 
            `AXI_MM_ASSIGN(src_mem, ddr_mem_reg, dest_mem, host_mem_reg)
         end

     endcase
  end

endmodule : dma_axi_mm_mux