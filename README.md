# JARVIS AI · Etapa 1

Asistente SwiftUI en español para iPhone con iOS 17 o posterior. Incluye transcripción de voz, respuestas locales, síntesis en español y una prueba de grabación y reproducción. El audio funciona mientras la app está abierta.

## Generar el IPA desde Windows

1. Sube este proyecto a un repositorio de GitHub con Actions habilitado. Un push a `main` o `master` compila automáticamente. También puedes abrir **Actions → Compilar IPA de JARVIS AI → Run workflow** para iniciarlo a mano.
2. Cuando termine la ejecución, descarga **JARVIS-AI-iOS** en **Artifacts**. Extrae `JARVIS-AI.ipa` del ZIP y guárdalo en **Archivos** en el iPhone.

El runner macOS compila para un iPhone físico (arm64) y empaqueta `Payload/JarvisAI.app` sin firma. SideStore firma el IPA con tu cuenta de Apple y genera el perfil de aprovisionamiento al instalarlo. GitHub Actions no requiere certificados, contraseñas ni una membresía de pago de Apple.

El runner estándar es gratuito en repositorios públicos. Si el repositorio es privado, ejecuta el workflow dentro de la cuota incluida en tu cuenta. [Facturación de GitHub Actions](https://docs.github.com/en/actions/concepts/billing-and-usage)

## Instalar y firmar

1. Si SideStore todavía no está instalado o configurado, sigue la [guía oficial para Windows](https://docs.sidestore.io/docs/installation/prerequisites.html) y completa la [instalación](https://docs.sidestore.io/docs/installation/install).
2. Con SideStore configurado, activa la VPN que requiere tu instalación. Abre **My Apps**, toca **+** y selecciona `JARVIS-AI.ipa`. Si iOS solicita activar Modo de desarrollador, sigue el aviso. Renueva la firma desde **My Apps** antes de la fecha que indique SideStore.
3. Si ya tienes [LiveContainer](https://livecontainer.github.io/docs/installation), puedes importar el IPA desde su botón **+**. Haz la primera prueba de permisos y audio con la instalación directa de SideStore. El comportamiento dentro de LiveContainer queda por comprobar.

## Probar con el Y12 Pro

1. Empareja y conecta el intercomunicador en **Ajustes → Bluetooth** de iOS. En JARVIS, abre **Bluetooth → Comprobar ruta**. Si iOS expone una ruta manos libres, comprueba que el casco aparece como entrada y salida. Una ruta de solo salida no confirma que el micrófono del casco esté disponible.
2. Toca **Grabar prueba**, habla, termina la grabación y toca **Reproducir grabación**. Escucha el resultado en el casco. La grabación es temporal y se reemplaza al guardar una nueva toma.
3. En **Inicio**, toca **Comenzar a escuchar**, concede los permisos y di «Hola, Jarvis». Toca **Terminar de hablar** o espera a que la transcripción deje de cambiar. Deberías ver el texto y escuchar «A sus órdenes, señor».
4. En **Configuración**, elige una voz masculina que el iPhone ofrezca, ajusta el ritmo y prueba la voz. **Solo sin conexión** exige reconocimiento local del idioma seleccionado. Cuando ese ajuste está desactivado y el idioma carece de reconocimiento local, Speech puede usar el servicio de Apple.
5. Desconecta el casco durante una prueba. JARVIS debe detener el audio si cambia la ruta. Reconecta y vuelve a comprobarla. Haz lo mismo después de una llamada que interrumpa la sesión.

El nombre del casco y los perfiles disponibles dependen de iOS y del accesorio. **Preferir manos libres** solicita una entrada HFP cuando está disponible. Con esa preferencia desactivada, iOS decide la ruta. Las pruebas de instalación, micrófono del Y12 Pro y salida por el casco requieren un iPhone físico.
