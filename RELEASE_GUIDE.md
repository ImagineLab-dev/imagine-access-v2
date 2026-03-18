# 🚀 Guía de Release para Google Play Store y Apple App Store

**Imagine Access** - Professional Event Access Control Platform

**Última actualización:** Marzo 2026  
**Versión del documento:** 1.0.1

---

## ⚡ Inicio Rápido

### Para desarrollo/testing (sin keystore):
```bash
flutter build apk --debug
```

### Para producción (CON keystore):
```bash
# 1. Generar keystore
.\generate_keystore.ps1

# 2. Configurar credenciales
# Editar android/key.properties con tus contraseñas

# 3. Build para Play Store
flutter build appbundle --release

# 4. El archivo se genera en:
# build/app/outputs/bundle/release/app-release.aab
```

---

## 📋 Prerrequisitos

### Para Google Play Store
1. **Cuenta de Desarrollador de Google Play** ($25 USD único)
2. **Keystore de firma** (generar con el script incluido)
3. **Assets gráficos**:
   - Icono de alta resolución (512x512 PNG)
   - Imagen destacada (1024x500 PNG)
   - Screenshots (mínimo 2, máximo 8)

### Para Apple App Store
1. **Cuenta de Desarrollador de Apple** ($99 USD/año)
2. **Certificado de distribución iOS**
3. **Provisioning Profile**
4. **Assets gráficos**:
   - Icono de alta resolución (1024x1024 PNG)
   - Screenshots para iPhone y iPad

---

## 🔐 Generar Keystore (Android)

### ⚠️ IMPORTANTE - LEER PRIMERO

El keystore es tu firma digital para aplicaciones Android. **Sin él, no podrás subir tu app a Play Store**.

### Opción 1: Usar el script PowerShell (Recomendado para Windows)
```powershell
.\generate_keystore.ps1
```

El script te guiará paso a paso para:
1. Generar el keystore
2. Configurar las contraseñas
3. Guardar la información de forma segura

### Opción 2: Manual con keytool (Cualquier plataforma)

**Windows (con Java instalado):**
```cmd
cd android
"%JAVA_HOME%\bin\keytool" -genkey -v -keystore imagine_access.keystore ^
  -alias imagine_access -keyalg RSA -keysize 2048 -validity 10000
```

**macOS/Linux:**
```bash
cd android
keytool -genkey -v -keystore imagine_access.keystore \
  -alias imagine_access -keyalg RSA -keysize 2048 -validity 10000
```

### 📝 Configurar key.properties

Después de generar el keystore, edita `android/key.properties`:

```properties
# CONTRASEÑAS REALES - CAMBIAR ESTOS VALORES
storePassword=TU_CONTRASEÑA_AQUI
keyPassword=TU_CONTRASEÑA_AQUI
keyAlias=imagine_access
storeFile=../imagine_access.keystore
```

### 🔒 Seguridad del Keystore

**NUNCA:**
- ❌ Pierdas el keystore (sin él, no puedes actualizar tu app)
- ❌ Compartas el keystore o las contraseñas
- ❌ Commitees el keystore a Git (está en .gitignore)

**SIEMPRE:**
- ✅ Guarda una copia de seguridad en un lugar seguro (USB, caja fuerte, password manager)
- ✅ Documenta las contraseñas en un password manager
- ✅ Mantén el keystore separado del código fuente

---

## 📱 Build para Google Play Store

### Paso 1: Verificar configuración

Antes de compilar, asegúrate de:
```bash
# 1. El keystore existe
ls android/imagine_access.keystore

# 2. key.properties tiene las contraseñas correctas
cat android/key.properties

# 3. No hay errores de compilación
flutter analyze
```

### Paso 2: Generar Android App Bundle (.aab)

**Build de release completo:**
```bash
flutter build appbundle --release
```

**Build con flavor específico:**
```bash
flutter build appbundle --release --flavor prod
```

### Paso 3: Ubicar el archivo generado

El archivo se genera en:
```
build/app/outputs/bundle/release/app-release.aab
```

O con flavors:
```
build/app/outputs/bundle/prodRelease/app-prod-release.aab
```

### Paso 4: Subir a Google Play Console

