//
//  AQPlayer.h
//  TestRecord
//
//  Created by Harlan on 2023/3/19.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AQPlayer : NSObject
/// 当前播放的分贝值
@property (nonatomic, copy) void (^normalizedValueBlock)(CGFloat value);
/// 是否正在播放
@property(nonatomic, assign, readonly) BOOL isPlaying;
@property(nonatomic, getter=isMeteringEnabled) BOOL meteringEnabled;

- (instancetype)initAudioFilePath:(NSString *_Nonnull)path;

- (void)startPlayer;

- (void)pausePlayer;

- (void)stopPlayer;

- (float)mPeakPowerValue;

@end

NS_ASSUME_NONNULL_END
