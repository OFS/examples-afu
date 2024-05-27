// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "afu_json_info.vh"

//
// Top level PIM-based module.
//

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    localparam NUM_HOST_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS;

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
        if (NUM_HOST_PORTS < 2)
        begin
            $fatal(2, "** ERROR ** %m: Test requires at least two ports! This FIM has only one.");
        end
    end
    // synthesis translate_on

    // Configure up to 2 children if ports are available
    localparam NUM_CHILDREN = (NUM_HOST_PORTS > 2) ? 2 : 1;

    // Three UUIDs are defined in hello_world_multi.json and exposed in afu_json_info.vh
    // by OPAE's afu_json_mgr script during the build.
    localparam [127:0] GUIDS[3] = { `AFU_ACCEL_UUID0, `AFU_ACCEL_UUID1, `AFU_ACCEL_UUID2 };


    // ====================================================================
    //
    //  Add parent/child feature headers to the incoming FIM host channels.
    //
    // ====================================================================

    // New host channel wrappers -- the same interface as found in
    // plat_ifc.host_chan.ports. The PIM-provided wrapper around
    // the FIM's multi_link_afu_dfh module will connect the plat_ifc
    // ports to these new host_chan_with_dfh ports. All traffic other
    // than the MMIO associated with the AFU features will reach them.
    ofs_plat_host_chan_axis_pcie_tlp_if host_chan_with_dfh[1+NUM_CHILDREN]();

    // Instantiate the parent feature at MMIO offset 0. The parent feature
    // contains a parameter that lists the children. OPAE will discover the
    // parameter and load children along with the parent.
    //
    // This module acts as a shim that implements only the one DFL entry.
    // Other traffic to/from the AFU flows on host_chan_with_dfh.
    ofs_plat_host_chan_fim_multi_link_afu_dfh
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
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .to_afu(host_chan_with_dfh[0])
        );

    generate
        // Instantiate child features at MMIO offset 0 of the children.
        // The same module is used. When NUM_CHILDREN is not set (defaults
        // to 0), a child feature is constructed. Except for building
        // a different header, the behavior is similar to the parent.
        for (genvar p = 1; p <= NUM_CHILDREN; p = p + 1)
        begin : child
            ofs_plat_host_chan_fim_multi_link_afu_dfh
              #(
                .CSR_ADDR('h1000),
                .CSR_SIZE('h1000),
                .GUID_H(GUIDS[p][127:64]),
                .GUID_L(GUIDS[p][63:0])
                )
              feature
               (
                .to_fiu(plat_ifc.host_chan.ports[p]),
                .to_afu(host_chan_with_dfh[p])
                );
        end
    endgenerate


    // ====================================================================
    //
    //  PIM-based AFUs
    //
    // ====================================================================

    generate
        // Instantiate the hello world AFU on each port.
        for (genvar p = 0; p < 1 + NUM_CHILDREN; p = p + 1)
        begin : hello_afus
            // Instance of the PIM's standard AXI memory interface.
            ofs_plat_axi_mem_if
              #(
                // The PIM provides parameters for configuring a standard host
                // memory DMA AXI memory interface.
                `HOST_CHAN_AXI_MEM_PARAMS,
                // PIM interfaces can be configured to log traffic during
                // simulation. In ASE, see work/log_ofs_plat_host_chan.tsv.
                .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
                )
              host_mem();

            // Instance of the PIM's AXI memory lite interface, which will be
            // used to implement the AFU's CSR space.
            ofs_plat_axi_mem_lite_if
              #(
                // The AFU choses the data bus width of the interface and the
                // PIM adjusts the address space to match.
                `HOST_CHAN_AXI_MMIO_PARAMS(64),
                // Log MMIO traffic. (See the same parameter above on host_mem.)
                .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
                )
              mmio64_to_afu();

            // Map the port to AXI-MM.
            ofs_plat_host_chan_as_axi_mem_with_mmio primary_axi
               (
                .to_fiu(host_chan_with_dfh[p]),
                .host_mem_to_afu(host_mem),
                .mmio_to_afu(mmio64_to_afu),

                // These ports would be used if the PIM is told to cross to
                // a different clock. In this example, native pClk is used.
                .afu_clk(),
                .afu_reset_n()
                );


            //
            // Instantiate the hello world implementation
            //
            hello_world_axi
              #(
                // In the parent, number of children. In children, 0.
                .NUM_CHILDREN(p == 0 ? NUM_CHILDREN : 0),
                .ID(p)
                )
              hello_afu
               (
                .mmio64_to_afu,
                .host_mem
                );

        end // block: hello_afus
    endgenerate


    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    // The PIM ties off unused devices, controlled by the AFU indicating
    // which devices it is using. This way, an AFU must know only about
    // the devices it uses. Tie-offs are thus portable, with the PIM
    // managing devices unused by and unknown to the AFU.
    ofs_plat_if_tie_off_unused
      #(
        // Host channel group 0 port 0 is connected. The mask is a
        // bit vector of indices used by the AFU.
        .HOST_CHAN_IN_USE_MASK('b111)
        )
        tie_off(plat_ifc);

endmodule
