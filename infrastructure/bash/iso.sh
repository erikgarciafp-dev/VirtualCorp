#!/usr/bin/env bash

# Descarrega una ISO fixada i en verifica la suma SHA256.
# Ús: download_iso <url> <ruta_desti> <sha256>
download_iso() {
    local url="$1"
    local dest="$2"
    local sha256="$3"

    mkdir -p "$(dirname "$dest")"

    if [[ -f "$dest" ]]; then
        if echo "${sha256}  ${dest}" | sha256sum --check --status; then
            log_info "ISO ja descarregada i verificada: $(basename "$dest")"
            return 0
        fi
        log_warn "La suma de '$(basename "$dest")' no coincideix. Es descarrega de nou."
        rm -f "$dest"
    fi

    log_info "Descarregant $url"
    curl -fL --retry 3 -o "${dest}.part" "$url" || {
        rm -f "${dest}.part"
        log_error "No s'ha pogut descarregar $url. No es canvia de versio automaticament."
        return 1
    }

    if ! echo "${sha256}  ${dest}.part" | sha256sum --check --status; then
        rm -f "${dest}.part"
        log_error "La suma SHA256 de '$(basename "$dest")' no coincideix amb la fixada."
        return 1
    fi

    mv "${dest}.part" "$dest"
    log_ok "ISO verificada: $(basename "$dest")"
}
