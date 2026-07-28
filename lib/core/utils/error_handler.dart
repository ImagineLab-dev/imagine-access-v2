import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

/// Tipos de errores de red
enum NetworkErrorType {
  noConnection,
  timeout,
  serverError,
  unauthorized,
  forbidden,
  notFound,
  badRequest,
  unknown;

  bool get isRetryable {
    switch (this) {
      case NetworkErrorType.noConnection:
      case NetworkErrorType.timeout:
      case NetworkErrorType.serverError:
        return true;
      default:
        return false;
    }
  }
}

/// Clase para información de error de red.
///
/// [message] NO es texto para mostrarle al usuario: es una clave interna. Los
/// mensajes visibles salen de [ErrorHandler.localizedMessage], que resuelve
/// contra el idioma activo. Antes eran cadenas fijas en español, así que un
/// usuario en inglés o portugués recibía errores en un idioma que no era el
/// suyo pese a que la app declara tres.
class NetworkError {
  final NetworkErrorType type;
  final String message;
  final int? statusCode;
  final bool isRetryable;

  const NetworkError({
    required this.type,
    required this.message,
    this.statusCode,
    this.isRetryable = false,
  });
}

/// Utility class for handling and displaying errors consistently
class ErrorHandler {
  /// Analiza un error y devuelve información estructurada
  static NetworkError analyzeError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // Error de conexión (sin internet).
    //
    // En web el mensaje depende del navegador y no hay una excepción tipada
    // que los unifique, así que se matchea por texto:
    //   Chrome/Edge → "Failed to fetch"
    //   Safari      → "Load failed"
    //   Firefox     → "NetworkError when attempting to fetch resource"
    if (errorString.contains('failed to fetch') ||
        errorString.contains('load failed') ||
        errorString.contains('networkerror') ||
        errorString.contains('network error') ||
        errorString.contains('socket') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection closed')) {
      return const NetworkError(
        type: NetworkErrorType.noConnection,
        message: 'errorNoConnection',
        isRetryable: true,
      );
    }

    // Timeout
    if (errorString.contains('timeout')) {
      return const NetworkError(
        type: NetworkErrorType.timeout,
        message: 'errorTimeout',
        isRetryable: true,
      );
    }
    
    // Errores HTTP específicos
    if (errorString.contains('401') || errorString.contains('unauthorized')) {
      return const NetworkError(
        type: NetworkErrorType.unauthorized,
        message: 'errorUnauthorized',
        statusCode: 401,
        isRetryable: false,
      );
    }
    
    if (errorString.contains('403') || errorString.contains('forbidden')) {
      return const NetworkError(
        type: NetworkErrorType.forbidden,
        message: 'errorForbidden',
        statusCode: 403,
        isRetryable: false,
      );
    }
    
    if (errorString.contains('404') || errorString.contains('not found')) {
      return const NetworkError(
        type: NetworkErrorType.notFound,
        message: 'errorNotFound',
        statusCode: 404,
        isRetryable: false,
      );
    }
    
    if (errorString.contains('400') || errorString.contains('bad request')) {
      return const NetworkError(
        type: NetworkErrorType.badRequest,
        message: 'errorBadRequest',
        statusCode: 400,
        isRetryable: false,
      );
    }
    
    if (errorString.contains('500') || 
        errorString.contains('502') || 
        errorString.contains('503') ||
        errorString.contains('server error')) {
      return const NetworkError(
        type: NetworkErrorType.serverError,
        message: 'errorServer',
        statusCode: 500,
        isRetryable: true,
      );
    }
    
