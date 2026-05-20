#!/bin/bash
#
# Script: crear-cliente.sh
# Propósito: Crear stack Wazuh por cliente + NPM automático
# Versión: 5.0 - FINAL con NPM integrado
# Autor: CyberShield GT
# Fecha: 2026-04-15
#

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }

if [ $# -ne 1 ]; then
    echo "Uso: $0 <nombre_cliente>"
    echo "Ejemplo: $0 ingwaltergomez"
    exit 1
fi

CLIENTE=$1
BASE_DIR="/opt/cybershield-soc-wazuh414/stacks/${CLIENTE}"
TEMPLATE_DIR="/opt/cybershield-soc-wazuh414/wazuh-docker-oficial/single-node"

if [[ ! "$CLIENTE" =~ ^[a-z0-9_-]+$ ]]; then
    log_error "Nombre inválido. Solo minúsculas, números, guión y guión bajo."
    exit 1
fi

if [ -d "$BASE_DIR" ]; then
    log_error "El cliente ${CLIENTE} ya existe"
    exit 1
fi

log_info "======================================================================"
log_info "CREANDO STACK WAZUH PARA: ${CLIENTE}"
log_info "======================================================================"

# ============================================================================
# DETECTAR VERSIÓN
# ============================================================================

log_info "Detectando versión de Wazuh instalada..."

AVAILABLE_VERSIONS=$(docker images wazuh/wazuh-manager --format "{{.Tag}}" | grep -E "^4\.[0-9]+\.[0-9]+$" | sort -V)

if [ -z "$AVAILABLE_VERSIONS" ]; then
    log_error "No se encontraron imágenes de Wazuh instaladas"
    exit 1
fi

WAZUH_VERSION=$(echo "$AVAILABLE_VERSIONS" | tail -1)
log_success "Versión detectada: ${WAZUH_VERSION}"

# ============================================================================
# GENERAR CREDENCIALES ÚNICAS
# ============================================================================

log_info ""
log_info "Generando credenciales únicas para ${CLIENTE}..."

CLIENTE_USER="${CLIENTE}_admin"
CLIENTE_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9@#%-_=' | head -c 24)

log_success "Usuario: ${CLIENTE_USER}"
log_success "Password: ${CLIENTE_PASSWORD}"

# ============================================================================
# DETECTAR PUERTOS
# ============================================================================

log_info ""
log_info "Detectando puertos disponibles..."

find_free_port() {
    local base_port=$1
    local port=$base_port
    for ((i=0; i<100; i++)); do
        if ! ss -tln | grep -q ":${port} "; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done
    exit 1
}

INDEXER_PORT=$(find_free_port 9200)
DASHBOARD_PORT=$(find_free_port 5601)
API_PORT=$(find_free_port 55000)
AGENT_PORT=$(find_free_port 1514)

log_success "Puertos asignados:"
log_info "  Indexer:    ${INDEXER_PORT}"
log_info "  Dashboard:  ${DASHBOARD_PORT}"
log_info "  API:        ${API_PORT}"
log_info "  Agentes:    ${AGENT_PORT}"

# ============================================================================
# COPIAR TEMPLATE
# ============================================================================

log_info ""
log_info "Copiando template oficial..."

mkdir -p ${BASE_DIR}
cp -r ${TEMPLATE_DIR}/* ${BASE_DIR}/

log_success "Template copiado"

# ============================================================================
# CONFIGURAR DOCKER-COMPOSE
# ============================================================================

cd ${BASE_DIR}

log_info ""
log_info "Configurando docker-compose.yml..."

sed -i "s/9200:9200/${INDEXER_PORT}:9200/g" docker-compose.yml
sed -i "s/443:5601/${DASHBOARD_PORT}:5601/g" docker-compose.yml
sed -i "s/55000:55000/${API_PORT}:55000/g" docker-compose.yml
sed -i "s/1514:1514/${AGENT_PORT}:1514/g" docker-compose.yml
sed -i "s/1515:1515/$((AGENT_PORT+1)):1515/g" docker-compose.yml
sed -i '/- "514:514\/udp"/d' docker-compose.yml
sed -i "s/:4\.14\.[0-9]/:${WAZUH_VERSION}/g" docker-compose.yml
sed -i "s/container_name: single-node-wazuh.indexer/container_name: ${CLIENTE}-wazuh.indexer-1/g" docker-compose.yml
sed -i "s/container_name: single-node-wazuh.manager/container_name: ${CLIENTE}-wazuh.manager-1/g" docker-compose.yml
sed -i "s/container_name: single-node-wazuh.dashboard/container_name: ${CLIENTE}-wazuh.dashboard-1/g" docker-compose.yml

for VOL in wazuh_api_configuration wazuh_etc wazuh_logs wazuh_queue wazuh_var_multigroups \
           wazuh_integrations wazuh_active_response wazuh_agentless wazuh_wodles \
           filebeat_etc filebeat_var wazuh-indexer-data wazuh-dashboard-config wazuh-dashboard-custom; do
    sed -i "s/single-node_${VOL}/${CLIENTE}_${VOL}/g" docker-compose.yml
done

log_success "Configuración completada"

# ============================================================================
# GENERAR CERTIFICADOS
# ============================================================================

log_info ""
log_info "Generando certificados SSL..."

docker compose -f generate-indexer-certs.yml run --rm generator

log_success "Certificados generados"

# ============================================================================
# INICIAR STACK
# ============================================================================

log_info ""
log_info "Iniciando stack..."

docker compose up -d

log_info "Esperando 90 segundos para inicialización..."
sleep 90

# ============================================================================
# CREAR USUARIO ÚNICO
# ============================================================================

log_info ""
log_info "Creando usuario único: ${CLIENTE_USER}..."

max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if docker exec ${CLIENTE}-wazuh.indexer-1 curl -s -k -u admin:SecretPassword https://localhost:9200 > /dev/null 2>&1; then
        log_success "Indexer listo"
        break
    fi
    attempt=$((attempt + 1))
    sleep 5
done

if [ $attempt -lt $max_attempts ]; then
    docker exec ${CLIENTE}-wazuh.indexer-1 curl -s -k -u admin:SecretPassword \
        -X PUT "https://localhost:9200/_plugins/_security/api/internalusers/${CLIENTE_USER}" \
        -H "Content-Type: application/json" \
        -d "{
          \"password\": \"${CLIENTE_PASSWORD}\",
          \"backend_roles\": [\"admin\"],
          \"attributes\": {}
        }" > /dev/null
    
    sleep 3
    
    if docker exec ${CLIENTE}-wazuh.indexer-1 curl -s -k -u ${CLIENTE_USER}:${CLIENTE_PASSWORD} https://localhost:9200 > /dev/null 2>&1; then
        log_success "Usuario ${CLIENTE_USER} creado"
        USER_CREATED=true
        
        docker exec ${CLIENTE}-wazuh.indexer-1 curl -s -k -u admin:SecretPassword \
            -X DELETE "https://localhost:9200/_plugins/_security/api/cache" > /dev/null 2>&1
    else
        log_warning "No se pudo crear usuario - usa admin/SecretPassword"
        USER_CREATED=false
        CLIENTE_USER="admin"
        CLIENTE_PASSWORD="SecretPassword"
    fi
else
    log_warning "Timeout - usa admin/SecretPassword"
    USER_CREATED=false
    CLIENTE_USER="admin"
    CLIENTE_PASSWORD="SecretPassword"
fi

# ============================================================================
# CONFIGURAR NPM
# ============================================================================

log_info ""
log_info "Configurando NPM..."

# Cargar configuración NPM
source /opt/cybershield-soc-wazuh414/lib/config.sh 2>/dev/null || true

if [ -n "$NPM_USER" ] && [ -n "$NPM_PASS" ]; then
    # Obtener token NPM
    NPM_TOKEN=$(curl -s -X POST "http://localhost:81/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${NPM_USER}\",\"secret\":\"${NPM_PASS}\"}" 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$NPM_TOKEN" ]; then
        DOMAIN="${CLIENTE}.${NPM_DOMAIN_BASE:-soc.yourdomain.com}"
        
        # Crear proxy host
        NPM_RESPONSE=$(curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" \
            -H "Authorization: Bearer $NPM_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\": [\"${DOMAIN}\"],
                \"forward_scheme\": \"https\",
                \"forward_host\": \"${WAZUH_SERVER_IP:-YOUR_SERVER_IP}\",
                \"forward_port\": ${DASHBOARD_PORT},
                \"access_list_id\": 0,
                \"certificate_id\": 1,
                \"ssl_forced\": true,
                \"http2_support\": true,
                \"hsts_enabled\": true,
                \"hsts_subdomains\": false,
                \"block_exploits\": true,
                \"allow_websocket_upgrade\": true,
                \"advanced_config\": \"# Wazuh Dashboard\\nproxy_ssl_verify off;\",
                \"enabled\": true
            }" 2>/dev/null)
        
        if echo "$NPM_RESPONSE" | grep -q '"id"'; then
            log_success "NPM configurado: https://${DOMAIN}"
            NPM_CONFIGURED=true
        else
            log_warning "NPM no configurado - hazlo manualmente"
            NPM_CONFIGURED=false
        fi
    else
        log_warning "No se pudo autenticar en NPM"
        NPM_CONFIGURED=false
    fi
else
    log_warning "Configuración NPM no encontrada"
    NPM_CONFIGURED=false
fi

# ============================================================================
# VERIFICAR ESTADO
# ============================================================================

log_info ""
log_info "Verificando estado..."

sleep 10

CONTAINERS_UP=$(docker ps | grep ${CLIENTE} | grep "Up" | wc -l)

if [ $CONTAINERS_UP -eq 3 ]; then
    log_success "Los 3 contenedores están UP"
else
    log_warning "Solo ${CONTAINERS_UP}/3 contenedores están UP"
fi

# ============================================================================
# GUARDAR CREDENCIALES
# ============================================================================

if [ "$USER_CREATED" = true ]; then
    CRED_STATUS="✅ Usuario único creado automáticamente"
else
    CRED_STATUS="⚠️  Usuario por defecto (cambiar manualmente)"
fi

if [ "$NPM_CONFIGURED" = true ]; then
    NPM_STATUS="✅ Configurado automáticamente"
    URL_DOMINIO="https://${CLIENTE}.${NPM_DOMAIN_BASE:-soc.yourdomain.com}"
else
    NPM_STATUS="⚠️  Configurar manualmente"
    URL_DOMINIO="https://${CLIENTE}.${NPM_DOMAIN_BASE:-soc.yourdomain.com} (pendiente)"
fi

cat > CLIENTE_INFO.txt << EOFINFO
================================================================================
WAZUH STACK - CLIENTE: ${CLIENTE}
================================================================================
Fecha: $(date)
Versión: Wazuh ${WAZUH_VERSION}

ACCESO WEB:
  URL Local:   https://${WAZUH_SERVER_IP:-YOUR_SERVER_IP}:${DASHBOARD_PORT}
  URL Dominio: ${URL_DOMINIO}
  Estado NPM:  ${NPM_STATUS}

🔐 CREDENCIALES PARA ENTREGAR AL CLIENTE:
  Usuario:  ${CLIENTE_USER}
  Password: ${CLIENTE_PASSWORD}
  
  Estado: ${CRED_STATUS}

📋 CREDENCIALES DE ADMINISTRACIÓN (NO COMPARTIR):
  Usuario:  admin
  Password: SecretPassword
  (Solo para configuración y soporte técnico)

PUERTOS:
  Dashboard:  ${DASHBOARD_PORT}
  API:        ${API_PORT}
  Indexer:    ${INDEXER_PORT}
  Agentes:    ${AGENT_PORT}

CONTENEDORES:
  - ${CLIENTE}-wazuh.indexer-1
  - ${CLIENTE}-wazuh.manager-1
  - ${CLIENTE}-wazuh.dashboard-1

DIRECTORIO:
  ${BASE_DIR}

COMANDOS:
  cd ${BASE_DIR}
  docker compose logs -f
  docker compose ps
  docker compose restart
  docker compose down
  docker compose up -d

REGISTRO DE AGENTES:
  WAZUH_MANAGER="${WAZUH_SERVER_IP:-YOUR_SERVER_IP}:${AGENT_PORT}"
  WAZUH_REGISTRATION_PASSWORD="${CLIENTE_PASSWORD}" \\
  WAZUH_AGENT_NAME="nombre-agente"

PRÓXIMOS PASOS:
  1. Acceder a ${URL_DOMINIO}
  2. Login: ${CLIENTE_USER} / ${CLIENTE_PASSWORD}
  3. Guardar credenciales en Bitwarden
  4. Registrar agentes

NOTAS:
  - El usuario ${CLIENTE_USER} tiene permisos completos
  - El usuario admin queda como respaldo para soporte
  - Cada cliente tiene credenciales únicas
  - NPM configurado con SSL automático (cert wildcard)

================================================================================
EOFINFO

chmod 600 CLIENTE_INFO.txt

# ============================================================================
# RESUMEN
# ============================================================================

log_success ""
log_success "======================================================================"
log_success "✅ CLIENTE ${CLIENTE} CREADO EXITOSAMENTE"
log_success "======================================================================"
echo ""
cat CLIENTE_INFO.txt
echo ""
log_warning "🔐 Credenciales: ${BASE_DIR}/CLIENTE_INFO.txt"
log_success "======================================================================"

docker ps | grep ${CLIENTE}

exit 0
