#import "ConnectionSettings.h"
#import "Appearance.h"
#import "BuildService.h"
#import "Toolchains.h"
#import "Workspace.h"

@interface PBWelcomeController : UIViewController
@property BOOL firstLaunch;
@property NSInteger page;
@property UIStackView *content;
@property UILabel *step;
@property UIButton *next, *previous;
@property UIImageView *brand;
@property UITextField *fixedField;
@property UISegmentedControl *mode;
@end
@implementation PBWelcomeController
- (void)viewDidLoad {
    [super viewDidLoad];self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.backButtonDisplayMode=UINavigationItemBackButtonDisplayModeMinimal;
    if(self.firstLaunch)self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"跳过介绍" style:UIBarButtonItemStylePlain target:self action:@selector(finishWithoutSetup)];
    UIStackView *footer=[UIStackView new];footer.axis=UILayoutConstraintAxisVertical;footer.spacing=12;footer.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:footer];self.step=PBLabel(@"",12,UIFontWeightSemibold,UIColor.secondaryLabelColor);self.step.textAlignment=NSTextAlignmentCenter;[footer addArrangedSubview:self.step];
    UIStackView *buttons=[UIStackView new];buttons.axis=UILayoutConstraintAxisHorizontal;buttons.spacing=12;
    self.previous=PBButton(@"上一步",@"chevron.left",NO);[self.previous addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    self.next=PBButton(@"开始使用",@"arrow.right",YES);[self.next addTarget:self action:@selector(advance) forControlEvents:UIControlEventTouchUpInside];
    [buttons addArrangedSubview:self.previous];[buttons addArrangedSubview:self.next];[footer addArrangedSubview:buttons];
    [NSLayoutConstraint activateConstraints:@[[footer.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12],
        [self.next.heightAnchor constraintGreaterThanOrEqualToConstant:54]]];
    self.content=PBPageContent(self.view,footer.topAnchor);[self.view bringSubviewToFront:footer];
    self.mode=[[UISegmentedControl alloc] initWithItems:@[@"固定连接码",@"每次随机"]];self.mode.selectedSegmentIndex=([NSUserDefaults.standardUserDefaults objectForKey:@"FixedConnectionCode"]?DXBuildService.shared.fixedCodeEnabled:YES)?0:1;
    [self.mode addTarget:self action:@selector(changeMode) forControlEvents:UIControlEventValueChanged];
    self.fixedField=[UITextField new];self.fixedField.borderStyle=UITextBorderStyleRoundedRect;self.fixedField.font=PBFont(14,UIFontWeightRegular);
    self.fixedField.placeholder=@"留空自动生成，也可设置 8–64 位连接码";self.fixedField.text=DXBuildService.shared.fixedCode;self.fixedField.secureTextEntry=YES;
    self.fixedField.keyboardType=UIKeyboardTypeASCIICapable;self.fixedField.autocapitalizationType=UITextAutocapitalizationTypeNone;self.fixedField.autocorrectionType=UITextAutocorrectionTypeNo;
    [self.fixedField.heightAnchor constraintEqualToConstant:48].active=YES;
    [self render];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated];[self animateIntro]; }
