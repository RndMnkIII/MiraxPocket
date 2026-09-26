#!/usr/bin/env python3
"""
Mirax — cálculo de niveles del DAC de vídeo a partir de resistencias leídas en la PCB
y comparación con los pesos del driver MAME (misc/mirax.cpp).

Paleta aceptada: 64 entradas (MRA3 = 0x00-0x1F, MRB3 = 0x20-0x3F), cada byte RGB332:
  bits 0-2 rojo, bits 3-5 verde, bits 6-7 azul (O1 = bit0 ... O8 = bit7).

Modelo: análisis nodal (Millman). Cada bit de la PROM de color excita el nodo de salida
a través de su resistencia; el nodo carga contra R_LOAD (entrada del monitor / pull-down).

  V_nodo = sum(V_i * G_i) / (sum(G_i) + G_load [+ G_pullup])

- Salida totem-pole/tri-state: bit=1 -> V_OH, bit=0 -> V_OL (la resistencia sigue conectada)
- Salida open-collector:       bit=1 -> abierto (resistencia desconectada), bit=0 -> V_OL
  (requiere pull-up; el nivel deja de ser lineal con los pesos)
"""
import argparse

# --- MAME misc/mirax.cpp (oráculo) -----------------------------------------
MAME = {
    "R": [0x21, 0x47, 0x97],   # bits 0..2  (equivale a 1K/470/220)
    "G": [0x21, 0x47, 0x97],   # bits 3..5  (equivale a 1K/470/220)
    "B": [0x52, 0xAD],         # bits 6..7  (equivale a 1K/470)
}

# --- PCB CT805-3 (trazado desde fotos, ambas caras registradas) -------------
# [HYP:AI H-021] [CONF:MEDIA] [VERIFY] continuidad O7->R2, nodos de suma, carga
# Valores: serigrafía + bandas de color. Orden LSB -> MSB.
PCB = {
    "R": [1000, 470, 270],     # O1->R8 1K, O2->"470" junto a B13, O3->R9 270
    "G": [1000, 470, 270],     # O4->R4 1K, O5->R5 470, O6->R6 270
    "B": [470, 270],           # O7->R2 470 (por vía, supuesto), O8->R1 270
}
R_LOAD = 75.0            # ohmios; entrada del monitor o resistencia a masa en la placa
V_OH, V_OL = 3.4, 0.2    # niveles típicos TTL (ajustar al datasheet de la PROM)
V_PULLUP, R_PULLUP = 5.0, None   # solo si open-collector


def node_voltage(res, code, oc=False):
    num, den = 0.0, 1.0 / R_LOAD
    for i, r in enumerate(res):
        bit = (code >> i) & 1
        if oc and bit:
            continue                       # salida en alta impedancia
        v = V_OH if bit else V_OL
        num += v / r
        den += 1.0 / r
    if oc and R_PULLUP:
        num += V_PULLUP / R_PULLUP
        den += 1.0 / R_PULLUP
    return num / den


def levels(res, oc=False):
    n = 1 << len(res)
    v = [node_voltage(res, c, oc) for c in range(n)]
    lo, hi = min(v), max(v)
    return [round(255 * (x - lo) / (hi - lo)) for x in v], v


def mame_levels(w):
    return [sum(wi for i, wi in enumerate(w) if (c >> i) & 1) for c in range(1 << len(w))]


def r2r_levels(nbits):
    return [round(255 * c / ((1 << nbits) - 1)) for c in range(1 << nbits)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--oc", action="store_true", help="PROM con salidas open-collector")
    ap.add_argument("--sv", metavar="FILE", help="genera LUT SystemVerilog con los niveles PCB")
    a = ap.parse_args()

    lut = {}
    for ch in ("R", "G", "B"):
        pcb, volts = levels(PCB[ch], a.oc)
        mame = mame_levels(MAME[ch])
        r2r = r2r_levels(len(PCB[ch]))
        lut[ch] = pcb
        print(f"\nCanal {ch}  resistencias PCB = {PCB[ch]}  ({'OC' if a.oc else 'totem-pole'})")
        print(" code |  V_nodo |  PCB | MAME | Δ(PCB-MAME) | R-2R ideal")
        for c in range(len(pcb)):
            d = pcb[c] - mame[c]
            flag = "  <-- DIFF" if abs(d) > 4 else ""
            print(f"  {c:03b} | {volts[c]:6.3f}V | {pcb[c]:4d} | {mame[c]:4d} | {d:+11d} | {r2r[c]:4d}{flag}")

    if a.sv:
        with open(a.sv, "w") as f:
            f.write("// Generado por dac_weights.py — NO EDITAR A MANO\n")
            f.write(f"// Modelo: {'open-collector' if a.oc else 'totem-pole'}, R_LOAD={R_LOAD} ohm, "
                    f"V_OH={V_OH} V, V_OL={V_OL} V\n")
            f.write("// [HYP:AI H-021] [CONF:MEDIA] [VERIFY] valores trazados desde fotos de la CT805-3\n")
            for ch in ("R", "G", "B"):
                f.write(f"// [SRC:PCB] resistencias {ch} (LSB->MSB): {PCB[ch]}  | MAME: {mame_levels(MAME[ch])}\n")
                vals = ", ".join(f"8'd{x}" for x in lut[ch])
                f.write(f"localparam logic [7:0] LVL_{ch} [{len(lut[ch])}] = '{{{vals}}};\n")
        print(f"\nLUT escrita en {a.sv}")


if __name__ == "__main__":
    main()
