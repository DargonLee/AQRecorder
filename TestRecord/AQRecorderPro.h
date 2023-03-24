//
//  AQRecorderPro.h
//  TestRecord
//
//  Created by Harlans on 2023/3/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AQRecorderPro : NSObject

/// 当前录音的分贝值
@property (nonatomic, copy) void(^currentLevelMeterDBValueBlock)(double value);
/// 是否正在录制
@property(nonatomic, assign, readonly) BOOL isRecording;
@property(nonatomic, getter=isMeteringEnabled) BOOL meteringEnabled;

- (instancetype)initAudioFilePath:(NSString *_Nonnull)path;

- (void)setAudioSampleRate:(Float64)sampleRate channels:(UInt32)channels bitsPerChannel:(UInt32)bitsPerChannel;

- (void)startRecord;

- (void)stopRecord;

- (float)peakPowerMeter;

@end

NS_ASSUME_NONNULL_END
