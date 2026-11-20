#import <Foundation/Foundation.h>

extern NSNotificationName const PBBackgroundBuildChanged;
BOOL PBBackgroundAudioEnabled(void);
void PBSetBackgroundAudioEnabled(BOOL enabled);
BOOL PBBackgroundAudioPlaying(void);
NSString *PBBackgroundAudioError(void);
void PBSetBackgroundBuildActive(BOOL active);
