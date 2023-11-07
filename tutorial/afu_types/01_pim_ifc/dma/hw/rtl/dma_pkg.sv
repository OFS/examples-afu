// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

package copy_engine_pkg;

    localparam CMD_NUM_LINES_BITS = 8;
    localparam CMD_ADDR_BITS = 64;
    localparam CMD_INTR_VEC_BITS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_INTR_VECS;

    typedef logic [CMD_NUM_LINES_BITS-1 : 0] t_cmd_num_lines;
    typedef logic [CMD_ADDR_BITS-1 : 0] t_cmd_addr;
    typedef logic [CMD_INTR_VEC_BITS-1 : 0] t_cmd_intr_id;

    // Read commands (CSR to read engine)
    typedef struct {
        logic enable;
        t_cmd_num_lines num_lines;
        t_cmd_addr addr;
    } t_rd_cmd;

    // Read state (read engine to CSR)
    typedef struct {
        logic [63:0] num_lines_read;
    } t_rd_state;

    // Write commands (CSR to write engine)
    typedef struct {
        logic enable;
        t_cmd_num_lines num_lines;
        t_cmd_addr addr;
        t_cmd_intr_id intr_id;
        logic intr_ack;

        // When use_mem_status is set, the write engine writes completion
        // updates to the mem_status_addr. Completions are indicated by
        // writing the total number of commands processed. When use_mem_status
        // is clear, the write engine indicates generates interrupts.
        logic use_mem_status;
        t_cmd_addr mem_status_addr;
    } t_wr_cmd;

    // Write state (write engine to CSR)
    typedef struct {
        logic [63:0] num_lines_write;
    } t_wr_state;

endpackage // copy_engine_pkg
