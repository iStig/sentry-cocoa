//
//  SentryReplayRecorder.m
//  Sentry
//
//  Created by Indragie Karunaratne on 8/22/22.
//  Copyright © 2022 Sentry. All rights reserved.
//

#import "SentryReplayRecorder.h"
#import "SentrySwizzle.h"
#import "SentryUIApplication.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

static NSDictionary<NSString *, id> *
serializeCGPoint(CGPoint point)
{
    return @{@"x" : @(point.x), @"y" : @(point.y)};
}

static NSDictionary<NSString *, id> *
serializeCGSize(CGSize size)
{
    return @{@"width" : @(size.width), @"height" : @(size.height)};
}

static NSDictionary<NSString *, id> *
serializeCGRect(CGRect rect)
{
    return @ { @"origin" : serializeCGPoint(rect.origin), @"size" : serializeCGSize(rect.size) };
}

static NSDictionary<NSString *, id> *
serializeUIColor(UIColor *color)
{
    if (color == nil) { return nil; }
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    const unsigned int rgb
        = (unsigned int)(r * 255) << 16 | (unsigned int)(g * 255) << 8 | (unsigned int)(b * 255);
    return @{@"color" : [NSString stringWithFormat:@"#%06x", rgb], @"alpha" : @(a)};
}

static NSDictionary<NSString *, id> *
serializeUIFont(UIFont *font)
{
    if (font == nil) { return nil; }
    return @{
        @"familyName" : font.familyName,
        @"fontName" : font.fontName,
        @"pointSize" : @(font.pointSize)
    };
}

static NSString *
serializeContentMode(UIViewContentMode contentMode)
{
    switch (contentMode) {
    case UIViewContentModeScaleAspectFit:
        return @"scaleAspectFit";
    case UIViewContentModeScaleToFill:
        return @"scaleToFill";
    case UIViewContentModeScaleAspectFill:
        return @"scaleAspectFill";
    case UIViewContentModeTop:
        return @"top";
    case UIViewContentModeLeft:
        return @"left";
    case UIViewContentModeRight:
        return @"right";
    case UIViewContentModeBottom:
        return @"bottom";
    case UIViewContentModeCenter:
        return @"center";
    case UIViewContentModeRedraw:
        return @"redraw";
    case UIViewContentModeTopLeft:
        return @"topLeft";
    case UIViewContentModeTopRight:
        return @"topRight";
    case UIViewContentModeBottomLeft:
        return @"bottomLeft";
    case UIViewContentModeBottomRight:
        return @"bottomRight";
    default:
        return @"";
    }
}

static NSString *
serializeTextAlignment(NSTextAlignment alignment)
{
    switch (alignment) {
    case NSTextAlignmentCenter:
        return @"center";
    case NSTextAlignmentRight:
        return @"right";
    case NSTextAlignmentLeft:
        return @"left";
    case NSTextAlignmentNatural:
        return @"natural";
    case NSTextAlignmentJustified:
        return @"justified";
    default:
        return @"";
    }
}

static void *kNodeIDAssociatedObjectKey = &kNodeIDAssociatedObjectKey;
static void *kTextNodeIDAssociatedObjectKey = &kTextNodeIDAssociatedObjectKey;

@interface SentryReplayNodeIDGenerator : NSObject
- (NSNumber *)idForNode:(nullable id)node;
- (NSNumber *)textIdForNode:(nullable id)node;
@end

@implementation SentryReplayNodeIDGenerator {
    NSUInteger _nodeID;
}

- (instancetype)init {
    if (self = [super init]) {
        _nodeID = 0;
    }
    return self;
}

- (NSNumber *)idForNode:(nullable id)node {
    return [self idForNode:node associatedObjectKey:kNodeIDAssociatedObjectKey];
}

- (NSNumber *)textIdForNode:(nullable id)node {
    return [self idForNode:node associatedObjectKey:kTextNodeIDAssociatedObjectKey];
}

