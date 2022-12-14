// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "afu_json_info.vh"

//
// CCI-P version of hello world AFU example.
//

module hello_world_ccip
   (
    // CCI-P interface
    ofs_plat_host_ccip_if.to_fiu host_ccip
    );

    logic clk;
    assign clk = host_ccip.clk;
    logic reset_n;
    assign reset_n = host_ccip.reset_n;


    // =========================================================================
    //
    //   CSR (MMIO) handling.
    //
    // =========================================================================

    // The AFU ID is a unique ID for a given program.  Here we generated
    // one with the "uuidgen" program and stored it in the AFU's JSON file.
    // ASE and synthesis setup scripts automatically invoke afu_json_mgr
    // to extract the UUID into afu_json_info.vh.
    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    //
    // A valid AFU must implement a device feature list, starting at MMIO
    // address 0.  Every entry in the feature list begins with 5 64-bit
    // words: a device feature header, two AFU UUID words and two reserved
    // words.
    //

    // Is a CSR read request active this cycle?
    logic is_csr_read;
    assign is_csr_read = host_ccip.sRx.c0.mmioRdValid;

    // Is a CSR write request active this cycle?
    logic is_csr_write;
    assign is_csr_write = host_ccip.sRx.c0.mmioWrValid;

    // The MMIO request header is overlayed on the normal c0 memory read
    // response data structure.  Cast the c0Rx header to an MMIO request
    // header.
    t_ccip_c0_ReqMmioHdr mmio_req_hdr;
    assign mmio_req_hdr = t_ccip_c0_ReqMmioHdr'(host_ccip.sRx.c0.hdr);


    //
    // Implement the device feature list by responding to MMIO reads.
    //

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            host_ccip.sTx.c2.mmioRdValid <= 1'b0;
        end
        else
        begin
            // Always respond with something for every read request
            host_ccip.sTx.c2.mmioRdValid <= is_csr_read;

            // The unique transaction ID matches responses to requests
            host_ccip.sTx.c2.hdr.tid <= mmio_req_hdr.tid;

            // Addresses are of 32-bit objects in MMIO space.  Addresses
            // of 64-bit objects are thus multiples of 2.
            case (mmio_req_hdr.address)
              0: // AFU DFH (device feature header)
                begin
                    // Here we define a trivial feature list.  In this
                    // example, our AFU is the only entry in this list.
                    host_ccip.sTx.c2.data <= t_ccip_mmioData'(0);
                    // Feature type is AFU
                    host_ccip.sTx.c2.data[63:60] <= 4'h1;
                    // End of list (last entry in list)
                    host_ccip.sTx.c2.data[40] <= 1'b1;
                end

              // AFU_ID_L
              2: host_ccip.sTx.c2.data <= afu_id[63:0];

              // AFU_ID_H
              4: host_ccip.sTx.c2.data <= afu_id[127:64];

              // DFH_RSVD0
              6: host_ccip.sTx.c2.data <= t_ccip_mmioData'(0);

              // DFH_RSVD1
              8: host_ccip.sTx.c2.data <= t_ccip_mmioData'(0);

              default: host_ccip.sTx.c2.data <= t_ccip_mmioData'(0);
            endcase
        end
    end


    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //

    // We use MMIO address 0 to set the memory address.  The read and
    // write MMIO spaces are logically separate so we are free to use
    // whatever we like.  This may not be good practice for cleanly
    // organizing the MMIO address space, but it is legal.
    logic is_mem_addr_csr_write;
    assign is_mem_addr_csr_write = is_csr_write &&
                                   (mmio_req_hdr.address == t_ccip_mmioAddr'(0));

    // Memory address to which this AFU will write.
    t_ccip_clAddr mem_addr;

    always_ff @(posedge clk)
    begin
        if (is_mem_addr_csr_write)
        begin
            mem_addr <= t_ccip_clAddr'(host_ccip.sRx.c0.data);
        end
    end
    


    // =========================================================================
    //
    //   Main AFU logic
    //
    // =========================================================================

    //
    // States in our simple example.
    //
    typedef enum logic [0:0]
    {
        STATE_IDLE,
        STATE_RUN
    }
    t_state;

    t_state state;

    //
    // State machine
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;
        end
        else
        begin
            // Trigger the AFU when mem_addr is set above.  (When the CPU
            // tells us the address to which the FPGA should write a message.)
            if ((state == STATE_IDLE) && is_mem_addr_csr_write)
            begin
                state <= STATE_RUN;
                $display("AFU running...");
            end

            // The AFU completes its task by writing a single line.  When
            // the line is written return to idle.  The write will happen
            // as long as the request channel is not full.
            if ((state == STATE_RUN) && ! host_ccip.sRx.c1TxAlmFull)
            begin
                state <= STATE_IDLE;
                $display("AFU done...");
            end
        end
    end


    //
    // Write "Hello world!" to memory when in STATE_RUN.
    //

    // Construct a memory write request header.  For this AFU it is always
    // the same, since we write to only one address.
    t_ccip_c1_ReqMemHdr wr_hdr;
    always_comb
    begin
        // Zero works for most write request header fields in this example
        wr_hdr = t_ccip_c1_ReqMemHdr'(0);
        // Set the write address
        wr_hdr.address = mem_addr;
        // Start of packet is always set for single beat writes
        wr_hdr.sop = 1'b1;
    end

    // Data to write to memory: little-endian ASCII encoding of "Hello world!"
    assign host_ccip.sTx.c1.data = t_ccip_clData'('h0021646c726f77206f6c6c6548);

    // Control logic for memory writes
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            host_ccip.sTx.c1.valid <= 1'b0;
        end
        else
        begin
            // Request the write as long as the channel isn't full.
            host_ccip.sTx.c1.valid <= ((state == STATE_RUN) &&
                                       ! host_ccip.sRx.c1TxAlmFull);
        end

        host_ccip.sTx.c1.hdr <= wr_hdr;
    end


    //
    // This AFU never makes a read request.
    //
    assign host_ccip.sTx.c0.valid = 1'b0;

endmodule
