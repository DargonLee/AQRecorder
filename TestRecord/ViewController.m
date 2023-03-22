//
//  ViewController.m
//  TestRecord
//
//  Created by Harlan on 2023/3/18.
//

#import "ViewController.h"
#import "AQRecorder.h"
#import "AQPlayer.h"
#import "SCSiriWaveformView.h"
#import <mach/mach_time.h>

double MachTimeToSecs(uint64_t time)
{
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    return (double)time * (double)timebase.numer /
    (double)timebase.denom / NSEC_PER_SEC;
}

#define kCodeTimeBegin uint64_t begin = mach_absolute_time()

#define kCodeTimeEnd uint64_t end = mach_absolute_time(); \
NSLog(@"Time taken to doSomething %g s", MachTimeToSecs(end - begin));
/*
 - (void)profileDoSomething
 {
     uint64_t begin = mach_absolute_time();
     [self doSomething];
     uint64_t end = mach_absolute_time();
     NSLog(@"Time taken to doSomething %g s",
     MachTimeToSecs(end - begin));
 }
 */

@interface ViewController ()

@property (weak, nonatomic) IBOutlet SCSiriWaveformView *waveView;
@property(nonatomic, strong)AQRecorder *recorder;
@property(nonatomic, strong)AQPlayer *player;
@property (nonatomic, strong) CADisplayLink *displaylink;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    kCodeTimeBegin;
    // Do any additional setup after loading the view.
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"caf"]];
    NSLog(@"----- %@", filePath);
    // 录音
    self.recorder = [[AQRecorder alloc] initAudioFilePath:filePath audioFormatType:AudioFormatLinearPCM];
    
    // 播放
    NSString *filePath1 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"701100889296.caf"];
    self.player = [[AQPlayer alloc] initAudioFilePath:filePath1];
    
    // 定时器读取音频的分贝值
    _displaylink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMeters)];
    _displaylink.preferredFramesPerSecond = 1;
    [_displaylink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    
    // 分贝图
    [self.waveView setWaveColor:[UIColor redColor]];
    [self.waveView setPrimaryWaveLineWidth:3.0f];
    [self.waveView setSecondaryWaveLineWidth:1.0];
    
    kCodeTimeEnd;
}

- (IBAction)begin:(id)sender
{
    [self.recorder startRecord];
}
- (IBAction)pause:(id)sender
{
    [self.recorder pauseRecord];
}
- (IBAction)stop:(id)sender
{
    [self.recorder stopRecord];
    // self.recorder = nil;
}
- (IBAction)startPlay:(id)sender
{
    [self.player startPlayer];
}
- (IBAction)pausePlay:(id)sender
{
    [self.player pausePlayer];
}
- (IBAction)stopPlay:(id)sender
{
    [self.player stopPlayer];
}


- (void)updateMeters
{
//    CGFloat metersValue = [self.player getCurrentLevelMeter];
    CGFloat metersValue = [self.recorder getCurrentLevelMeter];
//    NSLog(@"metersValue -> %f", metersValue);
    CGFloat normalizedValue = [self normalizedPowerLevelFromDecibels:metersValue];
    NSLog(@"normalizedValue -> %f", normalizedValue);
    [self.waveView updateWithLevel:normalizedValue];
}

- (CGFloat)normalizedPowerLevelFromDecibels:(CGFloat)decibels
{
    if (decibels < -60.0f || decibels == 0.0f) {
        return 0.0f;
    }
    CGFloat value = powf((powf(10.0f, 0.05f * decibels) - powf(10.0f, 0.05f * -60.0f)) * (1.0f / (1.0f - powf(10.0f, 0.05f * -60.0f))), 1.0f / 2.0f);
    return value;
}

@end
