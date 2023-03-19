//
//  ViewController.m
//  TestRecord
//
//  Created by Harlan on 2023/3/18.
//

#import "ViewController.h"
#import "AQRecorder.h"
#import "AQPlayer.h""
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

@property(nonatomic, strong)AQRecorder *recorder;
@property(nonatomic, strong)AQPlayer *player;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    kCodeTimeBegin;
    // Do any additional setup after loading the view.
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"caf"]];
    NSLog(@"----- %@", filePath);
    self.recorder = [[AQRecorder alloc] initAudioFilePath:filePath audioFormatType:AudioFormatLinearPCM];
    NSString *filePath1 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"700911886073.caf"];
    self.player = [[AQPlayer alloc] initAudioFilePath:filePath1];
    
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



@end
