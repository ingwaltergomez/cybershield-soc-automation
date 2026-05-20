#!/bin/bash
# UTILITIES.SH - Funciones helper y utilidades

# ========== LOGGING ==========
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { [ "${DEBUG:-false}" = "true" ] && echo -e "${MAGENTA}[DEBUG]${NC} $1"; }

# ========== PRUEBAS UNITARIAS ==========
run_tests() {
    local test_name="$1"
    echo -e "${BLUE}[TEST] ${test_name}...${NC}"
}

assert() {
    local condition="$1"
    local message="$2"
    
    if eval "$condition"; then
        echo -e "  ${GREEN}✓ ${message}${NC}"
        return 0
    else
        echo -e "  ${RED}✗ FAIL: ${message}${NC}"
        return 1
    fi
}

# ========== VALIDACIONES ==========
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Comando requerido no encontrado: $cmd"
        return 1
    fi
    return 0
}

check_service() {
    local service="$1"
    local url="$2"
    local timeout="${3:-5}"
    
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null || echo "000")
    
    if [ "$status_code" = "200" ] || [ "$status_code" = "401" ] || [ "$status_code" = "403" ]; then
        return 0
    else
        log_error "Servicio $service no responde (HTTP $status_code)"
        return 1
    fi
}

# ========== MANEJO DE ARCHIVOS ==========
create_directory() {
    local dir="$1"
    local description="${2:-Directorio}"
    
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        if [ $? -eq 0 ]; then
            log_success "$description creado: $dir"
            return 0
        else
            log_error "No se pudo crear $description: $dir"
            return 1
        fi
    else
        log_warning "$description ya existe: $dir"
        return 0
    fi
}

safe_cp() {
    local src="$1"
    local dst="$2"
    
    if [ -e "$src" ]; then
        cp -r "$src" "$dst" 2>/dev/null && return 0 || {
            log_warning "No se pudo copiar $src a $dst"
            return 1
        }
    else
        log_warning "Origen no existe: $src"
        return 1
    fi
}

# ========== SEGURIDAD ==========
generate_password() {
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
    echo
}

sanitize_filename() {
    local filename="$1"
    echo "$filename" | sed 's/[^a-zA-Z0-9._-]/-/g'
}

# ========== FORMATO ==========
print_header() {
    local title="$1"
    local color="${2:-CYAN}"
    local length="${3:-50}"
    
    eval "local color_code=\$$color"
    
    echo -e "${color_code}${BOLD}"
    printf "═%.0s" $(seq 1 "$length")
    echo ""
    echo " $title"
    printf "═%.0s" $(seq 1 "$length")
    echo -e "${NC}\n"
}

print_separator() {
    local char="${1:-─}"
    local length="${2:-50}"
    printf "$char%.0s" $(seq 1 "$length")
    echo ""
}

# ========== HELPERS JSON ==========
json_get() {
    local file="$1"
    local key="$2"
    
    if [ -f "$file" ] && command -v jq &> /dev/null; then
        jq -r ".$key" "$file" 2>/dev/null || echo ""
    else
        grep -o "\"$key\":\"[^\"]*\"" "$file" 2>/dev/null | cut -d'"' -f4 || \
        grep -o "\"$key\":[0-9]*" "$file" 2>/dev/null | cut -d: -f2 || echo ""
    fi
}

json_set() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    if [ -f "$file" ] && command -v jq &> /dev/null; then
        jq ".$key = \"$value\"" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    else
        log_warning "jq no disponible, no se puede modificar JSON"
    fi
}

# ========== RETRY LOGIC ==========
retry_command() {
    local cmd="$1"
    local max_retries="${2:-3}"
    local delay="${3:-2}"
    local description="${4:-Comando}"
    
    local retry_count=0
    local exit_code=1
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$cmd"; then
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warning "Reintento $retry_count/$max_retries para: $description"
                sleep "$delay"
            fi
        fi
    done
    
    log_error "Falló después de $max_retries intentos: $description"
    return 1
}

# -- FIN UTILITIES --




# ========== FUNCIONES PARA CLIENT-MANAGEMENT.SH ==========
# Estas funciones son requeridas por create_client()

