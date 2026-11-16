
## Activitat 3: Ansible i VPN WireGuard

Tot el codi és a `automation/ansible`. Execució:

    cd automation/ansible
    ansible-playbook playbooks/start_routers.yml
    ansible-playbook playbooks/configure_wireguard.yml

### Variables (`inventories/group_vars/all/wireguard.yml`)

- Adreçament: servidor `10.7.10.1/24` a la interfície `wg-vcorp` de mikrotik0; client `10.7.10.2`; xarxa del túnel `10.7.10.0/24`.
- AllowedIPs del client (split tunnel): `10.7.0.0/25`, `10.7.0.128/26`, `10.7.0.192/27`, `10.7.1.0/24`, `10.7.2.0/24`, `10.7.3.0/25` i la xarxa del túnel. `pl3_direccio` (`10.7.3.128/25`) queda fora a propòsit.
- Escolta: UDP `13231` a mikrotik0. Endpoint del client: `127.0.0.1:13231`; no es publica cap adreça pública.
- PersistentKeepalive = 25.

### Reenviament UDP de VirtualBox

El rol `wireguard_vbox_forward` consulta `VBoxManage showvminfo mikrotik0 --machinereadable` i, només si la regla no hi és, executa `VBoxManage controlvm mikrotik0 natpf1 "wireguard,udp,127.0.0.1,13231,,13231"`.

### Claus i secrets

Les claus i el `.conf` del client es generen amb `wg genkey` / `wg pubkey` a `artifacts/vpn` (permisos 0700/0600, ignorat per Git). Les tasques amb claus privades porten `no_log: true`. No hi ha cap clau, contrasenya ni fitxer de client al repositori.

### Regles de tallafoc afegides a mikrotik0

| Cadena | Regla | Motiu |
|---|---|---|
| input | accept udp dst-port 13231 (primera de la cadena) | obrir el port abans de qualsevol descart |
| forward | accept in-interface wg-vcorp dst-address-list vcorp-wg-allowed | només cap a les xarxes autoritzades |
| forward | drop in-interface wg-vcorp | tallar la resta del trànsit del túnel |

La llista `vcorp-wg-allowed` conté les 6 xarxes autoritzades. No hi ha NAT entre el túnel i les xarxes internes; la xarxa `10.7.10.0/24` es propaga per RIP.

### Proves realitzades

- Segona execució de `configure_wireguard.yml`: `changed=0` (sense duplicats d'interfície, adreça, peer, llista ni regles).
- Handshake correcte (`latest handshake` i tràfic als dos sentits) i ping a `10.7.10.1`.
- Ping a l'adreça del router de cada xarxa autoritzada (pl0, privada, dmz, pl1, pl2, pl3): tots responen.
- `10.7.3.129` (pl3_direccio) no és accessible. Amb AllowedIPs ampliat temporalment al client, la regla `vcorp-wg-forward-drop` va comptar els 2 paquets de la prova.
- Split tunnel: `ip route get 8.8.8.8` surt per la interfície normal, no pel túnel.
- Persistència: `stop_routers.yml` + `start_routers.yml`; la regla de VirtualBox, el servidor i el túnel es recuperen sense reconfigurar.
