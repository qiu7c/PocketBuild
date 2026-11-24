#import "BuildService.h"
#import "Toolchains.h"
#import "Appearance.h"
#import "ConnectionSettings.h"
#import "Workspace.h"
#import "ProjectRecords.h"

@interface DXBuildHomeController : UIViewController
@property UILabel *serviceStatus, *serviceTitle, *serviceDetail, *networkLabel;
@property UILabel *addressLabel, *codeLabel, *codeKind, *jobTitle, *jobDetail, *readiness;
@property UIStackView *connection, *credentialActions, *serviceActions;
@property UIButton *startButton, *stopButton, *refreshButton, *connectionHelp, *jobAction;
@property UIProgressView *jobProgress;
@property UIView *statusDot;
@property NSString *address;
@property NSUInteger port;
@end

@implementation DXBuildHomeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PocketBuild";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]
        style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"连接设置";
    UIStackView *content = PBPageContent(self.view, nil);

    UIStackView *service = PBCard();
    UIStackView *status = [UIStackView new];
    status.axis = UILayoutConstraintAxisHorizontal;
    status.alignment = UIStackViewAlignmentCenter;
    status.spacing = 8;
    self.statusDot = [UIView new];
    self.statusDot.layer.cornerRadius = 3;
    [NSLayoutConstraint activateConstraints:@[
        [self.statusDot.widthAnchor constraintEqualToConstant:6],
        [self.statusDot.heightAnchor constraintEqualToConstant:6]
    ]];
    self.serviceStatus = PBLabel(@"局域网服务", 12, UIFontWeightMedium, UIColor.secondaryLabelColor);
    [status addArrangedSubview:self.statusDot];
    [status addArrangedSubview:self.serviceStatus];
    [service addArrangedSubview:status];
    self.serviceTitle = PBLabel(@"连接电脑", 20, UIFontWeightSemibold, UIColor.labelColor);
    self.serviceDetail = PBLabel(@"", 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [service addArrangedSubview:self.serviceTitle];
    [service setCustomSpacing:5 afterView:self.serviceTitle];
    [service addArrangedSubview:self.serviceDetail];

    self.connection = [UIStackView new];
    self.connection.axis = UILayoutConstraintAxisVertical;
    self.connection.spacing = 6;
    [self.connection addArrangedSubview:PBLabel(@"访问地址", 12, UIFontWeightSemibold, UIColor.secondaryLabelColor)];
    self.addressLabel = PBLabel(@"", 15, UIFontWeightMedium, UIColor.labelColor);
    self.addressLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium]];
    self.addressLabel.lineBreakMode = NSLineBreakByCharWrapping;
    [self.connection addArrangedSubview:self.addressLabel];
    [self.connection setCustomSpacing:12 afterView:self.addressLabel];
    self.codeKind = PBLabel(@"连接码", 12, UIFontWeightSemibold, UIColor.secondaryLabelColor);
    [self.connection addArrangedSubview:self.codeKind];
    self.codeLabel = PBLabel(@"", 14, UIFontWeightMedium, UIColor.labelColor);
    self.codeLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium]];
    self.codeLabel.lineBreakMode = NSLineBreakByCharWrapping;
    [self.connection addArrangedSubview:self.codeLabel];
    [service addArrangedSubview:self.connection];

    self.credentialActions = [UIStackView new];
    self.credentialActions.axis = UILayoutConstraintAxisHorizontal;
    self.credentialActions.distribution = UIStackViewDistributionFillEqually;
    self.credentialActions.spacing = 8;
    UIButton *address = PBButton(@"复制地址", @"doc.on.doc", NO);
    [address addTarget:self action:@selector(copyURL) forControlEvents:UIControlEventTouchUpInside];
    UIButton *credentials = PBButton(@"复制连接", @"link", NO);
    credentials.accessibilityLabel = @"复制访问地址与连接码";
    [credentials addTarget:self action:@selector(copyConnection) forControlEvents:UIControlEventTouchUpInside];
    [self.credentialActions addArrangedSubview:address];
    [self.credentialActions addArrangedSubview:credentials];
    [service addArrangedSubview:self.credentialActions];

    self.networkLabel = PBLabel(@"", 13, UIFontWeightMedium, UIColor.secondaryLabelColor);
    [service addArrangedSubview:self.networkLabel];
    self.startButton = PBButton(@"启动服务", @"play.fill", YES);
    [self.startButton addTarget:self action:@selector(toggleService) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton = PBButton(@"停止服务", @"stop.fill", NO);
    [self.stopButton addTarget:self action:@selector(toggleService) forControlEvents:UIControlEventTouchUpInside];
    self.serviceActions = [UIStackView new];
    self.serviceActions.spacing = 8;
    self.refreshButton = PBButton(@"刷新地址", @"arrow.clockwise", NO);
    [self.refreshButton addTarget:self action:@selector(refreshAddress) forControlEvents:UIControlEventTouchUpInside];
    [self.serviceActions addArrangedSubview:self.startButton];
    [self.serviceActions addArrangedSubview:self.refreshButton];
    [self.serviceActions addArrangedSubview:self.stopButton];
    [service addArrangedSubview:self.serviceActions];
    self.connectionHelp = PBLinkButton(@"连接诊断", @"stethoscope");
    [self.connectionHelp addTarget:self action:@selector(diagnostics) forControlEvents:UIControlEventTouchUpInside];
    [service addArrangedSubview:self.connectionHelp];
    UIButton *guide = PBLinkButton(@"连接指南", @"book.closed");
    [guide addTarget:self action:@selector(guide) forControlEvents:UIControlEventTouchUpInside];
    [service addArrangedSubview:guide];
    [content addArrangedSubview:service];

    UIStackView *job = PBCard();
    [job addArrangedSubview:PBLabel(@"最近构建", 12, UIFontWeightMedium, UIColor.secondaryLabelColor)];
    self.jobTitle = PBLabel(@"暂无构建记录", 16, UIFontWeightSemibold, UIColor.labelColor);
    self.jobDetail = PBLabel(@"", 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    self.jobProgress = [UIProgressView new];
    self.jobProgress.progressTintColor = PBAccent();
    [job addArrangedSubview:self.jobTitle];
    [job addArrangedSubview:self.jobProgress];
    [job addArrangedSubview:self.jobDetail];
    self.jobAction = PBLinkButton(@"查看构建", @"chevron.right");
    [self.jobAction addTarget:self action:@selector(openJob) forControlEvents:UIControlEventTouchUpInside];
    [job addArrangedSubview:self.jobAction];
    [content addArrangedSubview:job];

    UIStackView *prepare = PBCard();
    [prepare addArrangedSubview:PBLabel(@"构建组件", 15, UIFontWeightMedium, UIColor.labelColor)];
    self.readiness = PBLabel(@"", 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [prepare addArrangedSubview:self.readiness];
    UIButton *tools = PBLinkButton(@"组件与试编译", @"shippingbox");
    [tools addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];
    [prepare addArrangedSubview:tools];
    [content addArrangedSubview:prepare];

    __weak typeof(self) weak = self;
    DXBuildService.shared.changed = ^{ [weak update]; };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update) name:PBPackagesChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update) name:PBBuildChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateConnection) name:PBConnectionChanged object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];self.address=[NSUserDefaults.standardUserDefaults stringForKey:@"BuildAddress"];
    self.port=[NSUserDefaults.standardUserDefaults integerForKey:@"BuildPort"]?:8787;
    if(!self.address.length)self.address=DXBuildService.interfaces.firstObject[@"address"];
    [self update];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded && ![previous.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory]) [self updateConnection];
}
- (void)settings { [self.navigationController pushViewController:PBConnectionSettings() animated:YES]; }
- (void)diagnostics { [self.navigationController pushViewController:PBConnectionDiagnostics() animated:YES]; }
- (void)openJob { [self.navigationController pushViewController:PBBuildResult(DXBuildService.shared.latestJob[@"id"]) animated:YES]; }
- (void)openTools {
    if (!PBOpenComponents(self)) [self.navigationController pushViewController:PBToolsHome() animated:YES];
}
- (void)guide { [self.navigationController pushViewController:PBWelcomeScreen(NO) animated:YES]; }
- (void)refreshAddress {
    if(DXBuildService.shared.origin){PBToast(self,@"停止服务后可以切换地址");return;}
    self.address=DXBuildService.interfaces.firstObject[@"address"];
    if(self.address)[NSUserDefaults.standardUserDefaults setObject:self.address forKey:@"BuildAddress"];
    [self update];PBToast(self,self.address?@"已更新网络地址":@"请先打开热点或连接 Wi-Fi");
}
- (void)toggleService {
    if(DXBuildService.shared.origin){[DXBuildService.shared stop];return;}
    if(!self.address.length){PBShowError(self,@"打开个人热点或连接 Wi-Fi 后刷新地址，也可以在连接设置中手动填写手机 IPv4。");return;}
    [NSUserDefaults.standardUserDefaults setObject:self.address forKey:@"BuildAddress"];
    [DXBuildService.shared startAddress:self.address port:self.port];
}
- (void)copyURL { UIPasteboard.generalPasteboard.string=DXBuildService.shared.origin;PBToast(self,@"访问地址已复制"); }
- (void)copyConnection {
    DXBuildService *s=DXBuildService.shared;UIPasteboard.generalPasteboard.string=[NSString stringWithFormat:@"访问地址：%@\n连接码：%@",s.origin,s.code];PBToast(self,@"地址与连接码已复制");
}
- (void)updateConnection {
    DXBuildService *service = DXBuildService.shared;
    NSDictionary *connection = service.connectionDiagnostics;
    BOOL active = service.origin.length > 0;
    BOOL running = [service.state isEqual:@"运行中"];
    BOOL failed = !active && ![service.state isEqual:@"已停止"];
    double accepted = [connection[@"authorizedAt"] doubleValue];
    BOOL rejected = [connection[@"rejectedAt"] doubleValue] > accepted;
    BOOL reached = [connection[@"httpAt"] doubleValue] > 0;
    self.serviceStatus.text = running ? (rejected ? @"连接码验证失败" : accepted ? @"已通过连接码验证" :
        reached ? @"等待验证连接码" : @"等待电脑访问") : active ? @"局域网服务 · 正在启动" :
        failed ? @"局域网服务 · 启动失败" : @"局域网服务 · 已停止";
    self.statusDot.backgroundColor = running || failed ? PBAccent() : UIColor.tertiaryLabelColor;
    self.serviceTitle.text = running ? (accepted && !rejected ? @"局域网服务已就绪" : @"在电脑打开地址") : @"连接电脑";
    self.serviceDetail.text = running
        ? (rejected ? @"请在电脑端重新输入下面的连接码。" : accepted ? @"电脑端可上传项目、编辑源码和编译。" :
            reached ? @"在浏览器输入连接码，或在 MCP 中验证。" : @"用电脑浏览器打开下面的地址。")
        : active ? @"正在监听手机的局域网地址。" : failed ? service.state : @"让电脑连接手机热点或同一 Wi-Fi，然后启动服务。";

    self.connection.hidden = !running;
    self.credentialActions.hidden = !running;
    self.refreshButton.hidden = active;
    self.startButton.hidden = active;
    self.stopButton.hidden = !active;
    self.connectionHelp.hidden = !running && !failed;
    self.networkLabel.hidden = active;
    self.networkLabel.text = self.address.length ? [NSString stringWithFormat:@"网络地址  %@:%lu", self.address, (unsigned long)self.port] : @"尚未发现局域网地址";
    self.addressLabel.text = service.origin;
    self.codeLabel.text = service.code;
    self.codeKind.text = service.activeCodeIsFixed ? @"连接码（固定）" : @"连接码（随机）";
    BOOL largeText = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    for (UIStackView *row in @[self.credentialActions, self.serviceActions]) {
        row.axis = largeText ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
        row.distribution = largeText ? UIStackViewDistributionFill : UIStackViewDistributionFillEqually;
    }
}