# Función: get_tier_price
get_tier_price() {
    local tier="$1"
    
    # Convertir a minúsculas para comparación
    local tier_lower=$(echo "$tier" | tr '[:upper:]' '[:lower:]')
    
    case "$tier_lower" in
        "basic")
            echo "1500"
            ;;
        "professional")
            echo "4500"
            ;;
        "enterprise")
            echo "9000"
            ;;
        *)
            echo "0"
            log_warning "Tier desconocido: $tier - usando precio 0"
            ;;
    esac
}

# Función: validate_client_name
validate_client_name() {
    local client_name="$1"
    
    if [ -z "$client_name" ]; then
        log_error "El nombre del cliente no puede estar vacío"
        return 1
    fi
    
    # Validar longitud mínima
    if [ ${#client_name} -lt 3 ]; then
        log_error "El nombre del cliente debe tener al menos 3 caracteres"
        return 1
    fi
    
    # Validar caracteres permitidos
    if [[ ! "$client_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Nombre inválido. Solo se permiten letras, números, guiones y guiones bajos"
        return 1
    fi
    
    # Verificar si ya existe
    local client_dir="/opt/cybershield-soc/clients/$client_name"
    if [ -d "$client_dir" ]; then
        log_error "El cliente '$client_name' ya existe en $client_dir"
        return 1
    fi
    
    log_success "Nombre de cliente válido: $client_name"
    return 0
}

# Función: validate_tier
validate_tier() {
    local tier="$1"
    
    # Convertir a minúsculas para comparación
    local tier_lower=$(echo "$tier" | tr '[:upper:]' '[:lower:]')
    
    case "$tier_lower" in
        "basic"|"professional"|"enterprise")
            log_success "Tier válido: $tier"
            return 0
            ;;
        *)
            log_error "Tier inválido: $tier"
            log_error "Tiers válidos: Basic, Professional, Enterprise"
            return 1
            ;;
    esac
}

# Función: test_environment
test_environment() {
    log_info "Ejecutando pruebas del entorno..."
    
    local all_tests_passed=true
    
    # 1. Verificar directorios críticos
    log_info "Verificando directorios críticos..."
    
    local critical_dirs=(
        "/opt/cybershield-soc"
        "/opt/cybershield-soc/clients"
        "/opt/cybershield-soc/lib"
        "/opt/cybershield-soc/templates"
    )
    
    for dir in "${critical_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_success "  Directorio $dir existe"
        else
            log_error "  Directorio $dir no existe"
            all_tests_passed=false
        fi
    done
    
    # 2. Verificar comandos críticos
    log_info "Verificando comandos críticos..."
    
    local critical_commands=(
        "docker"
        "docker-compose"
        "curl"
        "jq"
        "grep"
        "awk"
        "sed"
    )
    
    for cmd in "${critical_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "  Comando $cmd disponible"
        else
            log_error "  Comando $cmd no disponible"
            all_tests_passed=false
        fi
    done
    
    # 3. Verificar servicios Docker críticos
    log_info "Verificando servicios Docker..."
    
    local critical_services=(
        "elasticsearch"
        "wazuh"
        "grafana"
        "nginx-proxy-manager"
    )
    
    for service in "${critical_services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "$service"; then
            log_success "  Servicio $service está corriendo"
        else
            log_warning "  Servicio $service no está corriendo"
            # No es crítico para todos los tests
        fi
    done
    
    # 4. Verificar puertos críticos
    log_info "Verificando puertos críticos..."
    
    local critical_ports=(
        "5601: Kibana"
        "9200: Elasticsearch"
        "3000: Grafana"
        "81: Nginx Proxy Manager"
    )
    
    for port_info in "${critical_ports[@]}"; do
        port=$(echo "$port_info" | cut -d: -f1)
        service=$(echo "$port_info" | cut -d: -f2-)
        
        if ss -tuln | grep -q ":$port "; then
            log_success "  Puerto $port ($service) está escuchando"
        else
            log_warning "  Puerto $port ($service) NO está escuchando"
        fi
    done
    
    # Resultado final
    if $all_tests_passed; then
        log_success "Todas las pruebas del entorno pasaron"
        return 0
    else
        log_error "Algunas pruebas del entorno fallaron"
        return 1
    fi
}

# Función: safe_cp (referenciada en client-management.sh)
safe_cp() {
    local source="$1"
    local destination="$2"
    
    if [ ! -e "$source" ]; then
        log_error "Origen no existe: $source"
        return 1
    fi
    
    # Crear directorio de destino si no existe
    mkdir -p "$(dirname "$destination")"
    
    # Copiar
    if cp -r "$source" "$destination" 2>/dev/null; then
        log_success "Copiado exitoso: $source → $destination"
        return 0
    else
        log_error "Error copiando: $source → $destination"
        return 1
    fi
}

# ========== STUB FUNCTIONS (para evitar errores) ==========
# Estas funciones son llamadas por client-management.sh pero pueden no estar implementadas

# Stub: get_services_json
get_services_json() {
    log_info "Generando JSON de servicios (stub)"
    
    # JSON básico con servicios del SOC
    cat << JSON
{
  "services": [
    {
      "name": "Wazuh HIDS",
      "status": "active",
      "description": "Sistema de detección de intrusiones basado en host"
    },
    {
      "name": "Elasticsearch SIEM",
      "status": "active", 
      "description": "Motor de búsqueda y análisis de logs"
    },
    {
      "name": "Grafana Dashboards",
      "status": "active",
      "description": "Dashboards de monitoreo y visualización"
    }
  ],
  "client": "$1",
  "timestamp": "$(date -Iseconds)"
}
JSON
}

# Stub: setup_elasticsearch_for_client
setup_elasticsearch_for_client() {
    local client_name="$1"
    log_info "Configurando Elasticsearch para $client_name (stub)"
    
    # En una implementación real, aquí se crearían índices, usuarios, etc.
    echo "  • Índice Elasticsearch: wazuh-alerts-${client_name,,}" > "/opt/cybershield-soc/configs/clients/$client_name/elastic-config.txt"
    echo "  • Usuario: ${client_name}_user" >> "/opt/cybershield-soc/configs/clients/$client_name/elastic-config.txt"
    echo "  • Configuración automática pendiente" >> "/opt/cybershield-soc/configs/clients/$client_name/elastic-config.txt"
    
    return 0
}

# Stub: create_grafana_dashboard
create_grafana_dashboard() {
    local client_name="$1"
    local tier="$2"
    local client_lower="$3"
    local domain="$4"
    
    log_info "Configurando dashboard Grafana para $client_name (stub)"
    
    # Crear archivo de configuración básico
    local config_file="/opt/cybershield-soc/configs/clients/$client_name/grafana-config.txt"
    
    cat > "$config_file" << CONFIG
# Configuración Grafana para ${client_name}
# Tier: ${tier}
# Domain: ${domain}

URL Dashboard: https://${domain}/dashboard
Usuario: admin
Contraseña: [configurar en Grafana]

Dashboards incluidos:
1. Visión General de Seguridad
2. Análisis de Logs
3. Monitorización de Sistemas
4. Alertas y Eventos

Para configurar manualmente:
1. Acceder a Grafana: http://localhost:3000
2. Crear organización: ${client_name}
3. Configurar datasource: Elasticsearch (http://elasticsearch:9200)
4. Importar dashboards desde templates/

NOTA: Configuración automática pendiente de implementación.
CONFIG
    
    log_success "Configuración Grafana creada: $config_file"
    return 0
}

# Stub: get_services_markdown
get_services_markdown() {
    local client_name="$1"
    
    cat << MARKDOWN
## Servicios Incluidos - ${client_name}

### ✅ Wazuh HIDS (Host-based Intrusion Detection System)
- Monitoreo continuo de sistemas
- Detección de malware y vulnerabilidades
- Cumplimiento de normativas
- Análisis de integridad de archivos

### ✅ Elasticsearch SIEM
- Centralización de logs
- Búsqueda y análisis en tiempo real
- Retención configurable (30 días)
- Alertas automatizadas

### ✅ Grafana Dashboards  
- Visualización personalizada
- Reportes automáticos
- Paneles multi-usuario
- Acceso remoto seguro

### 🔄 Nginx Proxy Manager
- Acceso HTTPS seguro
- Balanceo de carga
- Control de acceso
- Certificados SSL automáticos

---

*Última actualización: $(date)*
MARKDOWN
}

# Stub: generate_invoice
generate_invoice() {
    local client_name="$1"
    local tier="$2"
    local price="$3"
    local client_dir="$4"
    
    log_info "Generando factura para $client_name (stub)"
    
    local invoice_file="$client_dir/facturas/factura-inicial-$(date +%Y%m%d).txt"
    
    cat > "$invoice_file" << INVOICE
==========================================
         FACTURA CYBERSHIELDGT SOC
==========================================
Cliente: ${client_name}
NIT/CUI: [PENDIENTE]
Dirección: [PENDIENTE]

==========================================
DETALLE DE SERVICIOS
==========================================
Servicio: SOC as a Service - Tier ${tier}
Período: $(date +"%B %Y")
Monto: Q${price}.00

Descripción:
- Monitoreo de seguridad 24/7
- Dashboards personalizados
- Alertas y notificaciones
- Soporte técnico básico
- Actualizaciones de seguridad

==========================================
TOTAL: Q${price}.00
==========================================
Forma de pago: Transferencia bancaria
Fecha de emisión: $(date +"%d/%m/%Y")
Fecha de vencimiento: $(date -d "+15 days" +"%d/%m/%Y")

==========================================
DATOS BANCARIOS
==========================================
Banco: [CONFIGURAR]
Cuenta: [CONFIGURAR]
Titular: CyberShieldGT SOC
Referencia: ${client_name}-$(date +%Y%m)

==========================================
NOTAS
==========================================
1. Esta es una factura de demostración
2. Para facturación real, configurar en billing.sh
3. Contacto: ${CONTACT_EMAIL:-contact@yourdomain.com}

INVOICE
    
    log_success "Factura generada: $invoice_file"
    return 0
}

# Stub: configure_npm_domain (si es necesaria)
configure_npm_domain() {
    log_info "Configurando dominio NPM (stub)"
    return 0
}

# Función: print_client_summary (completa)
print_client_summary() {
    local client_name="$1"
    local tier="$2"
    local price="$3"
    local client_dir="$4"
    
    print_header "RESUMEN DE CLIENTE CREADO"
    echo -e "Nombre: ${GREEN}$client_name${NC}"
    echo -e "Tier: ${CYAN}$tier${NC}"
    echo -e "Precio mensual: ${GREEN}Q$price${NC}"
    echo -e "Directorio: $client_dir"
    
    if [ -f "$client_dir/install-summary.txt" ]; then
        echo -e "\n${YELLOW}Resumen de instalación:${NC}"
        cat "$client_dir/install-summary.txt"
    fi
    
    echo -e "\n${CYAN}Próximos pasos:${NC}"
    echo "1. Instalar agente en sistemas del cliente"
    echo "2. Configurar alertas y notificaciones"
    echo "3. Revisar dashboards personalizados"
    echo "4. Programar revisión de seguridad inicial"
    
    print_separator "="
}

# ========== FUNCIÓN: create_npm_manual_fallback ==========
create_npm_manual_fallback() {
    local client_name="$1"
    local domain="$2"
    local dest_port="$3"
    local client_dir="$4"
    
    echo "[NPM-MANUAL] Creando configuración manual para $client_name"
    
    local manual_file="$client_dir/npm-manual-config.txt"
    
    cat > "$manual_file" << MANUAL
# CONFIGURACIÓN MANUAL NPM - $client_name
# La configuración automática falló - siga estos pasos:

1. ACCEDER A NPM:
   URL: ${NPM_API_URL:-http://localhost:81}
   Usuario: ${NPM_USER:-email@example.com}
   Contraseña: [configurada en el sistema]

2. CREAR PROXY HOST:
   - Click en "Proxy Hosts" → "Add Proxy Host"
   - Domain Names: $domain
   - Scheme: http
   - Forward Hostname: localhost
   - Forward Port: $dest_port
   - Cache Assets: ON
   - Block Common Exploits: ON
   - Force SSL: ON (recomendado)

3. GUARDAR Y VERIFICAR:
   - Acceder a: https://$domain/dashboard
   - Debería mostrar el dashboard de Grafana

NOTA: Esta configuración es NECESARIA para acceso remoto seguro.
MANUAL
    
    echo "[NPM-MANUAL] ✅ Instrucciones manuales creadas: $(basename "$manual_file")"
    
    # Agregar al resumen
    if [ -f "$client_dir/install-summary.txt" ]; then
        echo "   • Ver archivo: npm-manual-config.txt" >> "$client_dir/install-summary.txt"
    fi
    
    return 0
}
