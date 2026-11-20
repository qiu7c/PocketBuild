#import "Workspace.h"
#import "Appearance.h"
#import "BuildBackground.h"
#import "BuildService.h"
#import "ConnectionSettings.h"

static UITableViewCell *SettingsCell(UITableView *table, NSIndexPath *index, NSString *title, NSString *detail, NSString *symbol) {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"setting" forIndexPath:index];
    UIListContentConfiguration *content = UIListContentConfiguration.subtitleCellConfiguration;
    content.text = title;
    content.secondaryText = detail;
    content.textProperties.font = PBFont(15, UIFontWeightRegular);
    content.textProperties.adjustsFontForContentSizeCategory = YES;
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.font = PBFont(12, UIFontWeightRegular);
    content.secondaryTextProperties.adjustsFontForContentSizeCategory = YES;
    content.secondaryTextProperties.numberOfLines = 0;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    if (symbol) {
        content.image = [UIImage systemImageNamed:symbol withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular]];
        content.imageProperties.tintColor = PBAccent();
        content.imageProperties.maximumSize = CGSizeMake(19, 19);
        content.imageProperties.reservedLayoutSize = CGSizeMake(22, 22);
    }
    content.imageToTextPadding = 10;
    content.textToSecondaryTextVerticalPadding = 3;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 14, 10, 14);
    cell.contentConfiguration = content;
    cell.separatorInset = UIEdgeInsetsMake(0, symbol ? 46 : 14, 0, 0);
    UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 18, 28)];
    disclosure.image = [UIImage systemImageNamed:@"chevron.forward" withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold]];
    disclosure.contentMode = UIViewContentModeCenter;
    disclosure.tintColor = UIColor.tertiaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = disclosure;
    cell.accessibilityTraits |= UIAccessibilityTraitButton;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

