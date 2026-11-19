#import <UIKit/UIKit.h>

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
+ (NSString *)newConnectionCode:(NSError **)error;
- (BOOL)saveFixedCode:(NSString *)code error:(NSError **)error;
- (void)setFixedCodeEnabled:(BOOL)enabled;
@property (nonatomic, copy) void (^changed)(void);
+ (NSArray<NSDictionary *> *)interfaces;
- (void)startAddress:(NSString *)address port:(NSUInteger)port;
- (void)stop;
@end

UIViewController *DXBuildHome(void);
