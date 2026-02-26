#!/usr/bin/env bash
set -euo pipefail

function build() {
    echo "iniciando build..."

    cd client
    npm install
    VITE_API_URL="bia-alb-1525537038.us-east-1.elb.amazonaws.com" npm run build

    echo "build finalizado"
    cd ..
}

build
