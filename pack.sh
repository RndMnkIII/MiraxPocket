#!/usr/bin/env bash
# =============================================================================
#  pack.sh - Empaqueta el core "Mirax" para Analogue Pocket tras compilar
#  en Quartus. Invierte los bits de cada byte del .rbf (bitstream.rbf_r) y
#  arma en release/ la estructura lista para copiar a la raiz de la SD:
#
#     release/
#       Cores/<AUTHOR>.<SHORTNAME>/   bitstream.rbf_r + *.json + info.txt + icon.bin
#       Assets/ ...                   (copiado de dist/Assets)
#       Platforms/ ...                (copiado de dist/Platforms)
#       Presets/ ...                  (copiado de dist/Presets)
#       <cualquier otra cosa en dist/>
#
#  y genera <AUTHOR>.<SHORTNAME>_<version>.zip con todo el contenido de release/.
#
#  Uso:   ./pack.sh [ruta/al/fichero.rbf]
#         (si se omite, se usa el .rbf mas reciente de src/fpga/output_files)
# =============================================================================
set -euo pipefail

# ---- Datos del core (edita si cambias autor/nombre/plataforma) --------------
AUTHOR="RndMnkIII"
SHORTNAME="MiraxPocket"
PLATFORM="mirax"

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
COREID="${AUTHOR}.${SHORTNAME}"
OUTDIR="$ROOT/release"
COREDIR="$OUTDIR/Cores/$COREID"

# Version leida de core.json (para el nombre del zip); "dev" si no se encuentra
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/core.json" 2>/dev/null | head -n1)"
VERSION="${VERSION:-dev}"

# ---- 1) Localizar el .rbf compilado ----------------------------------------
RBF="${1:-}"
if [ -z "$RBF" ]; then
  RBF="$(ls -t "$ROOT"/src/fpga/output_files/*.rbf 2>/dev/null | head -n1 || true)"
fi
if [ -z "$RBF" ] || [ ! -f "$RBF" ]; then
  echo "ERROR: no encuentro el .rbf. Compila en Quartus o pasa la ruta:"
  echo "       ./pack.sh src/fpga/output_files/ap_core.rbf"
  exit 1
fi
[ -d "$DIST" ] || { echo "ERROR: no existe la carpeta dist/"; exit 1; }
echo "RBF de entrada : $RBF"
echo "Version        : $VERSION"

# ---- 2) Preparar release/ y copiar TODO dist/ ------------------------------
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"
# Copia recursiva de dist/ (Assets, Platforms, Presets, ...) salvo icon.bin,
# que va dentro de la carpeta del core.
( cd "$DIST" && tar cf - --exclude='./icon.bin' . ) | ( cd "$OUTDIR" && tar xf - )
# Quitar ficheros marcador de git; las carpetas vacias se mantienen
find "$OUTDIR" -type f \( -name '.gitkeep' -o -name '.keep' \) -delete

# ---- 3) Crear carpetas del core y de assets --------------------------------
mkdir -p "$COREDIR" \
         "$OUTDIR/Platforms/_images" \
         "$OUTDIR/Assets/$PLATFORM/common" \
         "$OUTDIR/Assets/$PLATFORM/$COREID"

# ---- 4) Invertir los bits de cada byte  ->  bitstream.rbf_r ------------------
REV="$COREDIR/bitstream.rbf_r"
echo "Invirtiendo bits -> bitstream.rbf_r ..."
if command -v python3 >/dev/null 2>&1; then
  python3 - "$RBF" "$REV" <<'PY'
import sys
lut=bytes(int(f"{b:08b}"[::-1],2) for b in range(256))
d=open(sys.argv[1],'rb').read()
open(sys.argv[2],'wb').write(d.translate(lut))
PY
elif command -v perl >/dev/null 2>&1; then
  perl -0777 -ne 'my @l=map{my $b=$_;my $r=0;for my $j(0..7){$r|=(1<<(7-$j)) if $b&(1<<$j)}$r}0..255;'\
'print pack("C*", map{$l[$_]} unpack("C*",$_))' "$RBF" > "$REV"
else
  echo "ERROR: necesito python3 o perl para invertir los bits."; exit 1
fi

# ---- 5) Copiar definiciones del core (JSON + info + icono) -----------------
for f in core.json video.json audio.json data.json input.json interact.json variants.json info.txt; do
  if [ -f "$ROOT/$f" ]; then cp "$ROOT/$f" "$COREDIR/"; else echo "AVISO: falta $f"; fi
done
if [ -f "$DIST/icon.bin" ]; then cp "$DIST/icon.bin" "$COREDIR/icon.bin"; else echo "AVISO: falta dist/icon.bin"; fi

# ---- 6) Comprobaciones minimas ---------------------------------------------
for f in "Platforms/$PLATFORM.json" "Platforms/_images/$PLATFORM.bin"; do
  [ -f "$OUTDIR/$f" ] || echo "AVISO: falta $f en dist/"
done

# ---- 7) Comprimir todo release/ --------------------------------------------
ZIP="$ROOT/${COREID}_${VERSION}.zip"
rm -f "$ZIP"
( cd "$OUTDIR" && zip -rq "$ZIP" . )

SZ=$(wc -c < "$REV")
echo "-----------------------------------------------------------------"
echo "OK. bitstream.rbf_r: $SZ bytes"
echo "Estructura   : $OUTDIR"
( cd "$OUTDIR" && find . -mindepth 1 | sort | sed 's|^\./|   |' )
echo "ZIP distrib. : $ZIP  (descomprimir en la raiz de la SD del Pocket)"
echo "-----------------------------------------------------------------"
