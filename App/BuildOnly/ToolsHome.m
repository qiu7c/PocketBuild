#import "Toolchains.h"
#import "Appearance.h"
#import "BuildService.h"
#import "Workspace.h"

@interface PBToolsController : UIViewController
@property UILabel *message, *coreLabel;
@property UIProgressView *progress;
@property UIButton *cancelButton;
@property UIStackView *downloadStatus;
@property UIBarButtonItem *sourceButton;
@property UISegmentedControl *buildPurpose;
@property UILabel *requirementsLabel;
@property UILabel *trialLabel;
@property UIProgressView *trialProgress;
@property UIButton *nextAction;
@property UIButton *cancelTrialButton;
@property UIStackView *packagesStack;
@property NSArray *renderedCatalog;
@property NSDictionary *renderedInstalled;
@property NSInteger renderedPurpose;
@property NSMutableArray<UIButton *> *packageButtons;
@property NSDictionary *buildIssue;
@property NSString *retryProject;
@end
@implementation PBToolsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"组件库";self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.backButtonDisplayMode=UINavigationItemBackButtonDisplayModeMinimal;
    UIStackView *content=PBPageContent(self.view,self.view.bottomAnchor);
    UIStackView *setup = PBCard();
    [setup addArrangedSubview:PBLabel(@"构建用途", 15, UIFontWeightMedium, UIColor.labelColor)];
    self.buildPurpose = [[UISegmentedControl alloc] initWithItems:@[@"常规", @"iOS 26", @"26 + C++"]];
    self.buildPurpose.selectedSegmentIndex = [self.buildIssue[@"sdk"] isEqual:@"26.0"] ?
        ([self.buildIssue[@"usesCXX"] boolValue] ? 2 : 1) : 0;
    self.buildPurpose.accessibilityLabel = @"构建用途";
    [self.buildPurpose addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    [setup addArrangedSubview:self.buildPurpose];
    self.requirementsLabel = PBLabel(@"", 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [setup addArrangedSubview:self.requirementsLabel];
    self.nextAction = PBButton(@"", @"arrow.down.circle", YES);
    [self.nextAction addTarget:self action:@selector(prepareOrTest) forControlEvents:UIControlEventTouchUpInside];
    [setup addArrangedSubview:self.nextAction];
    self.trialProgress = [UIProgressView new];
    self.trialProgress.progressTintColor = PBAccent();
    [setup addArrangedSubview:self.trialProgress];
    self.trialLabel = PBLabel(@"", 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [setup addArrangedSubview:self.trialLabel];
    self.cancelTrialButton = PBButton(@"取消试编译", @"xmark", NO);
    [self.cancelTrialButton addTarget:DXBuildService.shared action:@selector(cancelTrial) forControlEvents:UIControlEventTouchUpInside];
    [setup addArrangedSubview:self.cancelTrialButton];
    [content addArrangedSubview:setup];
    UIStackView *core=PBCard();[core addArrangedSubview:PBFeature(@"checkmark.seal",@"本机编译核心",@"Clang · LLVM · LLD · Perl")];
    self.coreLabel=PBLabel(@"",13,UIFontWeightMedium,UIColor.secondaryLabelColor);[core addArrangedSubview:self.coreLabel];[content addArrangedSubview:core];
    self.sourceButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
        style:UIBarButtonItemStylePlain target:self action:@selector(chooseSource)];
    self.sourceButton.accessibilityLabel = @"下载源设置";
    self.navigationItem.rightBarButtonItem = self.sourceButton;

    self.downloadStatus = PBCard();
    self.progress = [UIProgressView new];
    self.progress.progressTintColor = PBAccent();
    [self.downloadStatus addArrangedSubview:self.progress];
    self.message = PBLabel(@"", 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [self.downloadStatus addArrangedSubview:self.message];
    self.cancelButton = PBButton(@"取消当前任务", @"xmark", NO);
    [self.cancelButton addTarget:PBToolchains.shared action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self.downloadStatus addArrangedSubview:self.cancelButton];
    [content addArrangedSubview:self.downloadStatus];
    self.packagesStack=[UIStackView new];self.packagesStack.axis=UILayoutConstraintAxisVertical;self.packagesStack.spacing=14;[content addArrangedSubview:self.packagesStack];
    [content addArrangedSubview:PBLabel(@"资源包下载完成后会校验 SHA-256。升级 App 时保留数据，已安装组件即可继续使用。",12,UIFontWeightRegular,UIColor.tertiaryLabelColor)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:PBPackagesChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:PBTrialChanged object:nil];
    [self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated];[self refresh]; }
- (NSArray<NSString *> *)missingPackagesFrom:(NSArray<NSString *> *)required installed:(NSDictionary *)installed {
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *identifier in required) {
        if (!installed[identifier]) [missing addObject:identifier];
    }
    return missing;
}
- (void)prepareOrTest {
    NSInteger purpose = self.buildPurpose.selectedSegmentIndex;
    NSString *sdk = purpose == 0 ? @"16.4" : @"26.0";
    BOOL usesCXX = purpose == 2;
    NSArray<NSString *> *required = [PBToolchains requiredPackagesForSDK:sdk usesCXX:usesCXX];
    NSArray<NSString *> *missing = [self missingPackagesFrom:required installed:PBToolchains.shared.status[@"installed"]];
    if (missing.count) {
        [PBToolchains.shared installPackages:missing];
        return;
    }

    NSError *error = nil;
    if (self.retryProject) {
        NSDictionary *job = [DXBuildService.shared startProjectBuild:self.retryProject error:&error];
        if (!job) {
            PBShowError(self, error.localizedDescription ?: @"无法重新构建。");
            return;
        }
        NSMutableArray *stack = [self.navigationController.viewControllers mutableCopy];
        [stack removeLastObject];
        [stack addObject:PBBuildResult(job[@"id"])];
        [self.navigationController setViewControllers:stack animated:YES];
        return;
    }
    if (![DXBuildService.shared runTrialWithSDK:sdk usesCXX:usesCXX error:&error]) {
        PBShowError(self, error.localizedDescription ?: @"无法创建试编译工程。");
    }
}
- (void)chooseSource {
    PBToolchains *store = PBToolchains.shared;
    NSString *source = store.usingCustomSource ? @"当前优先使用备用下载源。" : @"当前使用 PocketBuild 内置下载源。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"下载源"
        message:[source stringByAppendingString:@"需要使用局域网镜像时，可以填写备用清单地址。"]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"备用清单地址";
        field.text = [NSUserDefaults.standardUserDefaults stringForKey:@"PackageManifestURL"];
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(alert) weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"启用备用源" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *url = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [store loadManifest:[NSURL URLWithString:url]];
    }]];
    if (store.usingCustomSource) {
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复内置源" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [store useDefaultSource];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)refresh {
    __weak typeof(self) weak=self;
    PBToolchains *store=PBToolchains.shared;NSDictionary *status=store.status;NSDictionary *installed=status[@"installed"];
    DXBuildService *service = DXBuildService.shared;
    NSInteger purpose = self.buildPurpose.selectedSegmentIndex;
    NSArray<NSString *> *required = [PBToolchains requiredPackagesForSDK:purpose == 0 ? @"16.4" : @"26.0" usesCXX:purpose == 2];
    NSArray<NSString *> *missing = [self missingPackagesFrom:required installed:installed];
    NSArray<NSString *> *descriptions = @[
        @"常规 UIKit App 和插件使用 16.4 SDK。构建资源与 16.4 SDK 必装。",
        @"工程选择 26.0 SDK 时，构建资源与 26.0 SDK 必装。适用于 C、Objective-C 和 Logos .x。",
        @"C++、Objective-C++ 和 Logos .xm 使用 26.0 SDK 时，三个组件都要装。16.4 SDK 提供兼容的 C++ 头文件。"
    ];
    self.requirementsLabel.text = descriptions[purpose];
    self.buildPurpose.enabled = !self.retryProject && !store.busy && !service.trialRunning;
    self.nextAction.enabled = !store.busy && !store.buildRunning && [status[@"compilerBundled"] boolValue];
    UIButtonConfiguration *action = self.nextAction.configuration;
    if (missing.count) {
        action.title = [NSString stringWithFormat:@"安装缺少的 %lu 项组件", (unsigned long)missing.count];
        action.image = [UIImage systemImageNamed:@"arrow.down.circle"];
    } else {
        action.title = self.retryProject ? @"重新构建此项目" : service.trialRunning ? @"正在试编译…" : @"试编译 UIKit 示例";
        action.image = [UIImage systemImageNamed:@"hammer"];
    }
    self.nextAction.configuration = action;
    self.trialProgress.hidden = !service.trialRunning;
    self.trialProgress.progress = service.trialProgress;
    self.cancelTrialButton.hidden = !service.trialRunning;
    self.trialLabel.text = self.retryProject ? @"安装完成后可用该项目当前源码重新构建。" :
        service.trialMessage ?: (missing.count ? @"" : @"试编译将在本机生成一个示例 IPA，结束后自动清理。");
    self.trialLabel.hidden = !self.trialLabel.text.length;
    self.coreLabel.text=[status[@"compilerBundled"] boolValue]?@"已包含在安装包中":@"安装包中未找到编译核心";
    self.sourceButton.enabled = !store.busy && !store.buildRunning;
    self.downloadStatus.hidden = !store.busy && !store.message.length;
    self.cancelButton.hidden=!store.busy;self.progress.hidden=!store.busy;
    self.progress.progress=store.progress;self.message.text=store.busy?[NSString stringWithFormat:@"%@  %.0f%%",store.message,store.progress*100]:store.message;
    if(self.renderedCatalog!=store.catalog||![self.renderedInstalled isEqual:installed]||self.renderedPurpose != purpose) {
        self.renderedPurpose = purpose;
        self.renderedCatalog=store.catalog;self.renderedInstalled=installed;
        for(UIView *v in self.packagesStack.arrangedSubviews){[self.packagesStack removeArrangedSubview:v];[v removeFromSuperview];}
        self.packageButtons=[NSMutableArray array];
        for(NSDictionary *package in store.catalog) {
            NSString *identifier=package[@"id"];BOOL ready=installed[identifier]!=nil;
            NSString *detail=[identifier isEqual:@"support"]?@"所有构建都需要。包含 Logos、Clang 头文件和打包辅助资源。":[identifier isEqual:@"sdk16"]?@"常规构建使用。也是 iOS 26 工程的 C++ 兼容依赖。":@"工程选择 26.0 SDK 时需要，用于获取新系统头文件和链接声明。";
            UIStackView *card=PBCard();[card addArrangedSubview:PBFeature([identifier isEqual:@"support"]?@"wrench.and.screwdriver":@"square.stack.3d.up",package[@"title"],detail)];
            NSString *role = [required containsObject:identifier] ? @"此用途必装" : @"按需安装";
            NSString *statusText = [NSString stringWithFormat:@"%@  ·  %@", role, ready ? @"已安装" : @"尚未安装"];
            if (package[@"bytes"]) {
                NSString *size = [NSByteCountFormatter stringFromByteCount:[package[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
                statusText = [NSString stringWithFormat:@"%@  ·  %@", statusText, size];
            }
            [card addArrangedSubview:PBLabel(statusText,12,UIFontWeightMedium,ready?PBAccent():UIColor.secondaryLabelColor)];
            UIStackView *actions=[UIStackView new];actions.axis=UILayoutConstraintAxisHorizontal;actions.spacing=10;
            UIButton *install=PBButton(ready?@"重新安装":@"下载安装",@"arrow.down.circle",NO);
            [install addAction:[UIAction actionWithHandler:^(UIAction *action) {
                [store install:identifier];
                [weak.view layoutIfNeeded];
                UIScrollView *scroll = (UIScrollView *)weak.downloadStatus.superview.superview;
                [scroll scrollRectToVisible:[weak.downloadStatus convertRect:weak.downloadStatus.bounds toView:scroll] animated:YES];
            }] forControlEvents:UIControlEventTouchUpInside];
            [actions addArrangedSubview:install];[self.packageButtons addObject:install];
            if(ready) {
                UIButton *more=PBButton(@"",@"ellipsis",NO);
                UIAction *remove=[UIAction actionWithTitle:@"移除组件" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *a){NSError *error=nil;if(![store remove:identifier error:&error])PBShowError(weak,error.localizedDescription);}];
                remove.attributes=UIMenuElementAttributesDestructive;more.menu=[UIMenu menuWithChildren:@[remove]];more.showsMenuAsPrimaryAction=YES;
                [actions addArrangedSubview:more];[self.packageButtons addObject:more];
            }
            [card addArrangedSubview:actions];[self.packagesStack addArrangedSubview:card];
        }
    }
    for(UIButton *button in self.packageButtons)button.enabled=!store.busy&&!store.buildRunning;
}
@end
UIViewController *PBToolsHome(void) { return [PBToolsController new]; }
UIViewController *PBToolsForBuildIssue(NSDictionary *issue, NSString *project) {
    PBToolsController *controller = [PBToolsController new];
    controller.buildIssue = issue;
    controller.retryProject = project;
    return controller;
}
