#import <Foundation/Foundation.h>

NSString *PBDocumentsDirectory(void);
NSArray<NSString *> *PBStoredBuildDirectories(void);
NSDictionary *PBReadBuildJob(NSString *directory);
BOOL PBWriteBuildJob(NSDictionary *job, NSError **error);
NSArray<NSString *> *PBBuildArtifacts(NSString *directory);
NSArray<NSString *> *PBProductFiles(NSArray<NSString *> *files);
NSDictionary *PBBuildIssue(NSString *directory);
NSArray<NSDictionary *> *PBJobsToClean(NSArray<NSDictionary *> *jobs);
unsigned long long PBAllocatedBytes(NSArray<NSString *> *paths);
NSString *PBBuildStateTitle(NSString *state);
NSRange PBSourceLocation(NSString *text, NSUInteger line, NSUInteger byteColumn);
