// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "FLEWindowSizePlugin.h"

#import <AppKit/AppKit.h>

// See window_size_channel.dart for documentation.
static NSString *const kChannelName = @"flutter/windowsize";
static NSString *const kGetScreenListMethod = @"getScreenList";
static NSString *const kGetWindowInfoMethod = @"getWindowInfo";
static NSString *const kSetWindowFrameMethod = @"setWindowFrame";
static NSString *const kSetWindowMinimumSizeMethod = @"setWindowMinimumSize";
static NSString *const kSetWindowMaximumSizeMethod = @"setWindowMaximumSize";
static NSString *const kSetWindowTitleMethod = @"setWindowTitle";
static NSString *const kSetWindowTitleRepresentedUrlMethod = @"setWindowTitleRepresentedUrl";
static NSString *const kSetWindowVisibilityMethod = @"setWindowVisibility";
static NSString *const kGetWindowMinimumSizeMethod = @"getWindowMinimumSize";
static NSString *const kGetWindowMaximumSizeMethod = @"getWindowMaximumSize";
static NSString *const kFrameKey = @"frame";
static NSString *const kVisibleFrameKey = @"visibleFrame";
static NSString *const kScaleFactorKey = @"scaleFactor";
static NSString *const kScreenKey = @"screen";

/**
 * Returns the max Y coordinate across all screens.
 */
CGFloat GetMaxScreenY(void) {
  CGFloat maxY = 0;
  for (NSScreen *screen in [NSScreen screens]) {
    maxY = MAX(maxY, CGRectGetMaxY(screen.frame));
  }
  return maxY;
}

/**
 * Given |frame| in screen coordinates, returns a frame flipped relative to
 * GetMaxScreenY().
 */
NSRect GetFlippedRect(NSRect frame) {
  CGFloat maxY = GetMaxScreenY();
  return NSMakeRect(frame.origin.x, maxY - frame.origin.y - frame.size.height, frame.size.width,
                    frame.size.height);
}

@interface FLEWindowSizePlugin ()

/// The view displaying Flutter content.
@property(nonatomic, readonly) NSView *flutterView;

/**
 * Extracts information from |screen| and returns the serializable form expected
 * by the platform channel.
 */
- (NSDictionary *)platformChannelRepresentationForScreen:(NSScreen *)screen;

/**
 * Extracts information from |window| and returns the serializable form expected
 * by the platform channel.
 */
- (NSDictionary *)platformChannelRepresentationForWindow:(NSWindow *)window;

/**
 * Returns the serializable form of |frame| expected by the platform channel.
 */
- (NSArray *)platformChannelRepresentationForFrame:(NSRect)frame;

@end

/**
 * Converts the channel representation for unconstrained maximum size `-1` to Cocoa's specific maximum size of `FLT_MAX`.
 */
static double MaxDimensionFromChannelRepresentation(double size) {
    return size == -1.0 ? FLT_MAX : size;
}

/**
 * Converts Cocoa's specific maximum size of `FLT_MAX` to channel representation for unconstrained maximum size `-1`.
 */
static double ChannelRepresentationForMaxDimension(double size) {
    return size == FLT_MAX ? -1 : size;
}

@implementation FLEWindowSizePlugin {
  // The channel used to communicate with Flutter.
  FlutterMethodChannel *_channel;

  // A reference to the registrar holding the NSView used by the plugin. Holding a reference
  // since the view might be nil at the time the plugin is created.
  id<FlutterPluginRegistrar> _registrar;
}

- (NSView *)flutterView {
  return _registrar.view;
}

+ (void)registerWithRegistrar:(id<FlutterPluginRegistrar>)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:kChannelName
                                                              binaryMessenger:registrar.messenger];
  FLEWindowSizePlugin *instance = [[FLEWindowSizePlugin alloc] initWithChannel:channel
                                                                     registrar:registrar];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithChannel:(FlutterMethodChannel *)channel
                      registrar:(id<FlutterPluginRegistrar>)registrar {
  self = [super init];
  if (self) {
    _channel = channel;
    _registrar = registrar;
  }
  return self;
}

