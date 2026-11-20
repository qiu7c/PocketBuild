#import "BuildBackground.h"
#import <AVFAudio/AVAudioPlayer.h>
#import <AVFAudio/AVAudioSession.h>
#import <UIKit/UIKit.h>

NSNotificationName const PBBackgroundBuildChanged = @"PocketBuild.BackgroundBuildChanged";
static NSString *const AudioPreference = @"PocketBuildBackgroundAudio";

@interface PBBackgroundBuild : NSObject
@property AVAudioPlayer *player;
@property BOOL active;
@property BOOL sessionActive;
@property UIBackgroundTaskIdentifier systemTask;
@property NSString *error;
@end

@implementation PBBackgroundBuild
- (instancetype)init {
    if ((self = [super init])) {
        _systemTask = UIBackgroundTaskInvalid;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:)
            name:AVAudioSessionInterruptionNotification object:nil];
    }
    return self;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self resumeIfNeeded];
}

- (void)endSystemTask {
    if (self.systemTask == UIBackgroundTaskInvalid) return;
    [UIApplication.sharedApplication endBackgroundTask:self.systemTask];
    self.systemTask = UIBackgroundTaskInvalid;
}

- (void)stopAudio {
    [self.player stop];
    self.player = nil;
    if (self.sessionActive) {
        [AVAudioSession.sharedInstance setActive:NO
            withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        self.sessionActive = NO;
    }
}

- (void)resumeIfNeeded {
    if (!self.active || !PBBackgroundAudioEnabled() || self.player.isPlaying) return;
    NSError *error = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    BOOL configured = [session setCategory:AVAudioSessionCategoryPlayback
        withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    self.sessionActive = configured && [session setActive:YES error:&error];
    if (self.sessionActive) {
        // One second of mono PCM silence. Generate the WAV in memory.
        const uint8_t header[] = {'R','I','F','F',0xa4,0x3e,0,0,'W','A','V','E',
            'f','m','t',' ',16,0,0,0,1,0,1,0,0x40,0x1f,0,0,0x80,0x3e,0,0,2,0,16,0,
            'd','a','t','a',0x80,0x3e,0,0};
        NSMutableData *wave = [NSMutableData dataWithLength:sizeof(header) + 16000];
        [wave replaceBytesInRange:NSMakeRange(0, sizeof(header)) withBytes:header];
        self.player = [[AVAudioPlayer alloc] initWithData:wave error:&error];
        self.player.numberOfLoops = -1;
    }
    if (![self.player play]) {
        self.error = error.localizedDescription ?: @"音频会话未能启动";
        [self stopAudio];
    } else {
        self.error = nil;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:PBBackgroundBuildChanged object:nil];
}

- (void)interrupted:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.active || !PBBackgroundAudioEnabled()) return;
        if ([info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
            self.sessionActive = NO;
            self.player = nil;
            self.error = @"音频会话已中断";
            [NSNotificationCenter.defaultCenter postNotificationName:PBBackgroundBuildChanged object:nil];
        } else if ([info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) {
            [self resumeIfNeeded];
        }
    });
}
@end

static PBBackgroundBuild *BackgroundBuild(void) {
    static PBBackgroundBuild *owner;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ owner = [PBBackgroundBuild new]; });
    return owner;
}

BOOL PBBackgroundAudioEnabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:AudioPreference];
}

void PBSetBackgroundAudioEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:AudioPreference];
    PBBackgroundBuild *owner = BackgroundBuild();
    owner.error = nil;
    if (enabled) [owner resumeIfNeeded];
    else [owner stopAudio];
    [NSNotificationCenter.defaultCenter postNotificationName:PBBackgroundBuildChanged object:nil];
}

BOOL PBBackgroundAudioPlaying(void) { return BackgroundBuild().player.isPlaying; }
NSString *PBBackgroundAudioError(void) { return BackgroundBuild().error; }

void PBSetBackgroundBuildActive(BOOL active) {
    PBBackgroundBuild *owner = BackgroundBuild();
    owner.active = active;
    owner.error = nil;
    if (active) {
        owner.systemTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"PocketBuild"
            expirationHandler:^{ [owner endSystemTask]; }];
        [owner resumeIfNeeded];
    } else {
        [owner stopAudio];
        [owner endSystemTask];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:PBBackgroundBuildChanged object:nil];
}
