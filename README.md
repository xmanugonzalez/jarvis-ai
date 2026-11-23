# JARVIS AI · Etapa 1

Asistente SwiftUI en español para iPhone con iOS 17 o posterior. Incluye transcripción de voz, respuestas locales, síntesis en español y una prueba de grabación y reproducción. El audio funciona mientras la app está abierta.

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

## Probar con el Y12 Pro

1. Empareja y conecta el intercomunicador en **Ajustes → Bluetooth** de iOS. En JARVIS, abre **Bluetooth → Comprobar ruta**. Si iOS expone una ruta manos libres, comprueba que el casco aparece como entrada y salida. Una ruta de solo salida no confirma que el micrófono del casco esté disponible.
2. Toca **Grabar prueba**, habla, termina la grabación y toca **Reproducir grabación**. Escucha el resultado en el casco. La grabación es temporal y se reemplaza al guardar una nueva toma.
3. En **Inicio**, toca **Comenzar a escuchar**, concede los permisos y di «Hola, Jarvis». Toca **Terminar de hablar** cuando acabes. Deberías ver el texto y escuchar «A sus órdenes, señor». Si falla, abre **Configuración → Diagnóstico de reconocimiento** y copia el último error.
4. En **Configuración**, elige una voz masculina que el iPhone ofrezca, ajusta el ritmo y prueba la voz. **Solo sin conexión** exige reconocimiento local del idioma seleccionado. Si lo desactivas, iOS puede usar el servicio de Apple.
5. Desconecta el casco durante una prueba. JARVIS debe detener el audio si cambia la ruta. Reconecta y vuelve a comprobarla. Haz lo mismo después de una llamada que interrumpa la sesión.

El nombre del casco y los perfiles disponibles dependen de iOS y del accesorio. **Preferir manos libres** solicita una entrada HFP cuando está disponible. Con esa preferencia desactivada, iOS decide la ruta. Las pruebas de instalación, micrófono del Y12 Pro y salida por el casco requieren un iPhone físico.