- (void)update {
    [self updateConnection];
    DXBuildService *service = DXBuildService.shared;
    NSDictionary *job = service.latestJob;
    NSString *state = job[@"state"];
    NSString *project = job[@"projectName"];
    BOOL building = [state isEqual:@"running"];
    NSString *status = state ? PBBuildStateTitle(state) : nil;
    self.jobTitle.text = project.length ? project : status ?: @"暂无构建记录";
    self.jobProgress.hidden = !building;
    self.jobProgress.progress = [job[@"progress"] floatValue];
    self.jobAction.hidden = !job[@"id"];
    NSString *detail = building ? (job[@"stage"] ?: @"正在准备编译器…") :
        [state isEqual:@"succeeded"] ? [NSString stringWithFormat:@"%lu 个产物", (unsigned long)PBProductFiles(job[@"artifacts"]).count] :
        state ? (job[@"issue"][@"message"] ?: @"可在「构建」查看日志。") : @"连接电脑后即可导入源码并编译。";
    self.jobDetail.text = project.length && status ? [NSString stringWithFormat:@"%@ · %@", status, detail] : detail;
    self.jobDetail.numberOfLines = 3;

    NSDictionary *installed = PBToolchains.shared.status[@"installed"];
    if (!installed[@"support"]) self.readiness.text = @"先安装构建资源，再按项目选择 SDK。";
    else if (installed[@"sdk16"] && installed[@"sdk26"]) self.readiness.text = @"两套 SDK 已就绪。";
    else if (installed[@"sdk16"]) self.readiness.text = @"iOS 16.4 SDK 已就绪。";
    else if (installed[@"sdk26"]) self.readiness.text = @"iOS 26 SDK 已就绪。编译 C++ 还需 iOS 16.4 SDK。";
    else self.readiness.text = @"构建资源已安装，请按项目选择 SDK。";
}

