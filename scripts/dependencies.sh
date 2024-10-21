#!/bin/bash

set -e

[[ ${UID} == "0" ]] || SUDO="sudo"

function install_essential_deps_linux() {
    $SUDO bash -c '
        apt update && apt install -y \
            ca-certificates \
            curl \
            git \
            gnupg \
            jq \
            libssl-dev \
            lsb-release \
            pkg-config \
            ripgrep \
            software-properties-common \
            zstd \
            wget
  '
}

function setup_llvm_deps() {
    case "$(uname)" in
    Darwin)
        brew update
        brew install llvm@19
        ;;
    Linux)
        $SUDO bash -c 'curl https://apt.llvm.org/llvm.sh -Lo llvm.sh
        bash ./llvm.sh 19 all
        rm -f ./llvm.sh
        apt update && apt install -y \
            libgmp3-dev \
            libmlir-19-dev \
            libpolly-19-dev \
            libzstd-dev \
            mlir-19-tools \
            lld
        '
        ;;
    *)
        echo "Error: Unsupported operating system"
        exit 1
        ;;
    esac
}

# Downloads libcairo_native_runtime.a
function download_cairo_native_runtime() {
    TARGET_LIB_DIR="$1"
    CAIRO_LIB_VERSION="0.2.0-alpha.2"
    curl "https://github.com/lambdaclass/cairo_native/releases/tag/v${CAIRO_LIB_VERSION}" --output ${LIBCAIRO_NATIVE_DIR}/libcairo_native_runtime.a
}

function main() {
    # Set LIBCAIRO_NATIVE_DIR as first argument.
    # Assumes this script is in `sequencer/scripts/`
    # By default, copy to `sequencer/scripts/../crates/blockifier`
    # Used in `.github/actions/bootstrap/action.yml` and when calling manually.
    THIS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    DEFAULT_DIR="$THIS_DIR/../crates/blockifier"
    LIBCAIRO_NATIVE_DIR=${1:-"$DEFAULT_DIR"}

    [ "$(uname)" = "Linux" ] && install_essential_deps_linux
    setup_llvm_deps
    echo "LLVM dependencies installed successfully."

    download_cairo_native_runtime "$LIBCAIRO_NATIVE_DIR"
    echo "Cairo Native runtime compiled successfully."
}

main "$@"

