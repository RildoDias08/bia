FROM public.ecr.aws/docker/library/node:22-slim
RUN npm install -g npm@11 --loglevel=error

# Instalando curl
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Copiar package.json raiz primeiro
COPY package*.json ./
RUN npm install --loglevel=error

# Copiar package.json do client e instalar dependências (incluindo devDependencies para build)
COPY client/package*.json ./client/
RUN cd client && npm install --legacy-peer-deps --loglevel=error

# Copiar todos os arquivos
COPY . .

# Build do front-end com Vite
RUN cd client && VITE_API_URL=https://teste.rio-aws.com.br npm run build

# Limpeza das dependências de desenvolvimento do client para reduzir tamanho
RUN cd client && npm prune --production && rm -rf node_modules/.cache

EXPOSE 8080

# Garanta que o arquivo foi copiado (você já tinha isso na linha 29)
COPY start.sh /usr/src/app/start.sh

# Garanta a permissão de execução
RUN chmod +x /usr/src/app/start.sh

# A mágica acontece aqui: mude de ["npm", "start"] para:
ENTRYPOINT ["/usr/src/app/start.sh"]
