# Aloha-HE: AMD OpenHW Competition
This repository contains an extension of Aloha-HE dedicated to the **AMD Open Hardware design contest 2024**.
Aloha-HE addresses the problem of high computational effort in the client-side operations in fully homomorphic encryption (FHE). By enhancing efficiency through algorithmic-level and hardware-level optimizatoins, Aloha-HE allows performant FHE deployment on constrained devices and cost-efficient FPGAs. Please refer to our [paper](https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=10546608) for more details.

## Extensions
Compared to the Aloha-HE version presented in the paper, this version provides runtime configurability of the polynomial degree. The software can control the used polynomial between $N=2^{13}$ and $N=2^{15}$. Due to the large supported polynomials and the limited memory, the FFT twiddle factors can only be generated (unlike to baseline Aloha, where they can either be generated or stored).

## Repository Structure
This is the repository layout and the most important files:
```
Aloha_HE
├── Aloha-HE_Common         // Contains the HDL files 
|   ├── BlockRAMs               // BRAM instances
|   ├── FloatingPoint           // Code for floating-point datapath
|   ├── MemoryInitialization    // Initial ROM content
|   ├── ModRing                 // Code for modular ring datapath
|   ├── RandomSampling          // Pseudo-random number generator
|   ├── SharedArithmetics       // Arithmetic units shared between floating-point and modular ring datapath
|   └── Utils                   // Various helper modules
├── Aloha-HE_Kintex         // Folder for Vivado project
|   ├── Bitstream               // Ready-to-use bitstream files
|   └── Aloha-HE_Kintex.tcl     // Tcl file to build the Vivado project
└── Aloha-HE_Software       // Contains the software code to interface with Aloha
    ├── main.c                  // File containing the main() function
    └── Testing                 // Testing code and reference output 
        └── ckksTest.c              // File with the actual testing and benchmarking code
```

## How to Run

This section explains how to run Aloha on a Genesys2 board. The **Vivado** section details the project set-up and synthesis + implementation steps to generate the bitstream. You can skip the **Vivado** steps and directly use the provided bitstream file located in `Aloha-HE_Kintex/Bitstream` during the **SDK** steps.

### Vivado
To set up the Vivado project and to synthesize and implement the design, follow these steps:
1) Prepare a Vivado 2019.1 setup with SDK and Genesys2 support (details are [here](https://digilent.com/reference/programmable-logic/guides/installing-vivado-and-sdk))
2) Launch Vivado 2019 and use the Tcl Console to navigate to the `Aloha_HE/Aloha-HE_Kintex/` folder: ``` cd /your/path/Aloha_HE/Aloha-HE_Kintex/```
3) Source the provided Tcl File: `source Aloha-HE_Kintex.tcl`. This will build the whole project.
4) Start the Synthesis, Implementation and the Generate Bitstream runs in Vivado.
5) Export the generated bitstream: `File -> Export -> Export Hardware`. Check `Include bitstream` and press OK.

### SDK
1) (a) Launch SDK via Vivado: `File -> Launch SDK` and click OK. OR
 (b) Launch SDK without Vivado project: Open a terminal in `Aloha-HE_Kintex/Bitstream/` and type `xsdk -bit=AlohaHE_wrapper.bit -bmm=AlohaHE_wrapper_bd.bmm -hwspec=AlohaHE_wrapper.hdf` in your console (you may have to add `/tools/Xilinx/SDK/2019.1/` to your PATH).
2) In SDK, create a new Application project: `File -> New -> Application project`. Enter some name, e.g. "Aloha_App". Click "Next".
3) Select "Empty Application" and click "Finish".
4) Open `Aloha_App -> src` and right-click on `src` folder.
5) Go to `Properties -> C/C++ General -> Paths and Symbols -> Source Location`.
6) Click "Link Folder", give some folder name (e.g. "SW"), check "Link to folder in the file system" and select the "Aloha-HE_Software" folder. Press OK.
7) Copy `lscript.ld` from `SW` to `src` folder and replace the existing file.
8) Build the project and plug in the Genesys2 Board.
9) Go to `Run -> Run Configurations -> Xilinx C/C++ Application (GDB)` and right-click on it. Select "New".
10) In the window, check "Reset entire system" and "Program FPGA". Then press "Run" to flash the FPGA and start execution of the software.

### Receiving serial output
1) Use for example PuTTY on Windows or `screen` on Ubuntu:
```
sudo screen /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A904DRFN-if00-port0 9600,cs8,-parenb,-cstopb,-hupcl
``` 
2) Note: Flashing the FPGA and verifying the encryption and decryption results take some time due to the large amount of data processed.

3) After the application is launched on the FPGA, users can select between three tests by entering `0\n`, `1\n`, and `2\n` in the console. When `0\n` is selected, hardware performs 1000 encryptions without correctness checks. Use this to simulate a productive deployment of Aloha. When `1\n` is entered, test and performance benchmark code is executed. The output of the encryption and decryption operation is verified against prepared test vectors. Finally, use `2\n` to verify correct timer settings.

## How to Use
In the file `Aloha-HE_Software/Testing/ckksTest.c` are the most important functions. It provides three defines (`TEST_ALOHA`, `FAST_ALOHA` and `POLY_DEGREE`). 

When `TEST_ALOHA` is defined, all intermediate and the end result of encryption and decryption are verified against the reference result (located in `Aloha-HE_Software/Testing/referenceEncryptionNN.h` for 2^13, 2^14, 2^15 degree polynomials). 

When `FAST_ALOHA` is defined, latency benchmarking code is executed. The code prints the measured latency of encryption and decryption.

Finally, `POLY_DEGREE` defines the used polynomial degree for testing and benchmarking. It can have values 13, 14, or 15. 

In the default case, `TEST_ALOHA` and `FAST_ALOHA` are enabled and `POLY_DEGREE` is set to 15.

## Contributors
Florian Krieger  -  `florian.krieger (at) iaik.tugraz.at`

Florian Hirner  -  `florian.hirner (at) iaik.tugraz.at`

Sujoy Sinha Roy  -  `sujoy.sinharoy (at) iaik.tugraz.at`

[Institute of Applied Information Processing and Communications](https://www.iaik.tugraz.at/), Graz University of Technology, Austria

-----

All content of this repo is for academic research use only. It does not come with any support, warranty, or responsibility.