@end
UIViewController *DXBuildHome(void) { UIViewController *c=[DXBuildHomeController new];c.navigationItem.backButtonDisplayMode=UINavigationItemBackButtonDisplayModeMinimal;return c; }
@interface DXBuildAppDelegate : UIResponder <UIApplicationDelegate,UINavigationControllerDelegate>
@property (strong,nonatomic) UIWindow *window;
@end
@implementation DXBuildAppDelegate
#if TARGET_OS_SIMULATOR
- (void)navigationController:(UINavigationController *)navigation didShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    UIView *page = controller.view;
    NSMutableDictionary *ready = [@{@"controller":NSStringFromClass(controller.class),
        @"width":@(page.bounds.size.width), @"height":@(page.bounds.size.height)} mutableCopy];
    if ([ready[@"controller"] isEqual:@"PBStorageController"]) {
        [page layoutIfNeeded];
        UIView *scroll = page.subviews.firstObject;
        for (UIView *child in scroll.subviews) {
            if (![child isKindOfClass:UIStackView.class]) continue;
            CGRect column = [child convertRect:child.bounds toView:page];
            CGRect viewport = page.safeAreaLayoutGuide.layoutFrame;
            ready[@"contentWidth"] = @(CGRectGetWidth(column));
            ready[@"viewportWidth"] = @(CGRectGetWidth(viewport));
            ready[@"leadingMargin"] = @(CGRectGetMinX(column) - CGRectGetMinX(viewport));
            break;
        }
    }
    [[NSJSONSerialization dataWithJSONObject:ready options:0 error:nil] writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pocketbuild-ui-ready.json"] atomically:YES];
}
#endif
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.tintColor=PBAccent();
    BOOL first=![NSUserDefaults.standardUserDefaults boolForKey:@"PocketBuildWelcomeCompleted"];
    UIViewController *root=first?PBWelcomeScreen(YES):nil;