- (NSNumber *)idForNode:(nullable id)node associatedObjectKey:(void *)associatedObjectKey {
    if (node == nil) {
        return nil;
    }
    NSNumber *nodeID = objc_getAssociatedObject(node, associatedObjectKey);
    if (nodeID == nil) {
        nodeID = [self nextNodeID];
        objc_setAssociatedObject(
            node, associatedObjectKey, nodeID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return nodeID;
}

- (NSNumber *)nextNodeID {
    return @(++_nodeID);
}

@end

@protocol SentryIntrospectableView <NSObject>
- (NSDictionary<NSString *, id> *)introspect_getAttributes;
@optional
- (NSString *)introspect_getTextContents;
@end

@interface
UIView (SentryReplay) <SentryIntrospectableView>
@end

@implementation
UIView (SentryReplay)
- (NSDictionary<NSString *, id> *)introspect_getAttributes
{
    NSMutableDictionary<NSString *, id> *const attributes =
        [NSMutableDictionary<NSString *, id> dictionary];
    attributes[@"frame"] = serializeCGRect(self.frame);
    if (self.isHidden || self.alpha == 0.0) {
        attributes[@"isHidden"] = @YES;
    } else if (self.alpha != 1.0) {
        attributes[@"alpha"] = @(self.alpha);
    }
    if (self.contentMode != UIViewContentModeScaleToFill) {
        attributes[@"contentMode"] = serializeContentMode(self.contentMode);
    }
    attributes[@"backgroundColor"] = serializeUIColor(self.backgroundColor);
    return attributes;
}
@end

@interface
UILabel (SentryReplay) <SentryIntrospectableView>
@end

@implementation
UILabel (SentryReplay)
- (NSDictionary<NSString *, id> *)introspect_getAttributes
{
    NSMutableDictionary<NSString *, id> *const attributes =
        [NSMutableDictionary<NSString *, id> dictionary];
    [attributes addEntriesFromDictionary:[super introspect_getAttributes]];
    attributes[@"font"] = serializeUIFont(self.font);
    attributes[@"textColor"] = serializeUIColor(self.textColor);
    attributes[@"textAlignment"] = serializeTextAlignment(self.textAlignment);
    return attributes;
}

- (NSString *)introspect_getTextContents {
    return self.text;
}
@end

@interface
UIButton (SentryReplay) <SentryIntrospectableView>
@end

@implementation
UIButton (SentryReplay)
- (NSDictionary<NSString *, id> *)introspect_getAttributes
{
    NSMutableDictionary<NSString *, id> *const attributes =
        [NSMutableDictionary<NSString *, id> dictionary];
    [attributes addEntriesFromDictionary:[super introspect_getAttributes]];
    attributes[@"title"] = self.currentTitle;
    attributes[@"titleColor"] = serializeUIColor(self.currentTitleColor);
    return attributes;
}
@end

@interface UITextField (SentryReplay) <SentryIntrospectableView>
@end

@implementation UITextField (SentryReplay)
- (NSDictionary<NSString *, id> *)introspect_getAttributes
{
    NSMutableDictionary<NSString *, id> *const attributes =
        [NSMutableDictionary<NSString *, id> dictionary];
    [attributes addEntriesFromDictionary:[super introspect_getAttributes]];
    attributes[@"placeholder"] = self.placeholder;
    attributes[@"font"] = serializeUIFont(self.font);
    attributes[@"textColor"] = serializeUIColor(self.textColor);
    attributes[@"textAlignment"] = serializeTextAlignment(self.textAlignment);
    attributes[@"isEditing"] = @(self.isEditing);
    return attributes;
}

- (NSString *)introspect_getTextContents {
    return self.text;
}

@end

typedef NS_ENUM(NSInteger, SentryReplayMutationType) {
    SentryReplayMutationTypeAddView,
    SentryReplayMutationTypeRemoveView,
    SentryReplayMutationTypeLayoutView
};

@interface SentryReplayMutation : NSObject
@property (nonatomic, assign) SentryReplayMutationType mutationType;
@property (nonatomic, copy, readonly, nonnull) NSString *viewClass;
@property (nonatomic, strong, readonly, nonnull) NSNumber *nodeID;
@property (nonatomic, strong, readonly, nullable) NSNumber *parentID;
@property (nonatomic, strong, readonly, nullable) NSNumber *nextID;
@property (nonatomic, copy) NSDictionary<NSString *, id> *attributes;
@property (nonatomic, copy, readonly, nullable) NSString *text;

+ (instancetype)addView:(UIView *)view
        nodeIDGenerator:(SentryReplayNodeIDGenerator *)nodeIDGenerator;
+ (instancetype)removeView:(UIView *)view
           nodeIDGenerator:(SentryReplayNodeIDGenerator *)nodeIDGenerator;
+ (instancetype)layoutView:(UIView *)view
           nodeIDGenerator:(SentryReplayNodeIDGenerator *)nodeIDGenerator;

@end

@implementation SentryReplayMutation

+ (instancetype)addView:(UIView *)view
        nodeIDGenerator:(SentryReplayNodeIDGenerator *)nodeIDGenerator {
    return [[self alloc] initWithMutationType:SentryReplayMutationTypeAddView view:view nodeIDGenerator:nodeIDGenerator];
}

+ (instancetype)removeView:(UIView *)view
           nodeIDGenerator:(SentryReplayNodeIDGenerator *)nodeIDGenerator {
    return [[self alloc] initWithMutationType:SentryReplayMutationTypeRemoveView view:view nodeIDGenerator:nodeIDGenerator];
}

+ (instancetype)layoutView:(UIView *)view
           nodeIDGenerator:(SentryReplayNodeIDGenerator *)nodeIDGenerator{
    return [[self alloc] initWithMutationType:SentryReplayMutationTypeLayoutView view:view nodeIDGenerator:nodeIDGenerator];
}

- (instancetype)initWithMutationType:(SentryReplayMutationType)mutationType
                                view:(UIView *)view
                     nodeIDGenerator:(SentryReplayNodeIDGenerator *)nodeIDGenerator {
    if (self = [super init]) {
        _mutationType = mutationType;
        _viewClass = NSStringFromClass(view.class);
        _nodeID = [nodeIDGenerator idForNode:view];
        _parentID = [nodeIDGenerator idForNode:view.superview];
        NSArray<UIView *> *const subviews = view.superview.subviews;
        if (subviews.count > 1) {
            const NSUInteger index = [subviews indexOfObjectIdenticalTo:view];
            if (index < (subviews.count - 1)) {
                _nextID = [nodeIDGenerator idForNode:subviews[index + 1]];
            }
        }
        _attributes = [[view introspect_getAttributes] copy];
        if ([view respondsToSelector:@selector(introspect_getTextContents)]) {
            _text = [[view introspect_getTextContents] copy];
        }
    }
    return self;
}

@end

@implementation SentryReplayRecorder {
    NSMutableDictionary<NSNumber *, NSMutableArray<SentryReplayMutation *> *> *_mutations;
    NSMutableArray<NSDictionary<NSString *, id> *> *_replay;
    NSMutableSet<NSNumber *> *_activeNodeIDs;
    NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> *_latestAttributes;
    BOOL _isRecording;
}

- (void)startRecording
{
    if (_isRecording) {
        return;
    }
    _isRecording = YES;
    NSNotificationCenter *const nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(windowDidBecomeKey:)
               name:UIWindowDidBecomeKeyNotification
             object:nil];
    
    __weak __typeof__(self) weakSelf = self;
    swizzleLayoutSubviews(
        ^(UIView *view) {
            [weakSelf appendMutation:
             [[SentryReplayMutation alloc] initWithMutationType:SentryReplayMutationTypeLayoutView
                                                           view:view
                                                nodeIDGenerator:sharedNodeIDGenerator()]
                           timestamp:getCurrentTimestamp()];
    });
    swizzleDidAddSubview(^(__unused UIView *__unsafe_unretained superview, UIView *subview) {
        [weakSelf appendMutation:
         [[SentryReplayMutation alloc] initWithMutationType:SentryReplayMutationTypeAddView
                                                       view:subview
                                            nodeIDGenerator:sharedNodeIDGenerator()]
                       timestamp:getCurrentTimestamp()];
    });
    swizzleWillRemoveSubview(^(__unused UIView *__unsafe_unretained superview, UIView *subview) {
        [weakSelf appendMutation:
         [[SentryReplayMutation alloc] initWithMutationType:SentryReplayMutationTypeRemoveView
                                                       view:subview
                                            nodeIDGenerator:sharedNodeIDGenerator()]
                       timestamp:getCurrentTimestamp()];
    });
    
    UIWindow *const keyWindow = getKeyWindow();
    if (keyWindow != nil) {
        [self recordInitialState:keyWindow];
    }
}

- (void)recordInitialState:(UIWindow *)keyWindow {
    _mutations = [NSMutableDictionary<NSNumber *, NSMutableArray<SentryReplayMutation *> *> dictionary];
    _replay =
        [NSMutableArray<NSDictionary<NSString *, id> *> array];
    _activeNodeIDs = [NSMutableSet<NSNumber *> set];
    _latestAttributes = [NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> dictionary];
    
    const CGRect screenBounds = keyWindow.screen.bounds;
    NSNumber *const timestamp = getCurrentTimestamp();
    [_replay addObject:@{
        @"type" : @4,
        @"data" :
            @ { @"width" : @(screenBounds.size.width), @"height" : @(screenBounds.size.height) },
        @"timestamp" : timestamp,
    }];
    
    NSNumber *const screenID = [sharedNodeIDGenerator() idForNode:keyWindow.screen];
    NSMutableArray<NSDictionary<NSString *, id> *> *const childNodes =
        [NSMutableArray<NSDictionary<NSString *, id> *> array];
    NSDictionary<NSString *, id> *const serializedWindow = [self serializeViewHierarchy:keyWindow];
    if (serializedWindow != nil) {
        [childNodes addObject:serializedWindow];
    }
    [_replay addObject:@{
        @"type" : @2,
        @"data" : @ {
            @"node" : @ {
                @"type" : @0,
                @"childNodes" : childNodes,
                @"id" : screenID,
            }
        },
        @"timestamp" : timestamp
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [self stopRecording]; });
}

- (void)stopRecording
{
    if (!_isRecording) {
        return;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [[[_mutations allKeys] sortedArrayUsingSelector:@selector(compare:)] enumerateObjectsUsingBlock:^(NSNumber * _Nonnull timestamp, NSUInteger idx, BOOL * _Nonnull stop) {
        NSMutableArray<SentryReplayMutation *> *const mutations = _mutations[timestamp];
        NSMutableDictionary<NSNumber *, SentryReplayMutation *> *const addedNodeMutations = [NSMutableDictionary<NSNumber *, SentryReplayMutation *> dictionary];
        NSMutableDictionary<NSNumber *, SentryReplayMutation *> *const removedNodeMutations = [NSMutableDictionary<NSNumber *, SentryReplayMutation *> dictionary];
        NSMutableDictionary<NSNumber *, SentryReplayMutation *> *const layoutNodeMutations = [NSMutableDictionary<NSNumber *, SentryReplayMutation *> dictionary];
        NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> *const latestAttributes = [NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> dictionary];
        for (SentryReplayMutation *mutation in mutations) {
            switch (mutation.mutationType) {
                case SentryReplayMutationTypeAddView: {
                    addedNodeMutations[mutation.nodeID] = mutation;
                    [removedNodeMutations removeObjectForKey:mutation.nodeID];
                    [layoutNodeMutations removeObjectForKey:mutation.nodeID];
                    break;
                }
                case SentryReplayMutationTypeRemoveView: {
                    removedNodeMutations[mutation.nodeID] = mutation;
                    [addedNodeMutations removeObjectForKey:mutation.nodeID];
                    [layoutNodeMutations removeObjectForKey:mutation.nodeID];
                    break;
                }
                case SentryReplayMutationTypeLayoutView:
                    layoutNodeMutations[mutation.nodeID] = mutation;
                    break;
            }
            latestAttributes[mutation.nodeID] = mutation.attributes;
        }
        
        NSMutableArray<NSDictionary<NSString *, id> *> *const adds = [NSMutableArray<NSDictionary<NSString *, id> *> array];
        NSMutableArray<NSDictionary<NSString *, id> *> *const removes = [NSMutableArray<NSDictionary<NSString *, id> *> array];
        NSMutableArray<NSDictionary<NSString *, id> *> *const attributes = [NSMutableArray<NSDictionary<NSString *, id> *> array];
        
        [addedNodeMutations enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull nodeID, SentryReplayMutation * _Nonnull mutation, BOOL * _Nonnull stop1) {
            [adds addObject:@{
                @"parentId": mutation.parentID ?: [NSNull null],
                @"nextId": mutation.nextID ?: [NSNull null],
                @"node": @{
                    @"type": @2,
                    @"id": mutation.nodeID,
                    @"viewClass": mutation.viewClass,
                    @"attributes": latestAttributes[mutation.nodeID],
                    @"childNodes": @[]
                }
            }];
        }];
        [removedNodeMutations enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull nodeID, SentryReplayMutation * _Nonnull mutation, BOOL * _Nonnull stop2) {
            [removes addObject:@{
                @"parentId": mutation.parentID,
                @"id": mutation.nodeID
            }];
        }];
        [layoutNodeMutations enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull nodeID, SentryReplayMutation * _Nonnull mutation, BOOL * _Nonnull stop3) {
            [attributes addObject:@{
                @"id": mutation.nodeID,
                @"attributes": latestAttributes[mutation.nodeID]
            }];
        }];
        
        [_replay addObject:@{
            @"type": @3,
            @"data": @{
                @"source": @0,
                @"texts": @[],
                @"attributes": attributes,
                @"removes": removes,
                @"adds": adds
            },
            @"timestamp": timestamp
        }];
    }];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:_replay options:0 error:nil];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"replay.json"];
    [data writeToFile:path atomically:YES];
    NSLog(@"[REPLAY] PATH: %@", path);
    
    _replay = nil;
    _mutations = nil;
    _activeNodeIDs = nil;
    _latestAttributes = nil;
    _isRecording = NO;
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if (_isRecording && _replay == nil) {
        [self recordInitialState:notification.object];
    }
}

