/// A CI usa a versão do pubspec e o mesmo número dos pacotes Android/Windows.
class AppVersion {
  static const name =
      String.fromEnvironment('SOMIA_VERSION', defaultValue: '0.2.0-alpha');
  static const build = String.fromEnvironment('SOMIA_BUILD_NUMBER');
  static const label = build == ''
      ? 'Versão $name · Compilação local'
      : 'Versão $name · Compilação $build';
}
