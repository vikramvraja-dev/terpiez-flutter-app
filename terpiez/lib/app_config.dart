class AppConfig {
  const AppConfig._();

  static const String redisHost = String.fromEnvironment(
    'TERPIEZ_REDIS_HOST',
  );

  static const int redisPort = int.fromEnvironment(
    'TERPIEZ_REDIS_PORT',
  );

  static String? validateRedisConfiguration({
    required String host,
    required int port,
  }) {
    if (host.trim().isEmpty) {
      return 'Redis configuration is missing. Start Terpiez with '
          '--dart-define=TERPIEZ_REDIS_HOST=<host> and '
          '--dart-define=TERPIEZ_REDIS_PORT=<port>.';
    }

    if (port < 1 || port > 65535) {
      return 'Redis configuration is invalid. TERPIEZ_REDIS_PORT must be '
          'between 1 and 65535.';
    }

    return null;
  }

  static String? get redisConfigurationError =>
      validateRedisConfiguration(
        host: redisHost,
        port: redisPort,
      );

  static bool get isRedisConfigured => redisConfigurationError == null;
}
