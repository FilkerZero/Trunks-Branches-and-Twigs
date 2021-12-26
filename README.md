# Trunks-Branches-and-Twigs
This is a place for various projects that I'd like to share with whoever is interested in them.

There is a 'forks' branch that has copies of sources that I have modified and/or added to where I've been unable to make contact with the original authors to see if they want me to give them the changes or maintain my own fork.  In one case, it would be a matter of a pull request, in the other case, there may be no repository on GitHub or any other on-line project repository that has the original sources (I obtained the original sources in 1998 or 1999, and made some major changes for that one.)

## What you might find here:
* A fork of Kevin Lawson's AtomThreads multithreading executive for small microcontrollers.  (https://github.com/kelvinlawson/atomthreads).  Currently, there is a kernel extension (in the "kernel" directory) and two new ports.
  * The kernel is extended with a new optional module, "atomgate.c", that provides a traffic light-like synchronization intended to control groups of threads where the groups are mutually exclusive, but the individual threads within a group are not. It is described in the source code, and I may enhance that documentation in the future.
  * An ARM Cortex-M CMSIS port targeting the STM32 family using the System Workbench for STM32 (SW4STM) IDE from ACT IDE or the STMCubeIDE available directly from ST Micro, and the MicroChip SmartFusion and SmartFusion2 FPGAs using the SoftConsole IDE available from MicroChip. My port handles a few things differently than the existing port, and works well with the firmware libraries provided by each of those vendors.  The original ARM Cortex-M port does not integrate well with the tools I have available.
  * A new port for the Xilinx(tm) MicroBlaze(tm) soft-core processor in a microcontroller configuration. This works nicely but has not been fully tested, and some of the code needs to be cleaned up and some documentation needs to be added.  The MicroBlaze configuration required to use it as-is must include an AXI Interrupt Controller and AXI Timer in the design, and must not include the MMU. A "Hello World" main is included in the 'port/microblaze-mc' directory.
* A fork of the original "chord" program, written in C.  This is a guitar lead-sheet formatter that went on to be the basis of ChordPRO and a number of other similar tools, and produces PostScript output from marked up ASCII text.  I added a lot of things to my fork of this code back around 2000-2003, but don't recall all that I added.  I hope to locate the original source archive so I can come up with a list of my changes.
* A set of original tcl/tk scripts/programs that use metadata files associated with image files to produce HTML web pages for a gallery.  This is not a general gallery, it was written for a specific purpose and I've put it here because some may find it useful. One of the programs is used to generate and edit the metadata files, the other pulls all the information together.
