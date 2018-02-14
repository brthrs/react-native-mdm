#import "RNMobileDeviceManager.h"

// Used to send events to JS
#if __has_include(<React/RCTBridge.h>)
#import <React/RCTBridge.h>
#elif __has_include("RCTBridge.h")
#import "RCTBridge.h"
#else
#import "React/RCTBridge.h"
#endif

#if __has_include(<React/RCTEventDispatcher.h>)
#import <React/RCTEventDispatcher.h>
#elif __has_include("RCTEventDispatcher.h")
#import "RCTEventDispatcher.h"
#else
#import "React/RCTEventDispatcher.h"
#endif

@interface MobileDeviceManager ()
@property dispatch_semaphore_t asamSem;
@end

@implementation MobileDeviceManager

@synthesize bridge = _bridge;

static NSString * const APP_CONFIG_CHANGED = @"react-native-mdm/managedAppConfigDidChange";
static NSString * const APP_LOCK_STATUS_CHANGED = @"react-native-mdm/appLockStatusDidChange";
static NSString * const APP_LOCKED = @"appLocked";
static NSString * const APP_LOCKING_ALLOWED = @"appLockingAllowed";

- (instancetype)init
{
    [ManagedAppConfigSettings clientInstance].delegate = self;
    [[ManagedAppConfigSettings clientInstance] start];
    if (self = [super init]) {
        self.asamSem = dispatch_semaphore_create(1);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(guidedAccessStatusChangeListenerCallback:) name:UIAccessibilityGuidedAccessStatusDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[ManagedAppConfigSettings clientInstance] end];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) settingsDidChange:(NSDictionary<NSString *, id> *) changes {
    id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
    [_bridge.eventDispatcher sendDeviceEventWithName:APP_CONFIG_CHANGED
                                                body:appConfig];
}

- (void)guidedAccessStatusChangeListenerCallback:(NSNotification*)notification
{
    [self isSAMEnabled:^(BOOL isEnabled) {
        [self isASAMSupported:^(BOOL isAllowed) {
            [_bridge.eventDispatcher sendDeviceEventWithName:APP_LOCK_STATUS_CHANGED
                                                        body:(@{
                                                                APP_LOCKED: @(isEnabled),
                                                                APP_LOCKING_ALLOWED: @(isAllowed)
                                                                })];
        }];
    }];

}

- (void) isASAMSupported:(void(^)(BOOL))callback {
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIAccessibilityIsGuidedAccessEnabled()) {
            UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didDisable) {
                if (didDisable) {
                    UIAccessibilityRequestGuidedAccessSession(YES, ^(BOOL didEnable) {
                        dispatch_semaphore_signal(self.asamSem);
                        callback(didEnable);
                    });
                } else {
                    dispatch_semaphore_signal(self.asamSem);
                    callback(didDisable);
                }
            });
        } else {
            UIAccessibilityRequestGuidedAccessSession(YES, ^(BOOL didEnable) {
                if (didEnable) {
                    UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didDisable) {
                        dispatch_semaphore_signal(self.asamSem);
                        callback(didDisable);
                    });
                } else {
                    dispatch_semaphore_signal(self.asamSem);
                    callback(didEnable);
                }
            });
        }
    });
}

- (void) isSAMEnabled:(void(^)(BOOL))callback {
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);

    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_semaphore_signal(self.asamSem);
        callback(@(UIAccessibilityIsGuidedAccessEnabled()));
    });
}

RCT_EXPORT_MODULE();

- (NSDictionary *)constantsToExport
{
    return @{ @"APP_CONFIG_CHANGED": APP_CONFIG_CHANGED,
              @"APP_LOCK_STATUS_CHANGED": APP_LOCK_STATUS_CHANGED,
              @"APP_LOCKED": APP_LOCKED,
              @"APP_LOCKING_ALLOWED": APP_LOCKING_ALLOWED };
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_queue_create("com.robinpowered.RNMobileDeviceManager", DISPATCH_QUEUE_SERIAL);
}

RCT_EXPORT_METHOD(isSupported: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];

    if (appConfig) {
        resolve(@YES);
    } else {
        resolve(@NO);
    }
}

RCT_EXPORT_METHOD(getConfiguration:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];

    if (appConfig) {
        resolve(appConfig);
    } else {
        reject(@"not-support", @"Managed App Config is not supported", nil);
    }
}


RCT_EXPORT_METHOD(isAppLockingAllowed: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self isASAMSupported:^(BOOL isSupported){
        resolve(@(isSupported));
    }];

}

RCT_EXPORT_METHOD(isAppLocked: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self isSAMEnabled:^(BOOL isEnabled) {
        resolve(@(isEnabled));
    }];
}

RCT_EXPORT_METHOD(lockApp: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAccessibilityRequestGuidedAccessSession(YES, ^(BOOL didSucceed) {
            dispatch_semaphore_signal(self.asamSem);
            resolve(@(didSucceed));
        });
    });
}

RCT_EXPORT_METHOD(unlockApp: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didSucceed) {
            dispatch_semaphore_signal(self.asamSem);
            resolve(@(didSucceed));
        });
    });
}

@end

