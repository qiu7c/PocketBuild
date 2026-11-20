#import "Workspace.h"
#import "Appearance.h"
#import "BuildBackground.h"
#import "BuildService.h"
#import "ConnectionSettings.h"
#import "Toolchains.h"

static UISwitch *AddSwitch(UIStackView *card, NSString *title, BOOL on, id target, SEL selector) {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [row addArrangedSubview:PBLabel(title, 15, UIFontWeightMedium, UIColor.labelColor)];
    UISwitch *control = [UISwitch new];
    control.on = on;
    control.onTintColor = PBAccent();
    control.accessibilityLabel = title;
    [control addTarget:target action:selector forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:control];
    [card addArrangedSubview:row];
    return control;
}

@interface PBBuildPreferencesController : UIViewController
@property UISegmentedControl *sdk;
@property UIButton *minimum;
@property UISwitch *dylib;
@property NSArray<UISwitch *> *packages;
@end

@implementation PBBuildPreferencesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"构建设置";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    UIStackView *content = PBPageContent(self.view, self.view.bottomAnchor);
    [content addArrangedSubview:PBLabel(@"工程未指定时使用以下设置。单个工程仍可在电脑上设置。", 14, UIFontWeightRegular, UIColor.secondaryLabelColor)];

    UIStackView *target = PBCard();
    [target addArrangedSubview:PBLabel(@"默认编译目标", 17, UIFontWeightBold, UIColor.labelColor)];
    self.sdk = [[UISegmentedControl alloc] initWithItems:@[@"iOS 16.4 SDK", @"iOS 26.0 SDK"]];
    self.sdk.selectedSegmentIndex = [[defaults stringForKey:@"StudioSDKVersion"] isEqual:@"26.0"] ? 1 : 0;
    self.sdk.accessibilityLabel = @"默认 SDK";
    [self.sdk addTarget:self action:@selector(changeSDK) forControlEvents:UIControlEventValueChanged];
    [target addArrangedSubview:self.sdk];
    self.minimum = PBButton(@"", @"iphone", NO);
    [target addArrangedSubview:self.minimum];
    [self updateMinimum];
    [content addArrangedSubview:target];

    UIStackView *optimization = PBCard();
    [optimization addArrangedSubview:PBLabel(@"默认优化", 17, UIFontWeightBold, UIColor.labelColor)];
    UISegmentedControl *profile = [[UISegmentedControl alloc] initWithItems:@[@"调试", @"速度", @"体积"]];
    NSString *saved = [defaults stringForKey:@"StudioOptimization"];
    profile.selectedSegmentIndex = [saved isEqual:@"debug"] ? 0 : [saved isEqual:@"release-size"] ? 2 : 1;
    profile.accessibilityLabel = @"默认优化";
    [profile addTarget:self action:@selector(changeProfile:) forControlEvents:UIControlEventValueChanged];
    [optimization addArrangedSubview:profile];
    [content addArrangedSubview:optimization];

    UIStackView *outputs = PBCard();
    [outputs addArrangedSubview:PBLabel(@"默认插件产物", 17, UIFontWeightBold, UIColor.labelColor)];
    self.dylib = AddSwitch(outputs, @"独立 dylib", ![[defaults objectForKey:@"StudioExportDylib"] isEqual:@NO], self, @selector(changeOutputs:));
    BOOL deb = ![[defaults objectForKey:@"StudioPackageEnabled"] isEqual:@NO];
    NSArray *schemes = [defaults arrayForKey:@"StudioPackageSchemes"] ?: @[@"rootless"];
    self.packages = @[
        AddSwitch(outputs, @"无根 DEB", deb && [schemes containsObject:@"rootless"], self, @selector(changeOutputs:)),
        AddSwitch(outputs, @"有根 DEB", deb && [schemes containsObject:@"rootful"], self, @selector(changeOutputs:)),
        AddSwitch(outputs, @"隐根 DEB", deb && [schemes containsObject:@"roothide"], self, @selector(changeOutputs:))
    ];
    [content addArrangedSubview:outputs];
}

- (void)changeSDK {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *sdk = self.sdk.selectedSegmentIndex == 0 ? @"16.4" : @"26.0";
    [defaults setObject:sdk forKey:@"StudioSDKVersion"];
    NSString *minimum = [defaults stringForKey:@"StudioDeploymentTarget"] ?: @"15.0";
    if ([minimum compare:sdk options:NSNumericSearch] == NSOrderedDescending) {
        [defaults setObject:@"15.0" forKey:@"StudioDeploymentTarget"];
    }
    [self updateMinimum];
}

