// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "afu_json_info.vh"

//
// AXI-MM version of hello world AFU example.
//

module hello_world_axi
  #(
    parameter NUM_CHILDREN = 0,
    parameter ID = 0
    )
   (
    // CSR interface (MMIO on the host)
    ofs_plat_axi_mem_lite_if.to_source mmio64_to_afu,

    // Host memory (DMA)
    ofs_plat_axi_mem_if.to_sink host_mem
    );

    // Each interface names its associated clock and reset.
    logic clk;
    assign clk = host_mem.clk;
    logic reset_n;
    assign reset_n = host_mem.reset_n;

    localparam DATA_WIDTH = host_mem.DATA_WIDTH;

    // =========================================================================
    //
    //   CSR (MMIO) handling with AXI lite.
    //
    // =========================================================================

    //
    // The primary DFH with the AFU ID and the parent/child info is handled
    // already, outside this module. Only the CSR space to which the v1 DFH
    // points has to be managed here.
    //

    //
    // The AXI lite interface is defined in
    // $OPAE_PLATFORM_ROOT/hw/lib/build/platform/ofs_plat_if/rtl/base_ifcs/axi/ofs_plat_axi_mem_lite_if.sv.
    // It contains fields defined by the AXI standard, though organized
    // slightly unusually. Instead of being a flat data structure, the
    // payload for each bus is a struct. The name of the AXI field is the
    // concatenation of the struct instance and field. E.g., AWADDR is
    // aw.addr. The use of structs makes it easier to bulk copy or bulk
    // initialize the full payload of a bus.
    //

    // Use a copy of the MMIO interface as registers.
    ofs_plat_axi_mem_lite_if
      #(
        // PIM-provided macro to replicate identically sized instances of an
        // AXI lite interface.
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio64_to_afu)
        )
      mmio64_reg();

    // Is a CSR read request active this cycle? The test is simple because
    // the mmio64_reg.arvalid can only be set when the read response buffer
    // is empty.
    logic is_csr_read;
    assign is_csr_read = mmio64_reg.arvalid;

    // Is a CSR write request active this cycle?
    logic is_csr_write;
    assign is_csr_write = mmio64_reg.awvalid && mmio64_reg.wvalid;


    //
    // Receive MMIO read requests
    //

    // Ready for new request iff read request and response registers are empty
    assign mmio64_to_afu.arready = !mmio64_reg.arvalid && !mmio64_reg.rvalid;

    always_ff @(posedge clk)
    begin
        if (is_csr_read)
        begin
            // Current read request was handled
            mmio64_reg.arvalid <= 1'b0;
        end
        else if (mmio64_to_afu.arvalid && mmio64_to_afu.arready)
        begin
            // Receive new read request
            mmio64_reg.arvalid <= 1'b1;
            mmio64_reg.ar <= mmio64_to_afu.ar;
        end

        if (!reset_n) begin
            mmio64_reg.arvalid <= 1'b0;
        end
    end

    //
    // Completion data. The AFU's primary feature, including the AFU ID,
    // is implemented outside this module by ofs_fim_pcie_multi_link_afu_dfh().
    // MMIO reads here are to addresses outside that feature.
    //
    assign mmio64_to_afu.rvalid = mmio64_reg.rvalid;
    assign mmio64_to_afu.r = mmio64_reg.r;

    always_ff @(posedge clk)
    begin
        if (is_csr_read)
        begin
            // New read response
            mmio64_reg.rvalid <= 1'b1;

            mmio64_reg.r <= '0;
            // The unique transaction ID matches responses to requests
            mmio64_reg.r.id <= mmio64_reg.ar.id;
            // Return user flags from request
            mmio64_reg.r.user <= mmio64_reg.ar.user;

            // AXI addresses are always in byte address space. Ignore the
            // low 3 bits to index 64 bit CSRs.
            // Check only a few address bits to simplify the decoder.
            // There will be multiple address aliases within the full MMIO space.
            case (mmio64_reg.ar.addr[5:3])
              // Parents: number of children.
              // Children: 0
              0: mmio64_reg.r.data <= NUM_CHILDREN;

              // Data bus width (bytes)
              1: mmio64_reg.r.data <= DATA_WIDTH / 8;

              default: mmio64_reg.r.data <= '0;
            endcase
        end
        else if (mmio64_to_afu.rready)
        begin
            // If a read response was pending it completed
            mmio64_reg.rvalid <= 1'b0;
        end

        if (!reset_n)
        begin
            mmio64_reg.rvalid <= 1'b0;
        end
    end


    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //

    // Ready for new request iff write request register is empty
    assign mmio64_to_afu.awready = !mmio64_reg.awvalid && !mmio64_reg.bvalid;
    assign mmio64_to_afu.wready  = !mmio64_reg.wvalid && !mmio64_reg.bvalid;

    always_ff @(posedge clk)
    begin
        if (is_csr_write)
        begin
            // Current write request was handled
            mmio64_reg.awvalid <= 1'b0;
            mmio64_reg.wvalid <= 1'b0;
        end
        else
        begin
            // Receive new write address
            if (mmio64_to_afu.awvalid && mmio64_to_afu.awready)
            begin
                mmio64_reg.awvalid <= 1'b1;
                mmio64_reg.aw <= mmio64_to_afu.aw;
            end

            // Receive new write data
            if (mmio64_to_afu.wvalid && mmio64_to_afu.wready)
            begin
                mmio64_reg.wvalid <= 1'b1;
                mmio64_reg.w <= mmio64_to_afu.w;
            end
        end

        if (!reset_n)
        begin
            mmio64_reg.awvalid <= 1'b0;
            mmio64_reg.wvalid <= 1'b0;
        end
    end

    // Write response
    assign mmio64_to_afu.bvalid = mmio64_reg.bvalid;
    assign mmio64_to_afu.b = mmio64_reg.b;

    always_ff @(posedge clk)
    begin
        if (is_csr_write)
        begin
            // New write response
            mmio64_reg.bvalid <= 1'b1;

            mmio64_reg.b <= '0;
            mmio64_reg.b.id <= mmio64_reg.aw.id;
            mmio64_reg.b.user <= mmio64_reg.aw.user;
        end
        else if (mmio64_to_afu.bready)
        begin
            // If a write response was pending it completed
            mmio64_reg.bvalid <= 1'b0;
        end

        if (!reset_n)
        begin
            mmio64_reg.bvalid <= 1'b0;
        end
    end

    // We use MMIO address 0 to set the memory address.  The read and
    // write MMIO spaces are logically separate so we are free to use
    // whatever we like.  This may not be good practice for cleanly
    // organizing the MMIO address space, but it is legal.
    logic is_mem_addr_csr_write;
    assign is_mem_addr_csr_write = is_csr_write && (mmio64_reg.aw.addr == '0);

    // DMA address to which this AFU will write.
    localparam MEM_ADDR_WIDTH = host_mem.ADDR_WIDTH;
    typedef logic [MEM_ADDR_WIDTH-1 : 0] t_mem_addr;
    t_mem_addr mem_addr;

    always_ff @(posedge clk)
    begin
        if (is_mem_addr_csr_write)
        begin
            // The host passed in a line address. AXI-MM wants byte-level.
            mem_addr <= t_mem_addr'({ mmio64_reg.w.data, 6'b0 });
        end
    end


    // =========================================================================
    //
    //   Main AFU logic
    //
    // =========================================================================

    //
    // States in our simple example. In an AFU where performance matters
    // we would write to both data and address buses in parallel. For
    // simplicity here we will write to them in different states.
    //
    typedef enum logic [1:0]
    {
        STATE_IDLE,
        STATE_ADDR,
        STATE_DATA
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
                state <= STATE_ADDR;
                $display("AFU running...");
            end

            // Sit in STATE_ADDR until the address is written to the DMA
            // interface.
            if ((state == STATE_ADDR) && host_mem.awready)
            begin
                state <= STATE_DATA;
            end

            // The AFU completes its task by writing a single line.  When
            // the line is written return to idle.  The write will happen
            // as long as the request channel is not full.
            if ((state == STATE_DATA) && host_mem.wready)
            begin
                state <= STATE_IDLE;
                $display("AFU done...");
            end
        end
    end

    //
    // Write address of line when in STATE_ADDR.
    //
    always_comb
    begin
        host_mem.awvalid = (state == STATE_ADDR);
        host_mem.aw = '0;
        host_mem.aw.addr = mem_addr;
        host_mem.aw.size = 3'b110;	// 64 bytes
    end

    //
    // Write "Hello world (<ID>)" to memory when in STATE_DATA.
    //
    always_comb
    begin
        host_mem.wvalid = (state == STATE_DATA);
        host_mem.w = '0;
        // "Hello world (<ID>)", ASCII encoded and backwards. Each instance
        // of this module is instantiated with a unique ID.
        host_mem.w.data = { '0, 16'h0029, 8'('h30 + ID), 104'h2820646c726f77206f6c6c6548 };
        host_mem.w.strb = ~64'b0;	// Byte mask (enable all)
    end


    //
    // This AFU never makes a read request and ignores write responses.
    //
    assign host_mem.arvalid = 1'b0;
    assign host_mem.rready = 1'b1;
    assign host_mem.bready = 1'b1;

endmodule
