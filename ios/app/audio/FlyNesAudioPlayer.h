#import <Foundation/Foundation.h>
@class AVAudioEngine;

NS_ASSUME_NONNULL_BEGIN
// Main-thread owner. Audio completion handlers never call the emulator.
@interface FlyNesAudioPlayer : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) NSUInteger focusPolicy;
- (instancetype)initWithEngine:(AVAudioEngine *)engine;
- (BOOL)start:(NSError * _Nullable * _Nullable)error;
- (void)pause;
- (void)flush;
- (void)enqueuePCM:(NSData *)samples;
@end
NS_ASSUME_NONNULL_END
