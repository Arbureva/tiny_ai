class TinyAIConfig {
  static TinyAIConfig? _instance;

  String? _baseUrl;
  String? _apiKey;
  String? _model;
  Duration _timeout = Duration(seconds: 30);
  bool _enableLogging = false;
  final Map<String, String> _headers = {};

  TinyAIConfig._internal();

  static TinyAIConfig get instance {
    _instance ??= TinyAIConfig._internal();
    return _instance!;
  }

  // Getters
  String? get baseUrl => _baseUrl;
  String? get apiKey => _apiKey;
  String? get model => _model;
  Duration get timeout => _timeout;
  bool get enableLogging => _enableLogging;
  Map<String, String> get headers => Map.unmodifiable(_headers);

  // Setters
  TinyAIConfig setBaseUrl(String url) {
    _baseUrl = url;
    return this;
  }

  TinyAIConfig setApiKey(String key) {
    _apiKey = key;
    return this;
  }

  TinyAIConfig setModel(String model) {
    _model = model;
    return this;
  }

  TinyAIConfig setTimeout(Duration timeout) {
    _timeout = timeout;
    return this;
  }

  TinyAIConfig setLogging(bool enable) {
    _enableLogging = enable;
    return this;
  }

  TinyAIConfig addHeader(String key, String value) {
    _headers[key] = value;
    return this;
  }

  TinyAIConfig addHeaders(Map<String, String> headers) {
    _headers.addAll(headers);
    return this;
  }

  TinyAIConfig clearHeaders() {
    _headers.clear();
    return this;
  }
}
