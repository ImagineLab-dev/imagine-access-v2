# Script para generar keystore de Android Release
# Ejecutar: .\generate_keystore.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Imagine Access - Android Keystore   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$keystoreName = "imagine_access.keystore"
$alias = "imagine_access"
$validity = 10000 # días (~27 años)

Write-Host "Este script generará un keystore para firmar tu aplicación Android." -ForegroundColor Yellow
Write-Host ""
Write-Host "IMPORTANTE:" -ForegroundColor Red
Write-Host "- Guarda las contraseñas en un lugar SEGURO (ej. administrador de contraseñas)" -ForegroundColor Yellow
Write-Host "- NUNCA pierdas este keystore o no podrás actualizar tu app en Play Store" -ForegroundColor Yellow
Write-Host "- NUNCA compartas este archivo" -ForegroundColor Yellow
Write-Host ""

$continue = Read-Host "¿Continuar? (y/n)"
if ($continue -ne 'y') {
    Write-Host "Operación cancelada." -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "Generando keystore..." -ForegroundColor Green

# Comando para generar keystore
$keytoolPath = "keytool"
if ($env:JAVA_HOME) {
    $keytoolPath = "$env:JAVA_HOME\bin\keytool"
}

& $keytoolPath -genkey -v `
    -keystore ".\android\$keystoreName" `
    -alias $alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity $validity

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ¡KEYSTORE GENERADO EXITOSAMENTE!    " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ubicación: .\android\$keystoreName" -ForegroundColor Cyan
    Write-Host "Alias: $alias" -ForegroundColor Cyan
    Write-Host "Validez: $validity días" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "SIGUIENTES PASOS:" -ForegroundColor Yellow
    Write-Host "1. Edita android\key.properties con tus contraseñas" -ForegroundColor White
    Write-Host "2. Ejecuta: flutter build appbundle --release" -ForegroundColor White
    Write-Host "3. ¡Sube el archivo .aab a Google Play Console!" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "ERROR: No se pudo generar el keystore." -ForegroundColor Red
    Write-Host "Verifica que JAVA_HOME esté configurado correctamente." -ForegroundColor Yellow
}