- (NSDictionary<NSString *, id> *)serializeViewHierarchy:(UIView *)view
{
    if (view == nil) {
        return nil;
    }
    NSMutableDictionary<NSString *, id> *const node =
        [NSMutableDictionary<NSString *, id> dictionary];
    NSMutableArray<NSDictionary<NSString *, id> *> *const childNodes =
        [NSMutableArray<NSDictionary<NSString *, id> *> array];
    
    NSNumber *const nodeID = [sharedNodeIDGenerator() idForNode:view];
    [_activeNodeIDs addObject:nodeID];
    NSDictionary<NSString *, id> *const attributes = [view introspect_getAttributes];
    _latestAttributes[nodeID] = attributes;
    
    node[@"type"] = @2;
    node[@"id"] = nodeID;
    node[@"viewClass"] = NSStringFromClass(view.class);
    node[@"attributes"] = attributes;
    if ([view respondsToSelector:@selector(introspect_getTextContents)]) {
        NSNumber *const textID = [sharedNodeIDGenerator() textIdForNode:view];
        [childNodes addObject:@{
            @"type": @2,
            @"id": textID,
            @"textContents": [view introspect_getTextContents]
        }];
        [_activeNodeIDs addObject:textID];
    }
    for (UIView *subview in view.subviews) {
        NSDictionary<NSString *, id> *const childNode = [self serializeViewHierarchy:subview];
        if (childNode != nil) {
            [childNodes addObject:childNode];
        }
    }
    node[@"childNodes"] = childNodes;
    return node;
}

