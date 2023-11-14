// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// This is not the main write engine. It is a wrapper around the main engine,
// which is named copy_write_engine_core().
//
// The module here is responsible for injecting completions (interrupts or
// status line writes) into the write stream as copy operations complete in
// order to signal the host. Putting just the completion logic here makes
// the code easier to read.
//

module dma_engine
  #(
    parameter MAX_REQS_IN_FLIGHT = 32
    )
   (
    ofs_plat_axi_mem_if.to_sink src_mem,
    ofs_plat_axi_mem_if.to_sink dest_mem,

    // Write engine control - initiate a write of num_lines from addr when enable is set.
    input  dma_pkg::t_control control,
    output dma_pkg::t_status status 
    );

  assign src_mem.awvalid = 'b0;
  assign src_mem.wvalid = 'b0;
  assign src_mem.arvalid = 'b0;
  // assign src_mem.rvalid = 'b0;

  assign src_mem.bready = 'b1;
  assign src_mem.rready = 'b1;

  assign dest_mem.awvalid = 'b0;
  assign dest_mem.wvalid = 'b0;
  assign dest_mem.arvalid = 'b0;
  // assign dest_mem.rvalid = 'b0;
  
  assign dest_mem.bready = 'b1;
  assign dest_mem.rready = 'b1;


endmodule // copy_write_engine
