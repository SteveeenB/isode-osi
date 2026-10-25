#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Demostracion de los protocolos de ISODE 8.0, capa por capa.
#  Uso (dentro de Ubuntu/WSL, despues de instalar-isode.sh):
#     bash demo-isode.sh
# ------------------------------------------------------------------
B=/usr/local/bin
S=/usr/local/sbin
ETC=/usr/local/etc/isode

titulo() { printf '\n\033[1;33m%s\033[0m\n\033[0;36m%s\033[0m\n\n' "$1" "$2"; }
pausa()  { printf '\n\033[2m(Enter para volver al menu)\033[0m'; read -r _; }

iniciar_demonios() {
    echo "Iniciando los servidores de ISODE (pide tu clave de Ubuntu)..."
    sudo -v
    pgrep -x tsapd     >/dev/null || sudo setsid $S/tsapd     </dev/null >/dev/null 2>&1 &
    pgrep -x lppd      >/dev/null || sudo setsid $S/lppd      </dev/null >/dev/null 2>&1 &
    pgrep -x snmpd     >/dev/null || sudo setsid $S/snmpd     </dev/null >/dev/null 2>&1 &
    pgrep -x ros.quipu >/dev/null || (cd $ETC/quipu-db && sudo setsid $S/ros.quipu </dev/null >/dev/null 2>&1 &)
    sleep 3
    for p in tsapd lppd snmpd ros.quipu; do
        if pgrep -x "$p" >/dev/null; then echo "  [OK] $p"; else echo "  [!!] $p no arranco"; fi
    done
}

eco() {  # $1 = capa (tsap/ssap/psap/rtsap/rosap)  $2.. = entidad
    local capa="$1"; shift
    local msg; msg=$(mktemp)
    echo "Hola OSI desde la UFPS" > "$msg"
    echo "Mensaje enviado: \"Hola OSI desde la UFPS\""
    $B/isoc localhost "$capa" "$@" < "$msg"
    rm -f "$msg"
}

menu() {
cat <<'EOF'

 =============================================================
   ISODE 8.0  -  Protocolos OSI sobre TCP/IP (RFC 1006)
 =============================================================
   CAPA 4 - TRANSPORTE
    1) TP0 - Transporte ISO          (ISO 8073 / X.224, RFC 1006)
   CAPA 5 - SESION
    2) Sesion ISO                    (ISO 8327 / X.225)
   CAPA 6 - PRESENTACION
    3) Presentacion ISO + ACSE       (ISO 8823 / X.226, ISO 8650)
    4) LPP - Presentacion ligera     (RFC 1085)
   CAPA 7 - ELEMENTOS DE SERVICIO
    5) RTSE - Transferencia fiable   (X.218 / X.228)
    6) ROSE - Operaciones remotas    (X.219 / X.229)
   CAPA 7 - APLICACIONES
    7) FTAM - Transferencia archivos (ISO 8571)
    8) VT   - Terminal virtual       (ISO 9040 / 9041)
    9) X.500 - Directorio QUIPU      (X.500 / X.511 / X.519)
   10) SNMP - Gestion de red         (RFC 1157, incluido en ISODE)
   ------------------------------------------------------------
   11) Prueba automatica de toda la pila (isode-test)
    0) Salir
EOF
printf '\nOpcion: '
}

iniciar_demonios
while true; do
    clear 2>/dev/null; menu; read -r op
    case "$op" in
    1) titulo "CAPA 4 - TP0 (ISO 8073)" "tsap: conexion de transporte ISO por el puerto TCP 102"
       eco tsap echo; pausa ;;
    2) titulo "CAPA 5 - SESION (ISO 8327)" "ssap: dialogo de sesion sobre el transporte TP0"
       eco ssap echo; pausa ;;
    3) titulo "CAPA 6 - PRESENTACION (ISO 8823) + ACSE (ISO 8650)" \
              "psap: contexto de presentacion con ASN.1/BER; ACSE abre la asociacion"
       eco psap isode/echo; pausa ;;
    4) titulo "CAPA 6 - LPP (RFC 1085)" "presentacion ligera directamente sobre TCP/UDP: pide la hora UTC"
       $B/imisc-lpp localhost utctime; pausa ;;
    5) titulo "CAPA 7 - RTSE (X.228)" "transferencia fiable con puntos de control sobre presentacion"
       eco rtsap isode/ros_echo; pausa ;;
    6) titulo "CAPA 7 - ROSE (X.229)" "operaciones remotas (tipo RPC) - servicio imisc"
       eco rosap isode/echo
       echo; echo "Operaciones remotas ROSE al servicio imisc:"
       for op2 in utctime gentime pwdgen; do echo "  -> $op2:"; $B/imisc localhost $op2 | sed 's/^/     /'; done
       pausa ;;
    7) titulo "CAPA 7 - FTAM (ISO 8571)" "Usuario: demo   Clave: demo123"
       echo "Escribe dentro de ftam:   ls .     get saludo.txt saludo.txt     quit"
       echo
       (cd /tmp && $B/ftam -u demo localhost)
       [ -f /tmp/saludo.txt ] && { echo; echo "Archivo recibido por FTAM:"; cat /tmp/saludo.txt; rm -f /tmp/saludo.txt; }
       pausa ;;
    8) titulo "CAPA 7 - VT (ISO 9041)" "login: demo   Password: demo123   (sal con: exit)"
       $B/vt localhost; pausa ;;
    9) titulo "CAPA 7 - DIRECTORIO X.500 (QUIPU)" "Escribe:  bind    moveto c=GB    list    quit"
       $B/dish; pausa ;;
    10) titulo "SNMP (RFC 1157)" "consulta al agente SNMP construido con ISODE"
        printf 'get sysDescr.0 sysUpTime.0\nquit\n' | $B/snmpi -a 127.0.0.1 -c public; pausa ;;
    11) titulo "PRUEBA COMPLETA" "isode-test: recorre transporte, sesion, presentacion, RTSE y ROSE"
        PATH=$PATH:$B sh "$HOME/isode-8.0/isode-test" localhost 2>&1 | grep -v "bytes echoed"
        pausa ;;
    0) exit 0 ;;
    esac
done
