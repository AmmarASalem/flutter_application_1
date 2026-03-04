import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mailchimp Campaigns',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const CampaignsScreen(),
    );
  }
}

class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    required this.date,
    required this.htmlContent,
  });

  final String id;
  final String title;
  final DateTime date;
  final String htmlContent;
}

class MailchimpApiClient {
  MailchimpApiClient({
    required this.apiKey,
    required this.serverPrefix,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final String serverPrefix;
  final http.Client _httpClient;
  static const _requestTimeout = Duration(seconds: 20);

  static String inferServerPrefix(String apiKey) {
    final parts = apiKey.split('-');
    return parts.length > 1 ? parts.last : '';
  }

  Future<List<Campaign>> fetchAllCampaignMetadata() async {
    const pageSize = 100;
    var offset = 0;
    final items = <Campaign>[];

    while (true) {
      final uri = Uri.https(
        '$serverPrefix.api.mailchimp.com',
        '/3.0/campaigns',
        {
          'count': '$pageSize',
          'offset': '$offset',
          'fields':
              'campaigns.id,campaigns.settings.title,campaigns.send_time,campaigns.create_time,total_items',
        },
      );

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Authorization': _basicAuthHeader(apiKey),
              'Content-Type': 'application/json',
            },
          )
          .timeout(
            _requestTimeout,
            onTimeout: () => throw TimeoutException(
              'Timed out fetching campaigns page (offset $offset).',
            ),
          );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to fetch campaigns (${response.statusCode}): ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final campaigns = (decoded['campaigns'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      if (campaigns.isEmpty) {
        break;
      }

      for (final raw in campaigns) {
        final id = raw['id'] as String?;
        final settings = raw['settings'] as Map<String, dynamic>?;
        final title = settings?['title'] as String?;
        final sendTime = raw['send_time'] as String?;
        final createTime = raw['create_time'] as String?;
        if (id == null) {
          continue;
        }

        final parsedDate = DateTime.tryParse(sendTime ?? '') ??
            DateTime.tryParse(createTime ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);

        items.add(
          Campaign(
            id: id,
            title: title?.isNotEmpty == true ? title! : 'Untitled campaign',
            date: parsedDate,
            htmlContent: '',
          ),
        );
      }

      if (campaigns.length < pageSize) {
        break;
      }
      offset += campaigns.length;
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<String> fetchCampaignHtml(String campaignId) async {
    final uri = Uri.https(
      '$serverPrefix.api.mailchimp.com',
      '/3.0/campaigns/$campaignId/content',
      {'fields': 'html,plain_text'},
    );

    final response = await _httpClient
        .get(
          uri,
          headers: {
            'Authorization': _basicAuthHeader(apiKey),
            'Content-Type': 'application/json',
          },
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw TimeoutException(
            'Timed out fetching campaign HTML for $campaignId.',
          ),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to fetch campaign HTML for $campaignId (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final html = decoded['html'] as String?;
    if (html != null && html.trim().isNotEmpty) {
      return html;
    }

    final plainText = decoded['plain_text'] as String?;
    if (plainText != null && plainText.trim().isNotEmpty) {
      return '<pre>${_escapeHtml(plainText)}</pre>';
    }

    return '<p>No HTML content.</p>';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _basicAuthHeader(String apiKey) {
    final token = base64Encode(utf8.encode('anystring:$apiKey'));
    return 'Basic $token';
  }
}

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  static const _apiKey = String.fromEnvironment('MAILCHIMP_API_KEY');
  static const _explicitServerPrefix = String.fromEnvironment(
    'MAILCHIMP_SERVER_PREFIX',
  );

  late final MailchimpApiClient _client = _createClient();
  late final Future<List<Campaign>> _campaignsFuture = _loadCampaigns();

  MailchimpApiClient _createClient() {
    if (_apiKey.isEmpty) {
      throw Exception(
        'Missing MAILCHIMP_API_KEY. Run with --dart-define=MAILCHIMP_API_KEY=your_key-usX',
      );
    }

    final serverPrefix = _explicitServerPrefix.isNotEmpty
        ? _explicitServerPrefix
        : MailchimpApiClient.inferServerPrefix(_apiKey);

    if (serverPrefix.isEmpty) {
      throw Exception(
        'Could not infer server prefix from API key. Provide --dart-define=MAILCHIMP_SERVER_PREFIX=usX',
      );
    }

    return MailchimpApiClient(
      apiKey: _apiKey,
      serverPrefix: serverPrefix,
    );
  }

  Future<List<Campaign>> _loadCampaigns() async {
    return _client.fetchAllCampaignMetadata();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mailchimp Campaigns')),
      body: FutureBuilder<List<Campaign>>(
        future: _campaignsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final campaigns = snapshot.data ?? const [];
          if (campaigns.isEmpty) {
            return const Center(child: Text('No campaigns found.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: campaigns.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final campaign = campaigns[index];
              final dateLabel = _formatDate(campaign.date);

              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CampaignDetailScreen(
                        campaign: campaign,
                        client: _client,
                      ),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campaign.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(dateLabel),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }
}

class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({
    super.key,
    required this.campaign,
    required this.client,
  });

  final Campaign campaign;
  final MailchimpApiClient client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(campaign.title),
      ),
      body: FutureBuilder<String>(
        future: client.fetchCampaignHtml(campaign.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final html = snapshot.data ?? '<p>No HTML content.</p>';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Html(data: html),
          );
        },
      ),
    );
  }
}