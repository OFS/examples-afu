// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// A very simple implemenation of hello world on PCIe SS TLP encoded AXI
// streams. The implementation here is not pipelined and generates only
// very short data writes. It demonstrates the mechanics of the minimally
// required transactions to receive a command that triggers a request
// from the FPGA.
//

module hello_world_multi
  #(
    parameter pcie_ss_hdr_pkg::ReqHdr_pf_num_t PF_ID,
    parameter pcie_ss_hdr_pkg::ReqHdr_vf_num_t VF_ID,
    parameter logic VF_ACTIVE,
    parameter NUM_CHILDREN = 0,
    parameter ID = 0
    )  
   (
    input  logic clk,
    input  logic rst_n,

    pcie_ss_axis_if.sink   i_rx_if,
    pcie_ss_axis_if.source o_tx_if,

    // These ports will be tied off and not used
    pcie_ss_axis_if.sink   i_rx_b_if,
    pcie_ss_axis_if.source o_tx_b_if
    );

    //
    // Watch for MMIO read requests on the RX stream.
    //

    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t rx_hdr;
    logic [255:0] rx_data;
    logic rx_hdr_valid;
    logic rx_sop;

    assign i_rx_if.tready = !rx_hdr_valid;

    // Incoming MMIO read?
    always_ff @(posedge clk)
    begin
        if (i_rx_if.tready)
        begin
            rx_hdr_valid <= 1'b0;

            if (i_rx_if.tvalid)
            begin
                rx_sop <= i_rx_if.tlast;

                // Only power user mode requests are detected. CSR requests
                // from the host will always be PU encoded.
                if (rx_sop && pcie_ss_hdr_pkg::func_hdr_is_pu_mode(i_rx_if.tuser_vendor))
                begin
                    {rx_data, rx_hdr} <= i_rx_if.tdata;
                    rx_hdr_valid <= 1'b1;
                end
            end
        end
        else if (o_tx_if.tready)
        begin
            // If a request was present, it was consumed
            rx_hdr_valid <= 1'b0;
        end

        if (!rst_n)
        begin
            rx_hdr_valid <= 1'b0;
            rx_sop <= 1'b1;
        end
    end

    // Construct MMIO completion in response to RX read request
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t tx_cpl_hdr;
    localparam TX_CPL_HDR_BYTES = $bits(pcie_ss_hdr_pkg::PCIe_PUCplHdr_t) / 8;

    always_comb
    begin
        // Build the header -- always the same for any address
        tx_cpl_hdr = '0;
        tx_cpl_hdr.fmt_type = pcie_ss_hdr_pkg::ReqHdr_FmtType_e'(pcie_ss_hdr_pkg::PCIE_FMTTYPE_CPLD);
        tx_cpl_hdr.length = rx_hdr.length;
        tx_cpl_hdr.req_id = rx_hdr.req_id;
        tx_cpl_hdr.tag_h = rx_hdr.tag_h;
        tx_cpl_hdr.tag_m = rx_hdr.tag_m;
        tx_cpl_hdr.tag_l = rx_hdr.tag_l;
        tx_cpl_hdr.TC = rx_hdr.TC;
        tx_cpl_hdr.byte_count = rx_hdr.length << 2;
        tx_cpl_hdr.low_addr[6:2] =
            pcie_ss_hdr_pkg::func_is_addr64(rx_hdr.fmt_type) ?
                rx_hdr.host_addr_l[4:0] : rx_hdr.host_addr_h[6:2];

        tx_cpl_hdr.comp_id = { VF_ID, VF_ACTIVE, PF_ID };
        tx_cpl_hdr.pf_num = PF_ID;
        tx_cpl_hdr.vf_num = VF_ID;
        tx_cpl_hdr.vf_active = VF_ACTIVE;
    end

    logic [63:0] cpl_data;

    //
    // Completion data. The AFU's primary feature, including the AFU ID,
    // is implemented outside this module by ofs_fim_pcie_multi_link_afu_dfh().
    // MMIO reads here are to addresses outside that feature.
    //
    always_comb
    begin
        // Check only a few address bits to simplify the decoder.
        // There will be multiple address aliases within the full MMIO space.
        case (tx_cpl_hdr.low_addr[6:3])
            // Parents: number of children.
            // Children: 0
            4'h0: cpl_data = NUM_CHILDREN;

            // Data bus width (bytes)
            4'h1: cpl_data = $bits(o_tx_if.tdata) / 8;

            default: cpl_data = '0;
        endcase

        // Was the request short, asking for the high 32 bits of the 64 bit register?
        if (tx_cpl_hdr.low_addr[2])
        begin
            cpl_data[31:0] = cpl_data[63:32];
        end
    end


    //
    // Generate a DMA write with the string in response to a
    // CSR write to any address. The payload of the CSR write holds the line offset
    // to which the string should be written.
    //
    // Of course a real AFU would have to decode the address of the CSR write
    // if it has more than 1 CSR.
    //
    wire gen_dma_write = rx_hdr_valid && pcie_ss_hdr_pkg::func_is_mwr_req(rx_hdr.fmt_type);
    pcie_ss_hdr_pkg::PCIe_ReqHdr_t tx_wr_hdr;

    // Data mover write request header to the address that just arrived in the
    // payload of an incoming CSR write.
    always_comb
    begin
        tx_wr_hdr = '0;
        tx_wr_hdr.fmt_type = pcie_ss_hdr_pkg::DM_WR;
        tx_wr_hdr.pf_num = PF_ID;
        tx_wr_hdr.vf_num = VF_ID;
        tx_wr_hdr.vf_active = VF_ACTIVE;
        {tx_wr_hdr.length_h, tx_wr_hdr.length_m, tx_wr_hdr.length_l} = 20; // Bytes
        // The incoming address is the offset of 512 bit lines. Shift it left
        // because DM encoding expects a byte address.
        {tx_wr_hdr.host_addr_h, tx_wr_hdr.host_addr_m, tx_wr_hdr.host_addr_l} =
            {rx_data[57:0], 6'b0};
    end


    // Generate traffic toward the host for CSR read response and writing
    // the hello world message.
    always_comb
    begin
        o_tx_if.tvalid = (rx_hdr_valid &&
                        pcie_ss_hdr_pkg::func_is_mrd_req(rx_hdr.fmt_type)) || gen_dma_write;
        if (!gen_dma_write)
        begin
            //
            // CSR read response
            //

            o_tx_if.tdata = { '0, cpl_data, tx_cpl_hdr };
            o_tx_if.tlast = 1'b1;
            o_tx_if.tuser_vendor = '0;
            // Keep matches the data: either 8 or 4 bytes of data and the header
            o_tx_if.tkeep = { '0, {4{(rx_hdr.length > 1)}}, {4{1'b1}}, {TX_CPL_HDR_BYTES{1'b1}} };
        end
        else
        begin
            //
            // DMA write with "Hello world TLP!" payload. The payload and header
            // fit in a single message, which simplifies the logic here.
            //

            // "Hello world (<ID>)", ASCII encoded and backwards. Each instance
            // of this module is instantiated with a unique ID.
            o_tx_if.tdata = { '0, 16'h0029, 8'('h30 + ID), 104'h2820646c726f77206f6c6c6548, tx_wr_hdr };
            o_tx_if.tlast = 1'b1;
            o_tx_if.tuser_vendor = 1;	// Data mover encoding
            o_tx_if.tkeep = { '0, {20{1'b1}}, {TX_CPL_HDR_BYTES{1'b1}} };
        end
    end

    // Tie off the B ports
    assign i_rx_b_if.tready = 1'b1;
    assign o_tx_b_if.tvalid = 1'b0;

endmodule
