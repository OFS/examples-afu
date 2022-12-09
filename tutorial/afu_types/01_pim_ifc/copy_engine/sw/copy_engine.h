// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __COPY_ENGINE_H__
#define __COPY_ENGINE_H__

int copy_engine(
    fpga_handle accel_handle, bool is_ase_sim,
    uint32_t chunk_size,
    uint32_t completion_freq,
    bool use_interrupts,
    uint32_t max_reqs_in_flight);

#endif // __COPY_ENGINE_H__
