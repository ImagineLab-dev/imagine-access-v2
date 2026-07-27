import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/utils/error_handler.dart';

void main() {
  group('ErrorHandler.analyzeError — fallos de red del navegador', () {
    test('clasifica "Failed to fetch" de Chrome como noConnection', () {
      final result = ErrorHandler.analyzeError(
        Exception('ClientException: Failed to fetch, uri=https://x.supabase.co'),
      );

      expect(result.type, NetworkErrorType.noConnection);
      expect(result.isRetryable, isTrue);
    });

    test('clasifica "Load failed" de Safari como noConnection', () {
      final result = ErrorHandler.analyzeError(
        Exception('ClientException: Load failed, uri=https://x.supabase.co'),
      );

      expect(result.type, NetworkErrorType.noConnection);
      expect(result.isRetryable, isTrue);
    });

    test('clasifica el NetworkError de Firefox como noConnection', () {
      final result = ErrorHandler.analyzeError(
        Exception('NetworkError when attempting to fetch resource.'),
      );

      expect(result.type, NetworkErrorType.noConnection);
      expect(result.isRetryable, isTrue);
    });

    test('clasifica timeouts como retryable', () {
      final result = ErrorHandler.analyzeError(
        Exception('TimeoutException after 0:00:30.000000'),
      );

      expect(result.type, NetworkErrorType.timeout);
      expect(result.isRetryable, isTrue);
    });
  });

  group('ErrorHandler.analyzeError — errores HTTP', () {
    test('clasifica 401', () {
      final result = ErrorHandler.analyzeError('401 Unauthorized');

      expect(result.type, NetworkErrorType.unauthorized);
      expect(result.statusCode, 401);
      expect(result.isRetryable, isFalse);
    });

    test('clasifica 403', () {
      final result = ErrorHandler.analyzeError('403 Forbidden');

      expect(result.type, NetworkErrorType.forbidden);
      expect(result.statusCode, 403);
    });

    test('clasifica 404', () {
      final result = ErrorHandler.analyzeError('404 Not Found');

      expect(result.type, NetworkErrorType.notFound);
      expect(result.statusCode, 404);
    });

    test('clasifica errores de servidor como retryable', () {
      final result = ErrorHandler.analyzeError('503 server error');

      expect(result.type, NetworkErrorType.serverError);
      expect(result.isRetryable, isTrue);
    });
  });

  group('ErrorHandler.analyzeError — desconocidos', () {
    test('no marca como retryable lo que no reconoce', () {
      final result = ErrorHandler.analyzeError(Exception('random failure'));

      expect(result.type, NetworkErrorType.unknown);
      expect(result.isRetryable, isFalse);
      expect(result.message, isNotEmpty);
    });

    test('devuelve el string tal cual cuando el error es un String', () {
      final result = ErrorHandler.analyzeError('algo raro pasó');

      expect(result.type, NetworkErrorType.unknown);
      expect(result.message, 'algo raro pasó');
    });
  });
}
