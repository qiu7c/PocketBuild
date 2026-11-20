#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSNotificationName const PBTrialChanged;
FOUNDATION_EXPORT NSNotificationName const PBBuildChanged;
FOUNDATION_EXPORT NSNotificationName const PBConnectionChanged;

@interface DXBuildService : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSString *state;
@property (nonatomic, readonly) NSString *origin;
@property (nonatomic, readonly) NSString *code;
@property (nonatomic, readonly) BOOL fixedCodeEnabled;
@property (nonatomic, readonly) BOOL activeCodeIsFixed;
@property (nonatomic, readonly) NSString *fixedCode;
@property (nonatomic, readonly) NSDate *startedAt;
@property (nonatomic, readonly) NSDate *lastRequestAt;
@property (nonatomic, readonly) NSUInteger requestCount;
@property (nonatomic, readonly) NSDictionary *latestJob;
@property (nonatomic, readonly) NSDictionary *connectionDiagnostics;
- (NSArray<NSDictionary *> *)projectList;
- (NSArray<NSDictionary *> *)recordedBuilds;
- (NSDictionary *)recordedBuild:(NSString *)identifier;
- (NSDictionary *)projectDetails:(NSString *)identifier;
- (NSArray<NSString *> *)sourceFilesForProject:(NSString *)identifier;
- (NSString *)sourceForProject:(NSString *)identifier path:(NSString *)path error:(NSError **)error;
- (BOOL)saveSource:(NSString *)text forProject:(NSString *)identifier path:(NSString *)path
            expected:(NSString *)original error:(NSError **)error;
- (NSDictionary *)diagnosticSourceForBuild:(NSString *)identifier error:(NSError **)error;
- (NSDictionary *)startProjectBuild:(NSString *)identifier error:(NSError **)error;
- (BOOL)renameProject:(NSString *)identifier name:(NSString *)name error:(NSError **)error;
- (BOOL)deleteProject:(NSString *)identifier error:(NSError **)error;
- (BOOL)deleteBuild:(NSString *)identifier error:(NSError **)error;
- (BOOL)assignBuild:(NSString *)buildID toProject:(NSString *)identifier error:(NSError **)error;
- (BOOL)cleanOldBuildsForProject:(NSString *)identifier error:(NSError **)error;
@property (nonatomic, readonly) BOOL trialRunning;
@property (nonatomic, readonly) double trialProgress;
@property (nonatomic, readonly) NSString *trialMessage;
- (BOOL)runTrialWithSDK:(NSString *)sdk usesCXX:(BOOL)usesCXX error:(NSError **)error;
- (void)cancelTrial;
- (void)cancelBuild;
- (void)discardBuildRecordsAtPaths:(NSArray<NSString *> *)paths;
+ (NSString *)newConnectionCode:(NSError **)error;
- (BOOL)saveFixedCode:(NSString *)code error:(NSError **)error;
- (void)setFixedCodeEnabled:(BOOL)enabled;
@property (nonatomic, copy) void (^changed)(void);
+ (NSArray<NSDictionary *> *)interfaces;
- (void)startAddress:(NSString *)address port:(NSUInteger)port;
- (void)stop;
@end

UIViewController *DXBuildHome(void);
