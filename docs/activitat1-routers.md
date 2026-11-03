# Activitat 1 — Decisions i problemes (delegació 7)

## Decisions

- Adreçament segons l'enunciat: enllaços `10.7.0.224/30`, `10.7.0.228/30` i `10.7.0.232/30`; planta baixa `10.7.0.0/25` a R0; plantes 1, 2 i 3 a `10.7.1.0/24`, `10.7.2.0/24` i `10.7.3.0/24`. Repartiment: router N porta la planta N.
- RIP entre els quatre routers.
- Només `mikrotik0` té NAT. R1, R2 i R3 surten a Internet a través seu, amb una ruta per defecte cap al router anterior de la cadena.
- Accés SSH: `sysadmin` amb clau personal i `auditor` amb la clau pública del professor, als quatre routers. La contrasenya de `sysadmin` és al `.env`, fora del repositori.

## Problemes trobats i resolts

- `deploy_routers.sh` tenia un adreçament antic i el README, adreces d'exemple `10.1.0.x`. S'han adaptat a la subxarxa 10.7.
- `create_router` omet les VM que ja existeixen, i per això els canvis no s'aplicaven. Es resol amb `make reset-routers`.
- L'script no instal·lava la clau del professor ni configurava el DNS, i `log_error` no existia. S'ha afegit tot.
- La contrasenya de `sysadmin` era dins l'script d'un repositori públic. S'ha mogut a `.env`.
- Els usuaris amb clau SSH no acceptaven contrasenya, i `mikrotik0` no deixava fer el salt cap a la resta. S'han ajustat `password-authentication` i `forwarding-enabled` a l'script.
