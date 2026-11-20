#import "Workspace.h"
#import "Appearance.h"
#import "BuildService.h"
#import "Toolchains.h"
#import "PackagePaths.h"

#import "ProjectRecords.h"

@interface PBStorageController : UIViewController
@property NSArray<UILabel *> *sizes;
@property UILabel *space;
@property NSString *documents;
@property NSString *checkpoints;
@property UIButton *clearCache;
@property UIButton *clearHistory;
@end

@implementation PBStorageController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"存储空间";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    self.checkpoints = [cache stringByAppendingPathComponent:@"DylixBuildCheckpoints"];
    UIStackView *content = PBPageContent(self.view, self.view.bottomAnchor);
    UIStackView *summary = PBCard();
    self.space = PBLabel(@"正在读取可用空间…", 16, UIFontWeightSemibold, UIColor.labelColor);
    [summary addArrangedSubview:self.space];
    [content addArrangedSubview:summary];

    NSArray *names = @[@"项目源码", @"历史构建", @"文件 App 中的产物副本", @"编译缓存", @"已下载组件"];
    NSArray *symbols = @[@"folder", @"hammer", @"doc.on.doc", @"internaldrive", @"shippingbox"];
    NSMutableArray *sizes = [NSMutableArray array];
    for (NSUInteger index = 0; index < names.count; index++) {
        UIStackView *card = PBCard();
        [card addArrangedSubview:PBFeature(symbols[index], names[index], @"")];
        UILabel *size = PBLabel(@"计算中…", 14, UIFontWeightRegular, UIColor.secondaryLabelColor);
        [sizes addObject:size];
        [card addArrangedSubview:size];
        if (index == 1) {
            self.clearHistory = PBButton(@"清除历史构建", @"trash", NO);
            self.clearHistory.enabled = NO;
            [self.clearHistory addTarget:self action:@selector(confirmHistory) forControlEvents:UIControlEventTouchUpInside];
            [card addArrangedSubview:self.clearHistory];
        } else if (index == 3) {
            self.clearCache = PBButton(@"清除编译缓存", @"trash", NO);
            self.clearCache.enabled = NO;
            [self.clearCache addTarget:self action:@selector(removeCache) forControlEvents:UIControlEventTouchUpInside];
            [card addArrangedSubview:self.clearCache];
        } else if (index == 4) {
            UIButton *components = PBButton(@"管理组件", @"shippingbox", NO);
            [components addTarget:self action:@selector(manageComponents) forControlEvents:UIControlEventTouchUpInside];
            [card addArrangedSubview:components];
        }
        [content addArrangedSubview:card];
    }
    self.sizes = sizes;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    NSString *documents = self.documents;
    NSString *checkpoints = self.checkpoints;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *paths = @[@[[documents stringByAppendingPathComponent:@"Projects"]],
            PBStoredBuildDirectories(), @[[documents stringByAppendingPathComponent:@"构建产物"]],
            @[checkpoints], @[PBPackagesDirectory()]];
        NSMutableArray *bytes = [NSMutableArray array];
        for (NSArray *pathsForCategory in paths) [bytes addObject:@(PBAllocatedBytes(pathsForCategory))];
        NSNumber *available = nil;
        [[NSURL fileURLWithPath:documents] getResourceValue:&available
            forKey:NSURLVolumeAvailableCapacityForImportantUsageKey error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *(^format)(NSNumber *) = ^NSString *(NSNumber *number) {
                return [NSByteCountFormatter stringFromByteCount:number.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
            };
            weak.space.text = available ? [@"设备可用 " stringByAppendingString:format(available)] : @"设备可用空间暂不可用";
            [weak.sizes enumerateObjectsUsingBlock:^(UILabel *label, NSUInteger index, BOOL *stop) {
                label.text = format(bytes[index]);
            }];
            weak.clearHistory.enabled = [bytes[1] longLongValue] > 0;
            weak.clearCache.enabled = [bytes[3] longLongValue] > 0;
        });
    });
}

- (void)manageComponents {
    if (!PBOpenComponents(self)) [self.navigationController pushViewController:PBToolsHome() animated:YES];
}

- (void)removeCache {
    if (PBToolchains.shared.buildRunning) {
        PBShowError(self, @"请等待当前构建结束。");
        return;
    }
    NSError *error = nil;
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:self.checkpoints] && ![files removeItemAtPath:self.checkpoints error:&error]) {
        PBShowError(self, error.localizedDescription);
    } else {
        PBToast(self, @"编译缓存已清除");
    }
    [self refresh];
}

- (void)confirmHistory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清除历史构建？"
        message:@"将删除构建记录、日志和内部产物。通过文件 App 或分享保存的副本会保留。"
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weak removeHistory];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)removeHistory {
    if (PBToolchains.shared.buildRunning) {
        PBShowError(self, @"请等待当前构建结束。");
        return;
    }
    NSMutableArray *removed = [NSMutableArray array];
    NSError *error = nil;
    for (NSString *path in PBStoredBuildDirectories()) {
        if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) break;
        [removed addObject:path];
    }
    [DXBuildService.shared discardBuildRecordsAtPaths:removed];
    [self refresh];
    if (error) PBShowError(self, error.localizedDescription);
    else PBToast(self, @"历史构建已清除");
}
@end

UIViewController *PBStoragePage(void) { return [PBStorageController new]; }
