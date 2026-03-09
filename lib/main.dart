import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:emojis/emojis.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final arabicTextTheme = GoogleFonts.notoSansArabicTextTheme();

    return MaterialApp(
      title: 'Jareed Stories',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        textTheme: arabicTextTheme,
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamilyFallback: [
                'Noto Sans Arabic',
                'Noto Color Emoji',
                'Apple Color Emoji',
                'Segoe UI Emoji',
              ],
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const CampaignsScreen(),
    );
  }
}

class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    required this.date,
    required this.createdLabel,
    required this.htmlContent,
    this.imageUrl,
    this.archiveUrl,
  });

  final String id;
  final String title;
  final DateTime date;
  final String createdLabel;
  final String htmlContent;
  final String? imageUrl;
  final String? archiveUrl;
}

class CampaignPageResult {
  const CampaignPageResult({
    required this.items,
    required this.nextPageUrl,
  });

  final List<Campaign> items;
  final String? nextPageUrl;
}

class CampaignContentResult {
  const CampaignContentResult({
    required this.html,
    required this.fallbackText,
  });

  final String html;
  final String fallbackText;
}

class MailchimpApiClient {
  MailchimpApiClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  static const _requestTimeout = Duration(seconds: 20);
  static const _storiesBaseUrl =
      'https://cad.jareed.net/api/v1/stories/?format=json&page_size=30';

