#!/bin/sh
set -e

echo "Executando migrations..."
npx sequelize db:migrate

echo "Iniciando servidor..."
exec npm start
