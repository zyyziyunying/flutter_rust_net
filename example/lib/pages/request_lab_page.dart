import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_net/flutter_rust_net.dart';

import '../apis/example_app_config.dart';
import '../apis/request_lab_models.dart';
import '../example_section_card.dart';

class RequestLabPage extends StatefulWidget {
  final RequestLabPageConfig config;

  const RequestLabPage({super.key, required this.config});

  @override
  State<RequestLabPage> createState() => _RequestLabPageState();
}

class _RequestLabPageState extends State<RequestLabPage> {
  late RequestPreset _selectedPreset;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _urlController;
  late final TextEditingController _headersController;
  late final TextEditingController _queryController;
  late final TextEditingController _bodyController;
  late final Dio _dio;
  late final DioAdapter _dioAdapter;
  late final RustAdapter _rustAdapter;

  NetHttpMethod _method = NetHttpMethod.get;
  RequestRouteMode _routeMode = RequestRouteMode.auto;
  RequestBodyMode _bodyMode = RequestBodyMode.empty;
  bool _autoUseRust = false;
  bool _enableFallback = true;
  bool _expectLargeResponse = false;
  bool _sending = false;
  String _eventLog =
      'Load a preset or edit the request form, then send traffic through Dio or Rust.';
  RequestResult? _lastResult;

