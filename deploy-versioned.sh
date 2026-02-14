#!/bin/bash
set -e

# Configurações
CLUSTER_NAME="cluster-bia"
SERVICE_NAME="service-bia"
TASK_FAMILY="task-def-bia"
ECR_REPO="749856334984.dkr.ecr.us-east-1.amazonaws.com/bia"
REGION="us-east-1"

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Deploy Versionado BIA ===${NC}\n"

# Validar repositório git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Erro: Não é um repositório git${NC}"
    exit 1
fi

# Obter commit hash
COMMIT_HASH=$(git rev-parse --short=7 HEAD)
echo -e "${GREEN}📌 Commit hash: ${COMMIT_HASH}${NC}"

# Obter IP público da instância EC2 do cluster
echo -e "\n${YELLOW}🔍 Buscando IP da instância EC2...${NC}"
INSTANCE_ID=$(aws ecs list-container-instances --cluster $CLUSTER_NAME --region $REGION --query 'containerInstanceArns[0]' --output text | awk -F'/' '{print $NF}')
if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}❌ Nenhuma instância encontrada no cluster${NC}"
    exit 1
fi

EC2_INSTANCE=$(aws ecs describe-container-instances --cluster $CLUSTER_NAME --container-instances $INSTANCE_ID --region $REGION --query 'containerInstances[0].ec2InstanceId' --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
    echo -e "${RED}❌ Instância não tem IP público${NC}"
    exit 1
fi

echo -e "${GREEN}✅ IP encontrado: ${PUBLIC_IP}${NC}"

# Verificar se imagem já existe
echo -e "\n${YELLOW}🔍 Verificando se imagem já existe no ECR...${NC}"
if aws ecr describe-images --repository-name bia --image-ids imageTag=$COMMIT_HASH --region $REGION > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Imagem ${COMMIT_HASH} já existe no ECR${NC}"
    read -p "Deseja continuar com o deploy? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deploy cancelado${NC}"
        exit 0
    fi
else
    # Login no ECR
    echo -e "\n${YELLOW}🔐 Login no ECR...${NC}"
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

    # Build da imagem
    echo -e "\n${YELLOW}🔨 Building imagem com tag ${COMMIT_HASH}...${NC}"
    docker build --build-arg VITE_API_URL=http://$PUBLIC_IP -t $ECR_REPO:$COMMIT_HASH .

    # Tag latest
    docker tag $ECR_REPO:$COMMIT_HASH $ECR_REPO:latest

    # Push para ECR
    echo -e "\n${YELLOW}📤 Push para ECR...${NC}"
    docker push $ECR_REPO:$COMMIT_HASH
    docker push $ECR_REPO:latest
    echo -e "${GREEN}✅ Imagem enviada para ECR${NC}"
fi

# Obter task definition atual
echo -e "\n${YELLOW}📋 Obtendo task definition atual...${NC}"
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION)

# Criar nova task definition com imagem versionada
echo -e "${YELLOW}📝 Criando nova task definition...${NC}"
NEW_TASK_DEF=$(echo $TASK_DEF | jq --arg IMAGE "$ECR_REPO:$COMMIT_HASH" '
  .taskDefinition |
  .containerDefinitions[0].image = $IMAGE |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
')

NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json "$NEW_TASK_DEF" --query 'taskDefinition.revision' --output text)
echo -e "${GREEN}✅ Task definition registrada: ${TASK_FAMILY}:${NEW_REVISION}${NC}"

# Atualizar serviço
echo -e "\n${YELLOW}🚀 Atualizando serviço ECS...${NC}"
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition ${TASK_FAMILY}:${NEW_REVISION} \
    --region $REGION \
    --query 'service.serviceName' \
    --output text > /dev/null

echo -e "${GREEN}✅ Deploy iniciado${NC}"

# Aguardar deploy
echo -e "\n${YELLOW}⏳ Aguardando deploy completar...${NC}"
aws ecs wait services-stable --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION

echo -e "\n${GREEN}✅ Deploy concluído com sucesso!${NC}"
echo -e "\n${GREEN}📦 Versão: ${COMMIT_HASH}${NC}"
echo -e "${GREEN}📋 Task Definition: ${TASK_FAMILY}:${NEW_REVISION}${NC}"
echo -e "${GREEN}🌐 URL: http://${PUBLIC_IP}${NC}"