- (void)appendMutation:(SentryReplayMutation *)mutation timestamp:(NSNumber *)timestamp {
    if (_mutations == nil) {
        return;
    }
    switch (mutation.mutationType) {
        case SentryReplayMutationTypeAddView:
            [_activeNodeIDs addObject:mutation.nodeID];
            _latestAttributes[mutation.nodeID] = mutation.attributes;
            break;
        case SentryReplayMutationTypeRemoveView:
            [_activeNodeIDs removeObject:mutation.nodeID];
            [_latestAttributes removeObjectForKey:mutation.nodeID];
            break;
        case SentryReplayMutationTypeLayoutView: {
            if (![_activeNodeIDs containsObject:mutation.nodeID]) {
                mutation.mutationType = SentryReplayMutationTypeAddView;
            } else {
                NSDictionary<NSString *, id> *const currentAttributes = _latestAttributes[mutation.nodeID];
                _latestAttributes[mutation.nodeID] = mutation.attributes;
                if (currentAttributes != nil) {
                    NSDictionary<NSString *, id> *const changedAttributes = diffAttributes(currentAttributes, mutation.attributes);
                    if (changedAttributes == nil) {
                        return;
                    }
                    mutation.attributes = changedAttributes;
                }
            }
            break;
        }
    }
    
    NSMutableArray<SentryReplayMutation *> *mutations = _mutations[timestamp];
    if (mutations == nil) {
        mutations = [NSMutableArray<SentryReplayMutation *> array];
        _mutations[timestamp] = mutations;
    }
    [mutations addObject:mutation];
}

