#import "FlutterMultipleWebviewPlugin.h"
#import "WebviewJavaScriptChannelHandler.h"

static NSString *const CHANNEL_NAME = @"flutter_multiple_webview_plugin";

// UIWebViewDelegate
@interface FlutterMultipleWebviewPlugin() <WKNavigationDelegate, UIScrollViewDelegate, WKUIDelegate> {
    BOOL _enableAppScheme;
    BOOL _enableZoom;
    NSMutableDictionary<NSString *, id> *_invalidUrlRegex;
    NSMutableSet* _javaScriptChannelNames;
    NSNumber*  _ignoreSSLErrors;
}
@end

@implementation FlutterMultipleWebviewPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    channel = [FlutterMethodChannel
               methodChannelWithName:CHANNEL_NAME
               binaryMessenger:[registrar messenger]];

    UIViewController *viewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    FlutterMultipleWebviewPlugin* instance = [[FlutterMultipleWebviewPlugin alloc] initWithViewController:viewController];
    instance->_invalidUrlRegex = [NSMutableDictionary dictionary];
    
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];
    if (self) {
        self.viewController = viewController;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"launch" isEqualToString:call.method]) {
        WKWebView *w = [self getRightWebView:call.arguments[@"id"]];
        if (w == nil)
            [self initWebview:call withResult:result];
        else
            [self navigate:call];
        result(nil);
    } else if ([@"close" isEqualToString:call.method]) {
        [self closeWebView:call];
        result(nil);
    } else if ([@"eval" isEqualToString:call.method]) {
        [self evalJavascript:call completionHandler:^(NSString * response) {
            result(response);
        }];
    } else if ([@"resize" isEqualToString:call.method]) {
        [self resize:call];
        result(nil);
    } else if ([@"reloadUrl" isEqualToString:call.method]) {
        [self reloadUrl:call];
        result(nil);
    } else if ([@"show" isEqualToString:call.method]) {
        [self show:call];
        result(nil);
    } else if ([@"hide" isEqualToString:call.method]) {
        [self hide:call];
        result(nil);
    } else if ([@"stopLoading" isEqualToString:call.method]) {
        [self stopLoading:call];
        result(nil);
    } else if ([@"cleanCookies" isEqualToString:call.method]) {
        [self cleanCookies:call result:result];
    } else if ([@"back" isEqualToString:call.method]) {
        [self back:call];
        result(nil);
    } else if ([@"forward" isEqualToString:call.method]) {
        [self forward:call];
        result(nil);
    } else if ([@"reload" isEqualToString:call.method]) {
        [self reload:call];
        result(nil);
    } else if ([@"canGoBack" isEqualToString:call.method]) {
        [self onCanGoBack:call result:result];
    } else if ([@"canGoForward" isEqualToString:call.method]) {
        [self onCanGoForward:call result:result];
    } else if ([@"cleanCache" isEqualToString:call.method]) {
        [self cleanCache:call result:result];
    } 
    else if([@"isWebViewAlive" isEqualToString:call.method]){
        [self isWebViewAlive:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (WKWebView *)getRightWebView:(NSString *)webViewId {
    UIViewController* presentedViewController = self.viewController.presentedViewController;
    WKWebView *webviewFromView = nil;
    if (presentedViewController != nil) {
        webviewFromView = (WKWebView *)[presentedViewController.view viewWithTag:[webViewId integerValue]];
    }

    if (webviewFromView == nil) {
        webviewFromView = (WKWebView *)[self.viewController.view viewWithTag:[webViewId integerValue]];
    }

    return webviewFromView;
}

- (void)initWebview:(FlutterMethodCall*)call withResult:(FlutterResult)result {
    NSNumber *clearCache = call.arguments[@"clearCache"];
    NSNumber *clearCookies = call.arguments[@"clearCookies"];
    NSNumber *hidden = call.arguments[@"hidden"];
    NSDictionary *rect = call.arguments[@"rect"];
    _enableAppScheme = call.arguments[@"enableAppScheme"];
    NSString *userAgent = call.arguments[@"userAgent"];
    NSNumber *withZoom = call.arguments[@"withZoom"];
    NSNumber *scrollBar = call.arguments[@"scrollBar"];
    NSNumber *withJavascript = call.arguments[@"withJavascript"];    
    _ignoreSSLErrors = call.arguments[@"ignoreSSLErrors"];
    _javaScriptChannelNames = [[NSMutableSet alloc] init];
    NSNumber *allowsInlineMediaPlayback = call.arguments[@"allowsInlineMediaPlayback"];
    NSString *webviewId = call.arguments[@"id"];
    _invalidUrlRegex[webviewId] = call.arguments[@"invalidUrlRegex"];
    NSNumber *transparentBackground = call.arguments[@"transparentBackground"];
    NSNumber *contentInsetAdjustmentBehaviorNever = call.arguments[@"contentInsetAdjustmentBehaviorNever"];
    
    WKUserContentController* userContentController = [[WKUserContentController alloc] init];
    if ([call.arguments[@"javascriptChannelNames"] isKindOfClass:[NSArray class]]) {
        NSArray* javaScriptChannelNames = call.arguments[@"javascriptChannelNames"];
        [_javaScriptChannelNames addObjectsFromArray:javaScriptChannelNames];
        [self registerJavaScriptChannels:_javaScriptChannelNames controller:userContentController];
    }

    if (clearCache != (id)[NSNull null] && [clearCache boolValue]) {
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [self cleanCache:call result:result];

    }

    if (clearCookies != (id)[NSNull null] && [clearCookies boolValue]) {
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [storage cookies])
        {
            [storage deleteCookie:cookie];
        }

        [self cleanCookies:call result:result];

    }

    if (userAgent != (id)[NSNull null]) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];
    }

    CGRect rc;
    if (rect != nil) {
        rc = [self parseRect:rect];
    } else {
        rc = self.viewController.view.bounds;
    }

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = userContentController;

    if (clearCache != (id)[NSNull null] && [clearCache boolValue]) {
      configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    }

    if (allowsInlineMediaPlayback != (id)[NSNull null]) {
      configuration.allowsInlineMediaPlayback = [allowsInlineMediaPlayback boolValue];
    }
    WKWebView *customWebview = [[WKWebView alloc] initWithFrame:rc configuration:configuration];
    customWebview.UIDelegate = self;
    customWebview.navigationDelegate = self;
    customWebview.scrollView.delegate = self;
    customWebview.hidden = [hidden boolValue];
    customWebview.scrollView.showsHorizontalScrollIndicator = [scrollBar boolValue];
    customWebview.scrollView.showsVerticalScrollIndicator = [scrollBar boolValue];
    [customWebview setTag:[webviewId integerValue]];
    [customWebview addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
    
    WKPreferences* preferences = [[customWebview configuration] preferences];
    if ([withJavascript boolValue]) {
        [preferences setJavaScriptEnabled:YES];
    } else {
        [preferences setJavaScriptEnabled:NO];
    }

    if ([transparentBackground boolValue]) {
        customWebview.opaque = NO;
        customWebview.backgroundColor = [UIColor clearColor];
    }

    if ([contentInsetAdjustmentBehaviorNever boolValue]) {
        [customWebview.scrollView setContentInsetAdjustmentBehavior: UIScrollViewContentInsetAdjustmentNever];
    }

    _enableZoom = [withZoom boolValue];

    UIViewController* presentedViewController = self.viewController.presentedViewController;
    UIViewController* currentViewController = presentedViewController != nil ? presentedViewController : self.viewController;
    [currentViewController.view addSubview:customWebview];
    
    [self navigate:call];
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if ([_ignoreSSLErrors boolValue]){
        SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
        CFDataRef exceptions = SecTrustCopyExceptions(serverTrust);
        SecTrustSetExceptions(serverTrust, exceptions);
        CFRelease(exceptions);
        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialForTrust:serverTrust]);
    }
    else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling,nil);
    }
    
}

