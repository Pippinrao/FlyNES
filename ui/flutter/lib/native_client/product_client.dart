import 'dart:async';
import 'package:flutter/services.dart';

typedef ProductMap = Map<String, Object?>;

abstract interface class ProductClient {
  Future<ProductMap> bootstrap();
  Future<ProductMap> call(String method, [ProductMap arguments = const {}]);
  void dispose();
}

abstract interface class ProductEventSource {
  Stream<ProductMap> get events;
}

final class ProductFailure implements Exception {
  const ProductFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Product owners remain native; this object owns only a channel observation.
final class ChannelProductClient implements ProductClient, ProductEventSource {
  ChannelProductClient({
    MethodChannel channel = const MethodChannel('flynes/product.v1'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onNativeEvent);
  }

  final MethodChannel _channel;
  int _request = 0;
  int _hostGeneration = 0;
  String? _instanceId;
  bool _disposed = false;
  int _bootstrapRequest = 0;
  final _events = StreamController<ProductMap>.broadcast();
  @override
  Stream<ProductMap> get events => _events.stream;

  Future<void> _onNativeEvent(MethodCall call) async {
    if (_disposed ||
        !const {'contextChanged', 'projectionChanged'}.contains(call.method) ||
        call.arguments is! Map) {
      return;
    }
    final event = Map<String, Object?>.from(call.arguments as Map);
    final host = event['hostGeneration'];
    if (event['instanceId'] != _instanceId ||
        host is! int ||
        host < _hostGeneration) {
      return;
    }
    if (call.method == 'contextChanged') {
      _hostGeneration = host;
      ++_bootstrapRequest;
    } else if (host != _hostGeneration) {
      return;
    }
    _events.add(Map.unmodifiable({...event, 'event': call.method}));
  }

  @override
  Future<ProductMap> bootstrap() async {
    final request = ++_bootstrapRequest;
    final result = await call('bootstrap');
    if (request != _bootstrapRequest) {
      throw const ProductFailure('stale_response');
    }
    if (result['protocolVersion'] != 1) {
      throw const ProductFailure('protocol_mismatch');
    }
    final generation = result['hostGeneration'];
    final instance = result['instanceId'];
    if (generation is! int ||
        generation <= 0 ||
        instance is! String ||
        instance.isEmpty) {
      throw const ProductFailure('invalid_response');
    }
    _hostGeneration = generation;
    _instanceId = instance;
    return result;
  }

  @override
  Future<ProductMap> call(
    String method, [
    ProductMap arguments = const {},
  ]) async {
    if (_disposed) throw const ProductFailure('disposed');
    final request = ++_request;
    final host = _hostGeneration;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(method, {
        ...arguments,
        'requestId': request,
        'hostGeneration': host,
      });
      if (_disposed) throw const ProductFailure('disposed');
      if (result == null || result['requestId'] != request) {
        throw const ProductFailure('invalid_response');
      }
      if (method == 'presentationContext') {
        final generation = result['hostGeneration'];
        final instance = result['instanceId'];
        if (generation is! int ||
            generation <= 0 ||
            instance is! String ||
            instance.isEmpty) {
          throw const ProductFailure('invalid_response');
        }
        if (generation < _hostGeneration) {
          throw const ProductFailure('stale_response');
        }
        _hostGeneration = generation;
        _instanceId = instance;
      } else if (method != 'bootstrap' &&
          (host != _hostGeneration ||
              result['hostGeneration'] != host ||
              result['instanceId'] != _instanceId)) {
        throw const ProductFailure('stale_response');
      }
      return Map.unmodifiable(result);
    } on PlatformException catch (error) {
      // Never expose a provider's paths, stack traces or arbitrary message.
      throw ProductFailure(error.code);
    } on MissingPluginException {
      throw const ProductFailure('service_unavailable');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_events.close());
  }
}
