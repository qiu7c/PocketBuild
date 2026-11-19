#import "Toolchains.h"
#import "PackagePaths.h"
#import "Appearance.h"

@interface PBToolsController : UIViewController
@property UITextField *urlField;
@property UILabel *message, *coreLabel;
@property UIProgressView *progress;
@property UIButton *loadButton, *cancelButton;
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
    [content addArrangedSubview:PBLabel(@"你需要的，\n再装进来。",30,UIFontWeightBold,UIColor.labelColor)];
    [content addArrangedSubview:PBLabel(@"编译器随 App 就位，SDK 与构建资源按需安装。",14,UIFontWeightRegular,UIColor.secondaryLabelColor)];
    UIStackView *core=PBCard();[core addArrangedSubview:PBFeature(@"checkmark.seal",@"本机编译核心",@"Clang · LLVM · LLD · Perl")];
    self.coreLabel=PBLabel(@"",13,UIFontWeightMedium,UIColor.secondaryLabelColor);[core addArrangedSubview:self.coreLabel];[content addArrangedSubview:core];
    UIStackView *source=PBCard();[source addArrangedSubview:PBLabel(@"资源来源",18,UIFontWeightBold,UIColor.labelColor)];
    self.urlField=[UITextField new];self.urlField.placeholder=@"HTTPS 或局域网资源清单地址";self.urlField.text=[NSUserDefaults.standardUserDefaults stringForKey:@"PackageManifestURL"];
    self.urlField.font=PBFont(14,UIFontWeightRegular);self.urlField.borderStyle=UITextBorderStyleRoundedRect;self.urlField.keyboardType=UIKeyboardTypeURL;
    self.urlField.autocorrectionType=UITextAutocorrectionTypeNo;self.urlField.autocapitalizationType=UITextAutocapitalizationTypeNone;
    [self.urlField.heightAnchor constraintEqualToConstant:48].active=YES;[source addArrangedSubview:self.urlField];
    self.loadButton=PBButton(@"读取资源清单",@"arrow.down.doc",YES);[self.loadButton addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];[source addArrangedSubview:self.loadButton];
    self.progress=[UIProgressView new];self.progress.progressTintColor=PBAccent();[source addArrangedSubview:self.progress];
    self.message=PBLabel(@"",13,UIFontWeightRegular,UIColor.secondaryLabelColor);[source addArrangedSubview:self.message];
    self.cancelButton=PBButton(@"取消当前任务",@"xmark",NO);[self.cancelButton addTarget:PBToolchains.shared action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];[source addArrangedSubview:self.cancelButton];
    [content addArrangedSubview:source];
    [content addArrangedSubview:PBLabel(@"可选组件",19,UIFontWeightBold,UIColor.labelColor)];
    self.packagesStack=[UIStackView new];self.packagesStack.axis=UILayoutConstraintAxisVertical;self.packagesStack.spacing=14;[content addArrangedSubview:self.packagesStack];
    [content addArrangedSubview:PBLabel(@"资源包下载完成后会校验 SHA-256。升级 App 时保留数据，已安装组件即可继续使用。",12,UIFontWeightRegular,UIColor.tertiaryLabelColor)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:PBPackagesChanged object:nil];[self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated];[self refresh]; }
- (void)load {
    [self.view endEditing:YES];NSString *text=[self.urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(![PBToolchains.shared loadManifest:[NSURL URLWithString:text]]){PBShowError(self,PBToolchains.shared.message);return;}
    [NSUserDefaults.standardUserDefaults setObject:text forKey:@"PackageManifestURL"];
}
- (void)refresh {
    __weak typeof(self) weak=self;
    PBToolchains *store=PBToolchains.shared;NSDictionary *status=store.status;NSDictionary *installed=status[@"installed"];
    self.coreLabel.text=[status[@"compilerBundled"] boolValue]?@"已包含在安装包中":@"安装包中未找到编译核心";
    self.loadButton.enabled=!store.busy&&!store.buildRunning;self.cancelButton.hidden=!store.busy;self.progress.hidden=!store.busy;
    self.progress.progress=store.progress;self.message.text=store.busy?[NSString stringWithFormat:@"%@  %.0f%%",store.message,store.progress*100]:store.message;
    if(self.renderedCatalog!=store.catalog||![self.renderedInstalled isEqual:installed]) {
        self.renderedCatalog=store.catalog;self.renderedInstalled=installed;
        for(UIView *v in self.packagesStack.arrangedSubviews){[self.packagesStack removeArrangedSubview:v];[v removeFromSuperview];}
        self.packageButtons=[NSMutableArray array];
        if(!store.catalog.count){UIStackView *empty=PBCard();[empty addArrangedSubview:PBFeature(@"shippingbox",@"等待添加组件",@"读取资源清单后，这里会显示 SDK、头文件与 Logos 构建资源。")];[self.packagesStack addArrangedSubview:empty];}
        for(NSDictionary *package in store.catalog) {
            NSString *identifier=package[@"id"];BOOL ready=installed[identifier]!=nil;
            NSString *detail=[identifier isEqual:@"support"]?@"Logos 预处理器、Clang 头文件与辅助资源":[identifier isEqual:@"sdk16"]?@"常见插件和 UIKit 工程的推荐 SDK":@"新系统头文件；C++ 工程还需要 SDK 16.4";
            UIStackView *card=PBCard();[card addArrangedSubview:PBFeature([identifier isEqual:@"support"]?@"wrench.and.screwdriver":@"square.stack.3d.up",package[@"title"],detail)];
            NSString *size=package[@"bytes"]?[NSByteCountFormatter stringFromByteCount:[package[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]:@"";
            [card addArrangedSubview:PBLabel([NSString stringWithFormat:@"%@  ·  %@",ready?@"已安装":@"尚未安装",size],12,UIFontWeightMedium,ready?PBAccent():UIColor.secondaryLabelColor)];
            UIStackView *actions=[UIStackView new];actions.axis=UILayoutConstraintAxisHorizontal;actions.spacing=10;
            UIButton *install=PBButton(ready?@"重新安装":@"下载安装",@"arrow.down.circle",NO);
            [install addAction:[UIAction actionWithHandler:^(UIAction *a){[store install:identifier];}] forControlEvents:UIControlEventTouchUpInside];[actions addArrangedSubview:install];[self.packageButtons addObject:install];
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
