// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

package dma_pkg;

    localparam SRC_ADDR_WIDTH = 32;
    localparam DEST_ADDR_WIDTH = 32;
    localparam LENGTH_WIDTH = 32;
    typedef enum {HOST_TO_DDR, DDR_TO_HOST, DDR_TO_DDR} e_dma_mode;

    typedef struct {
      logic go;
    } t_descriptor_control;

    typedef struct {
        logic [SRC_ADDR_WIDTH-1:0] src_addr;
        logic [DEST_ADDR_WIDTH-1:0] dest_addr;
        logic [LENGTH_WIDTH-1:0] length;
        t_descriptor_control control;
    } t_descriptor;

    typedef struct {
      logic reset_engine;
      e_dma_mode mode;
      t_descriptor descriptor;
    } t_control;

    typedef struct {
        logic [32:0] descriptor_fifo_count;
        logic [32:0] descriptor_fifo_depth;
        logic [15:0] rd_state;
        logic [15:0] wr_state;
    } t_status;


   endpackage // dma_pkg
