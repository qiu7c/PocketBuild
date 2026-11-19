#import <UIKit/UIKit.h>

@interface DXBuildService : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSString *state;
@property (nonatomic, readonly) NSString *origin;
@property (nonatomic, readonly) NSString *code;
@property (nonatomic, copy) void (^changed)(void);
+ (NSArray<NSDictionary *> *)interfaces;
- (void)startAddress:(NSString *)address port:(NSUInteger)port;
- (void)stop;
@end

UIViewController *DXBuildHome(void);
