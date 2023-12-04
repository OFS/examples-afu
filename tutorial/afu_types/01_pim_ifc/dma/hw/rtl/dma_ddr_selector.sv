

module dma_ddr_selector #(
   parameter NUM_LOCAL_MEM_BANKS = 1,
   parameter ADDR_WIDTH = 2
)(
   input dma_pkg::t_dma_descriptor descriptor,
   ofs_plat_axi_mem_if.to_source selected_ddr_mem,
   ofs_plat_axi_mem_if.to_sink ddr_mem[NUM_LOCAL_MEM_BANKS]
);

   localparam SEL_WIDTH = $clog2(ADDR_WIDTH);
   logic [SEL_WIDTH:0] channel_select;

   always_comb begin
     case (descriptor.descriptor_control.mode) 
         dma_pkg::DDR_TO_HOST: begin 
            channel_select = descriptor.src_addr[ADDR_WIDTH-1 -: SEL_WIDTH];
         end

         dma_pkg::HOST_TO_DDR: begin 
            channel_select = descriptor.dest_addr[ADDR_WIDTH-1 -: SEL_WIDTH];
         end
 
         default: begin 
            channel_select = {SEL_WIDTH{1'b1}};
         end

     endcase
  end
  
   wire [NUM_LOCAL_MEM_BANKS-1:0] unified_arready;

   wire [NUM_LOCAL_MEM_BANKS-1:0] unified_rvalid;
   wire [NUM_LOCAL_MEM_BANKS-1:0][dma_pkg::DDR_DATA_W-1:0] unified_r;

   wire [NUM_LOCAL_MEM_BANKS-1:0] unified_awready;

   wire [NUM_LOCAL_MEM_BANKS-1:0] unified_wready;

   wire [NUM_LOCAL_MEM_BANKS-1:0] unified_bvalid;
   wire [NUM_LOCAL_MEM_BANKS-1:0] [dma_pkg::DDR_DATA_W-1:0] unified_b;

   genvar i;
    generate
        for (i = 0; i < NUM_LOCAL_MEM_BANKS; i++) begin : gen_ddr_assignment
            assign unified_arready[i]  = ddr_mem[i].arready;
            assign unified_rvalid[i]   = ddr_mem[i].rvalid;
            assign unified_awready[i]  = ddr_mem[i].awready;
            assign unified_wready[i]   = ddr_mem[i].wready;
            assign unified_bvalid[i]   = ddr_mem[i].bvalid;
            assign unified_r[i]        = ddr_mem[i].r;
            assign unified_b[i]        = ddr_mem[i].b;
        end
    endgenerate

    always_comb begin
      selected_ddr_mem.arready = &unified_arready;
      selected_ddr_mem.rvalid  = |unified_rvalid;
      selected_ddr_mem.awready = &unified_awready;
      selected_ddr_mem.wready  = &unified_wready;
      selected_ddr_mem.bvalid  = |unified_bvalid;
    end

   genvar i;
    generate
        for (i = 0; i < dma_pkg::DDR_DATA_W; i++) begin
            assign selected_ddr_mem.r[i] = |unified_r[i];
            assign selected_ddr_mem.b[i] = |unified_b[i];
        end
    endgenerate

   genvar i;
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


   // always_comb begin : if1
   //    if(channel_select == 0) begin
   //       ddr_mem[0].arvalid = selected_ddr_mem.arvalid;
   //       selected_ddr_mem.arready = ddr_mem[0].arready;
   //       ddr_mem[0].ar      = selected_ddr_mem.ar;

   //       selected_ddr_mem.rvalid = ddr_mem[0].rvalid;
   //       ddr_mem[0].rready  = selected_ddr_mem.rready;
   //       selected_ddr_mem.r = ddr_mem[0].r;

   //       ddr_mem[0].awvalid = selected_ddr_mem.awvalid;
   //       selected_ddr_mem.awready = ddr_mem[0].awready;
   //       ddr_mem[0].aw      = selected_ddr_mem.aw;

   //       ddr_mem[0].wvalid  = selected_ddr_mem.wvalid;
   //       selected_ddr_mem.wready = ddr_mem[0].wready;
   //       ddr_mem[0].w       = selected_ddr_mem.w;

   //       selected_ddr_mem.bvalid = ddr_mem[0].bvalid;
   //       ddr_mem[0].bready  = selected_ddr_mem.bready;
   //       selected_ddr_mem.b = ddr_mem[0].b;

   //       ddr_mem[1].arvalid = 'b0;
   //       ddr_mem[1].ar      = 'b0;
   //       ddr_mem[1].rready  = 'b0;
   //       ddr_mem[1].awvalid = 'b0;
   //       ddr_mem[1].aw      = 'b0;
   //       ddr_mem[1].wvalid  = 'b0;
   //       ddr_mem[1].w       = 'b0;
   //       ddr_mem[1].bready  = 'b0;

   //    end else if (channel_select == 1) begin
               
   //       ddr_mem[1].arvalid = selected_ddr_mem.arvalid;
   //       selected_ddr_mem.arready = ddr_mem[1].arready;
   //       ddr_mem[1].ar      = selected_ddr_mem.ar;

   //       selected_ddr_mem.rvalid = ddr_mem[1].rvalid;
   //       ddr_mem[1].rready  = selected_ddr_mem.rready;
   //       selected_ddr_mem.r = ddr_mem[1].r;

   //       ddr_mem[1].awvalid = selected_ddr_mem.awvalid;
   //       selected_ddr_mem.awready = ddr_mem[1].awready;
   //       ddr_mem[1].aw      = selected_ddr_mem.aw;

   //       ddr_mem[1].wvalid  = selected_ddr_mem.wvalid;
   //       selected_ddr_mem.wready = ddr_mem[1].wready;
   //       ddr_mem[1].w       = selected_ddr_mem.w;

   //       selected_ddr_mem.bvalid = ddr_mem[1].bvalid;
   //       ddr_mem[1].bready  = selected_ddr_mem.bready;
   //       selected_ddr_mem.b = ddr_mem[1].b;

   //       ddr_mem[0].arvalid = 'b0;
   //       ddr_mem[0].ar      = 'b0;
   //       ddr_mem[0].rready  = 'b1;
   //       ddr_mem[0].awvalid = 'b0;
   //       ddr_mem[0].aw      = 'b0;
   //       ddr_mem[0].wvalid  = 'b0;
   //       ddr_mem[0].w       = 'b0;
   //       ddr_mem[0].bready  = 'b1;


   //    end else begin
   //       ddr_mem[0].arvalid = 'b0;
   //       ddr_mem[0].ar      = 'b0;
   //       ddr_mem[0].rready  = 'b1;
   //       ddr_mem[0].awvalid = 'b0;
   //       ddr_mem[0].aw      = 'b0;
   //       ddr_mem[0].wvalid  = 'b0;
   //       ddr_mem[0].w       = 'b0;
   //       ddr_mem[0].bready  = 'b1;

   //       ddr_mem[1].arvalid = 'b0;
   //       ddr_mem[1].ar      = 'b0;
   //       ddr_mem[1].rready  = 'b0;
   //       ddr_mem[1].awvalid = 'b0;
   //       ddr_mem[1].aw      = 'b0;
   //       ddr_mem[1].wvalid  = 'b0;
   //       ddr_mem[1].w       = 'b0;
   //       ddr_mem[1].bready  = 'b0;

   //       selected_ddr_mem.arready = 'b0;
   //       selected_ddr_mem.rvalid = 'b0;
   //       selected_ddr_mem.r = 'b0;
   //       selected_ddr_mem.awready = 'b0;
   //       selected_ddr_mem.wready = 'b0;
   //       selected_ddr_mem.bvalid = 'b0;
   //       selected_ddr_mem.b = 'b0;
   //    end
   // end      



   //  always_comb begin
   //    for (integer i = 0; i < NUM_LOCAL_MEM_BANKS; i = i + 1) begin : gen_mux
   //          ddr_mem[i].arvalid = 'b0;
   //          ddr_mem[i].ar      = 'b0;
   //          ddr_mem[i].rready  = 'b1;
   //          ddr_mem[i].awvalid = 'b0;
   //          ddr_mem[i].aw      = 'b0;
   //          ddr_mem[i].wvalid  = 'b0;
   //          ddr_mem[i].w       = 'b0;
   //          ddr_mem[i].bready  = 'b1;
   //          if (channel_select == i) begin
   //             ddr_mem[i].arvalid = selected_ddr_mem.arvalid;
   //             selected_ddr_mem.arready = ddr_mem[i].arready;
   //             ddr_mem[i].ar      = selected_ddr_mem.ar;

   //             selected_ddr_mem.rvalid = ddr_mem[i].rvalid;
   //             ddr_mem[i].rready  = selected_ddr_mem.rready;
   //             selected_ddr_mem.r = ddr_mem[i].r;

   //             ddr_mem[i].awvalid = selected_ddr_mem.awvalid;
   //             selected_ddr_mem.awready = ddr_mem[i].awready;
   //             ddr_mem[i].aw      = selected_ddr_mem.aw;

   //             ddr_mem[i].wvalid  = selected_ddr_mem.wvalid;
   //             selected_ddr_mem.wready = ddr_mem[i].wready;
   //             ddr_mem[i].w       = selected_ddr_mem.w;

   //             selected_ddr_mem.bvalid = ddr_mem[i].bvalid;
   //             ddr_mem[i].bready  = selected_ddr_mem.bready;
   //             selected_ddr_mem.b = ddr_mem[i].b;
   //          end
   //      end
   //  end


//    genvar i;
//    generate
//       for (i = 0; i < NUM_LOCAL_MEM_BANKS; i = i + 1) begin : gen_ddr_mem_assignment
//          always_comb begin
//                if (channel_select == i) begin
//                   ddr_mem[i].arvalid = selected_ddr_mem.arvalid;
//                   ddr_mem[i].ar      = selected_ddr_mem.ar;
//                   ddr_mem[i].rready  = selected_ddr_mem.rready;
//                   ddr_mem[i].awvalid = selected_ddr_mem.awvalid;
//                   ddr_mem[i].aw      = selected_ddr_mem.aw;
//                   ddr_mem[i].wvalid  = selected_ddr_mem.wvalid;
//                   ddr_mem[i].w       = selected_ddr_mem.w;
//                   ddr_mem[i].bready  = selected_ddr_mem.bready;
//                end else begin
//                   ddr_mem[i].arvalid = 'b0;
//                   ddr_mem[i].ar      = 'b0;
//                   ddr_mem[i].rready  = 'b1;
//                   ddr_mem[i].awvalid = 'b0;
//                   ddr_mem[i].aw      = 'b0;
//                   ddr_mem[i].wvalid  = 'b0;
//                   ddr_mem[i].w       = 'b0;
//                   ddr_mem[i].bready  = 'b1;
//                end
//          end
//       end
//    endgenerate

//    always_comb begin
//     for (int i = 0; i < NUM_LOCAL_MEM_BANKS; i++) begin
        
//         ddr_mem[i].arvalid =  (channel_select == i) ? selected_ddr_mem.arvalid : 'b0;
//         ddr_mem[i].ar      =  (channel_select == i) ? selected_ddr_mem.ar : 'b0;

//         ddr_mem[i].rready  =  (channel_select == i) ? selected_ddr_mem.rready : 'b1;

//         ddr_mem[i].awvalid =  (channel_select == i) ? selected_ddr_mem.awvalid : 'b0;
//         ddr_mem[i].aw      =  (channel_select == i) ? selected_ddr_mem.aw : 'b0;

//         ddr_mem[i].wvalid  =  (channel_select == i) ? selected_ddr_mem.wvalid : 'b0;
//         ddr_mem[i].w       =  (channel_select == i) ? selected_ddr_mem.w : 'b0;

//         ddr_mem[i].bready  =  (channel_select == i) ? selected_ddr_mem.bready : 'b1;

//     end
//   end



   //    // Interface Multiplexor
   //  always_comb begin
   //      if (channel_select < NUM_LOCAL_MEM_BANKS) begin
           
   //      end else begin
   //          selected_ddr_mem.r = 'b0;
   //          selected_ddr_mem.rvalid = 'b0;
   //      end
   //  end

// generate
//     genvar i;
//     for (i = 0; i < NUM_LOCAL_MEM_BANKS; i = i + 1) begin : gen_block
//         always_comb begin
//             if (channel_select == i) begin
//                 selected_ddr_mem.arready &= ddr_mem[i].arready;
//                 selected_ddr_mem.rvalid  |= ddr_mem[i].rvalid;
//                 selected_ddr_mem.r       |= ddr_mem[i].r;
//                 selected_ddr_mem.awready &= ddr_mem[i].awready;
//                 selected_ddr_mem.wready  |= ddr_mem[i].wready;
//                 selected_ddr_mem.bvalid  |= ddr_mem[i].bvalid;
//                 selected_ddr_mem.b       |= ddr_mem[i].b;
//             end
//         end
//     end
// endgenerate




//    `define AXI_MM_ASSIGN(dma_mem_src, pim_mem_src, dma_mem_dest, pim_mem_dest) \
//       ``pim_mem_src``.arvalid= ``dma_mem_src``.arvalid; \
//       ``dma_mem_src``.arready= ``pim_mem_src``.arready; \
//       ``pim_mem_src``.ar     = ``dma_mem_src``.ar; \
//       ``pim_mem_src``.rready = ``dma_mem_src``.rready; \
//       ``dma_mem_src``.rvalid = ``pim_mem_src``.rvalid; \
//       ``dma_mem_src``.r      = ``pim_mem_src``.r; \
//       ``dma_mem_src``.awready= ``pim_mem_src``.awready; \
//       ``pim_mem_src``.awvalid= ``dma_mem_src``.awvalid; \
//       ``pim_mem_src``.aw     = ``dma_mem_src``.aw; \
//       ``dma_mem_src``.wready = ``pim_mem_src``.wready; \
//       ``pim_mem_src``.wvalid = ``dma_mem_src``.wvalid; \
//       ``pim_mem_src``.w      = ``dma_mem_src``.w; \
//       ``pim_mem_src``.bready = ``dma_mem_src``.bready; \
//       ``dma_mem_src``.bvalid = ``pim_mem_src``.bvalid; \
//       ``dma_mem_src``.b      = ``pim_mem_src``.b; \
//       ``dma_mem_dest``.arready = ``pim_mem_dest``.arready; \
//       ``pim_mem_dest``.arvalid = ``dma_mem_dest``.arvalid; \
//       ``pim_mem_dest``.ar      = ``dma_mem_dest``.ar; \
//       ``pim_mem_dest``.rready  = ``dma_mem_dest``.rready; \
//       ``dma_mem_dest``.rvalid  = ``pim_mem_dest``.rvalid; \
//       ``dma_mem_dest``.r       = ``pim_mem_dest``.r; \
//       ``dma_mem_dest``.awready = ``pim_mem_dest``.awready; \
//       ``pim_mem_dest``.awvalid = ``dma_mem_dest``.awvalid; \
//       ``pim_mem_dest``.aw      = ``dma_mem_dest``.aw; \
//       ``dma_mem_dest``.wready  = ``pim_mem_dest``.wready; \
//       ``pim_mem_dest``.wvalid  = ``dma_mem_dest``.wvalid; \
//       ``pim_mem_dest``.w       = ``dma_mem_dest``.w; \
//       ``pim_mem_dest``.bready  = ``dma_mem_dest``.bready; \
//       ``dma_mem_dest``.bvalid  = ``pim_mem_dest``.bvalid; \
//       ``dma_mem_dest``.b       = ``pim_mem_dest``.b; 

  
//   always_comb begin
//      case (descriptor.descriptor_control.mode) 
//          dma_pkg::DDR_TO_HOST: begin 
//             `AXI_MM_ASSIGN(src_mem, selected_ddr_mem, dest_mem, host_mem)
//          end

//          dma_pkg::HOST_TO_DDR: begin 
//             `AXI_MM_ASSIGN(src_mem, host_mem, dest_mem, selected_ddr_mem)
//          end
 
//          default: begin 
//             `AXI_MM_ASSIGN(src_mem, selected_ddr_mem, dest_mem, host_mem)
//          end

//      endcase
//   end


// genvar i;
// generate
//    for (i = 0; i < NUM_LOCAL_MEM_BANKS; i++) begin
//       always_comb begin
//             if (channel_select == i)begin 
//                ddr_mem[i].arvalid       = selected_ddr_mem.arvalid;
//                ddr_mem[i].ar            = selected_ddr_mem.ar; 

//                ddr_mem[i].rready        = selected_ddr_mem.rready; 
//                selected_ddr_mem.r       = ddr_mem[i].r;

//                ddr_mem[i].awvalid       = selected_ddr_mem.awvalid;
//                ddr_mem[i].aw            = selected_ddr_mem.aw; 

//                ddr_mem[i].wvalid        = selected_ddr_mem.wvalid;
//                ddr_mem[i].w             = selected_ddr_mem.w; 

//                ddr_mem[i].bready        = selected_ddr_mem.bready; 
//                selected_ddr_mem.b       = ddr_mem[i].b;
//             end else begin
//                ddr_mem[i].awvalid = 'b0;
//                ddr_mem[i].wvalid  = 'b0;
//                ddr_mem[i].arvalid = 'b0;
//                ddr_mem[i].bready  = 'b1;
//                ddr_mem[i].rready  = 'b1;
//             end
//          end         
//       end
// endgenerate

// always_comb begin
//    for (int i = 0; i < NUM_LOCAL_MEM_BANKS; i++) begin
//       selected_ddr_mem.arready = selected_ddr_mem.arready & ddr_mem[i].arready;
      
//       selected_ddr_mem.rvalid  = selected_ddr_mem.rvalid | ddr_mem[i].rvalid;
      
//       selected_ddr_mem.awready = selected_ddr_mem.awready & ddr_mem[i].awready;
      
//       selected_ddr_mem.wready  = selected_ddr_mem.wready & ddr_mem[i].wready;
      
//       selected_ddr_mem.bvalid  = selected_ddr_mem.bvalid | ddr_mem[i].bvalid;
//    end
// end

endmodule : dma_ddr_selector
