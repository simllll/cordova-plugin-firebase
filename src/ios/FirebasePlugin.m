#import "FirebasePlugin.h"
#import <Cordova/CDV.h>
#import "AppDelegate.h"
#import "Firebase.h"
#import <objc/runtime.h>
@import FirebaseInstanceID;
@import FirebaseAnalytics;
@import FirebaseDynamicLinks;

static NSString *const CUSTOM_URL_SCHEME = @"com.jobswipr.hokify";

@implementation FirebasePlugin

- (void)pluginInitialize {
    NSLog(@"Starting Firebase plugin");
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishLaunching:)
                                                 name:UIApplicationDidFinishLaunchingNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tokenRefreshNotification:)
                                                 name:kFIRInstanceIDTokenRefreshNotification object:nil];
    
    /*    [[NSNotificationCenter defaultCenter] addObserver:self
     selector:@selector(applicationDidBecomeActive:)
     name:UIApplicationDidBecomeActiveNotification object:nil];
     
     [[NSNotificationCenter defaultCenter] addObserver:self
     selector:@selector(applicationDidEnterBackground:)
     name:UIApplicationDidEnterBackgroundNotification object:nil];
     */
}
/*- (BOOL)application:(UIApplication *)app
 openURL:(NSURL *)url
 options:(NSDictionary<NSString *, id> *)options {
 return [self application:app openURL:url sourceApplication:nil annotation:@{}];
 }*/

- (void) applicationDidFinishLaunching:(NSNotification *) notification {
    [FIROptions defaultOptions].deepLinkURLScheme = CUSTOM_URL_SCHEME;
    [FIRApp configure];
}

- (void)getInstanceId:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    
    if ([[FIRInstanceID instanceID] token]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:
                        [[FIRInstanceID instanceID] token]];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:
                        @"FCM is not connected, or token is not yet available."];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)grantPermission:(CDVInvokedUrlCommand *)command {
    UIUserNotificationType allNotificationTypes =
    (UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge);
    UIUserNotificationSettings *settings =
    [UIUserNotificationSettings settingsForTypes:allNotificationTypes categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setBadgeNumber:(CDVInvokedUrlCommand *)command {
    int number    = [[command.arguments objectAtIndex:0] intValue];
    
    [self.commandDelegate runInBackground:^{
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:number];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)getBadgeNumber:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        long badge = [[UIApplication sharedApplication] applicationIconBadgeNumber];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:badge];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)logEvent:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString* name = [command.arguments objectAtIndex:0];
        NSDictionary* parameters = [command.arguments objectAtIndex:1];
        
        [FIRAnalytics logEventWithName:name parameters:parameters];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)tokenRefreshNotification:(NSNotification *)notification {
    // Note that this callback will be fired everytime a new token is generated, including the first
    // time. So if you need to retrieve the token as soon as it is available this is where that
    // should be done.
    NSString *refreshedToken = [[FIRInstanceID instanceID] token];
    NSLog(@"InstanceID token: %@", refreshedToken);
    
    // TODO: If necessary send token to appliation server.
}

/*
 - (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
 fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
 // If you are receiving a notification message while your app is in the background,
 // this callback will not be fired till the user taps on the notification launching the application.
 // TODO: Handle data of notification
 
 // Print message ID.
 NSLog(@"Message ID: %@", userInfo[@"gcm.message_id"]);
 
 // Pring full message.
 NSLog(@"%@", userInfo);
 }
 */
@end


#pragma mark - AppDelegate Overrides

@implementation AppDelegate (FirebasePlugin)

void FirebaseMethodSwizzle(Class c, SEL originalSelector) {
    NSString *selectorString = NSStringFromSelector(originalSelector);
    SEL newSelector = NSSelectorFromString([@"swizzledFirebase_" stringByAppendingString:selectorString]);
    SEL noopSelector = NSSelectorFromString([@"noopFirebase_" stringByAppendingString:selectorString]);
    Method originalMethod, newMethod, noop;
    originalMethod = class_getInstanceMethod(c, originalSelector);
    newMethod = class_getInstanceMethod(c, newSelector);
    noop = class_getInstanceMethod(c, noopSelector);
    if (class_addMethod(c, originalSelector, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(c, newSelector, method_getImplementation(originalMethod) ?: method_getImplementation(noop), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, newMethod);
    }
}

+ (void)load
{
    NSLog(@"Load FirebasePlugin");
    FirebaseMethodSwizzle([self class], @selector(application:openURL:sourceApplication:annotation:));
    FirebaseMethodSwizzle([self class], @selector(application:openURL:options:));
    FirebaseMethodSwizzle([self class], @selector(application:continueUserActivity:restorationHandler:));
}

- (void)noopFirebase_application:(UIApplication *)application
    continueUserActivity:(NSUserActivity *)userActivity
      restorationHandler:(void (^)(NSArray *))restorationHandler {
}

- (void)swizzledFirebase_application:(UIApplication *)application
        continueUserActivity:(NSUserActivity *)userActivity
          restorationHandler:(void (^)(NSArray *))restorationHandler {
    
    NSLog(@"Firebase plugin continueUserActivity");
    
    [[FIRDynamicLinks dynamicLinks]
     handleUniversalLink:userActivity.webpageURL
     completion:^(FIRDynamicLink * _Nullable dynamicLink,
                  NSError * _Nullable error) {
         if(dynamicLink != NULL && dynamicLink.url != NULL)
         {
             NSLog(@"handleUniversalLink");
             
             // all plugins will get the notification, and their handlers will be called - again with new url
             [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:dynamicLink.url]];
         }
     }];
    
    // Call existing method
    [self swizzledFirebase_application:application continueUserActivity:userActivity restorationHandler:restorationHandler];
}

- (void)noopFirebase_application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
}

- (void)swizzledFirebase_application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    NSLog(@"Firebase plugin openURL");
    
    FIRDynamicLink *dynamicLink = [[FIRDynamicLinks dynamicLinks] dynamicLinkFromCustomSchemeURL:url];
    if (dynamicLink && dynamicLink.url != NULL) {
        // all plugins will get the notification, and their handlers will be called - again with new url
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:dynamicLink.url]];
    }
    
    // Call existing method
    [self swizzledFirebase_application:application openURL:url sourceApplication:sourceApplication annotation:annotation];
}

- (void)noopFirebase_application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<NSString *, id> *)options {
}

- (void)swizzledFirebase_application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<NSString *, id> *)options {
            
    FIRDynamicLink *dynamicLink = [[FIRDynamicLinks dynamicLinks] dynamicLinkFromCustomSchemeURL:url];
    if (dynamicLink && dynamicLink.url != NULL) {
        // all plugins will get the notification, and their handlers will be called - again with new url
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:dynamicLink.url]];
    }
  
    [self swizzledFirebase_application:app openURL:url options:options];
}
@end
