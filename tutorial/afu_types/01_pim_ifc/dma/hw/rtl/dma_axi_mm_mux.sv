
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

   `define AXI_REG_ASSIGN(axi_s, axi_m) \
      axi_register #(  \
         .AW_REG_MODE          (SIMPLE_BUFFER), \
         .W_REG_MODE           (SIMPLE_BUFFER), \
         .B_REG_MODE           (SIMPLE_BUFFER), \
         .AR_REG_MODE          (SIMPLE_BUFFER), \
         .R_REG_MODE           (SIMPLE_BUFFER), \
         .ENABLE_AWUSER        (SIMPLE_BUFFER), \
         .ENABLE_WUSER         (SIMPLE_BUFFER), \
         .ENABLE_BUSER         (SIMPLE_BUFFER), \
         .ENABLE_ARUSER        (SIMPLE_BUFFER), \
         .ENABLE_RUSER         (SIMPLE_BUFFER), \
         .AWID_WIDTH           ($bits(``axi_s``.aw.id)),   \
         .AWADDR_WIDTH         ($bits(``axi_s``.aw.addr)), \
         .AWUSER_WIDTH         ($bits(``axi_s``.aw.user)), \
         .WDATA_WIDTH          ($bits(``axi_s``.w.data)),  \
         .WUSER_WIDTH          ($bits(``axi_s``.w.user)),  \
         .BUSER_WIDTH          ($bits(``axi_s``.b.user)),  \
         .ARID_WIDTH           ($bits(``axi_s``.ar.id)),   \
         .ARADDR_WIDTH         ($bits(``axi_s``.ar.addr)), \
         .ARUSER_WIDTH         ($bits(``axi_s``.ar.user)), \
         .RDATA_WIDTH          ($bits(``axi_s``.r.data)),  \
         .RUSER_WIDTH          ($bits(``axi_s``.r.user))   \
      ) ``axi_s``_to_``axi_m``_reg_inst ( \
         .clk                (clk         ), \
         .rst_n              (reset_n     ), \
         \
         .s_awready          (``axi_s``.awready     ), \
         .s_awvalid          (``axi_s``.awvalid     ), \
         .s_awid             (``axi_s``.aw.id       ), \
         .s_awaddr           (``axi_s``.aw.addr     ), \
         .s_awlen            (``axi_s``.aw.len      ), \
         .s_awsize           (``axi_s``.aw.size     ), \
         .s_awburst          (``axi_s``.aw.burst    ), \
         .s_awlock           (``axi_s``.aw.lock     ), \
         .s_awcache          (``axi_s``.aw.cache    ), \
         .s_awprot           (``axi_s``.aw.prot     ), \
         .s_awqos            (``axi_s``.aw.qos      ), \
         .s_awregion         (``axi_s``.aw.region   ), \
         .s_awuser           (``axi_s``.aw.user     ), \
         \
         .s_wready           (``axi_s``.wready      ), \
         .s_wvalid           (``axi_s``.wvalid      ), \
         .s_wdata            (``axi_s``.w.data      ), \
         .s_wstrb            (``axi_s``.w.strb      ), \
         .s_wlast            (``axi_s``.w.last      ), \
         .s_wuser            (``axi_s``.w.user      ), \
         \
         .s_bready            (``axi_s``.bready     ), \
         .s_bvalid            (``axi_s``.bvalid     ), \
         .s_bid               (``axi_s``.b.id       ), \
         .s_bresp             (``axi_s``.b.resp     ), \
         .s_buser             (``axi_s``.b.user     ), \
         \
         .s_arready           (``axi_s``.arready    ), \
         .s_arvalid           (``axi_s``.arvalid    ), \
         .s_arid              (``axi_s``.ar.id      ), \
         .s_araddr            (``axi_s``.ar.addr    ), \
         .s_arlen             (``axi_s``.ar.len     ), \
         .s_arsize            (``axi_s``.ar.size    ), \
         .s_arburst           (``axi_s``.ar.burst   ), \
         .s_arlock            (``axi_s``.ar.lock    ), \
         .s_arcache           (``axi_s``.ar.cache   ), \
         .s_arprot            (``axi_s``.ar.prot    ), \
         .s_arqos             (``axi_s``.ar.qos     ), \
         .s_arregion          (``axi_s``.ar.region  ), \
         .s_aruser            (``axi_s``.ar.user    ), \
         \
         .s_rready            (``axi_s``.rready     ), \
         .s_rvalid            (``axi_s``.rvalid     ), \
         .s_rid               (``axi_s``.r.id       ), \
         .s_rdata             (``axi_s``.r.data     ), \
         .s_rresp             (``axi_s``.r.resp     ), \
         .s_rlast             (``axi_s``.r.last     ), \
         .s_ruser             (``axi_s``.r.user     ), \
         \
         .m_awready           (``axi_m``.awready    ), \
         .m_awvalid           (``axi_m``.awvalid    ), \
         .m_awid              (``axi_m``.aw.id      ), \
         .m_awaddr            (``axi_m``.aw.addr    ), \
         .m_awlen             (``axi_m``.aw.len     ), \
         .m_awsize            (``axi_m``.aw.size    ), \
         .m_awburst           (``axi_m``.aw.burst   ), \
         .m_awlock            (``axi_m``.aw.lock    ), \
         .m_awcache           (``axi_m``.aw.cache   ), \
         .m_awprot            (``axi_m``.aw.prot    ), \
         .m_awqos             (``axi_m``.aw.qos     ), \
         .m_awregion          (``axi_m``.aw.region  ), \
         .m_awuser            (``axi_m``.aw.user    ), \
         \
         .m_wready            (``axi_m``.wready     ), \
         .m_wvalid            (``axi_m``.wvalid     ), \
         .m_wdata             (``axi_m``.w.data     ), \
         .m_wstrb             (``axi_m``.w.strb     ), \
         .m_wlast             (``axi_m``.w.last     ), \
         .m_wuser             (``axi_m``.w.user     ), \
         \
         .m_bready            (``axi_m``.bready     ), \
         .m_bvalid            (``axi_m``.bvalid     ), \
         .m_bid               (``axi_m``.b.id       ), \
         .m_bresp             (``axi_m``.b.resp     ), \
         .m_buser             (``axi_m``.b.user     ), \
         \
         .m_arready           (``axi_m``.arready    ), \
         .m_arvalid           (``axi_m``.arvalid    ), \
         .m_arid              (``axi_m``.ar.id      ), \
         .m_araddr            (``axi_m``.ar.addr    ), \
         .m_arlen             (``axi_m``.ar.len     ), \
         .m_arsize            (``axi_m``.ar.size    ), \
         .m_arburst           (``axi_m``.ar.burst   ), \
         .m_arlock            (``axi_m``.ar.lock    ), \
         .m_arcache           (``axi_m``.ar.cache   ), \
         .m_arprot            (``axi_m``.ar.prot    ), \
         .m_arqos             (``axi_m``.ar.qos     ), \
         .m_arregion          (``axi_m``.ar.region  ), \
         .m_aruser            (``axi_m``.ar.user    ), \
         \
         .m_rready            (``axi_m``.rready    ), \
         .m_rvalid            (``axi_m``.rvalid    ), \
         .m_rid               (``axi_m``.r.id       ), \
         .m_rdata             (``axi_m``.r.data     ), \
         .m_rresp             (``axi_m``.r.resp     ), \
         .m_rlast             (``axi_m``.r.last     ), \
         .m_ruser             (``axi_m``.r.user     ) \
      ); \

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
  ) src_mem_m();

  `AXI_REG_ASSIGN(src_mem, src_mem_m)


  ofs_plat_axi_mem_if #(
    `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(dest_mem)
  ) dest_mem_m();

  `AXI_REG_ASSIGN(dest_mem, dest_mem_m)


  ofs_plat_axi_mem_if #(
    `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(ddr_mem)
  ) ddr_mem_s();

  `AXI_REG_ASSIGN(ddr_mem_s, ddr_mem)

  ofs_plat_axi_mem_if #(
    `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem)
  ) host_mem_s();

  `AXI_REG_ASSIGN(host_mem_s, host_mem)

  always_comb begin
     case (mode) 
         dma_pkg::DDR_TO_HOST: begin 
            `AXI_MM_ASSIGN(src_mem_m, ddr_mem_s, dest_mem_m, host_mem_s)
         end

         dma_pkg::HOST_TO_DDR: begin 
            `AXI_MM_ASSIGN(src_mem_m, host_mem_s, dest_mem_m, ddr_mem_s)
         end
 
         default: begin 
            `AXI_MM_ASSIGN(src_mem_m, ddr_mem_s, dest_mem_m, host_mem_s)
         end

     endcase
     host_mem.aw.atop = 0;
     ddr_mem.aw.atop = 0;
  end

endmodule : dma_axi_mm_mux
