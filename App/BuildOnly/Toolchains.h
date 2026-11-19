#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSNotificationName const PBPackagesChanged;

@interface PBToolchains : NSObject <NSURLSessionDownloadDelegate>
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<NSDictionary *> *catalog;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic) BOOL buildRunning;
@property (nonatomic, readonly) double progress;
@property (nonatomic, readonly) NSString *message;
- (BOOL)loadManifest:(NSURL *)url;
- (void)install:(NSString *)identifier;
- (void)cancel;
- (BOOL)remove:(NSString *)identifier error:(NSError **)error;
- (NSDictionary *)status;
- (BOOL)loadCompiler:(NSError **)error;
@end

UIViewController *PBToolsHome(void);
