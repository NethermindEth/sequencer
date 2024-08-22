# Dockerfile with multi-stage builds for efficient dependency caching and lightweight final image.
# For more on Docker stages, visit: https://docs.docker.com/build/building/multi-stage/

# We use Cargo Chef to compile dependencies before compiling the rest of the crates.
# This approach ensures proper Docker caching, where dependency layers are cached until a dependency changes.
# Code changes in our crates won't affect these cached layers, making the build process more efficient.
# More info on Cargo Chef: https://github.com/LukeMathWalker/cargo-chef

# We start by creating a base image using 'clux/muslrust' with additional required tools.
FROM ubuntu:latest AS chef
WORKDIR /app

# Install dependencies
RUN apt update -y && apt install -y lsb-release \
    wget \
    curl \
    git \
    build-essential \
    libclang-dev \
    libz-dev \
    libzstd-dev \
    libssl-dev \
    pkg-config \
    protobuf-compiler

# Install LLVM 18
RUN echo "deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-18 main" > /etc/apt/sources.list.d/llvm-18.list
RUN echo "deb-src http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-18 main" >> /etc/apt/sources.list.d/llvm-18.list
RUN wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
RUN apt update -y && apt install -y \
    libmlir-18-dev \
    libpolly-18-dev \
    llvm-18-dev \
    mlir-18-tools
ENV MLIR_SYS_180_PREFIX=/usr/lib/llvm-18/
ENV LLVM_SYS_181_PREFIX=/usr/lib/llvm-18/
ENV TABLEGEN_180_PREFIX=/usr/lib/llvm-18/

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Fetch Cairo Native Repository and build Cairo Native Runtime
RUN git clone --branch cairo-lang2.7.0-rc.3 https://github.com/lambdaclass/cairo_native.git && \
    cd cairo_native/runtime && \
    cargo build --release

# Set environment variable for Cairo Native Runtime Library
ENV CAIRO_NATIVE_RUNTIME_LIBRARY=/app/cairo_native/target/release/libcairo_native_runtime.a

######################
# Stage 3 (builder): #
######################
FROM chef AS builder
COPY . .
# Disable incremental compilation for a cleaner build.
ENV CARGO_INCREMENTAL=0

# Compile the papyrus_node crate for the x86_64-unknown-linux-musl target in release mode, ensuring dependencies are locked.
RUN cargo build --release --package papyrus_node --locked

###########################
# Stage 4 (papyrus_node): #
###########################
# Uses Alpine Linux to run a lightweight and secure container.
FROM alpine:3.17.0 AS papyrus_node
ENV ID=1000
WORKDIR /app

# Copy LLVM-18 libraries from the chef stage.
COPY --from=chef /usr/lib/llvm-18 /usr/lib/llvm-18
COPY --from=chef /app/cairo_native/target/release/libcairo_native_runtime.a /app/cairo_native/target/release/libcairo_native_runtime.a

ENV MLIR_SYS_180_PREFIX=/usr/lib/llvm-18/
ENV LLVM_SYS_181_PREFIX=/usr/lib/llvm-18/
ENV TABLEGEN_180_PREFIX=/usr/lib/llvm-18/
ENV CAIRO_NATIVE_RUNTIME_LIBRARY=/app/cairo_native/target/release/libcairo_native_runtime.a

# Copy the node executable and its configuration.
COPY --from=builder /app/target/release/papyrus_node /app/target/release/papyrus_node
COPY config config

# Install tini, a lightweight init system, to call our executable.
RUN set -ex; \
    apk update; \
    apk add --no-cache tini; \
    mkdir data

# Create a new user "papyrus".
RUN set -ex; \
    addgroup --gid ${ID} papyrus; \
    adduser --ingroup $(getent group ${ID} | cut -d: -f1) --uid ${ID} --gecos "" --disabled-password --home /app papyrus; \
    chown -R papyrus:papyrus /app

# Expose RPC and monitoring ports.
EXPOSE 8080 8081

# Switch to the new user.
USER ${ID}

# Set the entrypoint to use tini to manage the process.
ENTRYPOINT ["/sbin/tini", "--", "/app/target/release/papyrus_node"]