import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'javascript_channel.dart';
import 'javascript_message.dart';

const _kChannel = 'flutter_multiple_webview_plugin';

enum ConsoleMessageLevel { DEBUG, ERROR, LOG, TIP, WARNING }

///Public class representing a JavaScript console message from WebCore.
///This could be a issued by a call to one of the console logging functions (e.g. console.log('...')) or a JavaScript error on the page.
class ConsoleMessage {
  ConsoleMessage(
      {this.id = '1',
      this.message = '',
      this.messageLevel = ConsoleMessageLevel.LOG});

  factory ConsoleMessage.fromJson(Map<String, dynamic> json) {
    return ConsoleMessage(
      id: json['id'],
      message: json['message'],
      messageLevel: ConsoleMessageLevel.values
          .firstWhere((level) => level.name == json['messageLevel']),
    );
  }

  final String id;
  final String message;
  final ConsoleMessageLevel messageLevel;
}

class IdValueDouble {
  IdValueDouble(this.id, this.value);

  factory IdValueDouble.fromJson(Map<String, dynamic> json) {
    return IdValueDouble(json['id'], json['value']);
  }
  final String id;
  final double value;
}

class IdValueString {
  IdValueString(this.id, this.value);

  factory IdValueString.fromJson(Map<String, dynamic> json) {
    return IdValueString(json['id'], json['value']);
  }
  final String id;
  final String value;
}

// TODO: more general state for iOS/android
enum WebViewState { shouldStart, startLoad, finishLoad, abortLoad }

/// Singleton class that communicate with a Webview Instance
class FlutterMultipleWebviewPlugin {
  factory FlutterMultipleWebviewPlugin() {
    if (_instance == null) {
      const MethodChannel methodChannel = const MethodChannel(_kChannel);
      _instance = FlutterMultipleWebviewPlugin.private(methodChannel);
    }
    return _instance!;
  }

  @visibleForTesting
  FlutterMultipleWebviewPlugin.private(this._channel) {
    _channel.setMethodCallHandler(_handleMessages);
  }

  static FlutterMultipleWebviewPlugin? _instance;

  final MethodChannel _channel;

  final _onBack = StreamController<Null>.broadcast();
  final _onDestroy = StreamController<Null>.broadcast();
  final _onUrlChanged = StreamController<IdValueString>.broadcast();
  final _onStateChanged = StreamController<WebViewStateChanged>.broadcast();
  final _onScrollXChanged = StreamController<IdValueDouble>.broadcast();
  final _onScrollYChanged = StreamController<IdValueDouble>.broadcast();
  final _onProgressChanged = new StreamController<IdValueDouble>.broadcast();
  final _onConsoleMessage = new StreamController<ConsoleMessage>.broadcast();
  final _onHttpError = StreamController<WebViewHttpError>.broadcast();
  final _onPostMessage = StreamController<JavascriptMessage>.broadcast();

  final Map<String, JavascriptChannel> _javascriptChannels =
      <String, JavascriptChannel>{};

  Future<Null> _handleMessages(MethodCall call) async {
    switch (call.method) {
      case 'onBack':
        _onBack.add(null);
        break;
      case 'onDestroy':
        _onDestroy.add(null);
        break;
      case 'onUrlChanged':
        _onUrlChanged
            .add(IdValueString(call.arguments['id'], call.arguments['url']));
        break;
      case 'onScrollXChanged':
        _onScrollXChanged.add(
            IdValueDouble(call.arguments['id'], call.arguments['xDirection']));
        break;
      case 'onScrollYChanged':
        _onScrollYChanged.add(
            IdValueDouble(call.arguments['id'], call.arguments['yDirection']));
        break;
      case 'onProgressChanged':
        _onProgressChanged.add(
            IdValueDouble(call.arguments['id'], call.arguments['progress']));
        break;
      case 'onConsoleMessage':
        _onConsoleMessage.add(
            ConsoleMessage.fromJson(Map<String, dynamic>.from(call.arguments)));
        break;
      case 'onState':
        _onStateChanged.add(
          WebViewStateChanged.fromMap(
            Map<String, dynamic>.from(call.arguments),
          ),
        );
        break;
      case 'onHttpError':
        _onHttpError.add(WebViewHttpError(call.arguments['id'],
            call.arguments['code'], call.arguments['url']));
        break;
      case 'javascriptChannelMessage':
        _handleJavascriptChannelMessage(
            call.arguments['channel'], call.arguments['message']);
        break;
    }
  }

