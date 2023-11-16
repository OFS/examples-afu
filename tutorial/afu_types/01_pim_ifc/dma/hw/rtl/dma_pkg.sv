// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

package dma_pkg;


    // Put CSR info in its own pkg?
    // Addresses/offsets:
    
    localparam HOST_ADDR_W = 28;
    localparam DDR_ADDR_W = 32;
    localparam SRC_ADDR_W = (HOST_ADDR_W > DDR_ADDR_W) ? HOST_ADDR_W : DDR_ADDR_W; //choose the larger address width so we support both directions
    localparam DEST_ADDR_W = SRC_ADDR_W;
    localparam LENGTH_W = 32;
    localparam AXI_MM_DATA_W = 512;
    localparam DDR_DATA_W = AXI_MM_DATA_W;
    localparam HOST_DATA_W = AXI_MM_DATA_W;

    typedef enum {HOST_TO_DDR, DDR_TO_HOST, DDR_TO_DDR} e_dma_mode;

    typedef struct {
      logic go; // bit 31
      logic [3:0] rsvd0;// bits 30-26
      logic wait_for_resp;
      //... 
    } t_descriptor_control;

    typedef struct {
        logic [SRC_ADDR_W-1:0] src_addr;
        logic [DEST_ADDR_W-1:0] dest_addr;
        logic [LENGTH_W-1:0] length;
        t_descriptor_control control;
    } t_descriptor;

    typedef struct {
      logic reset_engine;
      e_dma_mode mode;
      t_descriptor descriptor;
    } t_control;

    typedef struct {
        logic [31:0] descriptor_fifo_count;
        logic [31:0] descriptor_fifo_depth;
        logic [15:0] rd_state;
        logic [15:0] wr_state;
    } t_status;

    typedef struct {
       logic [HOST_ADDR_W-1:0]   host_addr;
       logic [AXI_MM_DATA_W-1:0] data;
   } t_fifo_host_data;

    typedef struct {
       logic [DDR_ADDR_W-1:0]    ddr_addr;
       logic [AXI_MM_DATA_W-1:0] data;
   } t_fifo_ddr_data;

endpackage // dma_pkg

