{ pkgs ? import <nixpkgs> { config.allowUnfree = true; config.nvidia.acceptLicense = true; } }:

#TODO: how can we programatically install the virtual environment for the python dependencies?

pkgs.mkShell {
  buildInputs = [
    pkgs.python39
    pkgs.pkg-config
    pkgs.cudaPackages_11.cudatoolkit
    pkgs.cudaPackages_11.cuda_cudart
    pkgs.linuxPackages.nvidia_x11_legacy470
#    pkgs.glibc
#    pkgs.glib
    pkgs.gcc10
#    pkgs.gcc-unwrapped
    pkgs.ninja
    pkgs.libxcrypt
#    pkgs.python3Packages.pytorchWithCuda
#    pkgs.python3Packages.transformers
#    pkgs.python3Packages.datasets
#    pkgs.python3Packages.peft
#    pkgs.python3Packages.pip
  ];

  shellHook = ''
    echo "You are now using a NIX environment"
    export CUDA_PATH=${pkgs.cudaPackages_11.cudatoolkit}
    export LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.gcc10}/lib
    export EXTRA_LD_FLAGS="-L\/lib -L${pkgs.linuxPackages.nvidia_x11_legacy470}\/lib"
#    export LD_LIBRARY_PATH=${pkgs.linuxPackages.nvidia_x11_legacy470}/lib:${pkgs.cudaPackages.cudatoolkit}/lib64:$LD_LIBRARY_PATH  
    export LD_LIBRARY_PATH=${pkgs.linuxPackages.nvidia_x11_legacy470}/lib:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=${pkgs.python39}/lib:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=$CUDA_PATH/lib:$LD_LIBRARY_PATH
    # Ensure gcc-10 binaries are findable in the PATH for scripts
    export PATH=${pkgs.gcc10}/bin:$PATH
    export CUDA_LIB_DIR=$CUDA_PATH/lib:$CUDA_PATH/lib64
    # Export specific paths for compilers to be used directly in build scripts
    export OLLAMA_GCC10_PATH=${pkgs.gcc10}/bin/gcc
    export OLLAMA_GPP10_PATH=${pkgs.gcc10}/bin/g++
export PKG_CONFIG_PATH="${pkgs.python39}/lib/pkgconfig:$PKG_CONFIG_PATH"
    alias gcc="${pkgs.gcc10}/bin/gcc"
  '';
}
