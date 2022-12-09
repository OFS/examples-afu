// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Streaming data engine. This could be a module that manipulates the data
// stream in some way that is useful to the algorithm. It sits here in
// the data path as an example of connecting the blocks.
//
// Data arrives in request order.
//

module data_stream_engine
   (
    ofs_plat_axi_stream_if.to_source data_stream_in,
    ofs_plat_axi_stream_if.to_sink   data_stream_out
    );

    wire clk = data_stream_in.clk;
    wire reset_n = data_stream_in.reset_n;

    //
    // Invert the payload as a proxy for doing something useful. Both the
    // incoming and outgoing streams have standard ready/enable signals.
    // This function may have any latency as ready/enable are honored.
    //

    assign data_stream_in.tready = data_stream_out.tready;
    assign data_stream_out.tvalid = data_stream_in.tvalid;
    always_comb
    begin
        data_stream_out.t = data_stream_in.t;
        data_stream_out.t.data = ~data_stream_in.t.data;
    end

endmodule // data_stream_engine