static NSDictionary<NSString *, id> *diffAttributes(NSDictionary<NSString *, id> *old, NSDictionary<NSString *, id> *new) {
    NSMutableSet<NSString *> *const changedKeys = [NSMutableSet<NSString *> set];
    [new enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull newValue, BOOL * _Nonnull stop) {
        id const oldValue = old[key];
        if (oldValue == nil || ![oldValue isEqual:newValue]) {
            [changedKeys addObject:key];
        }
    }];
    if (changedKeys.count == 0) {
        return nil;
    }
    NSMutableDictionary<NSString *, id> *const updatedAttributes = [NSMutableDictionary<NSString *, id> dictionary];
    [changedKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull key, BOOL * _Nonnull stop) {
        updatedAttributes[key] = new[key];
    }];
    return updatedAttributes;
}

static UIWindow *getKeyWindow() {
    SentryUIApplication *const app = [[SentryUIApplication alloc] init];
    for (UIWindow *window in app.windows) {
        if (window.isKeyWindow) {
            return window;
        }
    }
    return nil;
}

static SentryReplayNodeIDGenerator *sharedNodeIDGenerator() {
    static SentryReplayNodeIDGenerator *generator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        generator = [[SentryReplayNodeIDGenerator alloc] init];
    });
    return generator;
}

