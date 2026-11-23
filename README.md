# 🚀 Turnip R27 — SD870 / Adreno 650 Optimized Edition

Driver gráfico **Mesa Turnip (Vulkan 1.3 / 1.4)** personalizado y compilado desde código fuente específicamente para dispositivos con procesador **Snapdragon 870 / 865 / 865+ (GPU Adreno 650)** y familia **A6xx**.

## ✨ Características y optimizaciones
* **Vulkan 1.3 y 1.4 desbloqueado (`vulkan-beta=true`):** Supera el límite de Vulkan 1.1 del driver oficial de Qualcomm, permitiendo ejecutar juegos modernos, emuladores y ports nativos sin errores de API.
* **Parche anti-crasheos para Adreno 650 (`has_vk_memory_model = false`):** Corrige cierres inesperados, pantallas negras y fallos gráficos en motores exigentes como **Unreal Engine 4/5**.
* **Compilación nativa para núcleos Kryo 585 (`-march=armv8.2-a+dotprod+fp16 -mtune=cortex-a77 -O3`):** Optimizado a nivel de instrucciones de CPU para los núcleos Cortex-A77 del Snapdragon 870, acelerando la carga de shaders y reduciendo micro-tirones (*stuttering*).
* **Release puro y ligero (`-Db_ndebug=true` + `strip` + `KGSL`):** Binario compacto (~2.4 MB) sin capas de depuración y con comunicación directa al kernel de Qualcomm para mayor estabilidad térmica en sesiones largas.

## 📱 Compatibilidad
* **Dispositivo objetivo:** Snapdragon 870 / Snapdragon 865 / 865+ (**Adreno 650**).
* **Compatible en:** Winlator, Eden, Vita3K, Dolphin y ports nativos con soporte para *Custom Drivers* (Adrenotools).

## 📥 Descarga e Instalación
1. Entra a la sección [**Releases (Último lanzamiento)**](https://github.com) y descarga **`Turnip_R27_Adreno650_Opt.zip`**.
2. Abre tu emulador o port nativo.
3. Ve a **Ajustes → Controlador Gráfico / Custom Driver** e importa el archivo `.zip` directamente sin descomprimir.

---
*Compilado mediante GitHub Actions (Android NDK / Meson Release) y probado en hardware real (Snapdragon 870 / 12 GB RAM).*
