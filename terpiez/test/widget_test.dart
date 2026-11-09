import 'package:flutter_test/flutter_test.dart';
import 'package:terpiez/app_config.dart';

void main() {
  group('Redis configuration validation', () {
    test('rejects a missing host', () {
      final error = AppConfig.validateRedisConfiguration(
        host: '',
        port: 1234,
      );

      expect(error, contains('TERPIEZ_REDIS_HOST'));
    });

    test('rejects missing or out-of-range ports', () {
      expect(
        AppConfig.validateRedisConfiguration(host: 'example.test', port: 0),
        contains('TERPIEZ_REDIS_PORT'),
      );
      expect(
        AppConfig.validateRedisConfiguration(
          host: 'example.test',
          port: 65536,
        ),
        contains('TERPIEZ_REDIS_PORT'),
      );
    });

    test('accepts a non-empty host and valid port', () {
      expect(
        AppConfig.validateRedisConfiguration(
          host: 'example.test',
          port: 1234,
        ),
        isNull,
      );
    });
  });
}
