# Include for Shared Header Libraries
This directory contains utility header libraries optimized for SYCL*-compliant FPGA designs.

## Available Header Libraries

### Utilities

| Filename                      | Description                                                                                                                               
---                             |---                                                                                                                                        
| `constexpr_math.hpp`          | Defines utilities for statically computing math functions (for example, Log2 and Pow2).                                                   
| `memory_utils.hpp`            | Generic functions for streaming data from memory to a SYCL pipe and vise versa.                                                           
| `metaprogramming_utils.hpp`   | Defines various metaprogramming utilities (for example, generating a power of 2 sequence and checking if a type has a subscript operator).
| `onchip_memory_with_cache.hpp`| Class that contains an on-chip memory array with a register backed cache to achieve high performance read-modify-write loops.             
| `pipe_utils.hpp`              | Utility classes for working with pipes, such as PipeArray.                                                                                
| `rom_base.hpp`                | A generic base class to create ROMs in the FPGA using and initializer lambda or functor.                                                  
| `tuple.hpp`                   | Defines a template to implement tuples.                                                                                                   
| `unrolled_loop.hpp`           | Defines a templated implementation of unrolled loops.                                                                                     
| `exception_handler.hpp`       | Defines an exception handler to catch SYCL asynchronous exceptions.                                                                      

