# Hybrid Local Memory

This example is less ambitious than the [hybrid hello world](../hello_world/) example, which has a more complete discussion of the ramifications of choosing a hybrid approach. Go through hello_world first for an explanation of the modules.

Recoding the local memory test itself with FIM interfaces is left to the reader. The logic here maps one bank of local memory from the FIM to the PIM interface in [port_afu_instances(\)](hw/rtl/port_afu_instances.sv) and drives it with the [PIM version of local\_memory](../../01_pim_ifc/local_memory). A new [NULL AFU](../../03_afu_main/hello_world/hw/rtl/null_afu.sv), which will also be used in later sections, ties off all but PCIe port 0.

If you have read the hybrid hello world example, this local memory version should appear familiar. In addition to mapping the FIM's TLP ports to a host\_channel, this version must also declare a PIM memory interface \(ofs\_plat\_axi\_mem\_if\) and instantiate a module to map FIM local memory to the PIM. That mapping introduces yet more platform-specific complexity. When the FIM exposes local memory as Avalon-MM the module name is *map\_fim\_emif\_avmm\_to\_local\_mem*. When the FIM exposes local memory as AXI-MM the module name is *map\_fim\_emif\_axi\_mm\_to\_local\_mem*. After this mapping, the memory interface is identical to the full-PIM version.

Use the [software from the full PIM version](../../01_pim_ifc/local_memory/sw). The AFU's external API is unchanged.