- (void)updateMinimum {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *minimum = [defaults stringForKey:@"StudioDeploymentTarget"] ?: @"15.0";
    UIButtonConfiguration *configuration = self.minimum.configuration;
    configuration.title = [@"最低系统 iOS " stringByAppendingString:minimum];
    self.minimum.configuration = configuration;
    NSArray *versions = self.sdk.selectedSegmentIndex == 0 ? @[@"15.0", @"16.0", @"16.4"] :
        @[@"15.0", @"16.0", @"16.4", @"17.0", @"18.0", @"26.0"];
    NSMutableArray *choices = [NSMutableArray array];
    __weak typeof(self) weak = self;
    for (NSString *version in versions) {
        UIAction *choice = [UIAction actionWithTitle:[@"iOS " stringByAppendingString:version]
            image:nil identifier:nil handler:^(UIAction *action) {
                [defaults setObject:version forKey:@"StudioDeploymentTarget"];
                [weak updateMinimum];
            }];
        choice.state = [version isEqual:minimum] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [choices addObject:choice];
    }
    self.minimum.menu = [UIMenu menuWithChildren:choices];
    self.minimum.showsMenuAsPrimaryAction = YES;
}

- (void)changeProfile:(UISegmentedControl *)control {
    NSArray *profiles = @[@"debug", @"release-speed", @"release-size"];
    [NSUserDefaults.standardUserDefaults setObject:profiles[control.selectedSegmentIndex] forKey:@"StudioOptimization"];
}

- (void)changeOutputs:(UISwitch *)control {
    NSArray *types = @[@"rootless", @"rootful", @"roothide"];
    NSMutableArray *selected = [NSMutableArray array];
    for (NSUInteger index = 0; index < types.count; index++) {
        if (self.packages[index].on) [selected addObject:types[index]];
    }
    if (!self.dylib.on && !selected.count) {
        [control setOn:YES animated:YES];
        PBToast(self, @"至少保留一种产物");
        return;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:self.dylib.on forKey:@"StudioExportDylib"];
    [defaults setBool:selected.count > 0 forKey:@"StudioPackageEnabled"];
    [defaults setObject:selected forKey:@"StudioPackageSchemes"];
}
@end

@interface PBSettingsController : UIViewController
@property UILabel *backgroundStatus;
@end