static NSNumber *getCurrentTimestamp() {
    return @((NSUInteger)([[NSDate date] timeIntervalSince1970] * 1000)); // milliseconds
}

static void
swizzleLayoutSubviews(void (^block)(__unsafe_unretained UIView *))
{
    const SEL selector = @selector(layoutSubviews);
    [SentrySwizzle
        swizzleInstanceMethod:selector
                      inClass:[UIView class]
                newImpFactory:^id(SentrySwizzleInfo *swizzleInfo) {
                    return ^void(__unsafe_unretained id self) {
                        void (*originalIMP)(__unsafe_unretained id, SEL);
                        originalIMP
                            = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
                        originalIMP(self, selector);
                        block((UIView *)self);
                    };
                }
                         mode:SentrySwizzleModeAlways
                          key:NULL];
}

static void swizzleDidAddSubview(void (^block)(__unsafe_unretained UIView *superview, UIView *subview)) {
    const SEL selector = @selector(didAddSubview:);
    [SentrySwizzle
        swizzleInstanceMethod:selector
                      inClass:[UIView class]
                newImpFactory:^id(SentrySwizzleInfo *swizzleInfo) {
                    return ^void(__unsafe_unretained id self, id subview) {
                        void (*originalIMP)(__unsafe_unretained id, SEL, id);
                        originalIMP
                            = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
                        originalIMP(self, selector, subview);
                        block((UIView *)self, (UIView *)subview);
                    };
                }
                         mode:SentrySwizzleModeAlways
                          key:NULL];
}

static void swizzleWillRemoveSubview(void (^block)(__unsafe_unretained UIView *superview, UIView *subview)) {
    const SEL selector = @selector(willRemoveSubview:);
    [SentrySwizzle
        swizzleInstanceMethod:selector
                      inClass:[UIView class]
                newImpFactory:^id(SentrySwizzleInfo *swizzleInfo) {
                    return ^void(__unsafe_unretained id self, id subview) {
                        void (*originalIMP)(__unsafe_unretained id, SEL, id);
                        originalIMP
                            = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
                        originalIMP(self, selector, subview);
                        block((UIView *)self, (UIView *)subview);
                    };
                }
                         mode:SentrySwizzleModeAlways
                          key:NULL];
}

@end

NS_ASSUME_NONNULL_END