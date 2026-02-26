#!/usr/bin/env bash
set -euo pipefail

. build_react.sh

echo "🚀 Iniciando deploy para o S3..."

. s3.sh

echo "✅ Deploy concluído com sucesso!"