1. Ve a [Google Play Console](https://play.google.com/console)
2. Selecciona tu aplicación (o crea una nueva)
3. Ve a **"Production"** → **"Create new release"**
4. Sube el archivo `.aab` (drag & drop o browse)
5. Completa la información del release:
   - Release name (ej: "1.0.0 - Initial release")
   - Release notes (en inglés y español)
6. Revisa los warnings/approvals
7. Click en **"Save"**
8. Click en **"Review release"**
9. Click en **"Start rollout to Production"**

### Build alternativo: APK (solo para testing interno)

```bash
# APK debug (para desarrollo)
flutter build apk --debug

# APK release (para testing)
flutter build apk --release

# APK dividido por arquitectura (recomendado)
flutter build apk --split-per-abi
```

Output:
```
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk  # 32-bit
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk    # 64-bit
build/app/outputs/flutter-apk/app-x86_64-release.apk       # Emulator
```

---

## 🐛 Troubleshooting Android Build

### Error: "Keystore file not found"

**Causa:** El archivo `key.properties` existe pero el keystore no.

**Solución:**
```bash
# Opción 1: Generar el keystore
.\generate_keystore.ps1

# Opción 2: Eliminar key.properties temporalmente para testing
rm android/key.properties
flutter build apk --debug
```

### Error: "Signing failed"

**Causa:** Contraseñas incorrectas en `key.properties`.

**Solución:**
1. Verifica las contraseñas en `key.properties`
2. Si las olvidaste, genera un nuevo keystore:
```bash
rm android/imagine_access.keystore
.\generate_keystore.ps1
```

### Error: "Gradle build failed"

**Causa:** Problemas con Gradle o dependencias.

**Solución:**
```bash
# Limpiar proyecto
flutter clean

# Eliminar caché de Gradle
rm android/.gradle

# Obtener dependencias
flutter pub get

# Rebuild
flutter build appbundle --release
```

### Build muy lento

**Soluciones:**
```bash
# Habilitar Gradle daemon
echo "org.gradle.daemon=true" >> android/gradle.properties
echo "org.gradle.parallel=true" >> android/gradle.properties
echo "org.gradle.caching=true" >> android/gradle.properties

# Aumentar memoria Gradle
echo "org.gradle.jvmargs=-Xmx4g" >> android/gradle.properties
```

### Error: "R8/ProGuard shrink failed"

**Causa:** Proguard está eliminando código necesario.

**Solución:** Deshabilitar temporalmente en `android/app/build.gradle`:
```gradle
buildTypes {
    release {
        minifyEnabled false
        shrinkResources false
    }
}
```

---

## 🍎 Build para Apple App Store

### Prerrequisitos
- macOS con Xcode instalado
- Cuenta de Apple Developer Program
- Certificados y provisioning profiles configurados

### 1. Configurar Bundle ID en App Store Connect
1. Ve a [App Store Connect](https://appstoreconnect.apple.com)
2. Crea una nueva app
3. Usa el Bundle ID: `com.imagineaccess.app`

### 2. Build desde macOS
```bash
# Limpiar proyecto
flutter clean

# Obtener dependencias
flutter pub get

# Build para iOS
flutter build ios --release --flavor prod
```

### 3. Archivar en Xcode
```bash
cd ios
open Runner.xcworkspace
```

En Xcode:
1. **Product** → **Archive**
2. Espera a que complete el archive
3. Se abrirá **Organizer** automáticamente
4. Click en **Distribute App**
5. Selecciona **App Store Connect** → **Upload**
6. Sigue los pasos del asistente

### 4. Subir desde línea de comandos (alternativa)
```bash
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/ios/archive/Runner.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions.plist
```

### 5. Subir a App Store Connect
1. Ve a [App Store Connect](https://appstoreconnect.apple.com)
2. Selecciona tu aplicación
3. Ve a la pestaña "App Store"
4. En la sección "Build", click en "+"
5. Selecciona el build que acabas de subir
6. Completa la información del release
7. Envía para revisión

---

## 📊 Versionado

### Convención de versiones
El proyecto usa versionado semántico: `X.Y.Z+B`

- **X** (Major): Cambios incompatibles
- **Y** (Minor): Nuevas features compatibles
- **Z** (Patch): Bug fixes
- **B** (Build): Número incremental para stores

### Ejemplos
```
1.0.0+1   - Primer release
1.0.1+2   - Bug fix
1.1.0+3   - Nueva feature
2.0.0+4   - Cambio mayor
```

### Actualizar versión
Edita `pubspec.yaml`:
```yaml
version: 1.0.1+2  # Cambia esto
```

---

## 🔒 Seguridad

### Variables de entorno
Nunca commitees archivos `.env` con credenciales reales:

```bash
# Archivos que NO deben ir a git
.env
.env.dev
.env.staging
.env.prod
android/key.properties
android/*.keystore
ios/ExportOptions.plist
```

### Usar .env.example
Crea un `.env.example` con placeholders:
```env
SUPABASE_URL=YOUR_SUPABASE_URL
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=YOUR_SUPABASE_SERVICE_ROLE_KEY
```

---

## ✅ Checklist Pre-Release

### General
- [ ] Tests pasan (`flutter test`)
- [ ] No hay errores de compilación (`flutter analyze`)
- [ ] Version actualizada en `pubspec.yaml`
- [ ] CHANGELOG.md actualizado

### Android
- [ ] Keystore generado y asegurado
- [ ] key.properties configurado
- [ ] Build de release exitoso
- [ ] Testing en dispositivo físico

### iOS
- [ ] Bundle ID configurado en App Store Connect
- [ ] Certificados válidos
- [ ] Provisioning profiles actualizados
- [ ] Info.plist completo
- [ ] Screenshots actualizados

### Store Listing
- [ ] Descripción actualizada
- [ ] Keywords optimizadas
- [ ] Screenshots actualizados
- [ ] Política de privacidad link
- [ ] Términos de uso link

---

## 🐛 Troubleshooting

### Android: "Signing failed"
```bash
# Verificar keystore
ls -la android/*.keystore

# Verificar key.properties
cat android/key.properties

# Limpiar y rebuild
flutter clean
flutter pub get
flutter build appbundle --release
```

### iOS: "No provisioning profiles found"
1. Ve a [Apple Developer Portal](https://developer.apple.com)
2. Crea/regenera el provisioning profile
3. Descarga e instala el profile
4. En Xcode: **Xcode** → **Preferences** → **Accounts** → **Download Manual Profiles**

### Build muy grande
```bash
# Analizar tamaño
flutter build apk --analyze-size

# Optimizar
# - Usar --split-per-abi
# - Revisar assets
# - Habilitar R8/ProGuard
```

---

## 📞 Soporte

Para issues relacionados con el build:
1. Revisa los logs de error
2. Ejecuta con `--verbose` para más detalles
3. Consulta la documentación oficial de Flutter:
   - [Android deployment](https://docs.flutter.dev/deployment/android)
   - [iOS deployment](https://docs.flutter.dev/deployment/ios)

---

**Última actualización:** Marzo 2026  
**Versión del documento:** 1.0.0
