//
//  AQPlayer.h
//  TestRecord
//
//  Created by Harlan on 2023/3/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AQPlayer : NSObject
/// normalizedValue
@property (nonatomic, copy) void(^normalizedValueBlock)(CGFloat value);
- (instancetype)initAudioFilePath:(NSString *_Nonnull)path;

- (void)startPlayer;

- (void)pausePlayer;

- (void)stopPlayer;

@end

NS_ASSUME_NONNULL_END
