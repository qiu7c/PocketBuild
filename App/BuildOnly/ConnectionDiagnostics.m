#import "Workspace.h"
#import "Appearance.h"
#import "BuildService.h"
#import "ConnectionSettings.h"

@interface PBConnectionDiagnosticsController : UIViewController
@property UILabel *listener;
@property UILabel *reach;
@property UILabel *auth;
@property UILabel *activity;
@property UILabel *nextStep;
@property UIButton *addressButton;
@end

@implementation PBConnectionDiagnosticsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"连接诊断";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIStackView *content = PBPageContent(self.view, nil);
    UIStackView *checks = PBCard();
    [checks addArrangedSubview:PBFeature(@"antenna.radiowaves.left.and.right", @"手机服务", @"")];
    self.listener = PBLabel(@"", 14, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [checks addArrangedSubview:self.listener];
    [checks addArrangedSubview:PBFeature(@"laptopcomputer", @"电脑访问", @"")];
    self.reach = PBLabel(@"", 14, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [checks addArrangedSubview:self.reach];
    [checks addArrangedSubview:PBFeature(@"key.horizontal", @"连接码验证", @"")];
    self.auth = PBLabel(@"", 14, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [checks addArrangedSubview:self.auth];
    self.activity = PBLabel(@"", 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [checks addArrangedSubview:self.activity];
    [content addArrangedSubview:checks];
    self.nextStep = PBLabel(@"", 15, UIFontWeightMedium, UIColor.labelColor);
    [content addArrangedSubview:self.nextStep];
    self.addressButton = PBButton(@"复制访问地址", @"doc.on.doc", YES);
    [self.addressButton addTarget:self action:@selector(copyOrigin) forControlEvents:UIControlEventTouchUpInside];
    [content addArrangedSubview:self.addressButton];
    UIButton *settings = PBButton(@"连接设置", @"slider.horizontal.3", NO);
    [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [content addArrangedSubview:settings];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh)
        name:PBConnectionChanged object:nil];
    [self refresh];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)refresh {
    DXBuildService *service = DXBuildService.shared;
    NSDictionary *connection = service.connectionDiagnostics;
    BOOL ready = [connection[@"ready"] boolValue];
    double http = [connection[@"httpAt"] doubleValue];
    double accepted = [connection[@"authorizedAt"] doubleValue];
    double rejected = [connection[@"rejectedAt"] doubleValue];
    NSString *address = connection[@"address"];
    self.listener.text = address.length ? [NSString stringWithFormat:@"%@\n%@", connection[@"listener"], address] : connection[@"listener"];
    NSString *peer = connection[@"peer"];
    if (http > 0) {
        NSString *time = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:http]
            dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        self.reach.text = [NSString stringWithFormat:@"已收到 HTTP 请求 · %@ · %@", peer, time];
    } else self.reach.text = @"本次服务尚未收到电脑的请求";
    self.auth.text = rejected > accepted ? @"最近一次认证被拒绝（HTTP 401）" :
        accepted > 0 ? @"已通过连接码验证" : @"等待浏览器或 MCP 提交连接码";
    self.activity.hidden = !ready;
    if (ready) {
        NSString *started = [NSDateFormatter localizedStringFromDate:service.startedAt
            dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
        self.activity.text = [NSString stringWithFormat:@"启动于 %@ · 已认证请求 %lu 次", started, (unsigned long)service.requestCount];
    }
    if (!ready) {
        self.nextStep.text = @"回到工作台启动服务。若监听失败，请检查手机地址、端口和局域网权限。";
    } else if (!http) {
        NSURL *url = [NSURL URLWithString:address];
        self.nextStep.text = [NSString stringWithFormat:@"让电脑连接手机热点或同一 Wi-Fi，再打开访问地址。打不开时，在 Windows PowerShell 检查端口：\nTest-NetConnection %@ -Port %@", url.host, url.port];
    } else if (rejected > accepted) {
        self.nextStep.text = @"以工作台显示的连接码为准。MCP 更新连接码后需要重启其进程。";
    } else if (!accepted) {
        self.nextStep.text = @"电脑已访问手机，在浏览器输入连接码，或在 MCP 调用 connect_device 继续验证。";
    } else self.nextStep.text = @"连接验证完成，可以上传项目或进行构建。";
    self.addressButton.enabled = ready;
}

- (void)copyOrigin {
    UIPasteboard.generalPasteboard.string = DXBuildService.shared.origin;
    PBToast(self, @"访问地址已复制");
}
- (void)openSettings { [self.navigationController pushViewController:PBConnectionSettings() animated:YES]; }
@end

UIViewController *PBConnectionDiagnostics(void) { return [PBConnectionDiagnosticsController new]; }
