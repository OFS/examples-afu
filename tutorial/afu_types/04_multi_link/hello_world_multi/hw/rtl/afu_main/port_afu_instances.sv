// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT


// The PIM's top-level wrapper is included only because it defines the
// platform macros used below to make the afu_main() port list slightly
// more portable. Except for those macros it is not needed for the non-PIM
// AFUs.
`include "ofs_plat_if.vh"
`include "afu_json_info.vh"

// Merge HSSI macros from various platforms into a single AFU_MAIN_HAS_HSSI
`ifdef INCLUDE_HSSI
  `define AFU_MAIN_HAS_HSSI 1
`endif
`ifdef PLATFORM_FPGA_FAMILY_S10
  `ifdef INCLUDE_HE_HSSI
    `define AFU_MAIN_HAS_HSSI 1
  `endif
`endif

module port_afu_instances
#(
   parameter PG_NUM_PORTS    = 1,
   // PF/VF to which each port is mapped
   parameter pcie_ss_hdr_pkg::ReqHdr_pf_vf_info_t[PG_NUM_PORTS-1:0] PORT_PF_VF_INFO =
                {PG_NUM_PORTS{pcie_ss_hdr_pkg::ReqHdr_pf_vf_info_t'(0)}},

   parameter NUM_MEM_CH      = 0,
   parameter MAX_ETH_CH      = ofs_fim_eth_plat_if_pkg::MAX_NUM_ETH_CHANNELS
)(
   input  logic clk,
   input  logic clk_div2,
   input  logic clk_div4,
   input  logic uclk_usr,
   input  logic uclk_usr_div2,

   input  logic rst_n,
   // port_rst_n at this point also includes rst_n. The two are combined
   // in afu_main().
   input  logic [PG_NUM_PORTS-1:0] port_rst_n,

   // PCIe A ports are the standard TLP channels. All host responses
   // arrive on the RX A port.
   pcie_ss_axis_if.source        afu_axi_tx_a_if [PG_NUM_PORTS-1:0],
   pcie_ss_axis_if.sink          afu_axi_rx_a_if [PG_NUM_PORTS-1:0],
   // PCIe B ports are a second channel on which reads and interrupts
   // may be sent from the AFU. To improve throughput, reads on B may flow
   // around writes on A through PF/VF MUX trees until writes are committed
   // to the PCIe subsystem. AFUs may tie off the B port and send all
   // messages to A.
   pcie_ss_axis_if.source        afu_axi_tx_b_if [PG_NUM_PORTS-1:0],
   // Write commits are signaled here on the RX B port, indicating the
   // point at which the A and B channels become ordered within the FIM.
   // Commits are signaled after tlast of a write on TX A, after arbitration
   // with TX B within the FIM. The commit is a Cpl (without data),
   // returning the tag value from the write request. AFUs that do not
   // need local write commits may ignore this port, but must set
   // tready to 1.
   pcie_ss_axis_if.sink          afu_axi_rx_b_if [PG_NUM_PORTS-1:0]

   `ifdef INCLUDE_DDR4
      // Local memory
     ,ofs_fim_emif_axi_mm_if.user ext_mem_if [NUM_MEM_CH-1:0]
   `endif
   `ifdef PLATFORM_FPGA_FAMILY_S10
      // S10 uses AVMM for DDR
     ,ofs_fim_emif_avmm_if.user   ext_mem_if [NUM_MEM_CH-1:0]
   `endif

   `ifdef AFU_MAIN_HAS_HSSI
     ,ofs_fim_hssi_ss_tx_axis_if.client hssi_ss_st_tx [MAX_ETH_CH-1:0],
      ofs_fim_hssi_ss_rx_axis_if.client hssi_ss_st_rx [MAX_ETH_CH-1:0],
      ofs_fim_hssi_fc_if.client         hssi_fc [MAX_ETH_CH-1:0],
      input logic [MAX_ETH_CH-1:0]      i_hssi_clk_pll
   `endif

    // S10 HSSI PTP interface
   `ifdef INCLUDE_PTP
     ,ofs_fim_hssi_ptp_tx_tod_if.client       hssi_ptp_tx_tod [MAX_ETH_CH-1:0],
      ofs_fim_hssi_ptp_rx_tod_if.client       hssi_ptp_rx_tod [MAX_ETH_CH-1:0],
      ofs_fim_hssi_ptp_tx_egrts_if.client     hssi_ptp_tx_egrts [MAX_ETH_CH-1:0],
      ofs_fim_hssi_ptp_rx_ingrts_if.client    hssi_ptp_rx_ingrts [MAX_ETH_CH-1:0]
   `endif
   );

    localparam TDATA_WIDTH = $bits(afu_axi_tx_a_if[0].tdata);
    localparam TUSER_WIDTH = $bits(afu_axi_tx_a_if[0].tuser_vendor);

    // ====================================================================
    //
    //  Put the parent on port 0 and a child on port 1. If port 2 is
    //  available, put another child on it.
    //
    //  In this example we are not considering bandwidth. The example
    //  demonstrates instantiation of parent/child features in the
    //  DFLs. Because parent/child relationships are defined only by
    //  GUIDs, they can be configured on any groups of ports -- any PFs,
    //  VFs or PCIe links.
    //
    // ====================================================================

    // synthesis translate_off
    initial
    begin
        if (PG_NUM_PORTS < 2)
        begin
            $fatal(2, "** ERROR ** %m: Test requires at least two ports! This FIM has only one.");
        end
    end
    // synthesis translate_on

    // Configure up to 2 children if ports are available
    localparam NUM_CHILDREN = (PG_NUM_PORTS > 2) ? 2 : 1;

    // Three UUIDs are defined in hello_world_multi.json and exposed in afu_json_info.vh
    // by OPAE's afu_json_mgr script during the build.
    localparam [127:0] GUIDS[3] = { `AFU_ACCEL_UUID0, `AFU_ACCEL_UUID1, `AFU_ACCEL_UUID2 };

    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) rx_a[1+NUM_CHILDREN](clk, rst_n);
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) tx_a[1+NUM_CHILDREN](clk, rst_n);

    // Instantiate the parent feature at MMIO offset 0. The parent feature
    // contains a parameter that lists the children. OPAE will discover the
    // parameter and load children along with the parent.
    //
    // This module acts as a shim that implements only the one DFL entry.
    // Other traffic to/from the AFU flows on o_rx_if/i_tx_if.
    ofs_fim_pcie_multi_link_afu_dfh
      #(
        .NUM_CHILDREN(NUM_CHILDREN),
        .CHILD_GUIDS(GUIDS[1:NUM_CHILDREN]),
        // Parent implements a CSR block at 'h1000
        .CSR_ADDR('h1000),
        .CSR_SIZE('h1000),
        // Parent ID
        .GUID_H(GUIDS[0][127:64]),
        .GUID_L(GUIDS[0][63:0])
        )
      parent_feature
       (
        .i_rx_if(afu_axi_rx_a_if[0]),
        .o_rx_if(rx_a[0]),
        .o_tx_if(afu_axi_tx_a_if[0]),
        .i_tx_if(tx_a[0])
        );

    generate
        // Instantiate child features at MMIO offset 0 of the children.
        // The same module is used. When NUM_CHILDREN is not set (defaults
        // to 0), a child feature is constructed. Except for building
        // a different header, the behavior is similar to the parent.
        for (genvar p = 1; p <= NUM_CHILDREN; p = p + 1)
        begin : child
            ofs_fim_pcie_multi_link_afu_dfh
              #(
                .CSR_ADDR('h1000),
                .CSR_SIZE('h1000),
                .GUID_H(GUIDS[p][127:64]),
                .GUID_L(GUIDS[p][63:0])
                )
              feature
               (
                .i_rx_if(afu_axi_rx_a_if[p]),
                .o_rx_if(rx_a[p]),
                .o_tx_if(afu_axi_tx_a_if[p]),
                .i_tx_if(tx_a[p])
                );
        end
    endgenerate

    generate
        // Instantiate the hello world AFU on each port. This is, of course,
        // a simple example. It is not necessary to instantiate the same
        // AFU on each parent/child port. Host SW has access to the MMIO
        // regions of each port. Because of the parent/child relationship,
        // each port operates in the same address space. Any pinned buffer
        // is accessible from the same IOVA on all ports.
        for (genvar p = 0; p < 1 + NUM_CHILDREN; p = p + 1)
        begin : hello_afus
            hello_world_multi
              #(
                .PF_ID(PORT_PF_VF_INFO[p].pf_num),
                .VF_ID(PORT_PF_VF_INFO[p].vf_num),
                .VF_ACTIVE(PORT_PF_VF_INFO[p].vf_active),
                // In the parent, number of children. In children, 0.
                .NUM_CHILDREN(p == 0 ? NUM_CHILDREN : 0),
                .ID(p)
                )
              hello_world
               (
                .clk,
                .rst_n(port_rst_n[p]),
                .o_tx_if(tx_a[p]), // Connect through the multi-link DFH above
                .o_tx_b_if(afu_axi_tx_b_if[p]), // b ports bypass the DFH block
                .i_rx_if(rx_a[p]), // Connect through the multi-link DFH above
                .i_rx_b_if(afu_axi_rx_b_if[p])
                );
        end
    endgenerate


    // ======================================================
    //
    // Tie off any remaining PCIe ports with a NULL AFU
    //
    // ======================================================

    generate
        for (genvar p = 3; p < PG_NUM_PORTS; p = p + 1)
        begin : null_afus
            null_afu
              #(
                .PF_ID(PORT_PF_VF_INFO[p].pf_num),
                .VF_ID(PORT_PF_VF_INFO[p].vf_num),
                .VF_ACTIVE(PORT_PF_VF_INFO[p].vf_active)
                )
              null_afu
               (
                .clk,
                .rst_n(port_rst_n[p]),
                .o_tx_if(afu_axi_tx_a_if[p]),
                .o_tx_b_if(afu_axi_tx_b_if[p]),
                .i_rx_if(afu_axi_rx_a_if[p]),
                .i_rx_b_if(afu_axi_rx_b_if[p])
                );
        end
    endgenerate


    // ======================================================
    //
    // Tie off unused local memory
    //
    // ======================================================

    for (genvar c=0; c<NUM_MEM_CH; c++) begin : mb
     `ifdef INCLUDE_DDR4
        assign ext_mem_if[c].awvalid = 1'b0;
        assign ext_mem_if[c].wvalid = 1'b0;
        assign ext_mem_if[c].arvalid = 1'b0;
        assign ext_mem_if[c].bready = 1'b1;
        assign ext_mem_if[c].rready = 1'b1;
     `endif

     `ifdef PLATFORM_FPGA_FAMILY_S10
        assign ext_mem_if[c].write = 1'b0;
        assign ext_mem_if[c].read = 1'b0;
     `endif
    end


    // ======================================================
    //
    // Tie off unused HSSI
    //
    // ======================================================

`ifdef AFU_MAIN_HAS_HSSI
    for (genvar c=0; c<MAX_ETH_CH; c++) begin : hssi
        assign hssi_ss_st_tx[c].tx = '0;
        assign hssi_fc[c].tx_pause = 0;
        assign hssi_fc[c].tx_pfc = 0;
    end
`endif

endmodule : port_afu_instances
