#!/bin/env bash
set -e
set -x

docker_image_name=sequencer-ci

(
    cd scripts
    docker build . -t ${docker_image_name} --file ${docker_image_name}.Dockerfile
)

id

docker run \
    --rm \
    --net host \
    -e CARGO_HOME=${HOME}/.cargo \
    -u 1001 \
    -v /tmp:/tmp \
    -v "${HOME}:${HOME}" \
    --workdir ${PWD} \
    ${docker_image_name} \
    "$@"