  /// Listening the OnDestroy LifeCycle Event for Android
  Stream<Null> get onDestroy => _onDestroy.stream;

  /// Listening the back key press Event for Android
  Stream<Null> get onBack => _onBack.stream;

  /// Listening url changed
  Stream<IdValueString> get onUrlChanged => _onUrlChanged.stream;

  /// Listening the onState Event for iOS WebView and Android
  /// content is Map for type: {shouldStart(iOS)|startLoad|finishLoad}
  /// more detail than other events
  Stream<WebViewStateChanged> get onStateChanged => _onStateChanged.stream;

  /// Listening web view loading progress estimation, value between 0.0 and 1.0
  Stream<IdValueDouble> get onProgressChanged => _onProgressChanged.stream;

  /// Listening web view console message
  Stream<ConsoleMessage> get onConsoleMessage => _onConsoleMessage.stream;

  /// Listening web view y position scroll change
  Stream<IdValueDouble> get onScrollYChanged => _onScrollYChanged.stream;

  /// Listening web view x position scroll change
  Stream<IdValueDouble> get onScrollXChanged => _onScrollXChanged.stream;

  Stream<WebViewHttpError> get onHttpError => _onHttpError.stream;

  /// Start the Webview with [url]
  /// - [id] WebView id (multiple webviews has to have different ids)
  /// - [headers] specify additional HTTP headers
  /// - [javascriptChannels] every instance of webview has to have different javascript channel
  /// - [withJavascript] enable Javascript or not for the Webview
  /// - [clearCache] clear the cache of the Webview
  /// - [clearCookies] clear all cookies of the Webview
  /// - [hidden] not show
  /// - [rect]: show in rect, fullscreen if null
  /// - [enableAppScheme]: false will enable all schemes, true only for httt/https/about
  ///     android: Not implemented yet
  /// - [userAgent]: set the User-Agent of WebView
  /// - [withZoom]: enable zoom on webview
  /// - [withLocalStorage] enable localStorage API on Webview
  ///     Currently Android only.
  ///     It is always enabled in UIWebView of iOS and  can not be disabled.
  /// - [withLocalUrl]: allow url as a local path
  ///     Allow local files on iOs > 9.0
  /// - [localUrlScope]: allowed folder for local paths
  ///     iOS only.
  ///     If null and withLocalUrl is true, then it will use the url as the scope,
  ///     allowing only itself to be read.
  /// - [scrollBar]: enable or disable scrollbar
  /// - [supportMultipleWindows] enable multiple windows support in Android
  /// - [invalidUrlRegex] is the regular expression of URLs that web view shouldn't load.
  /// For example, when webview is redirected to a specific URL, you want to intercept
  /// this process by stopping loading this URL and replacing webview by another screen.
  ///   Android only settings:
  /// - [displayZoomControls]: display zoom controls on webview
  /// - [withOverviewMode]: enable overview mode for Android webview ( setLoadWithOverviewMode )
  /// - [useWideViewPort]: use wide viewport for Android webview ( setUseWideViewPort )
  /// - [ignoreSSLErrors]: use to bypass Android/iOS SSL checks e.g. for self-signed certificates
  /// - [androidOverScrollNever]: it's only for Android, use it for setOverScrollMode to OVER_SCROLL_NEVER
  /// - [transparentBackground]: make webview background to be transparent, it's enabled by default
  /// - [iosContentInsetAdjustmentBehaviorNever]: it's only for iOS, set UIScrollViewContentInsetAdjustmentBehavior to UIScrollViewContentInsetAdjustmentNever - Do not adjust the scroll view insets.
  /// - [disableSystemFontSize]: it's only for Android, do not allow Webview reflect system font size on web, it's enabled by default
  Future<void> launch(
    String url, {
    String id = '1',
    Map<String, String>? headers,
    Set<JavascriptChannel> javascriptChannels = const <JavascriptChannel>{},
    bool withJavascript = true,
    bool clearCache = false,
    bool clearCookies = false,
    bool mediaPlaybackRequiresUserGesture = true,
    bool hidden = false,
    bool enableAppScheme = true,
    Rect? rect,
    String? userAgent,
    bool withZoom = false,
    bool displayZoomControls = false,
    bool withLocalStorage = true,
    bool withLocalUrl = false,
    String? localUrlScope,
    bool withOverviewMode = false,
    bool scrollBar = true,
    bool supportMultipleWindows = false,
    bool appCacheEnabled = false,
    bool allowFileURLs = false,
    bool useWideViewPort = false,
    String? invalidUrlRegex,
    bool geolocationEnabled = false,
    bool debuggingEnabled = false,
    bool ignoreSSLErrors = false,
    bool? allowsInlineMediaPlayback,
    bool androidOverScrollNever = false,
    bool transparentBackground = true,
    bool iosContentInsetAdjustmentBehaviorNever = false,
    bool disableSystemFontSize = true,
  }) async {
    final args = <String, dynamic>{
      'url': url,
      'withJavascript': withJavascript,
      'clearCache': clearCache,
      'hidden': hidden,
      'clearCookies': clearCookies,
      'mediaPlaybackRequiresUserGesture': mediaPlaybackRequiresUserGesture,
      'enableAppScheme': enableAppScheme,
      'userAgent': userAgent,
      'withZoom': withZoom,
      'displayZoomControls': displayZoomControls,
      'withLocalStorage': withLocalStorage,
      'withLocalUrl': withLocalUrl,
      'localUrlScope': localUrlScope,
      'scrollBar': scrollBar,
      'supportMultipleWindows': supportMultipleWindows,
      'appCacheEnabled': appCacheEnabled,
      'allowFileURLs': allowFileURLs,
      'useWideViewPort': useWideViewPort,
      'invalidUrlRegex': invalidUrlRegex,
      'geolocationEnabled': geolocationEnabled,
      'withOverviewMode': withOverviewMode,
      'debuggingEnabled': debuggingEnabled,
      'ignoreSSLErrors': ignoreSSLErrors,
      'allowsInlineMediaPlayback': allowsInlineMediaPlayback,
      'overScrollNever': androidOverScrollNever,
      'transparentBackground': transparentBackground,
      'contentInsetAdjustmentBehaviorNever':
          iosContentInsetAdjustmentBehaviorNever,
      'disableSystemFontSize': disableSystemFontSize,
    };

    if (headers != null) {
      args['headers'] = headers;
    }

    _assertJavascriptChannelNamesAreUnique(javascriptChannels);

    javascriptChannels.forEach((channel) {
      _javascriptChannels[channel.name] = channel;
    });

    args['javascriptChannelNames'] =
        _extractJavascriptChannelNames(javascriptChannels).toList();
    args['id'] = id;

    if (rect != null) {
      args['rect'] = {
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }
    await _channel.invokeMethod('launch', args);
  }

  /// Execute Javascript inside webview
  Future<String?> evalJavascript(String code, {String id = '1'}) async {
    final res =
        await _channel.invokeMethod<String>('eval', {'code': code, 'id': id});
    return res;
  }

  /// Close the Webview
  /// Will trigger the [onDestroy] event
  Future<void> close({String id = '1', String channelName = 'handleJs'}) async {
    _javascriptChannels.remove(channelName);
    await _channel.invokeMethod('close', {'id': id});
  }

  /// Reloads the WebView.
  Future<void> reload({String id = '1'}) async =>
      await _channel.invokeMethod('reload', {'id': id});

  /// Navigates back on the Webview.
  Future<void> goBack({String id = '1'}) async =>
      await _channel.invokeMethod('back', {'id': id});

  /// Checks if webview can navigate back
  Future<bool> canGoBack({String id = '1'}) async =>
      await _channel.invokeMethod('canGoBack', {'id': id});

  /// Checks if webview can navigate back
  Future<bool> canGoForward({String id = '1'}) async =>
      await _channel.invokeMethod('canGoForward', {'id': id});

  /// Navigates forward on the Webview.
  Future<void> goForward({String id = '1'}) async =>
      await _channel.invokeMethod('forward', {'id': id});

  // Hides the webview
  Future<void> hide({String id = '1'}) async =>
      await _channel.invokeMethod('hide', {'id': id});

  // Shows the webview
  Future<void> show({String id = '1'}) async =>
      await _channel.invokeMethod('show', {'id': id});

  // Clears browser cache
  Future<void> clearCache({String id = '1'}) async =>
      await _channel.invokeMethod('cleanCache', {'id': id});

  // Reload webview with a url
  Future<void> reloadUrl(String url,
      {Map<String, String>? headers, String id = '1'}) async {
    final args = <String, dynamic>{'url': url, 'id': id};
    if (headers != null) {
      args['headers'] = headers;
    }
    await _channel.invokeMethod('reloadUrl', args);
  }

  // Check if webview with specific ID (default '1') is alive
  Future<bool> isWebViewAlive({String id = '1'}) async {
    return await _channel.invokeMethod('isWebViewAlive', {'id': id});
  }

  // Clean cookies on WebView
  Future<void> cleanCookies({String id = '1'}) async {
    // one liner to clear javascript cookies
    await evalJavascript(
        'document.cookie.split(";").forEach(function(c) { document.cookie = c.replace(/^ +/, "").replace(/=.*/, "=;expires=" + new Date().toUTCString() + ";path=/"); });');
    return await _channel.invokeMethod('cleanCookies', {'id': id});
  }

  // Stops current loading process
  Future<void> stopLoading({String id = '1'}) async =>
      await _channel.invokeMethod('stopLoading', {'id': id});

  /// Close all Streams
  void dispose() {
    _onDestroy.close();
    _onUrlChanged.close();
    _onStateChanged.close();
    _onProgressChanged.close();
    _onConsoleMessage.close();
    _onScrollXChanged.close();
    _onScrollYChanged.close();
    _onHttpError.close();
    _onPostMessage.close();
    _instance = null;
  }

  Future<Map<String, String>> getCookies({String id = '1'}) async {
    final cookiesString = await evalJavascript('document.cookie', id: id);
    final cookies = <String, String>{};

    if (cookiesString?.isNotEmpty == true) {
      cookiesString!.split(';').forEach((String cookie) {
        final split = cookie.split('=');
        cookies[split[0]] = split[1];
      });
    }

    return cookies;
  }

  /// resize webview
  Future<void> resize(Rect rect, {String id = '1'}) async {
    final Map<String, dynamic> args = {'id': id};
    args['rect'] = {
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
    await _channel.invokeMethod('resize', args);
  }

  Set<String> _extractJavascriptChannelNames(Set<JavascriptChannel> channels) {
    final Set<String> channelNames =
        channels.map((JavascriptChannel channel) => channel.name).toSet();
    return channelNames;
  }

  void _handleJavascriptChannelMessage(
      final String channelName, final String message) {
    if (_javascriptChannels.containsKey(channelName))
      _javascriptChannels[channelName]!
          .onMessageReceived(JavascriptMessage(message));
    else
      print('Channel "$channelName" is not exstis');
  }

  void _assertJavascriptChannelNamesAreUnique(
      final Set<JavascriptChannel>? channels) {
    if (channels == null || channels.isEmpty) {
      return;
    }

    assert(_extractJavascriptChannelNames(channels).length == channels.length);
  }
}

class WebViewStateChanged {
  WebViewStateChanged(this.id, this.type, this.url, this.navigationType);

  factory WebViewStateChanged.fromMap(Map<String, dynamic> map) {
    WebViewState t;
    switch (map['type']) {
      case 'shouldStart':
        t = WebViewState.shouldStart;
        break;
      case 'startLoad':
        t = WebViewState.startLoad;
        break;
      case 'finishLoad':
        t = WebViewState.finishLoad;
        break;
      case 'abortLoad':
        t = WebViewState.abortLoad;
        break;
      default:
        throw UnimplementedError(
            'WebViewState type "${map['type']}" is not supported.');
    }
    return WebViewStateChanged(map['id'], t, map['url'], map['navigationType']);
  }

  final String id;
  final WebViewState type;
  final String url;
  final int? navigationType;
}

class WebViewHttpError {
  WebViewHttpError(this.id, this.code, this.url);

  final String id;
  final String url;
  final String code;
}