@implementation PBSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    UIStackView *content = PBPageContent(self.view, self.view.bottomAnchor);
    UIStackView *preferences = PBCard();
    [preferences addArrangedSubview:PBLabel(@"工作偏好", 18, UIFontWeightBold, UIColor.labelColor)];
    [preferences addArrangedSubview:[self button:@"连接设置" symbol:@"network" action:@selector(connection)]];
    [preferences addArrangedSubview:[self button:@"构建设置" symbol:@"hammer" action:@selector(buildSettings)]];
    AddSwitch(preferences, @"滚动时收起底栏",
        ![[NSUserDefaults.standardUserDefaults objectForKey:@"PocketBuildCollapseTabs"] isEqual:@NO],
        self, @selector(setCollapse:));
    [content addArrangedSubview:preferences];

    UIStackView *background = PBCard();
    AddSwitch(background, @"后台构建辅助", PBBackgroundAudioEnabled(), self, @selector(setBackground:));
    [background addArrangedSubview:PBLabel(@"构建或试编译期间混播静音音频，任务结束自动停止。切换应用或锁屏时，系统仍可能中断任务。", 13, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    self.backgroundStatus = PBLabel(@"", 13, UIFontWeightMedium, UIColor.labelColor);
    [background addArrangedSubview:self.backgroundStatus];
    [content addArrangedSubview:background];
    [content addArrangedSubview:[self button:@"存储空间管理" symbol:@"internaldrive" action:@selector(storage)]];

    UIStackView *info = PBCard();
    [info addArrangedSubview:PBLabel(@"帮助与信息", 18, UIFontWeightBold, UIColor.labelColor)];
    [info addArrangedSubview:[self button:@"关于 PocketBuild" symbol:@"info.circle" action:@selector(about)]];
    [info addArrangedSubview:[self button:@"反馈问题" symbol:@"bubble.left" action:@selector(feedback)]];
    [info addArrangedSubview:[self button:@"项目开源地址" symbol:@"arrow.up.right" action:@selector(source)]];
    [info addArrangedSubview:[self button:@"软件许可证" symbol:@"doc.text" action:@selector(licenses)]];
    [content addArrangedSubview:info];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshBackground)
        name:PBBackgroundBuildChanged object:nil];
    [self refreshBackground];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (UIButton *)button:(NSString *)name symbol:(NSString *)symbol action:(SEL)action {
    UIButton *button = PBButton(name, symbol, NO);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)setCollapse:(UISwitch *)control {
    [NSUserDefaults.standardUserDefaults setBool:control.on forKey:@"PocketBuildCollapseTabs"];
}
- (void)setBackground:(UISwitch *)control { PBSetBackgroundAudioEnabled(control.on); }
- (void)refreshBackground {
    if (!PBBackgroundAudioEnabled()) self.backgroundStatus.text = @"已关闭";
    else if (PBBackgroundAudioPlaying()) self.backgroundStatus.text = @"后台辅助运行中";
    else if (PBBackgroundAudioError()) self.backgroundStatus.text = [@"后台辅助未启动 · " stringByAppendingString:PBBackgroundAudioError()];
    else self.backgroundStatus.text = @"已开启，等待构建";
}
- (void)connection { [self.navigationController pushViewController:PBConnectionSettings() animated:YES]; }
- (void)buildSettings { [self.navigationController pushViewController:[PBBuildPreferencesController new] animated:YES]; }
- (void)storage { [self.navigationController pushViewController:PBStoragePage() animated:YES]; }
- (void)feedback { [self openURL:@"https://github.com/qiu7c/PocketBuild/issues/new"]; }
- (void)source { [self openURL:@"https://github.com/qiu7c/PocketBuild"]; }
- (void)openURL:(NSString *)address {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:address] options:@{} completionHandler:nil];
}

- (void)about {
    UIViewController *about = [UIViewController new];
    about.title = @"关于";
    UIStackView *content = PBPageContent(about.view, about.view.bottomAnchor);
    UIStackView *card = PBCard();
    NSBundle *bundle = NSBundle.mainBundle;
    UIImageView *mark = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"BrandMark"]];
    mark.contentMode = UIViewContentModeScaleAspectFit;
    [mark.heightAnchor constraintEqualToConstant:112].active = YES;
    [card addArrangedSubview:mark];
    UILabel *title = PBLabel(@"PocketBuild", 26, UIFontWeightBold, UIColor.labelColor);
    title.textAlignment = NSTextAlignmentCenter;
    [card addArrangedSubview:title];
    NSString *version = [NSString stringWithFormat:@"%@ · Build %@", [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
    UILabel *label = PBLabel(version, 14, UIFontWeightMedium, UIColor.secondaryLabelColor);
    label.textAlignment = NSTextAlignmentCenter;
    [card addArrangedSubview:label];
    [content addArrangedSubview:card];
    [content addArrangedSubview:PBLabel(@"在 iPhone 和 iPad 上编译，并通过浏览器或 MCP 与电脑协作。PocketBuild 基于 Dylix 的本机构建核心。", 15, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [self.navigationController pushViewController:about animated:YES];
}

- (void)licenses {
    UIViewController *page = [UIViewController new];
    page.title = @"软件许可证";
    page.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    UIStackView *content = PBPageContent(page.view, page.view.bottomAnchor);
    NSString *folder = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ThirdPartyNotices"];
    NSDictionary *titles = @{@"LICENSE":@"GNU GPL v3", @"COPYRIGHT":@"版权声明", @"THIRD_PARTY_NOTICES.md":@"第三方组件与许可"};
    __weak UIViewController *weakPage = page;
    for (NSString *file in @[@"LICENSE", @"COPYRIGHT", @"THIRD_PARTY_NOTICES.md"]) {
        UIButton *open = PBButton(titles[file], @"doc.text", NO);
        [open addAction:[UIAction actionWithHandler:^(UIAction *action) {
            NSString *text = [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:nil];
            [weakPage.navigationController pushViewController:PBTextPage(titles[file], text ?: @"文件无法读取。") animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [content addArrangedSubview:open];
    }
    [self.navigationController pushViewController:page animated:YES];
}
@end

UIViewController *PBSettingsHome(void) { return [PBSettingsController new]; }
