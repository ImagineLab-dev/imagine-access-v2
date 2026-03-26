// Imagine Access - Staging Flavor
import 'main.dart' as original_main;

const String flavorName = 'staging';
const bool isDevelopment = false;
const bool enableDebugFeatures = true;

void main() async {
  await original_main.main(
    flavor: flavorName,
    production: false,
  );
}
