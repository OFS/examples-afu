// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Top level PIM-based module.
//

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    // ====================================================================
    //
    //  Get an Avalon-MM host channel connection from the platform.
    //
    // ====================================================================

    // Instance of the PIM's standard Avalon memory interface. The DMA
    // interface exposed by the PIM splits the read and write buses into
    // separate channels. This split bus matches the topologies of the
    // equivalent AXI-MM and CCI-P interfaces. It also offers greater
    // throughput than a shared read/write bus.
    ofs_plat_avalon_mem_rdwr_if
      #(
        // The PIM provides parameters for configuring a standard host
        // memory DMA Avalon memory interface.
        `HOST_CHAN_AVALON_MEM_RDWR_PARAMS,
        // PIM interfaces can be configured to log traffic during
        // simulation. In ASE, see work/log_ofs_plat_host_chan.tsv.
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
      host_mem();

    // Instance of the PIM's Avalon interface, which will be used to
    // implement the AFU's CSR space.
    ofs_plat_avalon_mem_if
      #(
        // The AFU choses the data bus width of the interface and the
        // PIM adjusts the address space to match.
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        // Log MMIO traffic. (See the same parameter above on host_mem.)
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();

    // Use the platform-provided module to map the primary host interface
    // to Avalon-MM. The "primary" interface is the port that includes the
    // main OPAE-managed MMIO connection. This primary port is always
    // index 0 of plat_ifc.host_chan.ports, indepedent of the platform
    // and the native protocol of the host channel. This same module
    // name is available both on platforms that expose AXI-S PCIe TLP
    // streams to the AFU and on platforms that expose CCI-P.
    ofs_plat_host_chan_as_avalon_mem_rdwr_with_mmio primary_avalon
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu(host_mem),
        .mmio_to_afu(mmio64_to_afu),

        // These ports would be used if the PIM is told to cross to
        // a different clock. In this example, native pClk is used.
        .afu_clk(),
        .afu_reset_n()
        );


    // Each interface names its associated clock and reset.
    logic clk;
    assign clk = host_mem.clk;
    logic reset_n;
    assign reset_n = host_mem.reset_n;


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
        .HOST_CHAN_IN_USE_MASK(1)
        )
        tie_off(plat_ifc);


    // =========================================================================
    //
    //   Instantiate the hello world implementation
    //
    // =========================================================================

    hello_world_avalon hello_afu
       (
        .mmio64_to_afu,
        .host_mem
        );

endmodule
