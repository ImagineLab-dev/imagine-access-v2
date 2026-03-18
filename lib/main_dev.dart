// Imagine Access - Development Flavor
// This file is used for development builds with debug features enabled.

import 'main.dart' as original_main;

// Flavor configuration
const String flavorName = 'dev';
const bool isDevelopment = true;
const bool enableDebugFeatures = true;

void main() async {
  // Set flavor-specific environment
  await original_main.main(
    flavor: flavorName,
    production: false,
  );
}
