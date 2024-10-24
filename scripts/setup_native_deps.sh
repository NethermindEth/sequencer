#!/bin/bash

install_essential_deps_linux() {
  apt-get update -y
  apt-get install -y \
    curl \
    jq \
    ripgrep \
    wget \
    ca-certificates \
    gnupg \
    git \
    lld
}

setup_llvm_deps() {
	case "$(uname)" in
	Darwin)
		brew update
		brew install llvm@19

		LIBRARY_PATH=/opt/homebrew/lib
		MLIR_SYS_190_PREFIX="$(brew --prefix llvm@19)"
		LLVM_SYS_191_PREFIX="$MLIR_SYS_190_PREFIX"
		TABLEGEN_190_PREFIX="$MLIR_SYS_190_PREFIX"

		export LIBRARY_PATH
		export MLIR_SYS_190_PREFIX
		export LLVM_SYS_191_PREFIX
		export TABLEGEN_190_PREFIX
		;;
	Linux)
    export DEBIAN_FRONTEND=noninteractive
    export TZ=America/New_York

		CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
		[ -z "$CODENAME" ] && { echo "Error: Unable to determine OS codename"; exit 1; }

		echo "deb http://apt.llvm.org/$CODENAME/ llvm-toolchain-$CODENAME-19 main" > /etc/apt/sources.list.d/llvm-19.list
		echo "deb-src http://apt.llvm.org/$CODENAME/ llvm-toolchain-$CODENAME-19 main" >> /etc/apt/sources.list.d/llvm-19.list
		wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -

    apt-get update && apt-get upgrade -y
    apt-get install -y zstd
    apt-get install -y llvm-19 llvm-19-dev llvm-19-runtime clang-19 clang-tools-19 lld-19 libpolly-19-dev libmlir-19-dev mlir-19-tools
    apt-get install -y libgmp3-dev

		MLIR_SYS_190_PREFIX=/usr/lib/llvm-19/
		LLVM_SYS_191_PREFIX=/usr/lib/llvm-19/
		TABLEGEN_190_PREFIX=/usr/lib/llvm-19/

		export MLIR_SYS_190_PREFIX
		export LLVM_SYS_191_PREFIX
		export TABLEGEN_190_PREFIX
		;;
	*)
		echo "Error: Unsupported operating system"
		exit 1
		;;
	esac

	# GitHub Actions specific
	[ -n "$GITHUB_ACTIONS" ] && {
    echo "MLIR_SYS_190_PREFIX=$MLIR_SYS_190_PREFIX" >> $GITHUB_ENV
    echo "LLVM_SYS_191_PREFIX=$LLVM_SYS_191_PREFIX" >> $GITHUB_ENV
    echo "TABLEGEN_190_PREFIX=$TABLEGEN_190_PREFIX" >> $GITHUB_ENV
	}
}

install_rust() {
	if command -v cargo >/dev/null 2>&1; then
		echo "Rust is already installed with cargo available in PATH."
		return 0
	fi

	echo "cargo not found. Installing Rust..."
	if ! curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
		echo >&2 "Failed to install Rust. Aborting."
		return 1
	fi

	# shellcheck disable=SC1090
	source "$HOME/.cargo/env" || {
		echo >&2 "Failed to source Rust environment. Aborting."
		return 1
	}

	echo "Rust installed successfully."
}

main() {
  [ "$(uname)" = "Linux" ] && install_essential_deps_linux

	setup_llvm_deps
  install_rust

	echo "LLVM and Cairo native runtime dependencies installed successfully."
}

main "$@"