// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

// import dma_pkg::*;

//
// Copy engine top-level. Take in a pair of AXI-MM interfaces, one for CSRs and
// one for reading and writing host memory.
//
// This engine can be instantiated either from a full-PIM system using
// ofs_plat_afu() or from a hybrid design in which the PIM host channel
// mapping is created by the AFU.
//

module dma_top #(
    parameter NUM_LOCAL_MEM_BANKS = 1
)(
    // CSR interface (MMIO on the host)
    ofs_plat_axi_mem_lite_if.to_source mmio64_to_afu,

    // Host memory (DMA)
    ofs_plat_axi_mem_if.to_sink host_mem,
    ofs_plat_axi_mem_if.to_sink ddr_mem[NUM_LOCAL_MEM_BANKS]
);

    // Each interface names its associated clock and reset.
    logic clk;
    assign clk = host_mem.clk;
    logic reset_n;
    assign reset_n = host_mem.reset_n;

    // ====================================================================
    //
    // CSR (MMIO) manager. Handle all MMIO reads and writes from the host
    // and output copy commands.
    //
    // ====================================================================

    dma_pkg::t_dma_csr_map dma_csr_map; //RO
    dma_pkg::t_dma_csr_status dma_csr_status;
    dma_pkg::t_dma_csr_status wr_dest_status;
    dma_pkg::t_dma_csr_status rd_src_status;
    dma_pkg::t_dma_csr_status dma_engine_status;
    dma_pkg::t_dma_descriptor dma_descriptor;
    dma_fifo_if #(.DATA_W ($bits(dma_pkg::t_dma_descriptor))) wr_desc_fifo_if();
    dma_fifo_if #(.DATA_W ($bits(dma_pkg::t_dma_descriptor))) rd_desc_fifo_if();
    logic descriptor_fifo_rdack;
    logic descriptor_fifo_not_empty;
    logic descriptor_fifo_not_full;

    always_comb begin
       wr_desc_fifo_if.wr_data = dma_csr_map.descriptor;
       wr_desc_fifo_if.wr_en   = dma_csr_map.descriptor.descriptor_control.go;
     
       dma_descriptor            = rd_desc_fifo_if.rd_data;
       rd_desc_fifo_if.rd_en     = descriptor_fifo_rdack;
       descriptor_fifo_not_empty = rd_desc_fifo_if.not_empty;
       dma_csr_status                              = 0;
       dma_csr_status.rsvd_63_30                   = 0;
       dma_csr_status.dma_mode                     = dma_descriptor.descriptor_control.mode;
       dma_csr_status.wr_dest_perf_cntr            = wr_dest_status.wr_dest_perf_cntr;
       dma_csr_status.rd_src_perf_cntr             = rd_src_status.rd_src_perf_cntr;
       dma_csr_status.descriptor_count             = rd_src_status.descriptor_count;
       dma_csr_status.rd_state                     = rd_src_status.rd_state;
       dma_csr_status.wr_state                     = wr_dest_status.wr_state;
       dma_csr_status.rd_resp_enc                  = '0;
       dma_csr_status.rd_rsp_err                   = rd_src_status.rd_rsp_err;
       dma_csr_status.wr_resp_enc                  = '0;
       dma_csr_status.wr_rsp_err                   = wr_dest_status.wr_rsp_err;
       dma_csr_status.irq                          = '0;
       dma_csr_status.stopped_on_early_termination = '0;
       dma_csr_status.stopped_on_error             = wr_dest_status.stopped_on_error | rd_src_status.stopped_on_error; 
       dma_csr_status.resetting                    = '0; 
       dma_csr_status.stopped                      = '0; 
       dma_csr_status.response_fifo_full           = dma_engine_status.response_fifo_full;
       dma_csr_status.response_fifo_empty          = dma_engine_status.response_fifo_empty;
       dma_csr_status.descriptor_fifo_full         = ~wr_desc_fifo_if.not_full;
       dma_csr_status.descriptor_fifo_empty        = ~rd_desc_fifo_if.not_empty;
       dma_csr_status.busy                         = wr_dest_status.busy | rd_src_status.busy;
     end


    csr_mgr #(
        // Maximum burst length is dictated by the size of the field in
        // the AXI-MM host_mem. The PIM will map AXI-MM bursts to legal
        // host channel bursts, including guaranteeing to satisfy any
        // necessary address alignment.
        .MAX_BURST_CNT(1 << host_mem.BURST_CNT_WIDTH_)
    ) csr_mgr_inst (
        .mmio64_to_afu,
        .dma_csr_map,
        .dma_csr_status
    );

    ofs_plat_prim_fifo_bram #(
      .N_DATA_BITS  ($bits(dma_pkg::t_dma_descriptor)),
      .N_ENTRIES    (dma_pkg::DMA_DESCRIPTOR_FIFO_DEPTH)
    ) descriptor_fifo_inst (
      .clk,
      .reset_n,

      .enq_data(wr_desc_fifo_if.wr_data),
      .enq_en(wr_desc_fifo_if.wr_en),
      .notFull(wr_desc_fifo_if.not_full),
      .almostFull(),

      .first(rd_desc_fifo_if.rd_data),
      .deq_en(rd_desc_fifo_if.rd_en & !dma_csr_map.control.stop_descriptors),
      .notEmpty(rd_desc_fifo_if.not_empty)
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
    ofs_plat_axi_mem_if #(
        // Copy the configuration from host_mem
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem)
    ) dest_mem();


     ofs_plat_axi_mem_if #(
        // Copy the configuration from ddr_mem
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(ddr_mem[0])
     ) src_mem();

    ofs_plat_axi_mem_if #(
      // Copy the configuration from ddr_mem
      `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(ddr_mem[0])
    ) selected_ddr_mem();

    dma_ddr_selector #(
        .NUM_LOCAL_MEM_BANKS (NUM_LOCAL_MEM_BANKS),
        .ADDR_WIDTH(dma_pkg::SRC_ADDR_W) // SRC_ADDR_W := DEST_ADDR_W
    ) ddr_selector (
        .descriptor(dma_descriptor),
        .selected_ddr_mem,
        .ddr_mem
     );

    dma_axi_mm_mux #(
    ) dma_axi_mm_mux (
        .mode (dma_descriptor.descriptor_control.mode),
        .src_mem,
        .dest_mem,
        .host_mem,
        .ddr_mem(selected_ddr_mem)
    );
   
    dma_engine #(
    ) dma_engine_inst (
        .clk,
        .reset_n,
        .src_mem,
        .dest_mem,
        .descriptor_fifo_not_empty,
        .descriptor_fifo_rdack,
        .descriptor (dma_descriptor),

        // Commands
        .csr_control (dma_csr_map.control),
        .wr_dest_status,
        .rd_src_status,
        .dma_engine_status
    );


endmodule