- (CGRect)parseRect:(NSDictionary *)rect {
    return CGRectMake([[rect valueForKey:@"left"] doubleValue],
                      [[rect valueForKey:@"top"] doubleValue],
                      [[rect valueForKey:@"width"] doubleValue],
                      [[rect valueForKey:@"height"] doubleValue]);
}

- (void) scrollViewDidScroll:(UIScrollView *)scrollView {
    id xDirection = @{@"xDirection": @(scrollView.contentOffset.x) };
    [channel invokeMethod:@"onScrollXChanged" arguments:xDirection];

    id yDirection = @{@"yDirection": @(scrollView.contentOffset.y) };
    [channel invokeMethod:@"onScrollYChanged" arguments:yDirection];
}

- (void)navigate:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];
    
    if (w != nil) {
            NSString *url = call.arguments[@"url"];
            NSNumber *withLocalUrl = call.arguments[@"withLocalUrl"];
            if ( [withLocalUrl boolValue]) {
                NSURL *htmlUrl = [NSURL fileURLWithPath:url isDirectory:false];
                NSString *localUrlScope = call.arguments[@"localUrlScope"];
                if (@available(iOS 9.0, *)) {
                    if(localUrlScope == nil) {
                        [w loadFileURL:htmlUrl allowingReadAccessToURL:htmlUrl];
                    }
                    else {
                        NSURL *scopeUrl = [NSURL fileURLWithPath:localUrlScope];
                        [w loadFileURL:htmlUrl allowingReadAccessToURL:scopeUrl];
                    }
                } else {
                    @throw @"not available on version earlier than ios 9.0";
                }
            } else {
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
                NSDictionary *headers = call.arguments[@"headers"];

                if (headers != nil) {
                    [request setAllHTTPHeaderFields:headers];
                }

                [w loadRequest:request];
            }
        }
}

