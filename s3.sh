#!/usr/bin/env bash
set -euo pipefail

function envio_s3 () {
    echo "iniciando envio para o s3..."

    aws s3 sync ./client/build/ s3://front-s3-pda \
        --delete \
        --profile bia \
        --cache-control "public, max-age=300"

    echo "envio concluido com sucesso"
}

envio_s3
