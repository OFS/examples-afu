

module dma_ddr_selector #(
   parameter ENABLE = 0,
   parameter NUM_LOCAL_MEM_BANKS = 1,
   parameter ADDR_WIDTH = 2
)(
   input dma_pkg::t_dma_descriptor descriptor,
   ofs_plat_axi_mem_if.to_source_clk selected_ddr_mem,
   ofs_plat_axi_mem_if.to_sink ddr_mem[NUM_LOCAL_MEM_BANKS]
);
   
//generate if (ENABLE) begin
// assign selected_ddr_mem.clk = ddr_mem[0].clk;
// assign selected_ddr_mem.reset_n = ddr_mem[0].reset_n;
// always_comb begin
//    selected_ddr_mem.arready = ddr_mem[0].arready;
//    selected_ddr_mem.rvalid  = ddr_mem[0].rvalid;
//    selected_ddr_mem.r       = ddr_mem[0].r;
//    selected_ddr_mem.awready = ddr_mem[0].awready;
//    selected_ddr_mem.wready  = ddr_mem[0].wready;
//    selected_ddr_mem.bvalid  = ddr_mem[0].bvalid;
//    selected_ddr_mem.b       = ddr_mem[0].b     ;
//    ddr_mem[0].arvalid = selected_ddr_mem.arvalid;
//    ddr_mem[0].ar      = selected_ddr_mem.ar;
//    ddr_mem[0].rready  = selected_ddr_mem.rready;
//    ddr_mem[0].awvalid = selected_ddr_mem.awvalid;
//    ddr_mem[0].aw      = selected_ddr_mem.aw;
//    ddr_mem[0].wvalid  = selected_ddr_mem.wvalid;
//    ddr_mem[0].w       = selected_ddr_mem.w;
//    ddr_mem[0].bready  = selected_ddr_mem.bready;
// end

// genvar i;
// generate
//    for (i = 1; i < NUM_LOCAL_MEM_BANKS; i = i + 1) begin : gen_ddr_mem_assignment
//       always_comb begin
//         ddr_mem[i].arvalid = 'b0;
//         ddr_mem[i].ar      = '0;
//         ddr_mem[i].rready  = 'b1;
//         ddr_mem[i].awvalid = 'b0;
//         ddr_mem[i].aw      = '0;
//         ddr_mem[i].wvalid  = 'b0;
//         ddr_mem[i].w       = '0;
//         ddr_mem[i].bready  = 'b1;
//       end
//    end
// endgenerate

//   end else begin
//     
       assign selected_ddr_mem.clk = ddr_mem[0].clk;
       assign selected_ddr_mem.reset_n = ddr_mem[0].reset_n;

       localparam SEL_WIDTH = $clog2(NUM_LOCAL_MEM_BANKS);
       logic [SEL_WIDTH:0] channel_select;

       always_comb begin
          channel_select = 'b0;
          case (descriptor.descriptor_control.mode) 
             dma_pkg::DDR_TO_HOST: begin 
                channel_select = descriptor.src_addr[ADDR_WIDTH-1 -: SEL_WIDTH];
             end

             dma_pkg::HOST_TO_DDR: begin 
                channel_select = descriptor.dest_addr[ADDR_WIDTH-1 -: SEL_WIDTH];
             end
         endcase
      end
      
       wire [NUM_LOCAL_MEM_BANKS-1:0] unified_arready;

       wire [NUM_LOCAL_MEM_BANKS-1:0] unified_rvalid;
       wire [$bits(selected_ddr_mem.r)-1:0][NUM_LOCAL_MEM_BANKS-1:0] unified_r;

       wire [NUM_LOCAL_MEM_BANKS-1:0] unified_awready;

       wire [NUM_LOCAL_MEM_BANKS-1:0] unified_wready;

       wire [NUM_LOCAL_MEM_BANKS-1:0] unified_bvalid;
       wire [$bits(selected_ddr_mem.b)-1:0][NUM_LOCAL_MEM_BANKS-1:0] unified_b;

       genvar i;
       genvar j;
        generate
            for (i = 0; i < NUM_LOCAL_MEM_BANKS; i++) begin : gen_ddr_assignment
                assign unified_arready[i]  = ddr_mem[i].arready;
                assign unified_rvalid[i]   = ddr_mem[i].rvalid;
                assign unified_awready[i]  = ddr_mem[i].awready;
                assign unified_wready[i]   = ddr_mem[i].wready;
                assign unified_bvalid[i]   = ddr_mem[i].bvalid;

                for (j = 0; j < $bits(selected_ddr_mem.r); j++) begin
                   assign unified_r[j][i]  = ddr_mem[i].r[j] & ddr_mem[i].rvalid;
                end

                for (j = 0; j < $bits(selected_ddr_mem.b); j++) begin
                   assign unified_b[j][i]  = ddr_mem[i].b[j] & ddr_mem[i].bvalid;
                end
            end
        endgenerate

        always_comb begin
          selected_ddr_mem.arready = &unified_arready;
          selected_ddr_mem.rvalid  = |unified_rvalid;
          selected_ddr_mem.awready = &unified_awready;
          selected_ddr_mem.wready  = &unified_wready;
          selected_ddr_mem.bvalid  = |unified_bvalid;
        end

        generate
            for (i = 0; i < $bits(selected_ddr_mem.r); i++) begin
                assign selected_ddr_mem.r[i] = |unified_r[i];
            end
        endgenerate

        generate
            for (i = 0; i < $bits(selected_ddr_mem.b); i++) begin
                assign selected_ddr_mem.b[i] = |unified_b[i];
            end
        endgenerate

       generate
          for (i = 0; i < NUM_LOCAL_MEM_BANKS; i = i + 1) begin : gen_ddr_mem_assignment
             always_comb begin
                   ddr_mem[i].arvalid = 'b0;
                   ddr_mem[i].ar      = 'b0;
                   ddr_mem[i].rready  = 'b1;
                   ddr_mem[i].awvalid = 'b0;
                   ddr_mem[i].aw      = 'b0;
                   ddr_mem[i].wvalid  = 'b0;
                   ddr_mem[i].w       = 'b0;
                   ddr_mem[i].bready  = 'b1;
                if (channel_select == i) begin
                   ddr_mem[i].arvalid = selected_ddr_mem.arvalid;
                   ddr_mem[i].ar      = selected_ddr_mem.ar;
                   ddr_mem[i].rready  = selected_ddr_mem.rready;
                   ddr_mem[i].awvalid = selected_ddr_mem.awvalid;
                   ddr_mem[i].aw      = selected_ddr_mem.aw;
                   ddr_mem[i].wvalid  = selected_ddr_mem.wvalid;
                   ddr_mem[i].w       = selected_ddr_mem.w;
                   ddr_mem[i].bready  = selected_ddr_mem.bready;
                end
             end
          end
       endgenerate
// endgenerate

endmodule : dma_ddr_selector
