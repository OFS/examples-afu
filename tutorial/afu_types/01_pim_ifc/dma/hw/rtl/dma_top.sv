// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Copy engine top-level. Take in a pair of AXI-MM interfaces, one for CSRs and
// one for reading and writing host memory.
//
// This engine can be instantiated either from a full-PIM system using
// ofs_plat_afu() or from a hybrid design in which the PIM host channel
// mapping is created by the AFU.
//

module dma_top
   (
    // CSR interface (MMIO on the host)
    ofs_plat_axi_mem_lite_if.to_source mmio64_to_afu,

    // Host memory (DMA)
    ofs_plat_axi_mem_if.to_sink host_mem
    ofs_plat_axi_mem_if.to_sink ddr_mem
    );

    // Each interface names its associated clock and reset.
    logic clk;
    assign clk = host_mem.clk;
    logic reset_n;
    assign reset_n = host_mem.reset_n;

    // Maximum number of copy commands in flight. This is exposed in a CSR. It
    // is the host's responsibility not to exceed. The host can track completions
    // by requesting interrupts.
    localparam MAX_REQS_IN_FLIGHT = 1024;


    // ====================================================================
    //
    // CSR (MMIO) manager. Handle all MMIO reads and writes from the host
    // and output copy commands.
    //
    // ====================================================================

    dma_pkg::t_control wr_host_control;
    dma_pkg::t_status  wr_host_status;
    dma_pkg::t_control wr_ddr_control;
    dma_pkg::t_status  wr_ddr_status;

    csr_mgr #(
        .MAX_REQS_IN_FLIGHT(MAX_REQS_IN_FLIGHT),
        // Maximum burst length is dictated by the size of the field in
        // the AXI-MM host_mem. The PIM will map AXI-MM bursts to legal
        // host channel bursts, including guaranteeing to satisfy any
        // necessary address alignment.
        .MAX_BURST_CNT(1 << host_mem.BURST_CNT_WIDTH_)
    ) csr_mgr_inst (
        .mmio64_to_afu,

        .wr_ddr_control,
        .wr_ddr_status,

        .wr_host_control,
        .wr_host_status
    );


    // ====================================================================
    //
    // Read engine
    //
    // ====================================================================

    // Declare a copy of the host memory read interface. The read ports
    // will be connected to the read engine and the write ports unused.
    // This will split the read channels from the write channels but keep
    // a single interface type.  Do this for each host/ddr read/write
    ofs_plat_axi_mem_if
      #(
        // Copy the configuration from host_mem
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem)
        )
      host_mem_rd();

    ofs_plat_axi_mem_if
      #(
        // Copy the configuration from host_mem
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem)
        )
      host_mem_wr();


     ofs_plat_axi_mem_if
      #(
        // Copy the configuration from ddr_mem
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(ddr_mem)
        )
      ddr_mem_wr();

     ofs_plat_axi_mem_if
      #(
        // Copy the configuration from ddr_mem
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(ddr_mem)
        )
      ddr_mem_rd();

    // Connect read ports to host_mem
    assign host_mem_rd.clk = clk;
    assign host_mem_rd.reset_n = reset_n;
    assign host_mem_rd.instance_number = host_mem.instance_number;

    assign host_mem.arvalid = host_mem_rd.arvalid;
    assign host_mem_rd.arready = host_mem.arready;
    assign host_mem.ar = host_mem_rd.ar;

    assign host_mem_rd.rvalid = host_mem.rvalid;
    assign host_mem.rready = host_mem_rd.rready;
    assign host_mem_rd.r = host_mem.r;

    // Write unused
    assign host_mem_rd.bvalid  = 1'b0;
    assign host_mem_rd.awready = 1'b0;
    assign host_mem_rd.wready  = 1'b0;

    // Connect read ports to host_mem
    assign host_mem_wr.clk             = clk;
    assign host_mem_wr.reset_n         = reset_n;
    assign host_mem_wr.instance_number = host_mem.instance_number;

    assign host_mem.awvalid    = host_mem_wr.awvalid;
    assign host_mem_wr.awready = host_mem.awready;
    assign host_mem.aw         = host_mem_wr.aw;

    assign host_mem.wvalid     = host_mem_wr.wvalid;
    assign host_mem_wr.wready  = host_mem.wready;
    assign host_mem.w          = host_mem_wr.w;

    assign host_mem_wr.bvalid = host_mem.bvalid;
    assign host_mem.bready    = host_mem_wr.bready;
    assign host_mem_wr.b      = host_mem.b;

    // Read unused
    assign host_mem_wr.rvalid  = 1'b0;
    assign host_mem_wr.arready = 1'b0;



 
 // Connect read ports to ddr_mem
    assign ddr_mem_rd.clk = clk;
    assign ddr_mem_rd.reset_n = reset_n;
    assign ddr_mem_rd.instance_number = ddr_mem.instance_number;

    assign ddr_mem.arvalid = ddr_mem_rd.arvalid;
    assign ddr_mem_rd.arready = ddr_mem.arready;
    assign ddr_mem.ar = ddr_mem_rd.ar;

    assign ddr_mem_rd.rvalid = ddr_mem.rvalid;
    assign ddr_mem.rready = ddr_mem_rd.rready;
    assign ddr_mem_rd.r = ddr_mem.r;

    // Write unused
    assign ddr_mem_rd.bvalid  = 1'b0;
    assign ddr_mem_rd.awready = 1'b0;
    assign ddr_mem_rd.wready  = 1'b0;

    // Connect read ports to ddr_mem
    assign ddr_mem_wr.clk             = clk;
    assign ddr_mem_wr.reset_n         = reset_n;
    assign ddr_mem_wr.instance_number = ddr_mem.instance_number;

    assign ddr_mem.awvalid    = ddr_mem_wr.awvalid;
    assign ddr_mem_wr.awready = ddr_mem.awready;
    assign ddr_mem.aw         = ddr_mem_wr.aw;

    assign ddr_mem.wvalid     = ddr_mem_wr.wvalid;
    assign ddr_mem_wr.wready  = ddr_mem.wready;
    assign ddr_mem.w          = ddr_mem_wr.w;

    assign ddr_mem_wr.bvalid = ddr_mem.bvalid;
    assign ddr_mem.bready    = ddr_mem_wr.bready;
    assign ddr_mem_wr.b      = ddr_mem.b;

    // Read unused
    assign ddr_mem_wr.rvalid  = 1'b0;
    assign ddr_mem_wr.arready = 1'b0;
   

    dma_engine #(
        .MAX_REQS_IN_FLIGHT(MAX_REQS_IN_FLIGHT)
    ) write_ddr_engine (
        .src_mem  (host_mem_rd),
        .dest_mem (ddr_mem_wr),

        // Commands
        .control (wr_ddr_ctrl),
        .status  (wr_ddr_status)
    );

    // ====================================================================
    //
    // Write engine
    //
    // ====================================================================

    // Declare a copy of the host memory write interface. The write ports
    // will be connected to the write engine and the read ports unused.
    // This will split the read channels from the write channels but keep
    // a single interface type.

    //
    // Write Host Engine
    //
    dma_engine #(
        .MAX_REQS_IN_FLIGHT(MAX_REQS_IN_FLIGHT)
    ) write_host_engine (
        .src_mem  (ddr_mem_rd),
        .dest_mem (host_mem_wr),

        // Commands
        .control (wr_host_control),
        .status  (wr_host_status)
    );

endmodule