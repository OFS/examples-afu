

module dma_axi_mm_mux #(
   parameter NUM_LOCAL_MEM_BANKS = 1
)(
   input dma_pkg::e_dma_mode mode,
   //input logic [NUM_LOCAL_MEM_BANKS] ddr_if_sel, // will add when ddr<->ddr transactions are added
   ofs_plat_axi_mem_if.to_source src_mem,
   ofs_plat_axi_mem_if.to_source dest_mem,
   ofs_plat_axi_mem_if.to_sink host_mem,
   ofs_plat_axi_mem_if.to_sink ddr_mem
);


   `define AXI_MM_ASSIGN(dma_mem_src, pim_mem_src, dma_mem_dest, pim_mem_dest) \
      ``pim_mem_src``.arvalid= ``dma_mem_src``.arvalid; \
      ``dma_mem_src``.arready= ``pim_mem_src``.arready; \
      ``pim_mem_src``.ar     = {'b0, ``dma_mem_src``.ar}; \
      ``pim_mem_src``.rready = ``dma_mem_src``.rready; \
      ``dma_mem_src``.rvalid = ``pim_mem_src``.rvalid; \
      ``dma_mem_src``.r      = {'b0, ``pim_mem_src``.r}; \
      ``dma_mem_src``.awready= ``pim_mem_src``.awready; \
      ``pim_mem_src``.awvalid= ``dma_mem_src``.awvalid; \
      ``pim_mem_src``.aw     = {'b0, ``dma_mem_src``.aw}; \
      ``dma_mem_src``.wready = ``pim_mem_src``.wready; \
      ``pim_mem_src``.wvalid = ``dma_mem_src``.wvalid; \
      ``pim_mem_src``.w      = {'b0, ``dma_mem_src``.w}; \
      ``pim_mem_src``.bready = ``dma_mem_src``.bready; \
      ``dma_mem_src``.bvalid = ``pim_mem_src``.bvalid; \
      ``dma_mem_src``.b      = {'b0, ``pim_mem_src``.b}; \
      ``dma_mem_dest``.arready = ``pim_mem_dest``.arready; \
      ``pim_mem_dest``.arvalid = ``dma_mem_dest``.arvalid; \
      ``pim_mem_dest``.ar      = {'b0, ``dma_mem_dest``.ar}; \
      ``pim_mem_dest``.rready  = ``dma_mem_dest``.rready; \
      ``dma_mem_dest``.rvalid  = ``pim_mem_dest``.rvalid; \
      ``dma_mem_dest``.r       = {'b0, ``pim_mem_dest``.r}; \
      ``dma_mem_dest``.awready = ``pim_mem_dest``.awready; \
      ``pim_mem_dest``.awvalid = ``dma_mem_dest``.awvalid; \
      ``pim_mem_dest``.aw      = {'b0, ``dma_mem_dest``.aw}; \
      ``dma_mem_dest``.wready  = ``pim_mem_dest``.wready; \
      ``pim_mem_dest``.wvalid  = ``dma_mem_dest``.wvalid; \
      ``pim_mem_dest``.w       = {'b0, ``dma_mem_dest``.w}; \
      ``pim_mem_dest``.bready  = ``dma_mem_dest``.bready; \
      ``dma_mem_dest``.bvalid  = ``pim_mem_dest``.bvalid; \
      ``dma_mem_dest``.b       = {'b0, ``pim_mem_dest``.b}; 
  
  always_comb begin
     case (mode) 
         dma_pkg::DDR_TO_HOST: begin 
            `AXI_MM_ASSIGN(src_mem, ddr_mem, dest_mem, host_mem)
         end

         dma_pkg::HOST_TO_DDR: begin 
            `AXI_MM_ASSIGN(src_mem, host_mem, dest_mem, ddr_mem)
         end
 
         default: begin 
            `AXI_MM_ASSIGN(src_mem, ddr_mem, dest_mem, host_mem)
         end

     endcase
  end










endmodule : dma_axi_mm_mux
