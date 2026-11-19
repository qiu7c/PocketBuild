#import "BuildService.h"
#import "Toolchains.h"
#import "Appearance.h"
#import "ConnectionSettings.h"

@interface DXBuildHomeController : UIViewController
@property UILabel *heroTitle, *heroDetail, *statusBadge, *uptime, *requests, *components;
@property UILabel *addressLabel, *codeLabel, *codeKind, *networkLabel, *jobTitle, *jobDetail, *readiness;
@property UIButton *toggle, *addressButton, *connectionButton;
@property UIProgressView *jobProgress;
@property UIView *statusDot;
@property NSTimer *timer;
@property NSString *address;
@property NSUInteger port;
@end
@implementation DXBuildHomeController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"PocketBuild";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"] style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"连接设置";
    UIStackView *content=PBPageContent(self.view,self.view.bottomAnchor);
    [content addArrangedSubview:PBLabel(@"本机编译，电脑协作。",15,UIFontWeightMedium,UIColor.secondaryLabelColor)];
    UIStackView *hero=PBCard();hero.backgroundColor=[UIColor colorWithRed:.09 green:.10 blue:.115 alpha:1];hero.spacing=18;
    UIStackView *badgeRow=[UIStackView new];badgeRow.axis=UILayoutConstraintAxisHorizontal;badgeRow.spacing=8;badgeRow.alignment=UIStackViewAlignmentCenter;
    self.statusDot=[UIView new];self.statusDot.backgroundColor=PBAccent();self.statusDot.layer.cornerRadius=4;
    [self.statusDot.widthAnchor constraintEqualToConstant:8].active=YES;[self.statusDot.heightAnchor constraintEqualToConstant:8].active=YES;
    self.statusBadge=PBLabel(@"未开启",12,UIFontWeightSemibold,[UIColor.whiteColor colorWithAlphaComponent:.7]);
    [badgeRow addArrangedSubview:self.statusDot];[badgeRow addArrangedSubview:self.statusBadge];[badgeRow addArrangedSubview:[UIView new]];[hero addArrangedSubview:badgeRow];
    self.heroTitle=PBLabel(@"准备好开始了吗",27,UIFontWeightBold,UIColor.whiteColor);self.heroDetail=PBLabel(@"",14,UIFontWeightRegular,[UIColor.whiteColor colorWithAlphaComponent:.62]);
    [hero addArrangedSubview:self.heroTitle];[hero addArrangedSubview:self.heroDetail];
    UIStackView *metrics=[UIStackView new];metrics.axis=UILayoutConstraintAxisHorizontal;metrics.distribution=UIStackViewDistributionFillEqually;metrics.spacing=10;
    NSMutableArray *values=[NSMutableArray array];
    for(NSString *caption in @[@"运行时长",@"认证请求",@"已装组件"]) {
        UIStackView *metric=[UIStackView new];metric.axis=UILayoutConstraintAxisVertical;metric.spacing=6;
        UILabel *value=PBLabel(@"—",18,UIFontWeightSemibold,UIColor.whiteColor);value.font=[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightSemibold];
        value.numberOfLines=1;value.adjustsFontSizeToFitWidth=YES;value.minimumScaleFactor=.65;[metric addArrangedSubview:value];[metric addArrangedSubview:PBLabel(caption,11,UIFontWeightRegular,[UIColor.whiteColor colorWithAlphaComponent:.45])];
        [metrics addArrangedSubview:metric];[values addObject:value];
    }
    self.uptime=values[0];self.requests=values[1];self.components=values[2];[hero addArrangedSubview:metrics];
    self.toggle=PBButton(@"启动服务",@"play.fill",YES);[self.toggle addTarget:self action:@selector(toggleService) forControlEvents:UIControlEventTouchUpInside];
    [self.toggle.heightAnchor constraintGreaterThanOrEqualToConstant:54].active=YES;[hero addArrangedSubview:self.toggle];[content addArrangedSubview:hero];
    UIStackView *connection=PBCard();[connection addArrangedSubview:PBLabel(@"连接你的电脑",18,UIFontWeightBold,UIColor.labelColor)];
    [connection addArrangedSubview:PBLabel(@"访问地址",11,UIFontWeightSemibold,UIColor.secondaryLabelColor)];
    self.addressLabel=PBLabel(@"启动后显示访问地址",20,UIFontWeightSemibold,UIColor.labelColor);self.addressLabel.adjustsFontSizeToFitWidth=YES;self.addressLabel.minimumScaleFactor=.7;
    [connection addArrangedSubview:self.addressLabel];
    UIStackView *codeHeader=[UIStackView new];codeHeader.axis=UILayoutConstraintAxisHorizontal;codeHeader.spacing=8;
    [codeHeader addArrangedSubview:PBLabel(@"连接码",11,UIFontWeightSemibold,UIColor.secondaryLabelColor)];
    self.codeKind=PBLabel(@"",11,UIFontWeightMedium,PBAccent());[codeHeader addArrangedSubview:self.codeKind];[codeHeader addArrangedSubview:[UIView new]];[connection addArrangedSubview:codeHeader];
    self.codeLabel=PBLabel(@"等待服务启动",15,UIFontWeightMedium,UIColor.secondaryLabelColor);self.codeLabel.font=[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium];self.codeLabel.lineBreakMode=NSLineBreakByCharWrapping;
    [connection addArrangedSubview:self.codeLabel];
    UIStackView *copyRow=[UIStackView new];copyRow.axis=UILayoutConstraintAxisHorizontal;copyRow.spacing=10;copyRow.distribution=UIStackViewDistributionFillEqually;
    self.addressButton=PBButton(@"复制地址",@"doc.on.doc",NO);[self.addressButton addTarget:self action:@selector(copyURL) forControlEvents:UIControlEventTouchUpInside];
    self.connectionButton=PBButton(@"连接信息",@"square.on.square",NO);[self.connectionButton addTarget:self action:@selector(copyConnection) forControlEvents:UIControlEventTouchUpInside];
    [copyRow addArrangedSubview:self.addressButton];[copyRow addArrangedSubview:self.connectionButton];[connection addArrangedSubview:copyRow];
    [connection addArrangedSubview:PBLabel(@"电脑浏览器与 MCP 使用同一地址和连接码。",12,UIFontWeightRegular,UIColor.secondaryLabelColor)];[content addArrangedSubview:connection];
    UIStackView *network=PBCard();[network addArrangedSubview:PBFeature(@"wifi",@"当前网络",@"")];
    self.networkLabel=PBLabel(@"正在读取地址",14,UIFontWeightMedium,UIColor.secondaryLabelColor);[network addArrangedSubview:self.networkLabel];
    UIStackView *networkActions=[UIStackView new];networkActions.axis=UILayoutConstraintAxisHorizontal;networkActions.spacing=10;networkActions.distribution=UIStackViewDistributionFillEqually;
    UIButton *refresh=PBButton(@"刷新地址",@"arrow.clockwise",NO);[refresh addTarget:self action:@selector(refreshAddress) forControlEvents:UIControlEventTouchUpInside];
    UIButton *settings=PBButton(@"连接设置",@"slider.horizontal.3",NO);[settings addTarget:self action:@selector(settings) forControlEvents:UIControlEventTouchUpInside];
    [networkActions addArrangedSubview:refresh];[networkActions addArrangedSubview:settings];[network addArrangedSubview:networkActions];[content addArrangedSubview:network];
    UIStackView *job=PBCard();[job addArrangedSubview:PBLabel(@"最近构建",18,UIFontWeightBold,UIColor.labelColor)];
    self.jobTitle=PBLabel(@"等待第一份作品",16,UIFontWeightSemibold,UIColor.labelColor);self.jobDetail=PBLabel(@"连接电脑后，上传工程并开始构建。",13,UIFontWeightRegular,UIColor.secondaryLabelColor);
    self.jobProgress=[UIProgressView new];self.jobProgress.progressTintColor=PBAccent();[job addArrangedSubview:self.jobTitle];[job addArrangedSubview:self.jobProgress];[job addArrangedSubview:self.jobDetail];[content addArrangedSubview:job];
    UIStackView *prepare=PBCard();[prepare addArrangedSubview:PBLabel(@"构建前准备",18,UIFontWeightBold,UIColor.labelColor)];self.readiness=PBLabel(@"",14,UIFontWeightRegular,UIColor.secondaryLabelColor);[prepare addArrangedSubview:self.readiness];
    UIButton *tools=PBButton(@"管理组件",@"shippingbox",NO);[tools addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];[prepare addArrangedSubview:tools];
    UIButton *guide=PBButton(@"连接指南与首次配置",@"book.closed",NO);[guide addTarget:self action:@selector(guide) forControlEvents:UIControlEventTouchUpInside];[prepare addArrangedSubview:guide];[content addArrangedSubview:prepare];
    NSString *build=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    [content addArrangedSubview:PBLabel([NSString stringWithFormat:@"PocketBuild  %@ · Build %@\n编译期间请保持 App 在前台。",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],build],12,UIFontWeightRegular,UIColor.tertiaryLabelColor)];
    __weak typeof(self) weak=self;DXBuildService.shared.changed=^{[weak update];};
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update) name:PBPackagesChanged object:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];self.address=[NSUserDefaults.standardUserDefaults stringForKey:@"BuildAddress"];
    self.port=[NSUserDefaults.standardUserDefaults integerForKey:@"BuildPort"]?:8787;
    if(!self.address.length)self.address=DXBuildService.interfaces.firstObject[@"address"];
    [self update];__weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){[weak update];}];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated];[self.timer invalidate];self.timer=nil; }
