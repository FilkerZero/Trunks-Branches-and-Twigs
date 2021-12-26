# ARM Cortex-M(3,4,4f,7fs,7fd) port for GCC based toolchains and ARM CMIS compatible headers and vendor supplied drivers

Author: Daniel A. Glasser <daniel.glasser@gmail.com> + (unwittingly) Tido Klaassen <tido@4gh.eu> and Kelvin Lawson <info@atomthreads.com>

License: BSD Revised.

ARM Cortex-M CMSIS port to the IDEs provided by vendors like MicroChip, STMicro, and others who provide official CMSIS headers rather than using the "OpenCM3" headers and drivers (from the "ports/arm" port) that are not 100% compatible with the ARM versions.
This port adds Cortex-M7 with single and double precision hard floating point support, and also has support Cortex-M4 with hard floating point.

This port was developed for STM32 microcontrollers (tested with M3-M7) using ST Micro's CubeMX firmware libraries, and MicroSemi's (now MicroChip) "SmartFusion" FPGAs with embedded Cortex-M hard cores using the "SoftConsole" IDE. It has also been used with TrueStudio, and AC6 System Workbench for STM32 (SW4STM32), all of which have ARM CMSIS headers and newlib nano, along with a GCC compiler toolchain.

This port is organized somewhat differently than the "cortex-m" port, in that there are no board sub-directories, and the addition of the "atomport_config.h" file.

The file "atomport_config.h" is intended to be where the macros that control the target and feature support of the kernel can be gathered and documented.  There are extensive comments in all of the original code in the "arm-cmsis" port.

Note: Daniel tried several timees to contact the author of AtomThreads (Kelvin Lawson <info@atomthreads.com>) to contribute this port (and other things), but never was able to get a response.
