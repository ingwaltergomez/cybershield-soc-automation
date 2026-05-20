#!/bin/bash
# NPM-INTEGRATION-WAZUH.SH - Adaptado para Wazuh Dashboard

NPM_API_URL="http://localhost:81"
[ -f /opt/cybershield-soc-wazuh414/lib/config.sh ] && source /opt/cybershield-soc-wazuh414/lib/config.sh 2>/dev/null

get_npm_token() {
    local response
    response=$(curl -s -X POST "${NPM_API_URL}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${NPM_USER}\",\"secret\":\"${NPM_PASS}\"}" \
        --max-time 5 2>/dev/null)
    
    echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

create_npm_access_list() {
    local client_name="$1"
    local access_name="${client_name}-wazuh-access"
    
    echo "[NPM] Creando Access List: $access_name" >&2
    
    local token
    token=$(get_npm_token)
    [ -z "$token" ] && { echo "[NPM] ❌ Sin token" >&2; echo "0"; return 1; }
    
    # Verificar existencia
    local check
    check=$(curl -s -X GET "${NPM_API_URL}/api/nginx/access-lists" \
        -H "Authorization: Bearer $token" --max-time 5 2>/dev/null)
    
    if echo "$check" | grep -q "\"$access_name\""; then
        local existing_id
        existing_id=$(echo "$check" | grep -o "\"id\":[0-9]*[^}]*\"$access_name\"" | grep -o "id\":[0-9]*" | cut -d: -f2 | head -1)
        echo "[NPM] ✅ Ya existe: ID $existing_id" >&2
        echo "$existing_id"
        return 0
    fi
    
    # Crear Access List vacío
    curl -s -X POST "${NPM_API_URL}/api/nginx/access-lists" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$access_name\",\"satisfy_any\":true,\"pass_auth\":true}" > /dev/null
    
    sleep 2
    
    # Verificar
    local verify
    verify=$(curl -s -X GET "${NPM_API_URL}/api/nginx/access-lists" \
        -H "Authorization: Bearer $token" --max-time 5 2>/dev/null)
    
    if echo "$verify" | grep -q "\"$access_name\""; then
        local new_id
        new_id=$(echo "$verify" | grep -o "\"id\":[0-9]*[^}]*\"$access_name\"" | grep -o "id\":[0-9]*" | cut -d: -f2 | head -1)
        echo "[NPM] ✅ Creada: ID $new_id" >&2
        echo "$new_id"
        return 0
    else
        echo "[NPM] ❌ No se pudo crear" >&2
        echo "0"
        return 1
    fi
}

create_npm_proxy_host_wazuh() {
    local domain="$1"
    local access_id="$2"
    local forward_port="$3"
    local cert_id="${NPM_WILDCARD_CERT_ID:-10}"
    
    echo "[NPM] Creando Proxy Host para Wazuh Dashboard" >&2
    echo "[NPM] $domain → ${WAZUH_SERVER_IP:-YOUR_SERVER_IP}" >&2
    
    local token
    token=$(get_npm_token)
    [ -z "$token" ] && { echo "[NPM] ❌ Sin token" >&2; return 1; }
    
    # Verificar existencia
    local check
    check=$(curl -s -X GET "${NPM_API_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" --max-time 5 2>/dev/null)
    
    if echo "$check" | grep -q "\"$domain\""; then
        echo "[NPM] ⚠️  Ya existe - actualizando..." >&2
        local existing_id
        existing_id=$(echo "$check" | grep -o "\"id\":[0-9]*[^}]*\"$domain\"" | grep -o "id\":[0-9]*" | cut -d: -f2 | head -1)
        
        # Actualizar
        curl -s -X PUT "${NPM_API_URL}/api/nginx/proxy-hosts/${existing_id}" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\":[\"$domain\"],
                \"forward_scheme\":\"https\",
                \"forward_host\":\"${WAZUH_SERVER_IP:-YOUR_SERVER_IP}\",
                \"forward_port\":$forward_port,
                \"access_list_id\":$access_id,
                \"certificate_id\":$cert_id,
                \"ssl_forced\":true,
                \"http2_support\":true,
                \"hsts_enabled\":true,
                \"hsts_subdomains\":false,
                \"block_exploits\":true,
                \"allow_websocket_upgrade\":true,
                \"advanced_config\":\"# Wazuh Dashboard\nproxy_ssl_verify off;\",
                \"enabled\":true,
                \"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}
            }" > /dev/null
        
        echo "[NPM] ✅ Actualizado" >&2
        return 0
    fi
    
    # Crear nuevo proxy
    local response
    response=$(curl -s -X POST "${NPM_API_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\":[\"$domain\"],
            \"forward_scheme\":\"https\",
            \"forward_host\":\"${WAZUH_SERVER_IP:-YOUR_SERVER_IP}\",
            \"forward_port\":$forward_port,
            \"access_list_id\":$access_id,
            \"certificate_id\":$cert_id,
            \"ssl_forced\":true,
            \"http2_support\":true,
            \"hsts_enabled\":true,
            \"hsts_subdomains\":false,
            \"block_exploits\":true,
            \"allow_websocket_upgrade\":true,
            \"advanced_config\":\"# Wazuh Dashboard\nproxy_ssl_verify off;\",
            \"enabled\":true,
            \"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}
        }")
    
    if echo "$response" | grep -q '"id"'; then
        echo "[NPM] ✅ Creado exitosamente" >&2
        return 0
    else
        echo "[NPM] ❌ Error: $response" >&2
        return 1
    fi
}

setup_npm_for_wazuh_client() {
    local client_name="$1"
    local dashboard_port="$2"
    local create_access_list="${3:-no}"
    
    local domain="${client_name}.${NPM_DOMAIN_BASE}"
    
    echo ""
    echo "========================================" >&2
    echo "[NPM] CONFIGURANDO NPM PARA WAZUH" >&2
    echo "========================================" >&2
    echo "Cliente: $client_name" >&2
    echo "Dominio: $domain" >&2
    echo "Puerto: $dashboard_port" >&2
    echo "Access List: $create_access_list" >&2
    echo "========================================" >&2
    
    # 1. Access List (opcional)
    local access_id="0"
    if [ "$create_access_list" = "yes" ]; then
        access_id=$(create_npm_access_list "$client_name")
        if [ -z "$access_id" ] || [ "$access_id" = "0" ]; then
            echo "[NPM] ⚠️  Continuando sin Access List" >&2
            access_id="0"
        fi
    fi
    
    # 2. Proxy Host
    if create_npm_proxy_host_wazuh "$domain" "$access_id" "$dashboard_port"; then
        echo ""
        echo "========================================" >&2
        echo "✅ NPM CONFIGURADO EXITOSAMENTE" >&2
        echo "========================================" >&2
        echo "URL: https://$domain" >&2
        echo "Redirige a: https://${WAZUH_SERVER_IP:-YOUR_SERVER_IP}" >&2
        echo "SSL: Certificado wildcard ID $NPM_WILDCARD_CERT_ID" >&2
        echo "HTTP → HTTPS: Forzado" >&2
        if [ "$access_id" != "0" ]; then
            echo "Access List: ID $access_id" >&2
        fi
        echo "========================================" >&2
        return 0
    else
        echo "[NPM] ❌ Falló configuración NPM" >&2
        return 1
    fi
}
