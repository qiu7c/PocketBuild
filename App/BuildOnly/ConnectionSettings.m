#import "ConnectionSettings.h"
#import "Appearance.h"
#import "BuildService.h"
#import "../Remote/DXRemoteNetwork.h"

@interface PBConnectionController : UIViewController
@property UITextField *addressField, *portField, *codeField;
@property UISegmentedControl *mode;
@property UIStackView *fixedFields;
@end
@implementation PBConnectionController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"连接设置";self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.backButtonDisplayMode=UINavigationItemBackButtonDisplayModeMinimal;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    UIStackView *content=PBPageContent(self.view,nil);
    UIStackView *network=PBCard();[network addArrangedSubview:PBFeature(@"network",@"局域网地址",@"选择手机的热点或 Wi-Fi 地址。")];
    self.addressField=[self field:@"手机 IPv4" text:[NSUserDefaults.standardUserDefaults stringForKey:@"BuildAddress"] keyboard:UIKeyboardTypeNumbersAndPunctuation secure:NO];
    [network addArrangedSubview:self.addressField];
    __weak typeof(self) weak=self;
    for(NSDictionary *item in DXBuildService.interfaces) {
        NSString *kind=[item[@"interface"] hasPrefix:@"bridge"]?@"个人热点":@"Wi-Fi";
        UIButton *pick=PBButton([NSString stringWithFormat:@"%@  %@",kind,item[@"address"]],@"arrow.down.left",NO);
        [pick addAction:[UIAction actionWithHandler:^(UIAction *action){weak.addressField.text=item[@"address"];} ] forControlEvents:UIControlEventTouchUpInside];
        [network addArrangedSubview:pick];
    }
    self.portField=[self field:@"端口" text:@([NSUserDefaults.standardUserDefaults integerForKey:@"BuildPort"]?:8787).stringValue keyboard:UIKeyboardTypeNumberPad secure:NO];
    [network addArrangedSubview:PBLabel(@"监听端口",12,UIFontWeightMedium,UIColor.secondaryLabelColor)];[network addArrangedSubview:self.portField];[content addArrangedSubview:network];
    UIStackView *pairing=PBCard();[pairing addArrangedSubview:PBFeature(@"key.horizontal",@"连接码",@"固定连接码保存在系统钥匙串中。")];
    self.mode=[[UISegmentedControl alloc] initWithItems:@[@"每次随机",@"固定连接码"]];self.mode.selectedSegmentIndex=DXBuildService.shared.fixedCodeEnabled?1:0;
    [self.mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];[pairing addArrangedSubview:self.mode];
    self.fixedFields=[UIStackView new];self.fixedFields.axis=UILayoutConstraintAxisVertical;self.fixedFields.spacing=12;
    self.codeField=[self field:@"留空自动生成，或输入 8–64 位连接码" text:DXBuildService.shared.fixedCode keyboard:UIKeyboardTypeASCIICapable secure:YES];
    [self.fixedFields addArrangedSubview:self.codeField];
    UIStackView *actions=[UIStackView new];actions.axis=UILayoutConstraintAxisHorizontal;actions.spacing=10;actions.distribution=UIStackViewDistributionFillEqually;
    UIButton *reveal=PBButton(@"显示",@"eye",NO);[reveal addTarget:self action:@selector(reveal:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *generate=PBButton(@"重新生成",@"arrow.clockwise",NO);[generate addTarget:self action:@selector(generate) forControlEvents:UIControlEventTouchUpInside];
    [actions addArrangedSubview:reveal];[actions addArrangedSubview:generate];[self.fixedFields addArrangedSubview:actions];[pairing addArrangedSubview:self.fixedFields];
    [pairing addArrangedSubview:PBLabel(@"随机模式每次启动服务都会换码。固定模式便于浏览器和 MCP 长期使用同一份连接配置。",13,UIFontWeightRegular,UIColor.secondaryLabelColor)];
    [content addArrangedSubview:pairing];[self modeChanged];
    [content addArrangedSubview:PBLabel(@"保存后，下次启动服务时使用新设置。",12,UIFontWeightRegular,UIColor.secondaryLabelColor)];
}
- (UITextField *)field:(NSString *)placeholder text:(NSString *)text keyboard:(UIKeyboardType)keyboard secure:(BOOL)secure {
    UITextField *field=[UITextField new];field.placeholder=placeholder;field.text=text;field.font=PBFont(15,UIFontWeightRegular);
    field.borderStyle=UITextBorderStyleRoundedRect;field.keyboardType=keyboard;field.autocorrectionType=UITextAutocorrectionTypeNo;
    field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.secureTextEntry=secure;[field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;return field;
}
- (void)modeChanged { self.fixedFields.hidden=self.mode.selectedSegmentIndex==0; }
- (void)reveal:(UIButton *)button {
    self.codeField.secureTextEntry=!self.codeField.secureTextEntry;
    UIButtonConfiguration *c=button.configuration;c.title=self.codeField.secureTextEntry?@"显示":@"隐藏";button.configuration=c;
}
- (void)generate {
    NSError *error=nil;NSString *code=[DXBuildService newConnectionCode:&error];
    if(code){self.codeField.text=code;PBToast(self,@"新连接码将在保存后生效");}else PBShowError(self,error.localizedDescription);
}
- (void)save {
    [self.view endEditing:YES];
    NSString *address=[self.addressField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *port=self.portField.text;
    if((address.length&&!DXRemotePrivateIPv4(address))||!port.length||[port rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound||port.integerValue<1024||port.integerValue>65535) {
        PBShowError(self,@"填写手机的局域网 IPv4，端口范围为 1024–65535。");return;
    }
    NSError *error=nil;BOOL fixed=self.mode.selectedSegmentIndex==1;
    if(fixed&&![DXBuildService.shared saveFixedCode:self.codeField.text error:&error]){PBShowError(self,error.localizedDescription);return;}
    [DXBuildService.shared setFixedCodeEnabled:fixed];
    [NSUserDefaults.standardUserDefaults setObject:address forKey:@"BuildAddress"];
    [NSUserDefaults.standardUserDefaults setInteger:port.integerValue forKey:@"BuildPort"];
    self.codeField.text=DXBuildService.shared.fixedCode;PBToast(self,@"连接设置已保存");
}
@end
UIViewController *PBConnectionSettings(void) { return [PBConnectionController new]; }