- (void)dealloc { [self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)settings { [self.navigationController pushViewController:PBConnectionSettings() animated:YES]; }
- (void)openTools { [self.navigationController pushViewController:PBToolsHome() animated:YES]; }
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
- (void)update {
    DXBuildService *s=DXBuildService.shared;BOOL active=s.origin.length>0,running=[s.state isEqual:@"运行中"];
    BOOL failed=!active&&![s.state isEqual:@"已停止"];
    self.statusBadge.text=running?@"局域网服务 · 运行中":active?@"正在启动":failed?@"局域网服务 · 启动失败":@"局域网服务 · 未开启";
    self.statusDot.backgroundColor=running?PBAccent():[UIColor.whiteColor colorWithAlphaComponent:.3];
    if(running&&!UIAccessibilityIsReduceMotionEnabled()) {
        if(![self.statusDot.layer animationForKey:@"servicePulse"]){CABasicAnimation *pulse=[CABasicAnimation animationWithKeyPath:@"opacity"];pulse.fromValue=@1;pulse.toValue=@.35;pulse.duration=1.2;pulse.autoreverses=YES;pulse.repeatCount=HUGE_VALF;[self.statusDot.layer addAnimation:pulse forKey:@"servicePulse"];}
    } else [self.statusDot.layer removeAnimationForKey:@"servicePulse"];
    self.heroTitle.text=running?@"服务已就绪":active?@"正在建立连接":failed?@"服务未能启动":@"准备好开始了吗";
    if(running&&s.lastRequestAt) {
        NSInteger elapsed=(NSInteger)[NSDate.date timeIntervalSinceDate:s.lastRequestAt];
        self.heroDetail.text=elapsed<3?@"刚刚收到已认证客户端的请求。":[NSString stringWithFormat:@"最近通信：%ld 秒前",(long)elapsed];
    } else self.heroDetail.text=running?@"等待浏览器或 MCP 的首次认证请求。":active?@"正在监听手机的局域网地址。":[s.state isEqual:@"已停止"]?@"让手机成为你的本机构建节点。":s.state;
    if(s.startedAt){NSInteger seconds=(NSInteger)[NSDate.date timeIntervalSinceDate:s.startedAt];self.uptime.text=[NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)(seconds/3600),(long)(seconds/60%60),(long)(seconds%60)];}else self.uptime.text=@"—";
    self.requests.text=@(s.requestCount).stringValue;
    NSDictionary *installed=PBToolchains.shared.status[@"installed"];self.components.text=[NSString stringWithFormat:@"%lu / 3",(unsigned long)installed.count];
    UIButtonConfiguration *c=self.toggle.configuration;c.title=active?@"停止服务":@"启动服务";c.image=[UIImage systemImageNamed:active?@"stop.fill":@"play.fill"];
    c.baseBackgroundColor=running?PBAccent():UIColor.whiteColor;c.baseForegroundColor=running?UIColor.whiteColor:UIColor.blackColor;self.toggle.configuration=c;
    self.addressLabel.text=s.origin?:@"启动后显示访问地址";self.codeLabel.text=s.code?:@"等待服务启动";
    self.codeLabel.textColor=s.code?UIColor.labelColor:UIColor.tertiaryLabelColor;
    self.codeKind.text=(active?s.activeCodeIsFixed:s.fixedCodeEnabled)?@"固定连接码":@"随机连接码";
    self.addressButton.enabled=running;self.connectionButton.enabled=running;
    NSString *kind=@"手动地址";NSString *address=active?[NSURL URLWithString:s.origin].host:self.address;
    for(NSDictionary *item in DXBuildService.interfaces)if([item[@"address"] isEqual:address])kind=[item[@"interface"] hasPrefix:@"bridge"]?@"个人热点":@"Wi-Fi";
    NSUInteger port=active?[NSURL URLWithString:s.origin].port.unsignedIntegerValue:self.port;
    self.networkLabel.text=address.length?[NSString stringWithFormat:@"%@  ·  %@:%lu",kind,address,(unsigned long)port]:@"尚未发现局域网地址";
    NSDictionary *job=s.latestJob;NSString *state=job[@"state"];
    self.jobTitle.text=state?(@{@"running":@"正在构建",@"succeeded":@"构建成功",@"failed":@"构建失败",@"cancelled":@"构建已取消"}[state]?:state):@"等待第一份作品";
    self.jobProgress.hidden=![state isEqual:@"running"];self.jobProgress.progress=[job[@"progress"] floatValue];
    self.jobDetail.text=[state isEqual:@"running"]?(job[@"stage"]?:@"准备编译器…"):[state isEqual:@"succeeded"]?[NSString stringWithFormat:@"%lu 个产物已就位，在电脑下载。",(unsigned long)[job[@"artifacts"] count]]:state?@"在电脑查看构建日志与报告。":@"连接电脑后，上传工程并开始构建。";
    BOOL support=installed[@"support"]!=nil,sdk=installed[@"sdk16"]||installed[@"sdk26"];
    self.readiness.text=support&&sdk?@"编译器与构建组件已就位，可以开始构建。":!support?@"编译器已内置，请安装构建资源和需要的 SDK。":@"构建资源已安装，再选择一套 SDK 即可。";
}
@end
UIViewController *DXBuildHome(void) { UIViewController *c=[DXBuildHomeController new];c.navigationItem.backButtonDisplayMode=UINavigationItemBackButtonDisplayModeMinimal;return c; }
@interface DXBuildAppDelegate : UIResponder <UIApplicationDelegate,UINavigationControllerDelegate>
@property (strong,nonatomic) UIWindow *window;
@end
@implementation DXBuildAppDelegate
#if TARGET_OS_SIMULATOR
- (void)navigationController:(UINavigationController *)navigation didShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    NSDictionary *ready=@{@"controller":NSStringFromClass(controller.class),@"width":@(controller.view.bounds.size.width),@"height":@(controller.view.bounds.size.height)};
    [[NSJSONSerialization dataWithJSONObject:ready options:0 error:nil] writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pocketbuild-ui-ready.json"] atomically:YES];
}
#endif
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.tintColor=PBAccent();
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithOpaqueBackground];appearance.backgroundColor=PBBackground();appearance.shadowColor=UIColor.clearColor;
    appearance.titleTextAttributes=@{NSFontAttributeName:PBFont(17,UIFontWeightSemibold),NSForegroundColorAttributeName:UIColor.labelColor};
    appearance.largeTitleTextAttributes=@{NSFontAttributeName:PBFont(32,UIFontWeightBold),NSForegroundColorAttributeName:UIColor.labelColor};
    BOOL first=![NSUserDefaults.standardUserDefaults boolForKey:@"PocketBuildWelcomeCompleted"];
    UIViewController *root=first?PBWelcomeScreen(YES):DXBuildHome();
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
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:root];navigation.navigationBar.prefersLargeTitles=YES;navigation.navigationBar.tintColor=UIColor.labelColor;
#if TARGET_OS_SIMULATOR
    if(screen!=NSNotFound&&screen+1<arguments.count&&[@[@"settings",@"tools",@"guide"] containsObject:arguments[screen+1]])[navigation setViewControllers:@[DXBuildHome(),root] animated:NO];
    navigation.delegate=self;
#endif
    navigation.navigationBar.standardAppearance=appearance;navigation.navigationBar.scrollEdgeAppearance=appearance;navigation.navigationBar.compactAppearance=appearance;
    self.window.rootViewController=navigation;[self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char *argv[]) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(DXBuildAppDelegate.class)); } }
