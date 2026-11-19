#import "Toolchains.h"
#import "Appearance.h"

@interface PBToolsController : UIViewController
@property UILabel *message, *coreLabel;
@property UIProgressView *progress;
@property UIButton *cancelButton;
@property UIStackView *downloadStatus;
@property UIBarButtonItem *sourceButton;
@property UIStackView *packagesStack;
@property NSArray *renderedCatalog;
@property NSDictionary *renderedInstalled;
@property NSMutableArray<UIButton *> *packageButtons;
@end
@implementation PBToolsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"组件库";self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.backButtonDisplayMode=UINavigationItemBackButtonDisplayModeMinimal;
    UIStackView *content=PBPageContent(self.view,self.view.bottomAnchor);
    [content addArrangedSubview:PBLabel(@"首次构建建议安装「构建资源」和「iOS 16.4 SDK」。",15,UIFontWeightMedium,UIColor.secondaryLabelColor)];
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
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:PBPackagesChanged object:nil];[self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated];[self refresh]; }
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
    self.coreLabel.text=[status[@"compilerBundled"] boolValue]?@"已包含在安装包中":@"安装包中未找到编译核心";
    self.sourceButton.enabled = !store.busy && !store.buildRunning;
    self.downloadStatus.hidden = !store.busy && !store.message.length;
    self.cancelButton.hidden=!store.busy;self.progress.hidden=!store.busy;
    self.progress.progress=store.progress;self.message.text=store.busy?[NSString stringWithFormat:@"%@  %.0f%%",store.message,store.progress*100]:store.message;
    if(self.renderedCatalog!=store.catalog||![self.renderedInstalled isEqual:installed]) {
        self.renderedCatalog=store.catalog;self.renderedInstalled=installed;
        for(UIView *v in self.packagesStack.arrangedSubviews){[self.packagesStack removeArrangedSubview:v];[v removeFromSuperview];}
        self.packageButtons=[NSMutableArray array];
        for(NSDictionary *package in store.catalog) {
            NSString *identifier=package[@"id"];BOOL ready=installed[identifier]!=nil;
            NSString *detail=[identifier isEqual:@"support"]?@"Logos 预处理器、Clang 头文件与辅助资源":[identifier isEqual:@"sdk16"]?@"常见插件和 UIKit 工程的推荐 SDK":@"新系统头文件；C++ 工程还需要 SDK 16.4";
            UIStackView *card=PBCard();[card addArrangedSubview:PBFeature([identifier isEqual:@"support"]?@"wrench.and.screwdriver":@"square.stack.3d.up",package[@"title"],detail)];
            NSString *statusText = ready ? @"已安装" : @"尚未安装";
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
