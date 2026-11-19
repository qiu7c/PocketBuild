#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSNotificationName const PBPackagesChanged;

@interface PBToolchains : NSObject <NSURLSessionDownloadDelegate>
+ (instancetype)shared;
+ (NSArray<NSString *> *)requiredPackagesForSDK:(NSString *)sdk usesCXX:(BOOL)usesCXX;
@property (nonatomic, readonly) NSArray<NSDictionary *> *catalog;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic) BOOL buildRunning;
@property (nonatomic, readonly) double progress;
@property (nonatomic, readonly) NSString *message;
- (BOOL)loadManifest:(NSURL *)url;
- (void)useDefaultSource;
@property (nonatomic, readonly) BOOL usingCustomSource;
- (void)install:(NSString *)identifier;
- (void)installPackages:(NSArray<NSString *> *)identifiers;
- (void)cancel;
- (BOOL)remove:(NSString *)identifier error:(NSError **)error;
- (NSDictionary *)status;
- (BOOL)loadCompiler:(NSError **)error;
@end

UIViewController *PBToolsHome(void);
