# Documentación de Pistas de Audio Experimentales (Sprint 2 · ACT-07 y ACT-09)

**Universidad de las Fuerzas Armadas ESPE**  
**Proyecto:** Evaluación de la contaminación acústica y su efecto sobre la atención y el rendimiento académico durante las evaluaciones en ambientes universitarios  
**Módulos:** M3: Audio (`ACT-07`) y M4: Lógica del servidor y normalización MP3 (`ACT-09`)  
**Responsable:** Fernando Camatón-Realpes

---

## 1. Descripción General

Para la evaluación experimental de comprensión lectora bajo dos condiciones acústicas contrastantes se seleccionaron, recortaron y procesaron en **Audacity** dos pistas sonoras continuas de **180 segundos (3 minutos)** configuradas para reproducción en bucle sin cortes audibles mediante `Web Audio API`.

---

## 2. Extracción y Recorte en Bucle de 180 s (ACT-07)

| Escenario Experimental | Archivo Recortado (WAV) | Fuente Original | Duración del Bucle | Canales y Muestreo | Edición en Audacity (ACT-07) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Escenario Adverso (Ruido Urbano)** | `public/audio/RU_3min.wav` | [YouTube — Ruido urbano (tráfico, bocinas y ambiente de calle)](https://youtu.be/g1m5M31lSFo?si=qA1y7huORxyhaE22) | 180 s (3:00 min) | Estéreo · 44 100 Hz | Extracción y recorte de tramo estable de 180 s sin silencios iniciales ni finales para reproducción cíclica continua. |
| **Escenario de Control (Sonido de Calma)** | `public/audio/Calma_3min.wav` | [YouTube — Sonido ambiental de calma](https://youtu.be/suIH-zolv7w?si=qNMNPER10BfjUVIs) | 180 s (3:00 min) | Estéreo · 44 100 Hz | Extracción y recorte de tramo continuo de 180 s con transición suavizada (fundido de entrada y de salida en los extremos) para bucle continuo sin cortes audibles. |

---

## 3. Normalización de Sonoridad (35 dB de diferencia) y Exportación MP3 (ACT-09)

| Escenario Experimental | Archivo Final Exportado (MP3) | Sonoridad Objetivo (LUFS) | Limitador de Picos | Formato y Canales | Diferencia Relativa |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Escenario Adverso (Ruido Urbano)** | `public/audio/ruido.mp3` | **`-14.0 LUFS`** | Umbral y salida a `-1.5 dB` (modo Moderno) | MP3 · Estéreo · 44 100 Hz | Referencia superior (`0 dB` rel.) |
| **Escenario de Control (Sonido de Calma)** | `public/audio/calma.mp3` | **`-49.0 LUFS`** | No requerido (picos < `-35 dB`) | MP3 · Estéreo · 44 100 Hz | **`-35.0 dB`** por debajo de `ruido.mp3` |

### Justificación Acústica y Experimental
1. **Diferencia relativa fija (35 dB):** Al normalizar la sonoridad percibida en Audacity a `-14 LUFS` (ruido urbano) y `-49 LUFS` (sonido de calma), la diferencia de **35 dB** queda grabada directamente dentro de los archivos MP3.
2. **Reproducción controlada en navegador:** Dado que el cliente web reproduce ambas pistas con ganancia fija mediante `Web Audio API` (sin control de volumen en la interfaz) y con el volumen del computador fijado al **50 %**, el escenario de ruido urbano reproduce un nivel moderadamente alto de **70–75 dB(A)** (representativo de exteriores de campus universitarios y seguro para la audición), mientras que el escenario de calma se mantiene como condición de control alrededor de **35–40 dB(A)**.
