#!/bin/bash -e

CWD=$(pwd)
SUPPORTED_REGISTRY=("zot" "dockerhub")

function help {
    echo "Usage"
    echo "  run.sh <registry-name> <notation-binary-path> [old-notation-binary-path]"
    echo ""
    echo "Arguments"
    echo "  registry-name             is the registry to use for running the E2E test. Currently support: ${SUPPORTED_REGISTRY[@]}."
    echo "  notation-binary-path      is the path of the notation executable binary file."
    echo "  old-notation-binary-path  is the path of an old notation executable bianry file. If it is not set, an RC.1 Notation will be downloaded automatically."
}

# check registry name
REGISTRY_NAME=$1
if [ -z "$REGISTRY_NAME" ]; then
    echo "registry name is missing."
    help
    exit 1
fi

# check notation binary path.
export NOTATION_E2E_BINARY_PATH=$(if [ ! -z "$2" ]; then realpath $2; fi)
if [ ! -f "$NOTATION_E2E_BINARY_PATH" ]; then
    echo "notation binary path doesn't exist."
    help
    exit 1
fi

# check old notation binary path for forward compatibility test.
export NOTATION_E2E_OLD_BINARY_PATH=$(if [ ! -z "$3" ]; then realpath $3; fi)
if [ ! -f "$NOTATION_E2E_OLD_BINARY_PATH" ]; then
    OLD_NOTATION_DIR=/tmp/notation_old
    export NOTATION_E2E_OLD_BINARY_PATH=$OLD_NOTATION_DIR/notation
    mkdir -p $OLD_NOTATION_DIR

    echo "Old notation binary path doesn't exist."
    echo "Try to use old notation binary at $NOTATION_E2E_OLD_BINARY_PATH"

    if [ ! -f $NOTATION_E2E_OLD_BINARY_PATH ]; then
        TAG=1.0.0-rc.1 # without 'v'
        echo "Didn't find old notation binary locally. Try to download notation v$TAG."

        TAR_NAME=notation_${TAG}_linux_amd64.tar.gz
        URL=https://github.com/notaryproject/notation/releases/download/v${TAG}/$TAR_NAME
        wget $URL -P $OLD_NOTATION_DIR
        tar -xf $OLD_NOTATION_DIR/$TAR_NAME -C $OLD_NOTATION_DIR

        if [ ! -f $NOTATION_E2E_OLD_BINARY_PATH ]; then
            echo "Failed to download old notation binary for forward compatibility test."
            exit 1
        fi
        echo "Downloaded notation v$TAG at $NOTATION_E2E_OLD_BINARY_PATH"
    fi
fi

# install dependency
go install -mod=mod github.com/onsi/ginkgo/v2/ginkgo@v2.3.0

# build e2e plugin
PLUGIN_NAME=e2e-plugin
( cd $CWD/plugin && go build -o ./bin/$PLUGIN_NAME . && echo "e2e plugin built." )

# setup registry
case $REGISTRY_NAME in

"zot")
    source ./scripts/zot.sh
    ;;

"dockerhub")
    source ./scripts/dockerhub.sh
    ;;

*)
    echo "invalid registry"
    help
    exit 1
    ;;
esac

setup_registry

# defer cleanup registry
function cleanup {
    cleanup_registry
}
trap cleanup EXIT

# set environment variable for E2E testing
export NOTATION_E2E_CONFIG_PATH=$CWD/testdata/config
export NOTATION_E2E_OCI_LAYOUT_PATH=$CWD/testdata/registry/oci_layout
export NOTATION_E2E_TEST_REPO=e2e
export NOTATION_E2E_TEST_TAG=v1
export NOTATION_E2E_PLUGIN_PATH=$CWD/plugin/bin/$PLUGIN_NAME

# run tests
ginkgo -r -p -v