- (void)evalJavascript:(FlutterMethodCall*)call
     completionHandler:(void (^_Nullable)(NSString * response))completionHandler {
        NSString *webviewId = call.arguments[@"id"];
        WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        NSString *code = call.arguments[@"code"];
        [w evaluateJavaScript:code
                       completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            completionHandler([NSString stringWithFormat:@"%@", response]);
        }];
    } else {
        completionHandler(nil);
    }
}

- (void)resize:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        NSDictionary *rect = call.arguments[@"rect"];
        CGRect rc = [self parseRect:rect];
        w.frame = rc;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"] && [object isKindOfClass:[WKWebView class]]) {
        WKWebView *w = (WKWebView *) object;
        [channel invokeMethod:@"onProgressChanged" arguments:@{@"progress": @(w.estimatedProgress), @"id": [NSString stringWithFormat: @"%ld", (long)w.tag]}];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)closeWebView:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        [w stopLoading];
        [w removeFromSuperview];
        w.navigationDelegate = nil;
        [w removeObserver:self forKeyPath:@"estimatedProgress"];
        w = nil;
        [_invalidUrlRegex removeObjectForKey:webviewId];

        // manually trigger onDestroy
        [channel invokeMethod:@"onDestroy" arguments:nil];
    }
}

- (void)reloadUrl:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
		NSString *url = call.arguments[@"url"];
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        NSDictionary *headers = call.arguments[@"headers"];
        
        if (headers != nil) {
            [request setAllHTTPHeaderFields:headers];
        }
        
        [w loadRequest:request];
    }
}

- (void)cleanCookies:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if(w != nil) {
        [[NSURLSession sharedSession] resetWithCompletionHandler:^{
        }];
        if (@available(iOS 9.0, *)) {
          NSSet<NSString *> *websiteDataTypes = [NSSet setWithObject:WKWebsiteDataTypeCookies];
          WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];

          void (^deleteAndNotify)(NSArray<WKWebsiteDataRecord *> *) =
              ^(NSArray<WKWebsiteDataRecord *> *cookies) {
                [dataStore removeDataOfTypes:websiteDataTypes
                              forDataRecords:cookies
                           completionHandler:^{
                            result(nil);
                           }];
              };

          [dataStore fetchDataRecordsOfTypes:websiteDataTypes completionHandler:deleteAndNotify];
        } else {
          // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
          NSLog(@"Clearing cookies is not supported for Flutter WebViews prior to iOS 9.");
        }
    }
}

- (void)cleanCache:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
       if (@available(iOS 9.0, *)) {
          NSSet* cacheDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
          WKWebsiteDataStore* dataStore = [WKWebsiteDataStore defaultDataStore];
          NSDate* dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
          [dataStore removeDataOfTypes:cacheDataTypes
                         modifiedSince:dateFrom
                     completionHandler:^{
              result(nil);
                     }];
        } else {
          // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
          NSLog(@"Clearing cache is not supported for Flutter WebViews prior to iOS 9.");
        }
    }
}

- (void)show:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        w.hidden = false;
    }
}

- (void)hide:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        w.hidden = true;
    }
}
- (void)stopLoading:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        [w stopLoading];
    }
}
- (void)back:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        [w goBack];
    }
}

- (void)onCanGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString *webviewId = call.arguments[@"id"];
  WKWebView *w = [self getRightWebView:webviewId];

  BOOL canGoBack = [w canGoBack];
  result([NSNumber numberWithBool:canGoBack]);
}

- (void)onCanGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString *webviewId = call.arguments[@"id"];
  WKWebView *w = [self getRightWebView:webviewId];

  BOOL canGoForward = [w canGoForward];
  result([NSNumber numberWithBool:canGoForward]);
}

- (void)isWebViewAlive:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString *webviewId = call.arguments[@"id"];
  WKWebView *w = [self getRightWebView:webviewId];

  result([NSNumber numberWithBool:w != nil]);
}

- (void)forward:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        [w goForward];
    }
}
- (void)reload:(FlutterMethodCall*)call {
    NSString *webviewId = call.arguments[@"id"];
    WKWebView *w = [self getRightWebView:webviewId];

    if (w != nil) {
        [w reload];
    }
}

