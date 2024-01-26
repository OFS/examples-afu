
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

   `define AXI_MM_ASSIGN(dma_mem_src, pim_mem_src, dma_mem_dest, pim_mem_dest) \
      ``pim_mem_src``.arvalid    = ``dma_mem_src``.arvalid; \
      ``dma_mem_src``.arready    = ``pim_mem_src``.arready; \
      ``pim_mem_src``.ar         = {'0, ``dma_mem_src``.ar}; \
      ``pim_mem_src``.ar.id      = {'0, ``dma_mem_src``.ar.id}; \
      ``pim_mem_src``.ar.addr    = {'0, ``dma_mem_src``.ar.addr}; \
      ``pim_mem_src``.ar.len     = {'0, ``dma_mem_src``.ar.len}; \
      ``pim_mem_src``.ar.size    = {'0, ``dma_mem_src``.ar.size}; \
      ``pim_mem_src``.ar.burst   = {'0, ``dma_mem_src``.ar.burst}; \
      ``pim_mem_src``.ar.lock    = {'0, ``dma_mem_src``.ar.lock}; \
      ``pim_mem_src``.ar.cache   = {'0, ``dma_mem_src``.ar.cache}; \
      ``pim_mem_src``.ar.prot    = {'0, ``dma_mem_src``.ar.prot}; \
      ``pim_mem_src``.ar.user    = {'0, ``dma_mem_src``.ar.user}; \
      ``pim_mem_src``.ar.qos     = {'0, ``dma_mem_src``.ar.qos}; \
      ``pim_mem_src``.ar.region  = {'0, ``dma_mem_src``.ar.region}; \
      \
      ``pim_mem_src``.rready  = ``dma_mem_src``.rready; \
      ``dma_mem_src``.rvalid  = ``pim_mem_src``.rvalid; \
      ``dma_mem_src``.r       = {'0, ``pim_mem_src``.r}; \
      ``dma_mem_src``.r.id    = {'0, ``pim_mem_src``.r.id}; \
      ``dma_mem_src``.r.data  = {'0, ``pim_mem_src``.r.data}; \
      ``dma_mem_src``.r.resp  = {'0, ``pim_mem_src``.r.resp}; \
      ``dma_mem_src``.r.user  = {'0, ``pim_mem_src``.r.user}; \
      \
      ``dma_mem_src``.awready    = ``pim_mem_src``.awready; \
      ``pim_mem_src``.awvalid    = ``dma_mem_src``.awvalid; \
      ``pim_mem_src``.aw         = {'0, ``dma_mem_src``.aw}; \
      ``pim_mem_src``.aw.id      = {'0, ``dma_mem_src``.aw.id}; \
      ``pim_mem_src``.aw.addr    = {'0, ``dma_mem_src``.aw.addr}; \
      ``pim_mem_src``.aw.len     = {'0, ``dma_mem_src``.aw.len}; \
      ``pim_mem_src``.aw.size    = {'0, ``dma_mem_src``.aw.size}; \
      ``pim_mem_src``.aw.burst   = {'0, ``dma_mem_src``.aw.burst}; \
      ``pim_mem_src``.aw.lock    = {'0, ``dma_mem_src``.aw.lock}; \
      ``pim_mem_src``.aw.cache   = {'0, ``dma_mem_src``.aw.cache}; \
      ``pim_mem_src``.aw.prot    = {'0, ``dma_mem_src``.aw.prot}; \
      ``pim_mem_src``.aw.user    = {'0, ``dma_mem_src``.aw.user}; \
      ``pim_mem_src``.aw.qos     = {'0, ``dma_mem_src``.aw.qos}; \
      ``pim_mem_src``.aw.region  = {'0, ``dma_mem_src``.aw.region}; \
      ``pim_mem_src``.aw.atop    = {'0, ``dma_mem_src``.aw.atop}; \
      \
      ``dma_mem_src``.wready  = ``pim_mem_src``.wready; \
      ``pim_mem_src``.wvalid  = ``dma_mem_src``.wvalid; \
      ``pim_mem_src``.w       = {'0, ``dma_mem_src``.w}; \
      ``pim_mem_src``.w.data  = {'0, ``dma_mem_src``.w.data}; \
      ``pim_mem_src``.w.strb  = {'0, ``dma_mem_src``.w.strb}; \
      ``pim_mem_src``.w.last  = {'0, ``dma_mem_src``.w.last}; \
      ``pim_mem_src``.w.user  = {'0, ``dma_mem_src``.w.user}; \
      \
      ``pim_mem_src``.bready  = ``dma_mem_src``.bready; \
      ``dma_mem_src``.bvalid  = ``pim_mem_src``.bvalid; \
      ``dma_mem_src``.b       = {'0, ``pim_mem_src``.b}; \
      ``dma_mem_src``.b.id    = {'0, ``pim_mem_src``.b.id}; \
      ``dma_mem_src``.b.resp  = {'0, ``pim_mem_src``.b.resp}; \
      ``dma_mem_src``.b.user  = {'0, ``pim_mem_src``.b.user}; \
      \
      ``dma_mem_dest``.arready   = ``pim_mem_dest``.arready; \
      ``pim_mem_dest``.arvalid   = ``dma_mem_dest``.arvalid; \
      ``pim_mem_dest``.ar        = {'0, ``dma_mem_dest``.ar}; \
      ``pim_mem_dest``.ar.id     = {'0, ``dma_mem_dest``.ar.id}; \
      ``pim_mem_dest``.ar.addr   = {'0, ``dma_mem_dest``.ar.addr}; \
      ``pim_mem_dest``.ar.id     = {'0, ``dma_mem_dest``.ar.id}; \
      ``pim_mem_dest``.ar.size   = {'0, ``dma_mem_dest``.ar.size}; \
      ``pim_mem_dest``.ar.burst  = {'0, ``dma_mem_dest``.ar.burst}; \
      ``pim_mem_dest``.ar.lock   = {'0, ``dma_mem_dest``.ar.lock}; \
      ``pim_mem_dest``.ar.cache  = {'0, ``dma_mem_dest``.ar.cache}; \
      ``pim_mem_dest``.ar.prot   = {'0, ``dma_mem_dest``.ar.prot}; \
      ``pim_mem_dest``.ar.user   = {'0, ``dma_mem_dest``.ar.user}; \
      ``pim_mem_dest``.ar.qos    = {'0, ``dma_mem_dest``.ar.qos}; \
      ``pim_mem_dest``.ar.region = {'0, ``dma_mem_dest``.ar.region}; \
      \
      ``pim_mem_dest``.rready  = ``dma_mem_dest``.rready; \
      ``dma_mem_dest``.rvalid  = ``pim_mem_dest``.rvalid; \
      ``dma_mem_dest``.r       = {'0, ``pim_mem_dest``.r}; \
      ``dma_mem_dest``.r.id    = {'0, ``pim_mem_dest``.r.id}; \
      ``dma_mem_dest``.r.data  = {'0, ``pim_mem_dest``.r.data}; \
      ``dma_mem_dest``.r.resp  = {'0, ``pim_mem_dest``.r.resp}; \
      ``dma_mem_dest``.r.user  = {'0, ``pim_mem_dest``.r.user}; \
      \
      ``dma_mem_dest``.awready   = ``pim_mem_dest``.awready; \
      ``pim_mem_dest``.awvalid   = ``dma_mem_dest``.awvalid; \
      ``pim_mem_dest``.aw        = {'0, ``dma_mem_dest``.aw}; \
      ``pim_mem_dest``.aw.id     = {'0, ``dma_mem_dest``.aw.id}; \
      ``pim_mem_dest``.aw.addr   = {'0, ``dma_mem_dest``.aw.addr}; \
      ``pim_mem_dest``.aw.len    = {'0, ``dma_mem_dest``.aw.len}; \
      ``pim_mem_dest``.aw.size   = {'0, ``dma_mem_dest``.aw.size}; \
      ``pim_mem_dest``.aw.burst  = {'0, ``dma_mem_dest``.aw.burst}; \
      ``pim_mem_dest``.aw.lock   = {'0, ``dma_mem_dest``.aw.lock}; \
      ``pim_mem_dest``.aw.cache  = {'0, ``dma_mem_dest``.aw.cache}; \
      ``pim_mem_dest``.aw.prot   = {'0, ``dma_mem_dest``.aw.prot}; \
      ``pim_mem_dest``.aw.user   = {'0, ``dma_mem_dest``.aw.user}; \
      ``pim_mem_dest``.aw.qos    = {'0, ``dma_mem_dest``.aw.qos}; \
      ``pim_mem_dest``.aw.region = {'0, ``dma_mem_dest``.aw.region}; \
      ``pim_mem_dest``.aw.atop   = {'0, ``dma_mem_dest``.aw.atop}; \
      \
      ``dma_mem_dest``.wready  = ``pim_mem_dest``.wready; \
      ``pim_mem_dest``.wvalid  = ``dma_mem_dest``.wvalid; \
      ``pim_mem_dest``.w       = {'0, ``dma_mem_dest``.w}; \
      ``pim_mem_dest``.w.data  = {'0, ``dma_mem_dest``.w.data}; \
      ``pim_mem_dest``.w.strb  = {'0, ``dma_mem_dest``.w.strb}; \
      ``pim_mem_dest``.w.last  = {'0, ``dma_mem_dest``.w.last}; \
      ``pim_mem_dest``.w.user  = {'0, ``dma_mem_dest``.w.user}; \
      \
      ``pim_mem_dest``.bready  = ``dma_mem_dest``.bready; \
      ``dma_mem_dest``.bvalid  = ``pim_mem_dest``.bvalid; \
      ``dma_mem_dest``.b       = {'0, ``pim_mem_dest``.b}; \
      ``dma_mem_dest``.b.id    = {'0, ``pim_mem_dest``.b.id}; \
      ``dma_mem_dest``.b.resp  = {'0, ``pim_mem_dest``.b.resp}; \
      ``dma_mem_dest``.b.user  = {'0, ``pim_mem_dest``.b.user};

  //src_mem
  ofs_plat_axi_mem_if #(
    `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(src_mem)
  ) src_mem_reg();

  assign src_mem_reg.clk = ddr_mem.clk;
  assign src_mem_reg.reset_n = ddr_mem.reset_n;

  ofs_plat_axi_mem_if_reg #(
  ) src_reg (
    .mem_sink(src_mem_reg.to_sink),
    .mem_source(src_mem)
  );

  ofs_plat_axi_mem_if #(
    `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(dest_mem)
  ) dest_mem_reg();

  assign dest_mem_reg.clk = host_mem.clk;
  assign dest_mem_reg.reset_n = host_mem.reset_n;

  ofs_plat_axi_mem_if_reg #(
  ) dest_reg (
    .mem_sink(dest_mem_reg.to_sink),
    .mem_source(dest_mem)
  );

  always_comb begin
     case (mode) 
         dma_pkg::DDR_TO_HOST: begin 
            `AXI_MM_ASSIGN(src_mem_reg, ddr_mem, dest_mem_reg, host_mem)
         end

         dma_pkg::HOST_TO_DDR: begin 
            `AXI_MM_ASSIGN(src_mem_reg, host_mem, dest_mem_reg, ddr_mem)
         end
 
         default: begin 
            `AXI_MM_ASSIGN(src_mem_reg, ddr_mem, dest_mem_reg, host_mem)
         end

     endcase
  end

endmodule : dma_axi_mm_mux
