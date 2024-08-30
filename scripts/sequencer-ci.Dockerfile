FROM ubuntu:20.04

RUN apt update && apt -y install \
    build-essential \
    clang \
    curl \
    python3-dev

ENV RUSTUP_HOME=/opt/rust
ENV CARGO_HOME=/opt/rust
ENV PATH=$PATH:/opt/rust/bin

ENV MLIR_SYS_180_PREFIX=/usr/lib/llvm-18/
ENV LLVM_SYS_181_PREFIX=/usr/lib/llvm-18/
ENV TABLEGEN_180_PREFIX=/usr/lib/llvm-18/

COPY install_build_tools.sh .
RUN bash install_build_tools.sh
