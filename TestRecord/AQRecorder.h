//
//  AQRecorderManager.h
//  TestRecord
//
//  Created by Harlan on 2023/3/18.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AudioFormatType)
{
    AudioFormatLinearPCM,
    AudioFormatMPEG4AAC,
};

@interface AQRecorder : NSObject
/// 当前录音的分贝值
@property (nonatomic, copy) void(^normalizedValueBlock)(CGFloat value);
/// 是否正在录制
@property(nonatomic, assign, readonly) BOOL isRecording;

- (instancetype)initAudioFilePath:(NSString *_Nonnull)path audioFormatType:(AudioFormatType)type;

- (void)startRecord;

- (void)pauseRecord;

- (void)stopRecord;

- (CGFloat)getCurrentLevelMeter;

@end

NS_ASSUME_NONNULL_END
