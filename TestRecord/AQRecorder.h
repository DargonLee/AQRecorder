//
//  AQRecorderManager.h
//  TestRecord
//
//  Created by Harlan on 2023/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AudioFormatType)
{
    AudioFormatLinearPCM,
    AudioFormatMPEG4AAC,
};

@interface AQRecorder : NSObject

@property(nonatomic, assign) BOOL isRecording;

- (instancetype)initAudioFilePath:(NSString *_Nonnull)path audioFormatType:(AudioFormatType)type;

- (void)startRecord;

- (void)pauseRecord;

- (void)stopRecord;

@end

NS_ASSUME_NONNULL_END
