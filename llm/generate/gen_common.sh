# common logic across linux and darwin

init_vars() {
    case "${GOARCH}" in
    "amd64")
        ARCH="x86_64"
        ;;
    "arm64")
        ARCH="arm64"
        ;;
    *)
        ARCH=$(uname -m | sed -e "s/aarch64/arm64/g")
    esac

    LLAMACPP_DIR=../llama.cpp
    CMAKE_DEFS=""
    CMAKE_TARGETS="--target ollama_llama_server"
    if echo "${CGO_CFLAGS}" | grep -- '-g' >/dev/null; then
        CMAKE_DEFS="-DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_VERBOSE_MAKEFILE=on -DLLAMA_GPROF=on -DLLAMA_SERVER_VERBOSE=on ${CMAKE_DEFS}"
    else
        # TODO - add additional optimization flags...
        CMAKE_DEFS="-DCMAKE_BUILD_TYPE=Release -DLLAMA_SERVER_VERBOSE=off ${CMAKE_DEFS}"
    fi
    case $(uname -s) in
    "Darwin")
        LIB_EXT="dylib"
        WHOLE_ARCHIVE="-Wl,-force_load"
        NO_WHOLE_ARCHIVE=""
        GCC_ARCH="-arch ${ARCH}"
        ;;
    "Linux")
        LIB_EXT="so"
        WHOLE_ARCHIVE="-Wl,--whole-archive"
        NO_WHOLE_ARCHIVE="-Wl,--no-whole-archive"

        # Cross compiling not supported on linux - Use docker
        GCC_ARCH=""
        ;;
    *)
        ;;
    esac
    if [ -z "${CMAKE_CUDA_ARCHITECTURES}" ] ; then
        CMAKE_CUDA_ARCHITECTURES="35;37;50;52;61;70;75;80"
    fi
}

git_module_setup() {
    if [ -n "${OLLAMA_SKIP_PATCHING}" ]; then
        echo "Skipping submodule initialization"
        return
    fi
    # Make sure the tree is clean after the directory moves
    if [ -d "${LLAMACPP_DIR}/gguf" ]; then
        echo "Cleaning up old submodule"
        rm -rf ${LLAMACPP_DIR}
    fi
    git submodule init
    git submodule update --force ${LLAMACPP_DIR}

}

apply_patches() {
    # Wire up our CMakefile
    if ! grep ollama ${LLAMACPP_DIR}/CMakeLists.txt; then
        echo 'add_subdirectory(../ext_server ext_server) # ollama' >>${LLAMACPP_DIR}/CMakeLists.txt
    fi

    if [ -n "$(ls -A ../patches/*.diff)" ]; then
        # apply temporary patches until fix is upstream
        for patch in ../patches/*.diff; do
            for file in $(grep "^+++ " ${patch} | cut -f2 -d' ' | cut -f2- -d/); do
                (cd ${LLAMACPP_DIR}; git checkout ${file})
            done
        done
        for patch in ../patches/*.diff; do
            (cd ${LLAMACPP_DIR} && git apply ${patch})
        done
    fi
}

build() {
    # Ensure CMake uses the correct compilers from the Nix environment
    # by using the specific paths exported from default.nix and exporting CC/CXX.
    # Also pass them directly via CMAKE definitions for robustness.
    if [ -z "$OLLAMA_GCC10_PATH" ] || [ -z "$OLLAMA_GPP10_PATH" ]; then
        echo "Error: OLLAMA_GCC10_PATH or OLLAMA_GPP10_PATH not set. Check default.nix shellHook."
        exit 1
    fi
    if [ ! -x "$OLLAMA_GCC10_PATH" ] || [ ! -x "$OLLAMA_GPP10_PATH" ]; then
        echo "Error: Compiler paths not executable: $OLLAMA_GCC10_PATH / $OLLAMA_GPP10_PATH"
        exit 1
    fi
    export CC="$OLLAMA_GCC10_PATH"
    export CXX="$OLLAMA_GPP10_PATH"
    local cmake_defs_with_compilers="${CMAKE_DEFS} -DCMAKE_C_COMPILER=${OLLAMA_GCC10_PATH} -DCMAKE_CXX_COMPILER=${OLLAMA_GPP10_PATH}"
    cmake -S ${LLAMACPP_DIR} -B ${BUILD_DIR} ${cmake_defs_with_compilers}
    cmake --build ${BUILD_DIR} ${CMAKE_TARGETS} -j8
}

compress() {
    echo "Compressing payloads to reduce overall binary size..."
    pids=""
    rm -rf ${BUILD_DIR}/bin/*.gz
    for f in ${BUILD_DIR}/bin/* ; do
        gzip -n --best -f ${f} &
        pids+=" $!"
    done
    # check for lib directory
    if [ -d ${BUILD_DIR}/lib ]; then
        for f in ${BUILD_DIR}/lib/* ; do
            gzip -n --best -f ${f} &
            pids+=" $!"
        done
    fi
    echo
    for pid in ${pids}; do
        wait $pid
    done
    echo "Finished compression"
}

# Keep the local tree clean after we're done with the build
cleanup() {
    (cd ${LLAMACPP_DIR}/ && git checkout CMakeLists.txt)

    if [ -n "$(ls -A ../patches/*.diff)" ]; then
        for patch in ../patches/*.diff; do
            for file in $(grep "^+++ " ${patch} | cut -f2 -d' ' | cut -f2- -d/); do
                (cd ${LLAMACPP_DIR}; git checkout ${file})
            done
        done
    fi
}
