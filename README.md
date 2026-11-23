# JARVIS AI · Etapa 1

Asistente SwiftUI en español para iPhone con iOS 17 o posterior. Incluye transcripción de voz, respuestas locales, síntesis en español y una prueba de grabación y reproducción. El Modo JARVIS mantiene una sesión de audio activa en segundo plano mientras iOS lo permite.

## Instalar y actualizar desde SideStore

1. Abre SideStore en el iPhone y ve a **Browse → Sources → +**. Pega la [URL de la fuente de JARVIS AI](https://raw.githubusercontent.com/xmanugonzalez/jarvis-ai/main/source.json) y confirma que quieres añadirla.
2. Activa la VPN que usa tu instalación de SideStore. Abre **JARVIS AI** en la fuente y toca **Instalar** para obtener la primera versión desde el catálogo.
3. Cuando haya una nueva versión, consulta **My Apps** y toca **Actualizar**. Si aún no aparece, vuelve a abrir SideStore para que consulte la fuente. La instalación de la actualización requiere tu acción y una firma válida. Renovar la firma prolonga la vigencia de una app y es un proceso separado.

Si instalaste el IPA manualmente con SideStore, conserva la app instalada y usa la misma cuenta de Apple y la misma identidad de firma. Si JARVIS aparece con **Actualizar**, úsalo. Si aparece **Instalar** en la fuente, úsalo una vez para asociar la instalación al catálogo, siempre que SideStore la trate como el mismo JARVIS. El IPA mantiene el identificador `dev.jarvisai.assistant`. Si SideStore propone un clon, un identificador personalizado o una instalación separada, cancela y conserva la app existente. [Fuentes de SideStore](https://docs.sidestore.io/docs/advanced/app-sources) · [Preguntas frecuentes](https://docs.sidestore.io/docs/faq.html)

## Publicación y descarga del IPA

Cada push a `main` que complete la compilación y la verificación del paquete publica una Release. El workflow añade al historial de `source.json` los metadatos del IPA de esa Release y enlaza a su etiqueta específica. El número de ejecución incrementa la versión visible y el número de compilación del IPA. Una ejecución antigua queda detrás de las más recientes en el historial. El commit de la fuente usa `GITHUB_TOKEN`, que no dispara otro workflow para ese push. Si `main` está protegido, la configuración del repositorio debe permitir el commit del bot. [Documentación de GitHub](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

La descarga manual sigue disponible como respaldo. [Descargar JARVIS-AI.ipa](https://github.com/xmanugonzalez/jarvis-ai/releases/latest/download/JARVIS-AI.ipa)

**Actions** conserva el artefacto **JARVIS-AI-iOS** como respaldo. Las ejecuciones manuales y los push a `master` generan el artefacto de Actions.

El runner macOS compila para un iPhone físico (arm64) y empaqueta `Payload/JarvisAI.app` sin firma. SideStore firma el IPA con tu cuenta de Apple y genera el perfil de aprovisionamiento al instalarlo. GitHub Actions no requiere certificados, contraseñas ni una membresía de pago de Apple.

El runner estándar es gratuito en repositorios públicos. Si el repositorio es privado, ejecuta el workflow dentro de la cuota incluida en tu cuenta. [Facturación de GitHub Actions](https://docs.github.com/en/actions/concepts/billing-and-usage)

## Instalación manual de respaldo

1. Si SideStore todavía no está instalado o configurado, sigue la [guía oficial para Windows](https://docs.sidestore.io/docs/installation/prerequisites.html) y completa la [instalación](https://docs.sidestore.io/docs/installation/install).
2. Con SideStore configurado, activa la VPN que requiere tu instalación. Abre **My Apps**, toca **+** y selecciona `JARVIS-AI.ipa`. Si iOS solicita activar Modo de desarrollador, sigue el aviso. Renueva la firma desde **My Apps** antes de la fecha que indique SideStore.
3. Si ya tienes [LiveContainer](https://livecontainer.github.io/docs/installation), puedes importar el IPA desde su botón **+**. Haz la primera prueba de permisos y audio con la instalación directa de SideStore. El comportamiento dentro de LiveContainer queda por comprobar.

## Voz local con Kokoro

En **Configuración → Kokoro · español**, descarga el modelo una vez (unos 142 MB). Escucha la demostración de em_alex desde esa sección. La descarga usa Hugging Face y la síntesis se ejecuta en el iPhone. En esa misma sección puedes cancelar la descarga o eliminar los archivos instalados.

La integración usa [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) v1.0 multilingüe INT8 mediante [sherpa-onnx 1.13.8](https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.8). La voz `em_alex` es el hablante 29 y el fonetizador usa `es`. Se usan dos hilos de CPU y se reutiliza el motor cargado. Si Kokoro falla o pasan diez segundos sin audio generado, JARVIS muestra el error. [Mapa oficial de voces](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html)

GitHub Actions prepara los datos del fonetizador y compila los binarios estáticos de iPhone mediante Swift Package Manager. Para abrir el proyecto y compilar en una Mac, ejecuta primero `bash .github/scripts/prepare_kokoro.sh` desde la raíz. La compilación incluye los avisos de Kokoro, sherpa-onnx, ONNX Runtime y eSpeak NG. Los binarios de sherpa-onnx usados aquí incluyen eSpeak NG bajo GPL. Consulta la información de código fuente y licencias de esa dependencia al distribuir el IPA. [Inventario de sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx/issues/4053)

## Modo JARVIS

1. Descarga Kokoro, empareja el Y12 Pro y verifica en **Bluetooth → Comprobar ruta** que aparece como entrada y salida manos libres.
2. En **Inicio**, activa **Modo JARVIS** y concede acceso al micrófono y a Apple Speech. Di «Jarvis» con pronunciación inglesa aproximada («Yárvis»), espera el tono y formula la pregunta. Prueba «¿Qué hora es?» y deja una pausa al terminar.
3. Después de oír la respuesta, puedes continuar con «¿Y qué fecha es hoy?». La ventana escucha continuaciones de hora y fecha que empiezan con «y» o «también». Cuando expire, di «Jarvis» de nuevo. En **Configuración → Modo JARVIS**, puedes ajustar el silencio de cierre y la duración de esa ventana. Elige **0 s** para exigir «Jarvis» en cada turno.

El detector INT8 de sherpa-onnx funciona localmente con un hilo de CPU y solo busca «Jarvis». Usa el modelo inglés GigaSpeech 3,3 M con licencia Apache 2.0. Se evaluó Porcupine, que requiere cuenta y AccessKey. Picovoice indica que actualmente no ofrece planes dedicados a uso personal o no comercial. [Modelo sherpa-onnx](https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html#sherpa-onnx-kws-zipformer-gigaspeech-3-3m-2024-01-01-english) · [Picovoice para iOS](https://picovoice.ai/docs/quick-start/porcupine-ios/) · [Preguntas de Picovoice](https://picovoice.ai/docs/faq/general/)

Apple Speech se abre tras el tono o durante la ventana de continuación. Cada turno automático se limita a 25 segundos de captura y 10 de finalización. Durante la reproducción, la app mantiene la sesión de audio y descarta los buffers del micrófono para evitar que su propia voz active otro turno. El audio de la conversación no se guarda en archivos. La ventana puede captar a otras personas cercanas y el filtro de instrucciones no identifica a quien habla. **Solo sin conexión** exige reconocimiento local de Apple Speech para la variante de español elegida.

### Pantalla bloqueada y Bluetooth

El modo usa una sesión de grabación y reproducción con `voiceChat`, HFP y la capacidad de audio en segundo plano. iOS decide si la sesión continúa al bloquear o dejar la app. Si suspende o termina el proceso, la detección se detiene. Después de volver a abrir JARVIS, puedes reactivar la escucha con el interruptor. Si hay una llamada, el turno se cancela. La detección puede reanudarse si iOS autoriza reactivar el audio tras la interrupción. Si se pierde HFP, la escucha se pausa y puede reanudarse al volver el casco. [AVAudioSession de Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)

La app permite mezclar audio en el Modo JARVIS. iOS y el casco pueden reducir la calidad, pausar la música o pasar de A2DP a HFP al abrir el micrófono. Desactiva el modo para liberar la sesión del casco. [Rutas Bluetooth de Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetooth)

### Pruebas

| Escenario en iPhone | Resultado esperado |
| --- | --- |
| App abierta, altavoz interno | «Jarvis» activa el tono. Una pregunta después del tono se transcribe y Kokoro responde. |
| Pantalla bloqueada y luego otra app en primer plano | Si iOS mantiene la sesión activa, se conserva el flujo de tono, captura y respuesta. Comprueba ambos casos por separado. |
| Micrófono y salida del Y12 Pro | El casco aparece como entrada y salida HFP y reproduce el tono y la respuesta. |
| Pausas y cierre | Una pausa inferior al umbral permite continuar. Tras superar el umbral, se procesa la instrucción. |
| Retorno al detector y activaciones accidentales | Habla sin decir «Jarvis» y comprueba que no hay respuesta. Prueba una continuación con «y», deja vencer la ventana y repite la frase sin activación. |
| Música, llamadas y reconexión | Comprueba cómo cambia la música con HFP. Recibe una llamada, cuelga, desconecta y reconecta el casco. Si iOS no reanuda la sesión, reactívala en Inicio. |
| Fallo de Kokoro y cierre de la app | Si falta el modelo, JARVIS indica cómo descargarlo. Al cerrar completamente la app, deja de escuchar. |

En Xcode o Console, filtra por las categorías `HandsFree`, `Speech` y `Synthesis` para ver los estados, el micrófono, las detecciones, los tiempos y los cambios de ruta. La pantalla **Configuración → Diagnóstico de reconocimiento** muestra el último error de Apple Speech.

En Windows se probó el detector con una muestra sintética de «Jarvis» pronunciada en inglés y dos grabaciones de conversación del modelo. La muestra inglesa activó el detector y las conversaciones no. Una muestra con jota española no activó el modelo. También se probó Kokoro con em_alex en español a 24 kHz. GitHub Actions ejecuta pruebas Swift de silencio, recuperación de la espera y filtrado de continuaciones antes de compilar el IPA. Las pruebas de la tabla, incluida la pantalla bloqueada, requieren un iPhone físico.
