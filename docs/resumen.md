# Mirax — Core arcade para Analogue Pocket

> ⚠️ **Core experimental.** Este proyecto es, ante todo, un experimento. Puede tener comportamientos incorrectos, cambios profundos entre versiones y partes del hardware todavía sin confirmar. No debe tomarse como una reimplementación definitiva ni como referencia de precisión, al menos por ahora.

**Juego:** Mirax — Current Technology, Inc. (Taipei, 1985)
**Placa de referencia:** CURRENT CT805-3 (se corresponde con el set `miraxa` de MAME)
**Plataforma:** Analogue Pocket (openFPGA), con soporte para Analogizer

---

## ¿Qué es este proyecto?

El objetivo no es simplemente traducir a FPGA el código C++ del driver de MAME. Se busca reconstruir el funcionamiento **real** de la placa original y, al mismo tiempo, **poner a prueba la inteligencia artificial como herramienta de inferencia y análisis de hardware**.

Por eso el proyecto tiene dos objetivos al mismo nivel:

1. **Un core fiel al hardware**, que modele la lógica de la época (TTL, PROM, PAL) en lugar de imitar solo el comportamiento visible.
2. **Evaluar con honestidad qué aporta la IA**: hasta dónde llega infiriendo circuitos, dónde se equivoca y cómo tiene que intervenir una persona para corregirla.

## Enfoque híbrido

El trabajo combina tres fuentes, y cada una cumple un papel distinto:

| Fuente | Papel |
|---|---|
| **Driver de MAME** (`misc/mirax.cpp`) | Punto de partida: da el mapa de memoria, los dispositivos principales y un comportamiento de referencia. Se usa como **oráculo de comparación**, no como especificación del hardware. |
| **Ruteado de la PCB a partir de imágenes de alta resolución** | Fuente primaria. Con una herramienta de trazado de pistas sobre fotografías de ambas caras de la placa se reconstruye la conectividad real entre componentes. |
| **IA como asistente de inferencia** | Ayuda a interpretar el ruteado, proponer hipótesis sobre el funcionamiento de cada bloque (temporización, decodificación, generación de vídeo…), contrastarlas con MAME y detectar incoherencias. |

Los componentes que ya tienen implementaciones probadas se reutilizan: la CPU Z80 (T80) y el sonido AY-3-8912 (jt49). El resto de la lógica se modela a mano a partir de lo que se deduce de la placa.

## Un proceso iterativo

Nada se da por cerrado a la primera. Cada bloque del hardware pasa por este ciclo:

```
  Fotografía / ruteado de la PCB
            │
            ▼
  Hipótesis (asistida por IA) ──► contraste con MAME y datasheets
            │                                │
            ▼                                │
  RTL en SystemVerilog  ◄────────────────────┘
            │
            ▼
  Simulación y prueba en hardware real
            │
            ▼
  ¿Coincide con la placa original? ── no ──► revisar la hipótesis
            │
           sí
            ▼
  Bloque validado (pendiente de revisión si aparecen datos nuevos)
```

Cuando MAME y lo que se infiere de la placa no coinciden, **manda la placa**. La discrepancia se documenta y se investiga en vez de copiar el comportamiento del emulador.

## Principios

- **La placa y los datasheets son las fuentes primarias.** MAME sirve de referencia, no de verdad absoluta.
- **Nada de RTL especulativo sin marcar.** Toda hipótesis no confirmada queda identificada como tal en el código y en la documentación.
- **Las conclusiones de la IA se tratan como hipótesis**, nunca como hechos. Todas se verifican contra el ruteado, la simulación o el hardware real.
- **Transparencia.** Se documentan los aciertos y también los errores de la IA, porque forman parte de lo que el proyecto quiere medir.

## Qué se espera aprender

- Si una IA puede ayudar de verdad a reconstruir hardware de los 80 a partir de fotografías y de un driver de emulador.
- Qué tipo de tareas acelera (lectura de pistas, consulta de datasheets, generación de hipótesis, RTL de partida) y en cuáles falla o necesita supervisión constante.
- Si este flujo híbrido puede aplicarse a otras placas poco documentadas.

## Estado

🧪 **En desarrollo activo — experimental.** El comportamiento del core puede cambiar a medida que se refinan las hipótesis sobre el hardware. Cualquier diferencia respecto a la placa original que se detecte es bienvenida como aportación.

---

*Autor: RndMnkIII*