- (bool)checkInvalidUrl:(NSURL*)url forWebViewId:(NSString *)webviewId {
  NSString* urlString = url != nil ? [url absoluteString] : nil;
  if (![_invalidUrlRegex[webviewId] isEqual:[NSNull null]] && urlString != nil) {
    NSError* error = NULL;
    NSRegularExpression* regex =
        [NSRegularExpression regularExpressionWithPattern:_invalidUrlRegex[webviewId]
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&error];
    NSTextCheckingResult* match = [regex firstMatchInString:urlString
                                                    options:0
                                                      range:NSMakeRange(0, [urlString length])];
    return match != nil;
  } else {
    return false;
  }
}

#pragma mark -- WkWebView Delegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSString *webViewId = [NSString stringWithFormat: @"%ld", (long)webView.tag];
    BOOL isInvalid = [self checkInvalidUrl: navigationAction.request.URL forWebViewId:webViewId];
    id data = @{@"url": navigationAction.request.URL.absoluteString,
                @"type": isInvalid ? @"abortLoad" : @"shouldStart",
                @"navigationType": [NSNumber numberWithInteger:navigationAction.navigationType],
                @"id": webViewId};
    [channel invokeMethod:@"onState" arguments:data];

    if (navigationAction.navigationType == WKNavigationTypeBackForward) {
        [channel invokeMethod:@"onBackPressed" arguments:nil];
    } else if (!isInvalid) {
        id data = @{@"url": navigationAction.request.URL.absoluteString, @"id": webViewId};
        [channel invokeMethod:@"onUrlChanged" arguments:data];
    }

    if (_enableAppScheme ||
        ([webView.URL.scheme isEqualToString:@"http"] ||
         [webView.URL.scheme isEqualToString:@"https"] ||
         [webView.URL.scheme isEqualToString:@"about"] ||
         [webView.URL.scheme isEqualToString:@"file"])) {
         if (isInvalid) {
            decisionHandler(WKNavigationActionPolicyCancel);
         } else {
            decisionHandler(WKNavigationActionPolicyAllow);
         }
    } else {
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {

    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }

    return nil;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"startLoad", @"url": webView.URL.absoluteString, @"id": [NSString stringWithFormat: @"%ld", (long)webView.tag]}];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSString* url = webView.URL == nil ? @"?" : webView.URL.absoluteString;
    
    [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", error.code], @"url": url, @"id": [NSString stringWithFormat: @"%ld", (long)webView.tag]}];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"finishLoad", @"url": webView.URL.absoluteString, @"id": [NSString stringWithFormat: @"%ld", (long)webView.tag]}];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", error.code], @"error": error.localizedDescription, @"id": [NSString stringWithFormat: @"%ld", (long)webView.tag]}];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse * response = (NSHTTPURLResponse *)navigationResponse.response;

        if (response.statusCode >= 400) {
            [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", response.statusCode], @"url": webView.URL.absoluteString, @"id": [NSString stringWithFormat: @"%ld", (long)webView.tag]}];
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)registerJavaScriptChannels:(NSSet*)channelNames
                        controller:(WKUserContentController*)userContentController {
    for (NSString* channelName in channelNames) {
        FLTCommunityJavaScriptChannel* _channel =
        [[FLTCommunityJavaScriptChannel alloc] initWithMethodChannel: channel
                                      javaScriptChannelName:channelName];
        [userContentController addScriptMessageHandler:_channel name:channelName];
        NSString* wrapperSource = [NSString
                                   stringWithFormat:@"window.%@ = webkit.messageHandlers.%@;", channelName, channelName];
        WKUserScript* wrapperScript =
        [[WKUserScript alloc] initWithSource:wrapperSource
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
        [userContentController addUserScript:wrapperScript];
    }
}

#pragma mark -- UIScrollViewDelegate
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView.pinchGestureRecognizer.isEnabled != _enableZoom) {
        scrollView.pinchGestureRecognizer.enabled = _enableZoom;
    }
}

#pragma mark -- WKUIDelegate
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler();
  }]];

  [self.viewController presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler
{
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler(NO);
  }]];

  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    completionHandler(YES);
  }]];

  [self.viewController presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *result))completionHandler
{
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                 message:prompt
                                                          preferredStyle:UIAlertControllerStyleAlert];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.placeholder = prompt;
    textField.secureTextEntry = NO;
    textField.text = defaultText;
  }];

  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler(nil);
  }]];

  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    completionHandler([alert.textFields.firstObject text]);
  }]];

  [self.viewController presentViewController:alert animated:YES completion:nil];
}

@end
