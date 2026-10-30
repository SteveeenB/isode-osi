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
   ------------------------------------------------------------
   POR DENTRO - captura de paquetes reales (tcpdump + tshark)
   12) Eco TP0 byte a byte          (TPKT + TP0 + mensaje)
   13) El mismo mensaje en cada capa (transporte -> RTSE)
   14) FTAM paso a paso             (secuencia ISO 8571)
    0) Salir
EOF
printf '\nOpcion: '
}

# ==================================================================
#  POR DENTRO: captura del trafico real en el puerto 102 y explicacion
#  de cada byte. tcpdump graba, tshark decodifica.
# ==================================================================
SRC="${ISODE_SRC:-$HOME/isode-8.0}"
CAP=/tmp/isode-capturas
MSG="Hola OSI desde la UFPS"

seguir() { printf '\n\033[2m(Enter para seguir)\033[0m'; read -r _; echo; }
paso()   { printf '\n\033[1;36m--- %s ---\033[0m\n' "$1"; }

capturar() {  # $1 = archivo .pcap   $2.. = comando a ejecutar mientras se graba
    local f="$1"; shift
    mkdir -p "$CAP"; sudo rm -f "$f"
    sudo tcpdump -i lo -U -w "$f" tcp port 102 >/dev/null 2>&1 &
    local pid=$!
    sleep 1
    "$@"
    sleep 1
    sudo kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    sudo chmod a+r "$f"
}

ts() { tshark "$@" 2>/dev/null; }   # tshark sin el aviso de "running as root"
hex2txt() { printf '%b' "$(sed 's/../\\x&/g')"; }   # 486f6c61 -> Hola

# Hexadecimal del primer paquete que lleva el mensaje
paquete_datos() { ts -r "$1" -Y "tcp.payload contains \"Hola OSI\"" -T fields -e tcp.payload | head -1; }