#if TARGET_OS_SIMULATOR
    NSArray *arguments=NSProcessInfo.processInfo.arguments;NSUInteger screen=[arguments indexOfObject:@"--ui-screen"];
    NSUInteger fixed=[arguments indexOfObject:@"--ui-fixed-code"];
    if(fixed!=NSNotFound&&fixed+1<arguments.count){NSError *error=nil;NSAssert([DXBuildService.shared saveFixedCode:arguments[fixed+1] error:&error],@"%@",error);[DXBuildService.shared setFixedCodeEnabled:YES];}
    if([arguments containsObject:@"--ui-random-code"])[DXBuildService.shared setFixedCodeEnabled:NO];
    if(screen!=NSNotFound&&screen+1<arguments.count) {
        NSString *name=arguments[screen+1];
        if([name isEqual:@"home"]||[name isEqual:@"running"])root=DXBuildHome();
        if([name isEqual:@"guide"])root=PBWelcomeScreen(NO);
        if([name isEqual:@"tools"])root=PBToolsHome();
        if([name isEqual:@"settings"])root=PBConnectionSettings();
        if([name isEqual:@"storage"])root=PBStoragePage();
        if([name isEqual:@"intro"])root=PBWelcomeScreen(YES);
        if([name isEqual:@"resources"]||[name isEqual:@"pairing"]){root=PBWelcomeScreen(YES);[root setValue:@([name isEqual:@"resources"]?2:3) forKey:@"page"];}
        if([name isEqual:@"running"])[DXBuildService.shared startAddress:@"127.0.0.1" port:8787];
    }
    if([arguments containsObject:@"--ui-pairing-check"]) {
        DXBuildService *service=DXBuildService.shared;NSError *error=nil;
        NSAssert(![service saveFixedCode:@"short" error:&error]&&error,@"Short pairing code must be rejected");
        error=nil;NSAssert(![service saveFixedCode:@"中文连接代码1234" error:&error]&&error,@"HTTP credentials must be ASCII");
        error=nil;NSAssert(![service saveFixedCode:@"PocketBuild-Test-Next\n" error:&error]&&error,@"HTTP credentials must not contain newlines");
        NSAssert([service saveFixedCode:@"PocketBuild-Test-Next" error:&error],@"%@",error);
        NSAssert(![service.code isEqual:service.fixedCode],@"Saving preferences must not replace the active code");
    }
    if([arguments containsObject:@"--ui-restart-service"]||[arguments containsObject:@"--ui-pairing-check"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [DXBuildService.shared stop];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.25*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [DXBuildService.shared startAddress:@"127.0.0.1" port:8787];
                if([arguments containsObject:@"--ui-pairing-check"])NSAssert([DXBuildService.shared.code isEqual:@"PocketBuild-Test-Next"],@"Restart must activate the saved code");
            });
        });
    }
#endif
    if (!root) {
        self.window.rootViewController = PBWorkspace();
        [self.window makeKeyAndVisible];
        return YES;
    }
    UINavigationController *navigation = PBNavigation(root);
#if TARGET_OS_SIMULATOR
    if(screen!=NSNotFound&&screen+1<arguments.count&&[@[@"settings",@"tools",@"guide",@"storage"] containsObject:arguments[screen+1]])[navigation setViewControllers:@[DXBuildHome(),root] animated:NO];
    navigation.delegate=self;
#endif
    self.window.rootViewController=navigation;[self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char *argv[]) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(DXBuildAppDelegate.class)); } }
