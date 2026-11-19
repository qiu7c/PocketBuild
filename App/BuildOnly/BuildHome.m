#import "BuildService.h"
#import "Toolchains.h"
#import "../Remote/DXRemoteNetwork.h"

@interface DXBuildHomeController : UITableViewController
@property NSArray<NSDictionary *> *interfaces;
@property NSString *address;
@property NSUInteger port;
@end

@implementation DXBuildHomeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PocketBuild";
    self.port = [NSUserDefaults.standardUserDefaults integerForKey:@"BuildPort"] ?: 8787;
    self.address = [NSUserDefaults.standardUserDefaults stringForKey:@"BuildAddress"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新地址"
        style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    __weak typeof(self) weak = self;
    DXBuildService.shared.changed = ^{ [weak.tableView reloadData]; };
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"工具链"
        style:UIBarButtonItemStylePlain target:self action:@selector(openTools)];
    [self refresh];
}
- (void)openTools { [self.navigationController pushViewController:PBToolsHome() animated:YES]; }
- (void)refresh {
    self.interfaces = DXBuildService.interfaces;
    BOOL found = NO;
    for (NSDictionary *item in self.interfaces) if ([item[@"address"] isEqual:self.address]) found = YES;
    if (!found && self.interfaces.count) self.address = self.interfaces.firstObject[@"address"];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 6; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return @"开启个人热点，让 Windows 连接热点，然后刷新地址。也可使用同一局域网。电脑浏览器打开访问地址并填写连接码。编译期间请保持本 App 在前台。";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    DXBuildService *service = DXBuildService.shared;
    NSArray *titles = @[@"监听地址", @"端口", @"服务状态", @"访问地址", @"连接码", service.origin ? @"停止服务" : @"启动服务"];
    cell.textLabel.text = titles[index.row];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.text = index.row == 0 ? (self.address ?: @"请选择或手动输入") :
        index.row == 1 ? @(self.port).stringValue : index.row == 2 ? service.state :
        index.row == 3 ? (service.origin ?: @"启动后显示") : index.row == 4 ? (service.code ?: @"启动后显示") : @"";
    cell.selectionStyle = index.row == 2 ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    return cell;
}
- (void)editAddress {
    UIAlertController *list = [UIAlertController alertControllerWithTitle:@"监听地址" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *item in self.interfaces) {
        NSString *title = [NSString stringWithFormat:@"%@  %@", item[@"interface"], item[@"address"]];
        [list addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.address = item[@"address"];
            [self.tableView reloadData];
        }]];
    }
    [list addAction:[UIAlertAction actionWithTitle:@"手动输入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self editField:NO];
    }]];
    [list addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    list.popoverPresentationController.sourceView = self.tableView;
    list.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    [self presentViewController:list animated:YES completion:nil];
}
- (void)editField:(BOOL)isPort {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isPort ? @"端口" : @"局域网 IPv4"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = isPort ? @(self.port).stringValue : self.address;
        field.keyboardType = isPort ? UIKeyboardTypeNumberPad : UIKeyboardTypeNumbersAndPunctuation;
    }];
    __weak UIAlertController *weak = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = [weak.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL valid = isPort ? text.integerValue >= 1024 && text.integerValue <= 65535 &&
            [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound :
            DXRemotePrivateIPv4(text);
        if (valid) {
            if (isPort) self.port = text.integerValue; else self.address = text;
            [self.tableView reloadData];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    DXBuildService *service = DXBuildService.shared;
    if (index.row == 0 && !service.origin) [self editAddress];
    if (index.row == 1 && !service.origin) [self editField:YES];
    if (index.row == 3 && service.origin) UIPasteboard.generalPasteboard.string = service.origin;
    if (index.row == 4 && service.code) UIPasteboard.generalPasteboard.string = service.code;
    if (index.row == 5) {
        if (service.origin) {
            [service stop];
        } else if (DXRemotePrivateIPv4(self.address)) {
            [NSUserDefaults.standardUserDefaults setObject:self.address forKey:@"BuildAddress"];
            [NSUserDefaults.standardUserDefaults setInteger:self.port forKey:@"BuildPort"];
            [service startAddress:self.address port:self.port];
        } else {
            [self editAddress];
        }
    }
}
@end

UIViewController *DXBuildHome(void) {
    return [[DXBuildHomeController alloc] initWithStyle:UITableViewStyleInsetGrouped];
}

@interface DXBuildAppDelegate : UIResponder <UIApplicationDelegate>
@property UIWindow *window;
@end
@implementation DXBuildAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:DXBuildHome()];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(DXBuildAppDelegate.class));
    }
}
