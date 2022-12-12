#import "SentryDefines.h"
#import "SentryScope+Private.h"
#import <SentryAppState.h>
#import <SentryAppStateManager.h>
#import <SentryClient+Private.h>
#import <SentryCrashWrapper.h>
#import <SentryDependencyContainer.h>
#import <SentryDispatchQueueWrapper.h>
#import <SentryHub.h>
#import <SentryOptions+Private.h>
#import <SentrySDK+Private.h>
#import <SentryWatchdogTerminationsLogic.h>
#import <SentryWatchdogTerminationsScopeObserver.h>
#import <SentryWatchdogTerminationsTracker.h>
#import <SentryWatchdogTerminationsTrackingIntegration.h>

NS_ASSUME_NONNULL_BEGIN

@interface
SentryWatchdogTerminationsTrackingIntegration ()

@property (nonatomic, strong) SentryWatchdogTerminationsTracker *tracker;
@property (nonatomic, strong) SentryANRTracker *anrTracker;
@property (nullable, nonatomic, copy) NSString *testConfigurationFilePath;
@property (nonatomic, strong) SentryAppStateManager *appStateManager;

@end

@implementation SentryWatchdogTerminationsTrackingIntegration

- (instancetype)init
{
    if (self = [super init]) {
        self.testConfigurationFilePath
            = NSProcessInfo.processInfo.environment[@"XCTestConfigurationFilePath"];
    }
    return self;
}

- (BOOL)installWithOptions:(SentryOptions *)options
{
    if (self.testConfigurationFilePath) {
        return NO;
    }

    if (![super installWithOptions:options]) {
        return NO;
    }

    dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(
        DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    SentryDispatchQueueWrapper *dispatchQueueWrapper =
        [[SentryDispatchQueueWrapper alloc] initWithName:"sentry-out-of-memory-tracker"
                                              attributes:attributes];

    SentryFileManager *fileManager = [[[SentrySDK currentHub] getClient] fileManager];
    SentryAppStateManager *appStateManager =
        [SentryDependencyContainer sharedInstance].appStateManager;
    SentryCrashWrapper *crashWrapper = [SentryDependencyContainer sharedInstance].crashWrapper;
    SentryWatchdogTerminationsLogic *logic =
        [[SentryWatchdogTerminationsLogic alloc] initWithOptions:options
                                                    crashAdapter:crashWrapper
                                                 appStateManager:appStateManager];

    self.tracker = [[SentryWatchdogTerminationsTracker alloc] initWithOptions:options
                                                    watchdogTerminationsLogic:logic
                                                              appStateManager:appStateManager
                                                         dispatchQueueWrapper:dispatchQueueWrapper
                                                                  fileManager:fileManager];

    [self.tracker start];

    self.anrTracker =
        [SentryDependencyContainer.sharedInstance getANRTracker:options.appHangTimeoutInterval];
    [self.anrTracker addListener:self];

    self.appStateManager = appStateManager;

    SentryWatchdogTerminationsScopeObserver *scopeObserver =
        [[SentryWatchdogTerminationsScopeObserver alloc]
            initWithMaxBreadcrumbs:options.maxBreadcrumbs
                       fileManager:[[[SentrySDK currentHub] getClient] fileManager]];

    [SentrySDK.currentHub configureScope:^(
        SentryScope *_Nonnull outerScope) { [outerScope addObserver:scopeObserver]; }];

    return YES;
}

- (SentryIntegrationOption)integrationOptions
{
    return kIntegrationOptionEnableWatchdogTerminationsTracking;
}

- (void)uninstall
{
    if (nil != self.tracker) {
        [self.tracker stop];
    }
    [self.anrTracker removeListener:self];
}

- (void)anrDetected
{
#if SENTRY_HAS_UIKIT
    [self.appStateManager
        updateAppState:^(SentryAppState *appState) { appState.isANROngoing = YES; }];
#endif
}

- (void)anrStopped
{
#if SENTRY_HAS_UIKIT
    [self.appStateManager
        updateAppState:^(SentryAppState *appState) { appState.isANROngoing = NO; }];
#endif
}

@end

NS_ASSUME_NONNULL_END