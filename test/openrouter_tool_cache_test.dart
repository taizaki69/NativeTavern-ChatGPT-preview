import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/domain/models/built_in_tool.dart';
import 'package:native_tavern/domain/models/tool_calling.dart';
import 'package:native_tavern/domain/models/tool_generation.dart';
import 'package:native_tavern/domain/services/tool_calling/tool_execution_audit_service.dart';
import 'package:native_tavern/domain/repositories/mcp_repository.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/mcp/mcp_client_manager.dart';
import 'package:native_tavern/domain/services/tool_calling/built_in_tool_service.dart';
import 'package:native_tavern/domain/services/tool_calling/tool_generation_loop.dart';

void main() {
  test(
      'OpenRouter tool rounds cache the same instructions and total actual usage',
      () async {
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      requests.add(Map<String, dynamic>.from(body));
      expect(request.uri.path, '/v1/chat/completions');
      request.response.headers.contentType = ContentType.json;
      final first = requests.length == 1;
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': first
                ? {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'synthetic-call',
                        'type': 'function',
                        'function': {
                          'name': 'roll_dice',
                          'arguments': '{"count":1,"sides":6}',
                        },
                      }
                    ],
                  }
                : {'role': 'assistant', 'content': 'The die has been rolled.'},
            'finish_reason': first ? 'tool_calls' : 'stop',
          }
        ],
        'usage': {
          'prompt_tokens_details': {
            'cached_tokens': first ? 1000 : 1100,
            'cache_write_tokens': first ? 100 : 0,
          },
          'private_payload': 'must-not-persist',
        },
      }));
      await request.response.close();
    });
    final manager = McpClientManager(
      settingsRepository: MemoryMcpSettingsRepository(),
      credentialRepository: MemoryMcpCredentialRepository(),
      activityRepository: MemoryMcpActivityRepository(),
      toolAuditRepository: MemoryToolExecutionAuditRepository(),
    );
    addTearDown(manager.close);
    final service = LLMService();
    final loop = ToolGenerationLoop(
      builtInTools: BuiltInToolExecutionService(
        registry: BuiltInToolRegistry([
          RollDiceToolExecutor(random: math.Random(7)),
        ]),
      ),
      mcpManager: manager,
      transport: service.generateToolTurn,
    );
    final result = await loop.run(
      chatId: 'synthetic-cache-tool-chat',
      messages: const [
        {
          'role': 'system',
          'content': 'Stable synthetic character and tool instructions.'
        },
        {'role': 'user', 'content': 'Roll one die.'},
      ],
      config: LLMConfig(
        provider: LLMProvider.openRouter,
        model: 'anthropic/claude-sonnet-5.5',
        apiKey: 'synthetic-key',
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        streamEnabled: false,
      ),
      settings: ToolCallingSettings(
        enabled: true,
        enabledBuiltInTools: const [RollDiceToolExecutor.toolName],
      ),
      capabilities: ToolCapabilitySnapshot.none,
      cancellationToken: ToolCancellationController().token,
    );
    expect(result!.content, 'The die has been rolled.');
    expect(result.toolRounds, 1);
    expect(result.callCount, 1);
    expect(result.cacheUsage!.cachedTokens, 2100);
    expect(result.cacheUsage!.cacheWriteTokens, 100);
    expect(requests, hasLength(2));
    expect(requests.first['tools'], requests.last['tools']);
    final firstMessages = requests.first['messages'] as List;
    final secondMessages = requests.last['messages'] as List;
    expect(firstMessages.first, secondMessages.first);
    expect(firstMessages.first['content'], [
      {
        'type': 'text',
        'text': 'Stable synthetic character and tool instructions.',
        'cache_control': {'type': 'ephemeral'},
      }
    ]);
    expect(firstMessages[1]['content'], 'Roll one die.');
    expect(secondMessages[2]['tool_calls'][0]['id'], 'synthetic-call');
    expect(secondMessages.last['tool_call_id'], 'synthetic-call');
    expect(jsonEncode(result.cacheUsage!.toJson()),
        isNot(contains('private_payload')));
  });
}
