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

    // *** When OFS_PLAT_HOST_CHAN_MULTIPLEXED is defined in the project
    // (from the AFU JSON file), host channels remain multiplexed.
    // Each host channel port corresponds to a separate multiplexed
    // physical channel. For example, a platform with a single Gen5x16
    // PCIe link will have a single host channel -- independent of the
    // PF/VF settings. A platform with a pair of bifurcated Gen5x8
    // links will have two multiplexed host channels.
    //
    // The example here will connect a hello world engine to each
    // virtual channel within each physical host channel.
    localparam NUM_HOST_CHAN = `OFS_PLAT_PARAM_HOST_CHAN_NUM_MULTIPLEXED_PORTS;

    // ====================================================================
    //
    //  Get an AXI-MM host channel connection from the platform.
    //
    // ====================================================================

    // Instance of the PIM's standard AXI memory interface. One for each
    // physical host channel.
    ofs_plat_axi_mem_if
      #(
        // The PIM provides parameters for configuring a standard host
        // memory DMA AXI memory interface.
        `HOST_CHAN_AXI_MEM_PARAMS,

        // *** Required for PIM with virtual channels ***
        // Virtual channel tags are stored in AXI-MM user flags. The PIM provides
        // a data structure for all PIM user flags. USER_WIDTH must be set at
        // least as large as the PIM's structure.
        .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_WITH_VCHAN_WIDTH),

        // PIM interfaces can be configured to log traffic during
        // simulation. In ASE, see work/log_ofs_plat_host_chan.tsv.
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
      host_mem[NUM_HOST_CHAN]();

    // Instance of the PIM's AXI memory lite interface, which will be used
    // to implement the AFU's CSR space. One for each physical host channel.
    ofs_plat_axi_mem_lite_if
      #(
        // The AFU choses the data bus width of the interface and the
        // PIM adjusts the address space to match.
        `HOST_CHAN_AXI_MMIO_PARAMS(64),

        // *** Required for PIM with virtual channels ***
        // Virtual channel tags are stored in AXI-MM user flags. The PIM provides
        // a data structure for all PIM user flags.
        .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_MMIO_UFLAG_WITH_VCHAN_WIDTH),

        // Log MMIO traffic. (See the same parameter above on host_mem.)
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu[NUM_HOST_CHAN]();

    // *** Multiplexed host channel to AXI-MM mapping with virtual channels ***
    // The module instantiation is identical to the non-mulitplexed version.
    // The internal behavior changes as a result of the OFS_PLAT_HOST_CHAN_MULTIPLEXED
    // Verilog macro being defined. Because of the macro:
    //  - The OFS FIM's afu_main() module does not add a PF/VF MUX and
    //    leaves all PCIe traffic multiplexed with SR-IOV tags.
    //  - The PIM module here maps the device-specific channel tags to
    //    generic PIM-generated virtual channel IDs.
    //
    // Instantiate one PIM AXI-MM to host channel mapping for each multiplexed
    // host channel. Traffic will remain multiplexed in host_mem and mmio64_to_afu.
    for (genvar hc = 0; hc < NUM_HOST_CHAN; hc += 1) begin : pim
        ofs_plat_host_chan_as_axi_mem_with_mmio
          #(
            // Map host_mem and mmio64_to_afu to user clock
            .ADD_CLOCK_CROSSING(1)
            )
          primary_axi
           (
            .to_fiu(plat_ifc.host_chan.ports[hc]),
            .host_mem_to_afu(host_mem[hc]),
            .mmio_to_afu(mmio64_to_afu[hc]),

            // *** Cross to user clock. The standard plat_ifc.clocks.ports
            // hold resets for each multiplexed physical host channel.
            // They do not include soft resets specific to virtual channels.
            // Those are managed separately, below.
            .afu_clk(plat_ifc.clocks.ports[hc].uClk_usr.clk),
            .afu_reset_n(plat_ifc.clocks.ports[hc].uClk_usr.reset_n)
            );
    end


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
        // All available host channels are mapped to the hello world AFU.
        .HOST_CHAN_IN_USE_MASK(-1)
        )
        tie_off(plat_ifc);


    // =========================================================================
    //
    //   Instantiate the hello world implementation
    //
    // =========================================================================

    // *** PIM-provided macro with the number of virtual channels per physical
    // channel. On PCIe this corresponds to the number of PF/VF tags per link.
    localparam NUM_VCHAN_PER_PORT = `OFS_PLAT_PARAM_HOST_CHAN_NUM_CHAN_PER_MULTIPLEXED_PORT;

    // Separate networks for each physical host channel
    for (genvar hc = 0; hc < NUM_HOST_CHAN; hc += 1) begin : per_hc

        // *** Declare AXI-MM (host memory) and AXI-Lite (MMIO) interfaces
        // for each individual virtual channel. These are exactly the same
        // interfaces used by the multiplexed channels -- just more of them.
        // Like the multiplexed ports, virtual channel tags must be allocated
        // in AXI user fields.
        ofs_plat_axi_mem_lite_if
          #(
            `HOST_CHAN_AXI_MMIO_PARAMS(64),
            .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_MMIO_UFLAG_WITH_VCHAN_WIDTH),
            .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
            )
          mmio64_ports[NUM_VCHAN_PER_PORT]();

        ofs_plat_axi_mem_if
          #(
            `HOST_CHAN_AXI_MEM_PARAMS,
            .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_WITH_VCHAN_WIDTH),
            .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
            )
          host_mem_ports[NUM_VCHAN_PER_PORT]();


        // *** Demultiplex MMIO AXI-Lite virtual channels within one host channel.
        // Each virtual channel now has its own interface in mmio64_ports.
        // 
        // The PIM generates a multiplexer for each AXI memory channel from AFU to FIM
        // and a demultiplexer for each channel from FIM to AFU. The complexity
        // of each network will depend on the number of ports and data widths.
        ofs_plat_host_chan_axi_mem_lite_if_vchan_mux
          #(
            .NUM_AFU_PORTS(NUM_VCHAN_PER_PORT)
            )
          mmio64_mux
           (
            // Multiplexed FIM side
            .host_mmio(mmio64_to_afu[hc]),
            // Demultiplexed AFU side. Clock and reset are not set yet. See below.
            .afu_mmio(mmio64_ports)
            );

        ofs_plat_host_chan_axi_mem_if_vchan_mux
          #(
            .NUM_AFU_PORTS(NUM_VCHAN_PER_PORT)
            )
          host_mem_mux
           (
            // Multiplexed FIM side
            .host_mem(host_mem[hc]),
            // Demultiplexed AFU side. Clock and reset are not set yet. See below.
            .afu_mem(host_mem_ports)
            );


        // *** Map each virtual channel port to a hello world engine
        for (genvar p = 0; p < NUM_VCHAN_PER_PORT; p = p + 1) begin
            // ** The PIM provides clocks with demultiplexed soft resets.
            // Since each soft reset corresponds to a single virtual channel
            // it can not be bound to multiplexed channels. Bind virtual
            // channel soft resets to each interface.
            assign mmio64_ports[p].clk = plat_ifc.clocks.demux_ports[hc][p].uClk_usr.clk;
            assign mmio64_ports[p].reset_n = plat_ifc.clocks.demux_ports[hc][p].uClk_usr.reset_n;
            assign mmio64_ports[p].instance_number = p;

            assign host_mem_ports[p].clk = plat_ifc.clocks.demux_ports[hc][p].uClk_usr.clk;
            assign host_mem_ports[p].reset_n = plat_ifc.clocks.demux_ports[hc][p].uClk_usr.reset_n;
            assign host_mem_ports[p].instance_number = p;

            // *** Instantiate hello world on a single virtual channel.
            // PIM virtual channel numbering has the following properties:
            //  - Virtual channel numbers are dense, starting with 0. The
            //    PIM maintains a private dense channel numbering space,
            //    even if the physical channel's tags are more complicated.
            //  - The PIM virtual channel numbering is local to a single
            //    physical channel. For a system with two PCIe links,
            //    both link 0 and link 1 start their virtual channel numbers
            //    at zero.
            hello_world_axi
              #(
                // Hello world must tag all requests with a virtual channel
                .VCHAN_NUM(p),

                // Used only for printing the physical channel number in the
                // output message.
                .PHYS_CHAN_NUM(hc)
                )
              hello_afu
               (
                .mmio64_to_afu(mmio64_ports[p]),
                .host_mem(host_mem_ports[p])
                );
        end

    end // block: per_hc

endmodule