# Pinta un paquete por tramos.  $1 = hex   $2.. = "bytes|color|capa|explicacion"
desarmar() {
    local hex="$1" pos=0 total=0 seg n col capa expl parte; shift
    for seg in "$@"; do total=$((total + ${seg%%|*})); done
    if [ $((${#hex} / 2)) -ne "$total" ]; then   # si el paquete no tiene la forma esperada
        echo "$hex" | sed 's/../& /g' | fold -w 48; return
    fi
    for seg in "$@"; do
        IFS='|' read -r n col capa expl <<<"$seg"
        parte=$(echo "${hex:pos:n*2}" | tr 'a-f' 'A-F' | sed 's/../& /g' | fold -w 48)
        pos=$((pos + n * 2))
        printf '\033[1;%sm%-13s\033[0m' "$col" "$capa"
        echo "$parte" | sed '2,$s/^/             /' | sed "s/.*/ \x1b[${col}m&\x1b[0m/"
        printf '              \033[2m%s\033[0m\n' "$expl"
    done
}

eco_silencioso() {  # isoc repite el eco 10 veces; uniq deja una sola linea
    local m; m=$(mktemp); echo "$MSG" > "$m"
    $B/isoc localhost "$@" < "$m" 2>&1 | uniq; rm -f "$m"
}

# ---------- 12) TP0 byte a byte ----------
por_dentro_tp0() {
    titulo "POR DENTRO - CAPA 4: TP0 sobre TCP (RFC 1006)" \
           "Se graba el puerto 102 mientras isoc hace el eco en la capa de transporte"
    capturar "$CAP/tp0.pcap" eco_silencioso tsap echo
    echo "(isoc envia el mensaje 10 veces: por eso hay 10 DT de ida y 10 de vuelta)"

    paso "1. Los paquetes de la conversacion"
    ts -r "$CAP/tp0.pcap" -Y cotp -T fields -e frame.number -e _ws.col.Info \
      | awk -F'\t' 'NR<=4 || /DR/ {printf "  %3s  %s\n",$1,$2} NR==5{print "  ...  (mas DT de ida y vuelta)"}'
    cat <<'EOF'

  CR = Connection Request  -> el cliente pide la conexion de transporte
  CC = Connection Confirm  -> el servidor (tsapd) la acepta
  DT = Data                -> lleva el mensaje
  (cada uno es una TPDU: Transport Protocol Data Unit)
  DR = Disconnect Request  -> se cierra la conexion
EOF
    seguir

    paso "2. El paquete CR (pedir conexion), byte a byte"
    local cr; cr=$(ts -r "$CAP/tp0.pcap" -Y "cotp.type == 0x0e" -T fields -e tcp.payload | head -1)
    desarmar "$cr" \
      "4|33|TPKT|Transport Packet (RFC 1006): version 3, reservado 0, longitud total" \
      "7|35|TP0 (CR)|largo del encabezado, E0 = CR (Connection Request), ref. destino 0000, ref. origen, clase 0" \
      "3|35|  opciones|C6: parametro de opciones (datos urgentes)" \
      "4|35|  TSAP dest.|C2: TSAP destino (Transport Service Access Point) -> 0x0080 = 128 = 'tsap/echo #128'" \
      "3|35|  tamano|C0: tamano maximo de TPDU, 0B -> 2^11 = 2048 bytes"
    echo
    echo "  En isoservices:  $(grep -m1 '^tsap/echo' $ETC/isoservices 2>/dev/null | tr -s '\t' ' ')"
    seguir

    paso "3. El paquete DT con el mensaje, byte a byte"
    desarmar "$(paquete_datos "$CAP/tp0.pcap")" \
      "4|33|TPKT|Transport Packet: 03 version 3 | 00 reservado | 00 1E longitud = 30 bytes" \
      "3|35|TP0 (DT)|Transport Protocol clase 0: 02 largo | F0 DT (Data) | 80 EOT (End of TSDU, ultimo fragmento)" \
      "23|32|Mensaje|\"$MSG\" + salto de linea = 23 bytes en ASCII, sin modificar"
    echo
    echo "  30 bytes = 4 (TPKT) + 3 (TP0) + 23 (mensaje).  Solo 7 bytes de encabezado OSI."
    seguir

    paso "4. Donde lo hace el codigo"
    echo "support/isoc.c  (el cliente)"
    grep -n "TConnRequest (NULLTA\|TDataRequest (sd, data\|TReadRequest (sd, tx" "$SRC/support/isoc.c" \
      | sed 's/^/   /;s/\t/ /g;s/  */ /g'
    echo "   -> TConnRequest = CR/CC,  TDataRequest = DT de ida,  TReadRequest = DT de vuelta"
    echo
    echo "tsap/fd2tpkt.c  (arma el TPKT antes de entregarlo a TCP)"
    grep -n "t_length = htons" "$SRC/tsap/fd2tpkt.c" | sed 's/^/   /;s/\t/ /g;s/  */ /g'
    echo "   -> largo del encabezado TP0 + 5 + datos = 2 + 5 + 23 = 30 = 0x001E"
    echo "      (los 5 son: 4 del TPKT + 1 del byte de longitud del encabezado TP0)"
}

# ---------- 13) El mismo mensaje en cada capa ----------
por_dentro_capas() {
    titulo "POR DENTRO - EL MISMO MENSAJE EN CADA CAPA" \
           "Se repite el eco en transporte, sesion, ROSE y RTSE; cada capa agrega su encabezado"
    capturar "$CAP/tsap.pcap"  eco_silencioso tsap echo
    capturar "$CAP/ssap.pcap"  eco_silencioso ssap echo
    capturar "$CAP/rosap.pcap" eco_silencioso rosap isode/echo
    capturar "$CAP/rtsap.pcap" eco_silencioso rtsap isode/ros_echo

    local t s r rt
    t=$(paquete_datos "$CAP/tsap.pcap");  s=$(paquete_datos "$CAP/ssap.pcap")
    r=$(paquete_datos "$CAP/rosap.pcap"); rt=$(paquete_datos "$CAP/rtsap.pcap")

    paso "1. Tamano del paquete que lleva los mismos 23 bytes"
    printf '  %-26s %6s %12s\n' "Eco en..." "Bytes" "Encabezados"
    printf '  %-26s %6s %12s\n' "Capa 4  TP0"            $((${#t}/2))  $((${#t}/2-23))
    printf '  %-26s %6s %12s\n' "Capa 5  Sesion"         $((${#s}/2))  $((${#s}/2-23))
    printf '  %-26s %6s %12s\n' "Capa 6+7 Presentacion+ROSE" $((${#r}/2))  $((${#r}/2-23))
    printf '  %-26s %6s %12s\n' "Capa 7  RTSE (+ROSE)"   $((${#rt}/2)) $((${#rt}/2-23))
    seguir

    paso "2. Capa 5 - Sesion (ISO 8327)"
    desarmar "$s" \
      "4|33|TPKT|longitud 0x22 = 34" \
      "3|35|TP0 (DT)|encabezado de datos de transporte, igual que en el eco TP0" \
      "2|34|Sesion GT|SPDU Give Tokens: dar el turno para hablar" \
      "2|34|Sesion DT|SPDU Data Transfer: lo que sigue son datos" \
      "23|32|Mensaje|\"$MSG\""
    seguir

    paso "3. Capa 6 - Presentacion (ISO 8823, BER) + Capa 7 - ROSE (X.229)"
    desarmar "$r" \
      "4|33|TPKT|longitud 0x35 = 53" \
      "3|35|TP0 (DT)|encabezado de datos de transporte, igual que en el eco TP0" \
      "4|34|Sesion|GT (Give Tokens) + DT (Data Transfer)" \
      "2|36|Present.|[APPLICATION 1] fully-encoded-data, 40 bytes" \
      "2|36|  PDV-list|SEQUENCE de 38 bytes" \
      "3|36|  contexto|INTEGER 1: id del contexto de presentacion" \
      "2|36|  valor|[0] single-ASN1-type, 33 bytes" \
      "2|31|ROSE|Remote Operations Service Element: [1] Invoke (invocar operacion remota), 31 bytes" \
      "3|31|  invokeID|INTEGER 1: numero de esta invocacion" \
      "3|31|  operacion|INTEGER 0: operacion 'echo'" \
      "2|31|  argumento|OCTET STRING de 23 bytes" \
      "23|32|Mensaje|\"$MSG\""
    cat <<'EOF'

  BER (Basic Encoding Rules) de ASN.1 (Abstract Syntax Notation One)
  se lee TIPO - LONGITUD - VALOR, y los valores se anidan como cajas.
    61 28 [ 30 26 [ 02 01 01   A0 21 [ A1 1F [ 02 01 01  02 01 00  04 17 [mensaje] ] ] ] ]
EOF
    seguir

    paso "4. Capa 7 - RTSE (X.228): los puntos de control se ven en el cable"
    desarmar "$rt" \
      "4|33|TPKT|1er paquete: 16 bytes" \
      "3|35|TP0 (DT)|encabezado de datos de transporte, igual que en el eco TP0" \
      "2|34|Sesion GT|Give Tokens" \
      "7|34|Sesion AS|AS = Activity Start: inicio de actividad" \
      "4|33|TPKT|2do paquete: 55 bytes (los datos)" \
      "3|35|TP0 (DT)|encabezado de datos de transporte, igual que en el eco TP0" \
      "4|34|Sesion|GT (Give Tokens) + DT (Data Transfer)" \
      "9|36|Present.|contexto 17 (RTSE)" \
      "2|37|RTSE|Reliable Transfer Service Element: OCTET STRING de 33 bytes con la APDU (Application PDU) de ROSE" \
      "10|31|ROSE|Invoke, id 1, operacion 0" \
      "23|32|Mensaje|\"$MSG\"" \
      "4|33|TPKT|3er paquete: 14 bytes" \
      "3|35|TP0 (DT)|encabezado de datos de transporte, igual que en el eco TP0" \
      "2|34|Sesion GT|Give Tokens" \
      "5|34|Sesion MAP|MAP = Major Sync Point: punto de sincronizacion mayor, serie '1'"
    cat <<'EOF'

  RTSE encierra cada transferencia en una ACTIVIDAD de sesion y la confirma con un
  PUNTO DE SINCRONIZACION. Si la conexion se cae, se reanuda desde el ultimo punto.
  Por eso RTSE es la prueba mas lenta.
EOF
    paso "Secuencia de sesion de un eco RTSE"
    ts -r "$CAP/rtsap.pcap" -Y "ses" -T fields -e _ws.col.Info | head -14 | sed 's/^/  /'
}

# ---------- 14) FTAM paso a paso ----------
por_dentro_ftam() {
    titulo "POR DENTRO - FTAM (ISO 8571)" "Usuario: demo   Clave: demo123"
    echo "Escribe dentro de ftam:   ls .     get saludo.txt saludo.txt     quit"
    echo
    capturar "$CAP/ftam.pcap" sh -c "cd /tmp && $B/ftam -u demo localhost"
    rm -f /tmp/saludo.txt

    paso "1. Los mensajes FTAM que viajaron (cada linea es un paquete)"
    ts -r "$CAP/ftam.pcap" -Y ftam -T fields -e _ws.col.Info \
      | sed 's/f-begin-group-[a-z]*: //;s/ f-end-group-[a-z]*://;s/: *$//;s/:/ +/g' \
      | awk '{ if ($0=="") $0="(datos del archivo / directorio)"; printf "  %2d  %s\n", NR, $0 }'
    cat <<'EOF'

  FTAM = File Transfer, Access and Management (ISO 8571)
  initialize  = abrir la asociacion FTAM (con usuario y clave)
  select      = elegir el archivo          open / close  = abrirlo / cerrarlo
  read        = pedir la lectura           data-end      = fin de los datos
  transfer-end= confirmar la transferencia deselect      = soltar el archivo
  terminate   = cerrar la asociacion
  (begin-group / end-group agrupan varias ordenes en un solo paquete)

  El primer bloque select ... close es tu "ls ." (leer el directorio) y el
  segundo es tu "get" (leer saludo.txt). Los datos del archivo van en un
  paquete aparte, entre read y data-end.
EOF
    seguir

    paso "2. La clave viaja en texto claro"
    local f1 pw
    f1=$(ts -r "$CAP/ftam.pcap" -Y ftam -T fields -e frame.number | head -1)
    ts -r "$CAP/ftam.pcap" -Y "frame.number==$f1" -O ftam \
      | grep -A2 "initiator-identity\|filestore-password" | grep -v "^--" | sed 's/^ */  /'
    pw=$(ts -r "$CAP/ftam.pcap" -Y "frame.number==$f1" -O ftam | grep "octetString:" | head -1 | awk '{print $2}')
    [ -n "$pw" ] && echo "  $pw  ->  \"$(echo "$pw" | hex2txt)\""
    echo "  En 1992 no habia cifrado: hoy se usa TLS (Transport Layer Security), como en SFTP y HTTPS."
    echo "  SFTP = SSH File Transfer Protocol."
    seguir

    paso "3. El contenido del archivo dentro de los paquetes"
    ts -r "$CAP/ftam.pcap" -Y 'tcp.payload contains "Hola desde FTAM"' -T fields -e tcp.payload \
      | hex2txt | strings | grep -o "Hola desde.*" | sed 's/^/  /'
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
              "ACSE abre la asociacion; el servidor devuelve 10 saludos (enteros BER) dentro del A-ASSOCIATE"
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
    12) por_dentro_tp0; pausa ;;
    13) por_dentro_capas; pausa ;;
    14) por_dentro_ftam; pausa ;;
    0) exit 0 ;;
    esac
done