static void SettingsSwitch(UITableViewCell *cell, NSString *title, BOOL on, NSInteger tag, id target, SEL action) {
    UISwitch *control = [UISwitch new];
    control.on = on;
    control.onTintColor = PBAccent();
    control.accessibilityLabel = title;
    control.tag = tag;
    [control addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = control;
    cell.accessibilityTraits &= ~UIAccessibilityTraitButton;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

@interface PBBuildPreferencesController : UITableViewController
@end

@implementation PBBuildPreferencesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"构建设置";
    self.tableView.backgroundColor = PBBackground();
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"setting"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : 4; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"默认目标" : @"插件产物";
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"项目单独指定的设置优先。" : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (index.section == 0) {
        NSArray *titles = @[@"编译 SDK", @"最低系统版本", @"编译优化"];
        NSString *sdk = [defaults stringForKey:@"StudioSDKVersion"] ?: @"16.4";
        NSString *minimum = [defaults stringForKey:@"StudioDeploymentTarget"] ?: @"15.0";
        NSString *profile = [defaults stringForKey:@"StudioOptimization"] ?: @"release-speed";
        NSString *optimization = @{@"debug":@"调试", @"release-speed":@"速度", @"release-size":@"体积"}[profile] ?: @"速度";
        NSArray *values = @[[@"iOS " stringByAppendingString:sdk], [@"iOS " stringByAppendingString:minimum], optimization];
        return SettingsCell(table, index, titles[index.row], values[index.row], nil);
    }
    NSArray *titles = @[@"独立 dylib", @"无根 DEB", @"有根 DEB", @"隐根 DEB"];
    NSString *title = titles[index.row];
    BOOL on;
    if (index.row == 0) on = ![[defaults objectForKey:@"StudioExportDylib"] isEqual:@NO];
    else {
        NSArray *schemes = [defaults arrayForKey:@"StudioPackageSchemes"] ?: @[@"rootless"];
        on = ![[defaults objectForKey:@"StudioPackageEnabled"] isEqual:@NO] &&
            [schemes containsObject:@[@"rootless", @"rootful", @"roothide"][index.row - 1]];
    }
    UITableViewCell *cell = SettingsCell(table, index, title, nil, nil);
    SettingsSwitch(cell, title, on, index.row, self, @selector(changeOutput:));
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.section != 0) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[@"StudioSDKVersion", @"StudioDeploymentTarget", @"StudioOptimization"];
    NSArray *titles = @[@"编译 SDK", @"最低系统版本", @"编译优化"];
    NSString *key = keys[index.row];
    NSString *sdk = [defaults stringForKey:@"StudioSDKVersion"] ?: @"16.4";
    NSArray *versions = [sdk isEqual:@"26.0"] ? @[@"15.0", @"16.0", @"16.4", @"17.0", @"18.0", @"26.0"] : @[@"15.0", @"16.0", @"16.4"];
    NSArray *options = @[@[@"16.4", @"26.0"], versions, @[@"debug", @"release-speed", @"release-size"]][index.row];
    NSArray *names = @[@"调试", @"速度", @"体积"];
    NSString *selected = [defaults stringForKey:key] ?: @[@"16.4", @"15.0", @"release-speed"][index.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:titles[index.row] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weak = self;
    for (NSUInteger i = 0; i < options.count; i++) {
        NSString *value = options[i];
        UIAlertAction *action = [UIAlertAction actionWithTitle:index.row == 2 ? names[i] : [@"iOS " stringByAppendingString:value]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *item) {
                [defaults setObject:value forKey:key];
                NSString *minimum = [defaults stringForKey:@"StudioDeploymentTarget"] ?: @"15.0";
                if (index.row == 0 && [minimum compare:value options:NSNumericSearch] == NSOrderedDescending) {
                    [defaults setObject:@"15.0" forKey:@"StudioDeploymentTarget"];
                }
                [weak.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
            }];
        [sheet addAction:action];
        if ([selected isEqual:value]) sheet.preferredAction = action;
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *row = [table cellForRowAtIndexPath:index];
    sheet.popoverPresentationController.sourceView = row;
    sheet.popoverPresentationController.sourceRect = row.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)changeOutput:(UISwitch *)control {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL dylib = ![[defaults objectForKey:@"StudioExportDylib"] isEqual:@NO];
    BOOL deb = ![[defaults objectForKey:@"StudioPackageEnabled"] isEqual:@NO];
    NSMutableArray *schemes = deb ? [([defaults arrayForKey:@"StudioPackageSchemes"] ?: @[@"rootless"]) mutableCopy] : [NSMutableArray array];
    if (control.tag == 0) dylib = control.on;
    else {
        NSString *scheme = @[@"rootless", @"rootful", @"roothide"][control.tag - 1];
        if (control.on) [schemes addObject:scheme]; else [schemes removeObject:scheme];
    }
    if (!dylib && !schemes.count) {
        [control setOn:YES animated:YES];
        PBToast(self, @"至少保留一种产物");
        return;
    }
    [defaults setBool:dylib forKey:@"StudioExportDylib"];
    [defaults setBool:schemes.count > 0 forKey:@"StudioPackageEnabled"];
    [defaults setObject:schemes forKey:@"StudioPackageSchemes"];
}
@end

@interface PBLicensesController : UITableViewController
@end

@implementation PBLicensesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"软件许可证";
    self.tableView.backgroundColor = PBBackground();
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"setting"];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 3; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    return SettingsCell(table, index, @[@"GNU GPL v3", @"版权声明", @"第三方组件与许可"][index.row], nil, @"doc.text");
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [table cellForRowAtIndexPath:index];
    UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
    [table deselectRowAtIndexPath:index animated:YES];
    NSString *file = @[@"LICENSE", @"COPYRIGHT", @"THIRD_PARTY_NOTICES.md"][index.row];
    NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:[@"ThirdPartyNotices" stringByAppendingPathComponent:file]];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    [self.navigationController pushViewController:PBTextPage(config.text, text ?: @"文件无法读取。") animated:YES];
}
@end

@interface PBSettingsController : UITableViewController
@end