    // Error desconocido
    return NetworkError(
      type: NetworkErrorType.unknown,
      message: 'errorUnknown',
      isRetryable: false,
    );
  }

  /// Logs error to console with consistent format
  static void logError(
    String context,
    dynamic error, {
    StackTrace? stackTrace,
    String? source,
  }) {
    final networkError = analyzeError(error);
    
    if (kDebugMode) {
      dev.log(
        '[${networkError.type.name.toUpperCase()}] Error in $context: ${networkError.message}',
        error: error,
        stackTrace: stackTrace,
        name: source ?? 'ErrorHandler',
      );
    }
  }

  /// Returns localized message for a NetworkErrorType
  static String localizedMessage(BuildContext context, NetworkErrorType type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case NetworkErrorType.noConnection:
        return l10n.errorNoConnection;
      case NetworkErrorType.timeout:
        return l10n.errorTimeout;
      case NetworkErrorType.unauthorized:
        return l10n.errorUnauthorized;
      case NetworkErrorType.forbidden:
        return l10n.errorForbidden;
      case NetworkErrorType.notFound:
        return l10n.errorNotFound;
      case NetworkErrorType.badRequest:
        return l10n.errorBadRequest;
      case NetworkErrorType.serverError:
        return l10n.errorServer;
      case NetworkErrorType.unknown:
        return l10n.errorUnknown;
    }
  }

  /// Shows a user-friendly error snackbar
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onRetry,
    IconData icon = Icons.error_outline,
  }) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon,
              color: theme.colorScheme.onError,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onError),
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.error,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: onRetry != null
            ? SnackBarAction(
                label: AppLocalizations.of(context).retryAction,
                textColor: theme.colorScheme.onError,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// Shows a network error with automatic retry option if applicable
  static void showNetworkError(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
  }) {
    final networkError = analyzeError(error);
    
    IconData icon;
    switch (networkError.type) {
      case NetworkErrorType.noConnection:
        icon = Icons.wifi_off;
        break;
      case NetworkErrorType.timeout:
        icon = Icons.timer_off;
        break;
      case NetworkErrorType.serverError:
        icon = Icons.cloud_off;
        break;
      case NetworkErrorType.unauthorized:
        icon = Icons.lock_outline;
        break;
      default:
        icon = Icons.error_outline;
    }
    
    showErrorSnackBar(
      context,
      localizedMessage(context, networkError.type),
      onRetry: networkError.isRetryable ? onRetry : null,
      icon: icon,
    );
  }

  /// Shows a success snackbar
  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: theme.colorScheme.onPrimary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              message,
              style: TextStyle(color: theme.colorScheme.onPrimary),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
  }

  /// Shows a warning/info snackbar
  static void showInfoSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: isDark ? Colors.black87 : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isDark ? Colors.black87 : Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: action,
      ),
    );
  }

  /// Gets user-friendly error message from exception
  @Deprecated('Use analyzeError instead')
  static String getErrorMessage(dynamic error) {
    return analyzeError(error).message;
  }
  
  /// Ejecuta una operación con retry automático
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      attempts++;
      
      try {
        return await operation();
      } catch (e) {
        final networkError = analyzeError(e);
        
        // Si no es retryable o es el último intento, lanzar error
        if (!networkError.isRetryable || attempts >= maxAttempts) {
          if (shouldRetry != null && !shouldRetry(e)) {
            rethrow;
          }
          rethrow;
        }
        
        // Esperar antes de reintentar
        await Future.delayed(delay * attempts);
      }
    }
    
    throw Exception('Max retry attempts reached');
  }
}

/// Mixin for consistent error handling in state classes
mixin ErrorHandlerMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;
  String? _errorMessage;
  NetworkErrorType? _errorType;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  NetworkErrorType? get errorType => _errorType;
  bool get canRetry => _errorType?.isRetryable ?? false;

  void setLoading(bool value) {
    if (mounted) {
      setState(() => _isLoading = value);
    }
  }

  void setError(dynamic error) {
    final networkError = ErrorHandler.analyzeError(error);
    
    if (mounted) {
      setState(() {
        _errorMessage = networkError.message;
        _errorType = networkError.type;
      });
    }
    ErrorHandler.logError(widget.runtimeType.toString(), error);
  }

  void clearError() {
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _errorType = null;
      });
    }
  }

  Future<void> handleAsync(Future<void> Function() operation) async {
    try {
      setLoading(true);
      clearError();
      await operation();
    } catch (e) {
      setError(e);
    } finally {
      setLoading(false);
    }
  }
  
  Future<void> handleAsyncWithRetry(
    Future<void> Function() operation, {
    int maxAttempts = 3,
  }) async {
    try {
      setLoading(true);
      clearError();
      await ErrorHandler.withRetry(operation, maxAttempts: maxAttempts);
    } catch (e) {
      setError(e);
    } finally {
      setLoading(false);
    }
  }
}
