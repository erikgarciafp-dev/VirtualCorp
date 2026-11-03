#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/router_base.sh"

check_prerequisites

# Desplegament de mikrotik0 (planta baixa)
create_router "mikrotik0" 2200 \
  --intnets "rt0_1" "pl0" "privada" "dmz" \
  --ips "10.7.0.225/30" "10.7.0.1/25" "10.7.0.129/26" "10.7.0.193/27" \
  --nat

# Desplegament de mikrotik1 (planta 1)
create_router "mikrotik1" 2201 \
  --intnets "rt0_1" "rt1_2" "pl1" \
  --ips "10.7.0.226/30" "10.7.0.229/30" "10.7.1.1/24" \
  --gateway "10.7.0.225"

# Desplegament de mikrotik2 (planta 2)
create_router "mikrotik2" 2202 \
  --intnets "rt1_2" "rt2_3" "pl2" \
  --ips "10.7.0.230/30" "10.7.0.233/30" "10.7.2.1/24" \
  --gateway "10.7.0.229"

# Desplegament de mikrotik3 (planta 3 i direccio)
create_router "mikrotik3" 2203 \
  --intnets "rt2_3" "pl3" "pl3_direccio" \
  --ips "10.7.0.234/30" "10.7.3.1/25" "10.7.3.129/25" \
  --gateway "10.7.0.233"

log_info "=========================================="
log_info "[+] Routers desplegats correctament."
log_info "=========================================="