- (void)render {
    [self.brand.layer removeAllAnimations];
    for(UIView *v in self.content.arrangedSubviews){[self.content removeArrangedSubview:v];[v removeFromSuperview];}
    self.step.text=[NSString stringWithFormat:@"%02ld / 04   ·   %@",(long)self.page+1,@[@"认识 PocketBuild",@"连接你的电脑",@"准备构建组件",@"设置配对方式"][self.page]];
    self.previous.hidden=self.page==0;UIButtonConfiguration *config=self.next.configuration;config.title=self.page==0?@"开始使用":self.page==3?@"进入工作台":@"继续";self.next.configuration=config;
    if(self.page==0) {
        UIView *stage=[UIView new];[stage.heightAnchor constraintEqualToConstant:230].active=YES;
        self.brand=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"BrandMark"]];self.brand.translatesAutoresizingMaskIntoConstraints=NO;self.brand.layer.cornerRadius=42;
        self.brand.layer.cornerCurve=kCACornerCurveContinuous;self.brand.clipsToBounds=YES;[stage addSubview:self.brand];
        [NSLayoutConstraint activateConstraints:@[[self.brand.widthAnchor constraintEqualToConstant:180],[self.brand.heightAnchor constraintEqualToConstant:180],
            [self.brand.centerXAnchor constraintEqualToAnchor:stage.centerXAnchor],[self.brand.centerYAnchor constraintEqualToAnchor:stage.centerYAnchor]]];[self.content addArrangedSubview:stage];
        [self.content addArrangedSubview:PBLabel(@"把编译工作台，\n放进口袋。",34,UIFontWeightBold,UIColor.labelColor)];
        [self.content addArrangedSubview:PBLabel(@"iPhone 负责构建，电脑负责创作。\n浏览器与 MCP 使用同一套本机编译能力。",16,UIFontWeightRegular,UIColor.secondaryLabelColor)];
        UIStackView *card=PBCard();[card addArrangedSubview:PBFeature(@"hammer",@"手机本机构建",@"插件 dylib、三种 DEB，以及受支持的 UIKit App。")];
        [card addArrangedSubview:PBFeature(@"laptopcomputer",@"Windows 也能顺手开发",@"上传、编辑、查看日志，直接下载编译产物。")];[self.content addArrangedSubview:card];
    } else if(self.page==1) {
        [self.content addArrangedSubview:PBLabel(@"一条局域网，\n连接两端。",32,UIFontWeightBold,UIColor.labelColor)];
        UIStackView *diagram=PBCard();UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.distribution=UIStackViewDistributionFillEqually;row.alignment=UIStackViewAlignmentCenter;
        for(NSString *symbol in @[@"iphone",@"arrow.left.arrow.right",@"laptopcomputer"]) {
            UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];icon.tintColor=[symbol isEqual:@"arrow.left.arrow.right"]?PBAccent():UIColor.labelColor;icon.contentMode=UIViewContentModeScaleAspectFit;
            [icon.heightAnchor constraintEqualToConstant:60].active=YES;[row addArrangedSubview:icon];
        }
        [diagram addArrangedSubview:row];[diagram addArrangedSubview:PBLabel(@"个人热点或同一 Wi-Fi 都可以",14,UIFontWeightMedium,UIColor.secondaryLabelColor)];[self.content addArrangedSubview:diagram];
        UIStackView *steps=PBCard();[steps addArrangedSubview:PBFeature(@"1.circle",@"连接网络",@"打开手机个人热点，让 Windows 连上；或让两端连接同一 Wi-Fi。")];
        [steps addArrangedSubview:PBFeature(@"2.circle",@"启动服务",@"在工作台开启服务，复制手机显示的访问地址。")];
        [steps addArrangedSubview:PBFeature(@"3.circle",@"打开浏览器或 MCP",@"电脑浏览器访问该地址并输入连接码。MCP 使用相同地址和连接码。")];[self.content addArrangedSubview:steps];
        [self.content addArrangedSubview:PBLabel(@"构建期间让 PocketBuild 保持前台。",13,UIFontWeightMedium,UIColor.secondaryLabelColor)];
    } else if(self.page==2) {
        [self.content addArrangedSubview:PBLabel(@"按需准备，\n轻装开始。",32,UIFontWeightBold,UIColor.labelColor)];
        UIStackView *card=PBCard();[card addArrangedSubview:PBFeature(@"checkmark.seal",@"编译器已随 App 就位",@"Clang、LLVM、LLD 与 Perl 已包含在安装包中。")];
        [card addArrangedSubview:PBFeature(@"shippingbox",@"构建资源 + SDK",@"构建资源必装，SDK 按工程选择。组件库会列出缺少的组件，安装完就能试编译。")];[self.content addArrangedSubview:card];
        UIButton *library = PBButton(@"打开组件库", @"arrow.down.circle", NO);
        [library addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];
        [self.content addArrangedSubview:library];
        [self.content addArrangedSubview:PBLabel(@"可以现在下载，也可以进入工作台后再安装。",13,UIFontWeightRegular,UIColor.secondaryLabelColor)];
    } else {
        [self.content addArrangedSubview:PBLabel(@"这台电脑，\n下次也认识。",32,UIFontWeightBold,UIColor.labelColor)];
        UIStackView *card=PBCard();[card addArrangedSubview:PBFeature(@"key.horizontal",@"选择连接码方式",@"固定码适合常用电脑和 MCP，随机码适合临时连接。")];
        [card addArrangedSubview:self.mode];[card addArrangedSubview:self.fixedField];[self changeMode];
        [card addArrangedSubview:PBLabel(@"固定连接码保存在系统钥匙串中；留空会自动生成。以后可在连接设置中修改。",13,UIFontWeightRegular,UIColor.secondaryLabelColor)];[self.content addArrangedSubview:card];
        [self.content addArrangedSubview:PBFeature(@"arrow.up.right",@"准备好之后",@"进入工作台，检查网络，启动服务，然后在电脑打开访问地址。")];
    }
}
- (void)animateIntro {
    if(self.page!=0)return;
    if(UIAccessibilityIsReduceMotionEnabled())return;
    self.brand.alpha=0;self.brand.transform=CGAffineTransformConcat(CGAffineTransformMakeTranslation(0,24),CGAffineTransformMakeScale(.88,.88));
    [UIView animateWithDuration:.8 delay:0 usingSpringWithDamping:.8 initialSpringVelocity:.2 options:0 animations:^{self.brand.alpha=1;self.brand.transform=CGAffineTransformIdentity;} completion:nil];
}
- (void)changeMode { self.fixedField.hidden=self.mode.selectedSegmentIndex==1; }
- (void)openTools { [self.navigationController pushViewController:PBToolsHome() animated:YES]; }
- (void)back { [self.view endEditing:YES];self.page--;[self transition]; }
- (void)advance {
    [self.view endEditing:YES];
    if(self.page<3){self.page++;[self transition];return;}
    NSError *error=nil;BOOL fixed=self.mode.selectedSegmentIndex==0;
    if(fixed&&![DXBuildService.shared saveFixedCode:self.fixedField.text error:&error]){PBShowError(self,error.localizedDescription);return;}
    [DXBuildService.shared setFixedCodeEnabled:fixed];[self finishWithoutSetup];
}
- (void)transition {
    [UIView transitionWithView:self.content duration:UIAccessibilityIsReduceMotionEnabled()?0:.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{[self render];} completion:nil];
    UIScrollView *scroll=(UIScrollView *)self.content.superview;[scroll setContentOffset:CGPointMake(0,-scroll.adjustedContentInset.top) animated:NO];[self animateIntro];
}
- (void)finishWithoutSetup {
    if (!self.firstLaunch) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"PocketBuildWelcomeCompleted"];
    UIWindow *window = self.view.window;
    [UIView transitionWithView:window duration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .25
        options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            window.rootViewController = PBWorkspace();
        } completion:nil];
}
@end
UIViewController *PBWelcomeScreen(BOOL firstLaunch) { PBWelcomeController *c=[PBWelcomeController new];c.firstLaunch=firstLaunch;c.page=firstLaunch?0:1;return c; }
