/// Loopback HTTP server that serves DeWeb files to the in-app WebView.
///
/// The WebView cannot read the blockchain directly, so the browser screen
/// binds a 127.0.0.1-only HTTP server, resolves the current `.massa` site to
/// a smart-contract address, and serves datastore files with proper MIME
/// types. Relative links (`/style.css`, `./app.js`) therefore work naturally.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'deweb_service.dart';

/// Serves one on-chain site at a time on a random loopback port.
class LocalSiteServer {
  final DeWebService _deweb;

  HttpServer? _server;

  String? _currentSite;

  final Map<String, String> _customHeaders = {};

  /// Creates the server.
  LocalSiteServer({required DeWebService deweb}) : _deweb = deweb;

  /// Whether the server is running.
  bool get isRunning => _server != null;

  /// The bound port (null when not running).
  int? get port => _server?.port;

  /// Base URL for the served site, e.g. `http://127.0.0.1:41234`.
  String? get baseUrl => port == null ? null : 'http://127.0.0.1:$port';

  /// The site currently being served (SC address).
  String? get currentSite => _currentSite;

  /// Starts the server (idempotent).
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(
      _handle,
      onError: (Object e) {},
      cancelOnError: false,
    );
  }

  /// Stops the server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _currentSite = null;
  }

  /// Switches the site being served.
  void serveSite(String scAddress) {
    _currentSite = scAddress;
    _customHeaders.clear();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final site = _currentSite;
      if (site == null) {
        await _error(req, 503, 'no site selected');
        return;
      }
      var path = Uri.decodeComponent(req.uri.path);
      if (path.isEmpty || path == '/') path = 'index.html';
      while (path.startsWith('/')) {
        path = path.substring(1);
      }

      final file = await _deweb.fetchFile(site, path);
      await _respond(req, file.bytes, file.mimeType);
    } on DeWebException catch (e) {
      await _error(req, 404, e.message);
    } on Exception catch (e) {
      await _error(req, 500, e.toString());
    }
  }

  Future<void> _respond(
    HttpRequest req,
    Uint8List bytes,
    String mimeType,
  ) async {
    final res = req.response;
    res.headers.contentType = ContentType.parse(mimeType);
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Cache-Control', 'no-store');
    res.statusCode = 200;
    res.add(bytes);
    await res.close();
  }

  Future<void> _error(HttpRequest req, int code, String message) async {
    try {
      final res = req.response;
      res.headers.contentType = ContentType.html;
      res.statusCode = code;
      final safe = const HtmlEscape().convert(message);
      res.add(
        utf8.encode(
          '<html><body style="font-family:sans-serif;background:#0d1117;'
          'color:#e6edf3;padding:40px"><h2>$code</h2><p>$safe</p>'
          '<p style="color:#8b949e">Massa DeWeb · in-app browser</p></body></html>',
        ),
      );
      await res.close();
    } on Exception {
      // Socket already closed.
    }
  }
}