/**
 * Handles platform messages generated by the Flutter framework on the platform channel.
 */
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  id methodResult = nil;
  if ([call.method isEqualToString:kGetScreenListMethod]) {
    NSMutableArray<NSDictionary *> *screenList =
        [NSMutableArray arrayWithCapacity:[NSScreen screens].count];
    for (NSScreen *screen in [NSScreen screens]) {
      [screenList addObject:[self platformChannelRepresentationForScreen:screen]];
    }
    methodResult = screenList;
  } else if ([call.method isEqualToString:kGetWindowInfoMethod]) {
    methodResult = [self platformChannelRepresentationForWindow:self.flutterView.window];
  } else if ([call.method isEqualToString:kSetWindowFrameMethod]) {
    NSArray<NSNumber *> *arguments = call.arguments;
    [self.flutterView.window
        setFrame:GetFlippedRect(NSMakeRect(arguments[0].doubleValue, arguments[1].doubleValue,
                                           arguments[2].doubleValue, arguments[3].doubleValue))
         display:YES];
    methodResult = nil;
  } else if ([call.method isEqualToString:kSetWindowMinimumSizeMethod]) {
    NSArray<NSNumber *> *arguments = call.arguments;
    self.flutterView.window.minSize =
      NSMakeSize(arguments[0].doubleValue, arguments[1].doubleValue);
    methodResult = nil;
  } else if ([call.method isEqualToString:kSetWindowMaximumSizeMethod]) {
    NSArray<NSNumber *> *arguments = call.arguments;
    self.flutterView.window.maxSize =
      NSMakeSize(MaxDimensionFromChannelRepresentation(arguments[0].doubleValue),
                 MaxDimensionFromChannelRepresentation(arguments[1].doubleValue));
    methodResult = nil;
  } else if ([call.method isEqualToString:kGetWindowMinimumSizeMethod]) {
    NSSize size = self.flutterView.window.minSize;
    methodResult = @[ @(size.width), @(size.height) ];
  } else if ([call.method isEqualToString:kGetWindowMaximumSizeMethod]) {
    NSSize size = self.flutterView.window.maxSize;
    methodResult =  @[
                              @(ChannelRepresentationForMaxDimension(size.width)),
                              @(ChannelRepresentationForMaxDimension(size.height)) ];
  } else if ([call.method isEqualToString:kSetWindowTitleMethod]) {
    NSString *title = call.arguments;
    self.flutterView.window.title = title;
    methodResult = nil;
  } else if ([call.method isEqualToString:kSetWindowTitleRepresentedUrlMethod]) {
    NSURL *representedURL = [NSURL URLWithString:call.arguments];
    self.flutterView.window.representedURL = representedURL;
    methodResult = nil;
  } else if ([call.method isEqualToString:kSetWindowVisibilityMethod]) {
    bool visible = [call.arguments boolValue];
    if (visible) {
      [self.flutterView.window makeKeyAndOrderFront:self];
    } else {
      [self.flutterView.window orderOut:self];
    }
    methodResult = nil;
  } else {
    methodResult = FlutterMethodNotImplemented;
  }
  result(methodResult);
}

#pragma mark - Private methods

- (NSDictionary *)platformChannelRepresentationForScreen:(NSScreen *)screen {
  return @{
    kFrameKey : [self platformChannelRepresentationForFrame:GetFlippedRect(screen.frame)],
    kVisibleFrameKey :
        [self platformChannelRepresentationForFrame:GetFlippedRect(screen.visibleFrame)],
    kScaleFactorKey : @(screen.backingScaleFactor),
  };
}

- (NSDictionary *)platformChannelRepresentationForWindow:(NSWindow *)window {
  return @{
    kFrameKey : [self platformChannelRepresentationForFrame:GetFlippedRect(window.frame)],
    kScreenKey : [self platformChannelRepresentationForScreen:window.screen],
    kScaleFactorKey : @(window.backingScaleFactor),
  };
}

- (NSArray *)platformChannelRepresentationForFrame:(NSRect)frame {
  return @[ @(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height) ];
}

@end
