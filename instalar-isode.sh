#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Instalador de ISODE 8.0 para Ubuntu 24.04 (WSL en Windows)
#  Compila e instala la pila OSI completa: transporte, sesion,
#  presentacion, ACSE, RTSE, ROSE, FTAM, VT, X.500 (QUIPU), SNMP y LPP.
#
#  Uso (dentro de Ubuntu/WSL):
#     bash instalar-isode.sh
# ------------------------------------------------------------------
set -e

SRC="${ISODE_SRC:-$HOME/isode-8.0}"
REPO="https://github.com/osiarchive/isode-8.0.git"

paso() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

paso "1/7 Instalando herramientas de compilacion (pide tu clave de Ubuntu)"
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential git bison flex libcrypt-dev

paso "2/7 Descargando el codigo fuente de ISODE 8.0"
if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 "$REPO" "$SRC"
else
    echo "Ya existe $SRC, se reutiliza."
fi
cd "$SRC"

paso "3/7 Aplicando arreglos para compiladores modernos"
# (a) ISODE (1992) define su propia funcion asprintf() con otra firma;
#     la glibc actual ya declara una asprintf() estandar y chocan.
#     Se renombra la de ISODE a isode_asprintf().
if grep -qw "asprintf" h/general.h; then
    grep -rlw "asprintf" --include=*.c --include=*.h --include=*.y \
         --include=*.ry --include=*.py . \
      | xargs sed -i 's/\basprintf\b/isode_asprintf/g'
    echo "asprintf -> isode_asprintf (hecho)"
fi

paso "4/7 Configurando para Linux"
cp config/linux.h      h/config.h
cp config/linux.make   config/CONFIG.make
cp config/*.local      support/
# (b) Ubuntu guarda las claves en /etc/shadow; sin esto FTAM y VT
#     rechazan siempre la contrasena.
grep -q "SHADOW_PW" h/config.h || echo '#define SHADOW_PW' >> h/config.h

paso "5/7 Compilando (tarda unos minutos)"
./make everything > "$HOME/isode-compilacion.log" 2>&1 || {
    echo "Fallo la compilacion. Revisa $HOME/isode-compilacion.log"; exit 1; }
echo "Compilacion correcta."

paso "6/7 Instalando en /usr/local"
sudo ./make inst-everything > "$HOME/isode-instalacion.log" 2>&1 || {
    echo "Fallo la instalacion. Revisa $HOME/isode-instalacion.log"; exit 1; }

paso "7/7 Configurando servicios, directorio X.500 y usuario de prueba"
agregar_servicio() { grep -q "^$1[[:space:]]" /etc/services || echo "$1 $2" | sudo tee -a /etc/services >/dev/null; }
agregar_servicio tsap        102/tcp
agregar_servicio snmp        161/udp
agregar_servicio snmp-trap   162/udp
agregar_servicio smux        199/tcp
agregar_servicio miscellany  17002/lpp

ETC=/usr/local/etc/isode
sudo mkdir -p "$ETC/quipu-db"
sudo cp -r others/quipu/quipu-db/organisation/* "$ETC/quipu-db/"
sudo sed -i 's/mydsaname\s*.*/mydsaname\tc=GB@cn=toucan/' "$ETC/quiputailor"

# Usuario "demo" (clave demo123) con un archivo para transferir por FTAM
if ! id demo >/dev/null 2>&1; then
    sudo useradd -m -s /bin/bash demo
    echo 'demo:demo123' | sudo chpasswd
fi
echo "Hola desde FTAM - archivo transferido con protocolos OSI (ISO 8571)" \
  | sudo tee /home/demo/saludo.txt >/dev/null
sudo chown demo:demo /home/demo/saludo.txt

printf '\n\033[1;32mISODE 8.0 instalado correctamente.\033[0m\n'
echo "Siguiente paso:  bash demo-isode.sh"
