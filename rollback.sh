#!/bin/bash
set -e

# Configurações
CLUSTER_NAME="cluster-bia"
SERVICE_NAME="service-bia"
TASK_FAMILY="task-def-bia"
REGION="us-east-1"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Rollback BIA ===${NC}\n"

# Obter revisão atual
echo -e "${YELLOW}🔍 Buscando revisão atual...${NC}"
CURRENT_REVISION=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $REGION \
    --query 'services[0].taskDefinition' \
    --output text | awk -F':' '{print $NF}')

echo -e "${GREEN}📋 Revisão atual: ${CURRENT_REVISION}${NC}"

# Listar últimas 5 revisões
echo -e "\n${YELLOW}📜 Últimas revisões disponíveis:${NC}\n"
REVISIONS=$(aws ecs list-task-definitions \
    --family-prefix $TASK_FAMILY \
    --region $REGION \
    --sort DESC \
    --max-items 5 \
    --query 'taskDefinitionArns[]' \
    --output text)

i=1
for rev in $REVISIONS; do
    REV_NUM=$(echo $rev | awk -F':' '{print $NF}')
    IMAGE=$(aws ecs describe-task-definition \
        --task-definition $rev \
        --region $REGION \
        --query 'taskDefinition.containerDefinitions[0].image' \
        --output text | awk -F':' '{print $NF}')
    
    if [ "$REV_NUM" == "$CURRENT_REVISION" ]; then
        echo -e "${GREEN}  $i) Revisão ${REV_NUM} (ATUAL) - ${IMAGE}${NC}"
    else
        echo -e "  $i) Revisão ${REV_NUM} - ${IMAGE}"
    fi
    i=$((i+1))
done

# Solicitar revisão para rollback
echo -e "\n${YELLOW}Digite o número da revisão para rollback:${NC}"
read -p "> " CHOICE

# Validar escolha
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt 5 ]; then
    echo -e "${RED}❌ Escolha inválida${NC}"
    exit 1
fi

# Obter revisão escolhida
TARGET_REVISION=$(echo "$REVISIONS" | awk -v choice=$CHOICE 'NR==choice {print $1}' | awk -F':' '{print $NF}')

if [ "$TARGET_REVISION" == "$CURRENT_REVISION" ]; then
    echo -e "${RED}❌ Revisão escolhida já é a atual${NC}"
    exit 1
fi

# Confirmar rollback
echo -e "\n${YELLOW}⚠️  Confirma rollback da revisão ${CURRENT_REVISION} para ${TARGET_REVISION}?${NC}"
read -p "(y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Rollback cancelado${NC}"
    exit 0
fi

# Executar rollback
echo -e "\n${YELLOW}🔄 Executando rollback...${NC}"
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition ${TASK_FAMILY}:${TARGET_REVISION} \
    --region $REGION \
    --query 'service.serviceName' \
    --output text > /dev/null

echo -e "${GREEN}✅ Rollback iniciado${NC}"

# Aguardar estabilização
echo -e "\n${YELLOW}⏳ Aguardando estabilização...${NC}"
aws ecs wait services-stable --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION

# Obter IP para teste
INSTANCE_ID=$(aws ecs list-container-instances --cluster $CLUSTER_NAME --region $REGION --query 'containerInstanceArns[0]' --output text | awk -F'/' '{print $NF}')
EC2_INSTANCE=$(aws ecs describe-container-instances --cluster $CLUSTER_NAME --container-instances $INSTANCE_ID --region $REGION --query 'containerInstances[0].ec2InstanceId' --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo -e "\n${GREEN}✅ Rollback concluído!${NC}"
echo -e "${GREEN}📋 Revisão: ${TASK_FAMILY}:${TARGET_REVISION}${NC}"
echo -e "${GREEN}🌐 URL: http://${PUBLIC_IP}${NC}"
