# Imagine Access - Flavor Configuration
# ======================================
# 
# This project uses flavors to manage different environments:
# - dev: Development environment
# - staging: Staging/QA environment  
# - prod: Production environment (App Store / Play Store)
#
# Usage:
# ------
# Android:
#   flutter run --flavor dev -t lib/main_dev.dart
#   flutter run --flavor staging -t lib/main_staging.dart
#   flutter run --flavor prod -t lib/main.dart
#
#   flutter build apk --flavor prod --release
#   flutter build appbundle --flavor prod --release
#
# iOS:
#   flutter run --flavor dev -t lib/main_dev.dart --dart-define=FLAVOR=dev
#   flutter run --flavor prod -t lib/main.dart --dart-define=FLAVOR=prod
#
#   flutter build ios --flavor prod --release
#
# Environment Variables:
# ----------------------
# Each flavor uses different .env files:
# - .env.dev
# - .env.staging
# - .env.prod (or just .env for production)

# Flavor-specific configuration
flavors:
  dev:
    app_name: "Imagine Access Dev"
    bundle_id: "com.imagineaccess.app.dev"
    description: "Development environment with debug features"
  staging:
    app_name: "Imagine Access Staging"
    bundle_id: "com.imagineaccess.app.staging"
    description: "Staging/QA environment for testing"
  prod:
    app_name: "Imagine Access"
    bundle_id: "com.imagineaccess.app"
    description: "Production environment for App Store and Play Store"