  Future<CampaignPageResult> fetchCampaignPage({String? pageUrl}) async {
    final storiesUri = Uri.parse(pageUrl ?? _storiesBaseUrl);

    final response = await _httpClient
        .get(
          storiesUri,
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw TimeoutException(
            'Timed out fetching stories page: $storiesUri',
          ),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to fetch stories (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final stories = (decoded['results'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final nextPageUrl = decoded['next'] as String?;
    final items = <Campaign>[];

    for (final raw in stories) {
      final campaign = _storyToCampaign(raw);
      if (campaign != null) {
        items.add(campaign);
      }
    }

    return CampaignPageResult(items: items, nextPageUrl: nextPageUrl);
  }

  Campaign? _storyToCampaign(Map<String, dynamic> raw) {
    final id = raw['id']?.toString();
    if (id == null) {
      return null;
    }

    final title = raw['title'] as String?;
    final created = (raw['created'] as String?)?.trim();
    final body = raw['body'] as String?;
    final imageUrl = (raw['image'] as String?)?.trim();
    final parsedDate =
        DateTime.tryParse(created ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return Campaign(
      id: id,
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'Untitled story',
      date: parsedDate,
      createdLabel: created?.isNotEmpty == true ? created! : 'Unknown date',
      htmlContent: body?.trim() ?? '',
      imageUrl: imageUrl?.isNotEmpty == true ? imageUrl : null,
      archiveUrl: null,
    );
  }

  Future<CampaignContentResult> fetchCampaignHtml(String campaignId) async {
    final storyUri = Uri.parse(
      'https://cad.jareed.net/api/v1/stories/$campaignId/?format=json',
    );

    final response = await _httpClient
        .get(
          storyUri,
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw TimeoutException(
            'Timed out fetching story HTML for $campaignId.',
          ),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to fetch story HTML for $campaignId (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final html = decoded['body'] as String?;
    if (html != null && html.trim().isNotEmpty) {
      return CampaignContentResult(
        html: _wrapLtrHtml(html),
        fallbackText: _htmlToPlainText(html),
      );
    }

    final fallbackText =
        (decoded['body_text'] as String?) ?? (decoded['excerpt'] as String?) ?? '';
    if (fallbackText.trim().isNotEmpty) {
      return CampaignContentResult(
        html: _wrapLtrHtml('<pre>${_escapeHtml(fallbackText)}</pre>'),
        fallbackText: fallbackText,
      );
    }

    throw Exception('Story $campaignId returned empty content.');
  }

  CampaignContentResult contentFromCampaign(Campaign campaign) {
    final html = campaign.htmlContent.trim();
    if (html.isNotEmpty) {
      return CampaignContentResult(
        html: _wrapLtrHtml(html),
        fallbackText: _htmlToPlainText(html),
      );
    }

    return const CampaignContentResult(
      html: '<p>No HTML content.</p>',
      fallbackText: 'No campaign content available.',
    );
  }

  String _htmlToPlainText(String html) {
    var text = html
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.length > 5000) {
      text = '${text.substring(0, 5000)}...';
    }
    return text;
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _wrapLtrHtml(String html) {
    return '<div dir="rtl" style="text-align:right;">$html</div>';
  }
}

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  late final MailchimpApiClient _client = _createClient();
  final List<Campaign> _campaigns = <Campaign>[];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialCampaigns();
  }

  MailchimpApiClient _createClient() {
    return MailchimpApiClient();
  }

  Future<void> _loadInitialCampaigns() async {
    setState(() {
      _isInitialLoading = true;
      _errorMessage = null;
    });

    try {
      final page = await _client.fetchCampaignPage();
      if (!mounted) {
        return;
      }
      setState(() {
        _campaigns
          ..clear()
          ..addAll(page.items);
        _nextPageUrl = page.nextPageUrl;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreCampaigns() async {
    if (_isLoadingMore || _nextPageUrl == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final page = await _client.fetchCampaignPage(pageUrl: _nextPageUrl);
      if (!mounted) {
        return;
      }
      setState(() {
        _campaigns.addAll(page.items);
        _nextPageUrl = page.nextPageUrl;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Jareed Stories ${Emojis.sparkles}'),
      ),
      body:
          _isInitialLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null && _campaigns.isEmpty
              ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: $_errorMessage',
                  style: const TextStyle(color: Colors.red),
                ),
              )
              : _campaigns.isEmpty
              ? const Center(child: Text('No stories found.'))
              : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _campaigns.length,
                      separatorBuilder:
                          (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final campaign = _campaigns[index];
                        final dateLabel = campaign.createdLabel;

                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.all(14),
                          ),
                          onPressed: () {
                            final contentFuture =
                                campaign.htmlContent.trim().isNotEmpty
                                    ? Future.value(
                                      _client.contentFromCampaign(campaign),
                                    )
                                    : _client.fetchCampaignHtml(campaign.id);

                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => CampaignDetailScreen(
                                      campaign: campaign,
                                      contentFuture: contentFuture,
                                    ),
                              ),
                            );
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      campaign.title,
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.left,
                                      style:
                                          Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${Emojis.calendar} $dateLabel',
                                      textDirection: TextDirection.ltr,
                                      textAlign: TextAlign.left,
                                    ),
                                  ],
                                ),
                              ),
                              if (campaign.imageUrl != null) ...[
                                const SizedBox(width: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    campaign.imageUrl!,
                                    width: 180,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const SizedBox.shrink(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Error: $_errorMessage',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (_nextPageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FilledButton(
                        onPressed: _isLoadingMore ? null : _loadMoreCampaigns,
                        child:
                            _isLoadingMore
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Text('Load more stories ${Emojis.downArrow}'),
                      ),
                    ),
                ],
              ),
    );
  }
}

class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({
    super.key,
    required this.campaign,
    required this.contentFuture,
  });

  final Campaign campaign;
  final Future<CampaignContentResult> contentFuture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          campaign.title,
          textDirection: TextDirection.rtl,
        ),
      ),
      body: FutureBuilder<CampaignContentResult>(
        future: contentFuture,
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

          final result = snapshot.data ??
              const CampaignContentResult(
                html: '<p>No HTML content.</p>',
                fallbackText: 'No campaign content available.',
              );
          final supportsInAppWebView =
              Theme.of(context).platform == TargetPlatform.android ||
              Theme.of(context).platform == TargetPlatform.iOS;

          if (supportsInAppWebView) {
            return _CampaignWebView(html: result.html);
          }

          // Desktop fallback while mobile uses full WebView rendering.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Html(
                  data: result.html,
                  style: {
                    '*': Style(
                      direction: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      fontFamily: GoogleFonts.notoSansArabic().fontFamily,
                      color: Colors.black,
                      fontSize: FontSize(14),
                    ),
                  },
                ),
                if (result.fallbackText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Desktop fallback text',
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    result.fallbackText,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CampaignWebView extends StatefulWidget {
  const _CampaignWebView({required this.html});

  final String html;

  @override
  State<_CampaignWebView> createState() => _CampaignWebViewState();
}

class _CampaignWebViewState extends State<_CampaignWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}