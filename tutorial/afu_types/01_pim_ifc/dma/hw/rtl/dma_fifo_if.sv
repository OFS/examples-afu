// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


interface dma_fifo_if  #(
  parameter DATA_W = dma_pkg::AXI_MM_DATA_W + dma_pkg::SRC_ADDR_W
);

   logic [DATA_W-1:0] wr_data;
   logic [DATA_W-1:0] rd_data;
   logic wr_en;
   logic almost_full;
   logic rd_en;
   logic not_full;
   logic not_empty;

   modport wr_in (
      input wr_en,
      input wr_data,
      output almost_full,
      output not_full
   );

   modport wr_out (
      output wr_en,
      output wr_data,
      input almost_full,
      input  not_full
   );

   modport rd_in (
      input rd_en,
      output not_empty,
      output rd_data  
   );

   modport rd_out (
      output rd_en,
      input not_empty,
      input rd_data  
   );

endinterface : dma_fifo_if

