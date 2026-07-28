import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imagine_access/features/tickets/data/ticket_repository.dart';
import 'package:imagine_access/core/offline/offline_queue_service.dart';
import 'package:imagine_access/core/offline/pending_operation.dart';

// ─── Mocks ──────────────────────────────────────────────
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class MockRef extends Mock implements Ref {}

class MockOfflineQueueService extends Mock implements OfflineQueueService {}

/// El repositorio lee la sesión antes de invocar la función: guarda el token,
/// intenta refrescar y vuelve a leerlo. Sin estos dobles, mocktail lanza al
/// primer acceso, el catch genérico lo convierte en TicketException y los
/// cuatro tests fallaban por el andamiaje, no por el código que querían probar.
class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      PendingOperation(
        id: 'fallback-op',
        type: 'create_ticket',
        payload: const <String, dynamic>{},
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  });

  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late MockRef mockRef;
  late MockOfflineQueueService mockOfflineQueue;
  late MockGoTrueClient mockAuth;

  // El repositorio lee el token de respaldo con flutter_secure_storage, que
  // habla por un canal de plataforma. En un test unitario ese canal no existe:
  // sin el binding y sin este doble, cualquier lectura lanza "Binding has not
  // yet been initialized" y el catch genérico lo disfraza de fallo al crear el
  // ticket.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'read' ? null : <String, String>{},
    );
  });
  late TicketRepository repository;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    mockRef = MockRef();
    mockOfflineQueue = MockOfflineQueueService();

    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    // Sin sesión: el repositorio cae en su respaldo y sigue igual. Es el camino
    // que importa acá — lo que se prueba es la llamada a la función, no el
    // manejo del token.
    when(() => mockAuth.currentSession).thenReturn(null);
    when(() => mockAuth.refreshSession()).thenAnswer(
        (_) async => AuthResponse(session: null, user: null));

    when(() => mockClient.functions).thenReturn(mockFunctions);
    when(() => mockRef.read(offlineQueueProvider)).thenReturn(mockOfflineQueue);
    when(() => mockOfflineQueue.enqueue(any())).thenAnswer((_) async {});
    repository = TicketRepository(mockClient, mockRef);
  });

  group('TicketRepository', () {
    group('createTicket', () {
      test('calls create_ticket edge function with correct body', () async {
        when(() => mockFunctions.invoke(
              'create_ticket',
              body: any(named: 'body'),
            )).thenAnswer((_) async => FunctionResponse(
              status: 200,
              data: {
                'ticket_id': 'tk-001',
                'status': 'created',
              },
            ));

        final result = await repository.createTicket(
          eventSlug: 'summer-party-2026',
          type: 'VIP',
          price: 150000.0,
          buyerName: 'Juan Pérez',
          buyerEmail: 'juan@test.com',
          buyerDoc: '12345678',
          buyerPhone: '+595981234567',
        );

        expect(result['ticket_id'], equals('tk-001'));
        expect(result['status'], equals('created'));

        verify(() => mockFunctions.invoke(
              'create_ticket',
              body: any(named: 'body'),
            )).called(1);
      });

      test('throws TicketException on non-200 response', () async {
        when(() => mockFunctions.invoke(
              'create_ticket',
              body: any(named: 'body'),
            )).thenAnswer((_) async => FunctionResponse(
              status: 400,
              data: 'Quota exceeded',
            ));

        expect(
          () => repository.createTicket(
            eventSlug: 'test-event',
            type: 'Standard',
            price: 50000.0,
            buyerName: 'Test',
            buyerEmail: 'test@test.com',
            buyerDoc: '99999999',
            buyerPhone: '+595900000000',
          ),
          throwsA(isA<TicketException>()),
        );
      });

      test('queues operation on retryable network errors', () async {
        when(() => mockFunctions.invoke(
              'create_ticket',
              body: any(named: 'body'),
            )).thenThrow(Exception('Network timeout'));

        final result = await repository.createTicket(
          eventSlug: 'test',
          type: 'Standard',
          price: 0,
          buyerName: 'Test',
          buyerEmail: 'test@test.com',
          buyerDoc: '00000000',
          buyerPhone: '+0',
        );

        expect(result['queued'], isTrue);
        verify(() => mockOfflineQueue.enqueue(any())).called(1);
      });

      test('wraps non-retryable errors in TicketException', () async {
        when(() => mockFunctions.invoke(
              'create_ticket',
              body: any(named: 'body'),
            )).thenThrow(Exception('Bad request payload'));

        expect(
          () => repository.createTicket(
            eventSlug: 'test',
            type: 'Standard',
            price: 0,
            buyerName: 'Test',
            buyerEmail: 'test@test.com',
            buyerDoc: '00000000',
            buyerPhone: '+0',
          ),
          throwsA(isA<TicketException>()),
        );
      });
    });

    group('resendTicket', () {
      test('calls resend_ticket_email edge function', () async {
        when(() => mockFunctions.invoke(
              'resend_ticket_email',
              body: {'ticket_id': 'tk-001'},
            )).thenAnswer((_) async => FunctionResponse(
              status: 200,
              data: {'success': true},
            ));

        await repository.resendTicket('tk-001');

        verify(() => mockFunctions.invoke(
              'resend_ticket_email',
              body: {'ticket_id': 'tk-001'},
            )).called(1);
      });

      test('throws TicketException on failure', () async {
        when(() => mockFunctions.invoke(
              'resend_ticket_email',
              body: {'ticket_id': 'tk-001'},
            )).thenAnswer((_) async => FunctionResponse(
              status: 500,
              data: 'SMTP error',
            ));

        expect(
          () => repository.resendTicket('tk-001'),
          throwsA(isA<TicketException>()),
        );
      });
    });

    group('voidTicket', () {
      test('calls void_ticket edge function', () async {
        when(() => mockFunctions.invoke(
              'void_ticket',
              body: {'ticket_id': 'tk-002'},
            )).thenAnswer((_) async => FunctionResponse(
              status: 200,
              data: {'success': true},
            ));

        await repository.voidTicket('tk-002');

        verify(() => mockFunctions.invoke(
              'void_ticket',
              body: {'ticket_id': 'tk-002'},
            )).called(1);
      });

      test('throws TicketException on failure', () async {
        when(() => mockFunctions.invoke(
              'void_ticket',
              body: {'ticket_id': 'tk-002'},
            )).thenAnswer((_) async => FunctionResponse(
              status: 403,
              data: 'Not authorized',
            ));

        expect(
          () => repository.voidTicket('tk-002'),
          throwsA(isA<TicketException>()),
        );
      });

      test('wraps unexpected errors in TicketException', () async {
        when(() => mockFunctions.invoke(
              'void_ticket',
              body: {'ticket_id': 'tk-002'},
            )).thenThrow(Exception('Connection refused'));

        expect(
          () => repository.voidTicket('tk-002'),
          throwsA(isA<TicketException>()),
        );
      });
    });
  });
}