  List<RequestPreset> get _presets => widget.config.presets;

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.config.initialPreset;
    _baseUrlController = TextEditingController(
      text: _baseUrlFor(_selectedPreset),
    );
    _urlController = TextEditingController(text: _selectedPreset.url);
    _headersController = TextEditingController(
      text: _selectedPreset.headersText,
    );
    _queryController = TextEditingController(text: _selectedPreset.queryText);
    _bodyController = TextEditingController(text: _selectedPreset.bodyText);
    _method = _selectedPreset.method;
    _routeMode = _selectedPreset.routeMode;
    _bodyMode = _selectedPreset.bodyMode;
    _autoUseRust = _selectedPreset.autoUseRust;
    _enableFallback = _selectedPreset.enableFallback;
    _expectLargeResponse = _selectedPreset.expectLargeResponse;
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    _dioAdapter = DioAdapter(client: _dio);
    _rustAdapter = RustAdapter();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _urlController.dispose();
    _headersController.dispose();
    _queryController.dispose();
    _bodyController.dispose();
    _dio.close(force: true);
    if (_rustAdapter.isReady) {
      unawaited(_rustAdapter.shutdownEngine());
    }
    super.dispose();
  }

  String _baseUrlFor(RequestPreset preset) {
    return preset.resolveBaseUrl(widget.config.defaultBaseUrl);
  }

  void _applyPreset(RequestPreset preset) {
    setState(() {
      _selectedPreset = preset;
      _method = preset.method;
      _routeMode = preset.routeMode;
      _bodyMode = preset.bodyMode;
      _autoUseRust = preset.autoUseRust;
      _enableFallback = preset.enableFallback;
      _expectLargeResponse = preset.expectLargeResponse;
      _baseUrlController.text = _baseUrlFor(preset);
      _urlController.text = preset.url;
      _headersController.text = preset.headersText;
      _queryController.text = preset.queryText;
      _bodyController.text = preset.bodyText;
    });
    _appendLog('[request] preset loaded: ${preset.label}');
  }

  Future<void> _sendRequest() async {
    if (_sending) {
      return;
    }

    final baseUrl = _baseUrlController.text.trim();
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _appendLog('[request] url/path cannot be empty.');
      setState(() {
        _lastResult = const RequestResult.error(
          message: 'Request URL or path cannot be empty.',
        );
      });
      return;
    }

    setState(() {
      _sending = true;
      _lastResult = null;
    });

    try {
      final headers = _parseHeaders(_headersController.text);
      final queryParameters = _parseQueryParameters(_queryController.text);
      final body = _parseBody(_bodyController.text);
      final forceChannel = _routeMode.forceChannel;
      final enableRustChannel = _autoUseRust || forceChannel == NetChannel.rust;

      if (enableRustChannel && !_rustAdapter.isReady) {
        _appendLog('[request] initializing Rust engine...');
        await _rustAdapter.initializeEngine();
      }

      final client = BytesFirstNetworkClient.standard(
        baseUrl: baseUrl,
        dioAdapter: _dioAdapter,
        rustAdapter: _rustAdapter,
        featureFlag: NetFeatureFlag(
          enableRustChannel: enableRustChannel,
          enableFallback: _enableFallback,
        ),
      );
      final request = NetRequest(
        method: _method.wireName,
        url: url,
        headers: headers,
        queryParameters: queryParameters,
        body: body,
        expectLargeResponse: _expectLargeResponse,
        forceChannel: forceChannel,
      );

      _appendLog(
        '[request] ${_method.wireName} ${_previewResolvedUrl(baseUrl, url)} '
        'route=${_routeMode.label}',
      );

      final decoded = await client.requestDecoded<String>(
        request,
        decoder: const Utf8BodyDecoder(allowMalformed: true),
      );
      final response = decoded.rawResponse;
      final result = RequestResult.success(
        statusCode: response.statusCode,
        requestId: response.requestId,
        channel: response.channel,
        routeReason: response.routeReason ?? '-',
        fromFallback: response.fromFallback,
        fallbackReason: response.fallbackReason,
        costMs: response.costMs,
        materializedBytes: decoded.metrics.materializedBytes,
        bridgeBytes: response.bridgeBytes,
        headers: response.headers,
        bodyText: _prettifyJsonText(decoded.decoded),
      );

      _appendLog(
        '[request] status=${response.statusCode}, '
        'channel=${response.channel.name}, '
        'cost=${response.costMs}ms',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResult = result;
      });
    } on FormatException catch (error) {
      final message = error.message;
      _appendLog('[request] invalid input: $message');
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResult = RequestResult.error(message: message);
      });
    } on NetException catch (error) {
      final message = _formatNetException(error);
      _appendLog('[request] failed: $message');
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResult = RequestResult.error(message: message);
      });
    } catch (error) {
      final message = '$error';
      _appendLog('[request] failed: $message');
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResult = RequestResult.error(message: message);
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Map<String, String> _parseHeaders(String input) {
    final headers = <String, String>{};
    for (final line in const LineSplitter().convert(input)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final separatorIndex = trimmed.indexOf(':');
      if (separatorIndex <= 0) {
        throw FormatException('Header lines must use "name: value": $trimmed');
      }
      final key = trimmed.substring(0, separatorIndex).trim();
      final value = trimmed.substring(separatorIndex + 1).trim();
      if (key.isEmpty) {
        throw FormatException('Header name cannot be empty: $trimmed');
      }
      headers[key] = value;
    }
    return headers;
  }

  Map<String, dynamic> _parseQueryParameters(String input) {
    final queryParameters = <String, dynamic>{};
    for (final line in const LineSplitter().convert(input)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final separatorIndex = trimmed.indexOf('=');
      if (separatorIndex < 0) {
        throw FormatException('Query lines must use "key=value": $trimmed');
      }
      final key = trimmed.substring(0, separatorIndex).trim();
      final value = trimmed.substring(separatorIndex + 1).trim();
      if (key.isEmpty) {
        throw FormatException('Query key cannot be empty: $trimmed');
      }
      queryParameters[key] = value;
    }
    return queryParameters;
  }

  Object? _parseBody(String input) {
    switch (_bodyMode) {
      case RequestBodyMode.empty:
        return null;
      case RequestBodyMode.json:
        final trimmed = input.trim();
        if (trimmed.isEmpty) {
          return null;
        }
        return jsonDecode(trimmed);
      case RequestBodyMode.text:
        return input;
    }
  }

  void _appendLog(String message) {
    debugPrint(message);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_eventLog.isEmpty) {
        _eventLog = message;
      } else {
        _eventLog = '$_eventLog\n$message';
      }
    });
  }

  String _previewResolvedUrl(String baseUrl, String url) {
    final trimmedBaseUrl = baseUrl.trim();
    if (trimmedBaseUrl.isEmpty ||
        url.startsWith('http://') ||
        url.startsWith('https://')) {
      return url;
    }
    final left = trimmedBaseUrl.endsWith('/')
        ? trimmedBaseUrl.substring(0, trimmedBaseUrl.length - 1)
        : trimmedBaseUrl;
    final right = url.startsWith('/') ? url.substring(1) : url;
    return '$left/$right';
  }

  String _prettifyJsonText(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '[empty body]';
    }
    try {
      final decoded = jsonDecode(trimmed);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return input;
    }
  }

  String _formatNetException(NetException error) {
    final buffer = StringBuffer()
      ..write('[${error.channel.name}] ${error.code.name}: ${error.message}');
    if (error.statusCode != null) {
      buffer.write(' (status=${error.statusCode})');
    }
    if (error.requestId != null && error.requestId!.isNotEmpty) {
      buffer.write(' requestId=${error.requestId}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ExampleSectionCard(
          title: 'Quick Presets',
          subtitle:
              'Load a template, then change URL, headers, or body before sending.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets
                .map(
                  (preset) => FilterChip(
                    label: Text(preset.label),
                    selected: identical(preset, _selectedPreset),
                    onSelected: _sending ? null : (_) => _applyPreset(preset),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        ExampleSectionCard(
          title: 'Request Builder',
          subtitle:
              'Auto routing follows the Rust toggle below. Force Dio/Rust overrides the routing policy per request.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'HTTP Method',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<NetHttpMethod>(
                    isExpanded: true,
                    value: _method,
                    items: NetHttpMethod.values
                        .map(
                          (method) => DropdownMenuItem<NetHttpMethod>(
                            value: method,
                            child: Text(method.wireName),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _sending
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _method = value;
                            });
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Route Mode',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<RequestRouteMode>(
                    isExpanded: true,
                    value: _routeMode,
                    items: RequestRouteMode.values
                        .map(
                          (mode) => DropdownMenuItem<RequestRouteMode>(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _sending
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _routeMode = value;
                            });
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                enabled: !_sending,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://example.com/api',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                enabled: !_sending,
                decoration: const InputDecoration(
                  labelText: 'Request URL or Path',
                  hintText: '/feed or https://example.com/feed',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _headersController,
                enabled: !_sending,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Headers',
                  hintText:
                      'content-type: application/json\nauthorization: Bearer xxx',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _queryController,
                enabled: !_sending,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Query Parameters',
                  hintText: 'page=1\nsize=20',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Body Mode',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<RequestBodyMode>(
                    isExpanded: true,
                    value: _bodyMode,
                    items: RequestBodyMode.values
                        .map(
                          (mode) => DropdownMenuItem<RequestBodyMode>(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _sending
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _bodyMode = value;
                            });
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                enabled: !_sending && _bodyMode != RequestBodyMode.empty,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  hintText: '{\n  "hello": "world"\n}',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto route to Rust'),
                subtitle: const Text(
                  'Only used when route mode stays on Auto.',
                ),
                value: _autoUseRust,
                onChanged: _sending
                    ? null
                    : (value) {
                        setState(() {
                          _autoUseRust = value;
                        });
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable fallback'),
                subtitle: const Text(
                  'Allows Rust failures to fall back to Dio when eligible.',
                ),
                value: _enableFallback,
                onChanged: _sending
                    ? null
                    : (value) {
                        setState(() {
                          _enableFallback = value;
                        });
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expect large response'),
                subtitle: const Text(
                  'Rust transport hint for file-backed large bodies.',
                ),
                value: _expectLargeResponse,
                onChanged: _sending
                    ? null
                    : (value) {
                        setState(() {
                          _expectLargeResponse = value;
                        });
                      },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _sending ? null : _sendRequest,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(_sending ? 'Sending...' : 'Send request'),
                  ),
                  OutlinedButton(
                    onPressed: _sending
                        ? null
                        : () {
                            setState(() {
                              _lastResult = null;
                            });
                          },
                    child: const Text('Clear response'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ExampleSectionCard(
          title: 'Response',
          subtitle:
              'Shows route metadata, response headers, and the decoded text body.',
          child: result == null
              ? const Text('No response yet.')
              : result.success
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(result.summaryLines),
                    const SizedBox(height: 12),
                    SelectableText(result.headersText),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 120),
                      child: SelectableText(result.bodyText),
                    ),
                  ],
                )
              : Text(
                  result.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
        ),
        ExampleSectionCard(
          title: 'Event Log',
          subtitle: 'Mirrors each request attempt to debugPrint.',
          child: SizedBox(
            height: 220,
            child: SingleChildScrollView(
              child: SelectableText(
                _eventLog.isEmpty ? '[request] log is empty' : _eventLog,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