@implementation PBSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.tableView.backgroundColor = PBBackground();
    self.tableView.sectionHeaderTopPadding = 8;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 54;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"setting"];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshBackground) name:PBBackgroundBuildChanged object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 4; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return [@[@2, @1, @1, @4][section] integerValue];
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return @[@"连接与构建", @"后台任务", @"数据", @"关于与支持"][section];
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section == 1 ? @"后台辅助仅在构建或试编译时混播静音音频。锁屏或切换应用时，系统仍可能中断任务。" : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSInteger row = index.row;
    switch (index.section) {
        case 0:
            return SettingsCell(table, index, @[@"连接设置", @"构建设置"][row],
                @[@"局域网地址与连接码", @"默认 SDK、最低系统与产物"][row], @[@"network", @"hammer"][row]);
        case 1: {
            NSString *title = @"后台构建辅助";
            UITableViewCell *cell = SettingsCell(table, index, title, [self backgroundStatus], @"waveform");
            SettingsSwitch(cell, title, PBBackgroundAudioEnabled(), 0, self, @selector(setBackground:));
            return cell;
        }
        case 2:
            return SettingsCell(table, index, @"存储空间", @"查看占用与清理缓存", @"internaldrive");
        default:
            return SettingsCell(table, index, @[@"关于 PocketBuild", @"反馈问题", @"开源仓库", @"软件许可证"][row],
                nil, @[@"info.circle", @"bubble.left", @"chevron.left.forwardslash.chevron.right", @"doc.text"][row]);
    }
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.section == 0) {
        UIViewController *screen = index.row == 0 ? PBConnectionSettings() : [[PBBuildPreferencesController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:screen animated:YES];
    } else if (index.section == 2) {
        [self.navigationController pushViewController:PBStoragePage() animated:YES];
    } else if (index.section == 3) {
        switch (index.row) {
            case 0: [self about]; break;
            case 1: [self openURL:@"https://github.com/qiu7c/PocketBuild/issues/new"]; break;
            case 2: [self openURL:@"https://github.com/qiu7c/PocketBuild"]; break;
            case 3: [self.navigationController pushViewController:[[PBLicensesController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; break;
        }
    }
}

- (void)setBackground:(UISwitch *)control { PBSetBackgroundAudioEnabled(control.on); }
- (NSString *)backgroundStatus {
    if (!PBBackgroundAudioEnabled()) return @"已关闭";
    if (PBBackgroundAudioPlaying()) return @"运行中";
    if (PBBackgroundAudioError()) return [@"启动失败 · " stringByAppendingString:PBBackgroundAudioError()];
    return @"已开启，等待构建";
}
- (void)refreshBackground {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.secondaryText = [self backgroundStatus];
    cell.contentConfiguration = content;
    ((UISwitch *)cell.accessoryView).on = PBBackgroundAudioEnabled();
}
- (void)openURL:(NSString *)address {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:address] options:@{} completionHandler:nil];
}

- (void)about {
    UIViewController *about = [UIViewController new];
    about.title = @"关于";
    UIStackView *content = PBPageContent(about.view, nil);
    UIStackView *card = PBCard();
    card.alignment = UIStackViewAlignmentCenter;
    NSBundle *bundle = NSBundle.mainBundle;
    UIImageView *mark = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"BrandMark"]];
    mark.contentMode = UIViewContentModeScaleAspectFill;
    mark.layer.cornerRadius = 16;
    mark.layer.cornerCurve = kCACornerCurveContinuous;
    mark.clipsToBounds = YES;
    [card addArrangedSubview:mark];
    [NSLayoutConstraint activateConstraints:@[
        [mark.widthAnchor constraintEqualToConstant:72],
        [mark.heightAnchor constraintEqualToAnchor:mark.widthAnchor],
    ]];
    UILabel *title = PBLabel(@"PocketBuild", 20, UIFontWeightSemibold, UIColor.labelColor);
    title.textAlignment = NSTextAlignmentCenter;
    [card addArrangedSubview:title];
    NSString *version = [NSString stringWithFormat:@"%@ · Build %@", [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
    UILabel *label = PBLabel(version, 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    label.textAlignment = NSTextAlignmentCenter;
    [card addArrangedSubview:label];
    UIButton *author = PBLinkButton(@"作者 · Cc", @"person.crop.circle");
    __weak typeof(self) weak = self;
    [author addAction:[UIAction actionWithHandler:^(UIAction *action) {
        [weak openURL:@"https://github.com/qiu7c"];
    }] forControlEvents:UIControlEventPrimaryActionTriggered];
    [card addArrangedSubview:author];
    [content addArrangedSubview:card];
    [content addArrangedSubview:PBLabel(@"在 iPhone 和 iPad 上编译，并通过浏览器或 MCP 与电脑协作。PocketBuild 基于 Dylix 的本机构建核心。", 14, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [self.navigationController pushViewController:about animated:YES];
}
@end

UIViewController *PBSettingsHome(void) { return [[PBSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped]; }
