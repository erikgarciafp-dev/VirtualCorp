#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/router_base.sh"


check_prerequisites

# Crea el template pel router
# create_router_template

# Desplegament de mikrotiK0
create_router "mikrotik0" 2200 \
  --intnets "r0-r1" "dmz" \
  --ips "10.7.254.1/30" "10.7.1.1/25" \
  --nat

# Desplegament de mikrotiK1
create_router "mikrotik1" 2201 \
  --intnets "r0-r1" "r1-r2" "plo" \
  --ips "10.7.254.2/30" "10.7.254.5/30" "10.7.2.1/25" \
  --gateway "10.7.254.1"

# Desplegament de mikrotiK2
create_router "mikrotik2" 2202 \
  --intnets "r1-r2" "r2-r3" "pl1" "pl2" \
  --ips "10.7.254.6/30" "10.7.254.9/30" "10.7.3.1/24" "10.7.4.1/24" \
  --gateway "10.7.254.5"

# Desplegament de mikrotiK3
create_router "mikrotik3" 2203 \
  --intnets "r2-r3" "pl3" "pl3-direccio" \
  --ips "10.7.254.10/30" "10.7.5.1/25" "10.7.5.129/25" \
  --gateway "10.7.254.9"

log_info "=========================================="
log_info "[+] Routers desplegats correctament."
log_info "=========================================="
