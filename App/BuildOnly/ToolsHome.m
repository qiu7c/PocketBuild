#import "Toolchains.h"
#import "PackagePaths.h"
#import <UIKit/UIKit.h>

@interface PBToolsController : UITableViewController
@property NSArray<NSDictionary *> *packages;
@end

@implementation PBToolsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"工具链管理";
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh)
        name:PBPackagesChanged object:nil];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消下载"
        style:UIBarButtonItemStylePlain target:PBToolchains.shared action:@selector(cancel)];
    [self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh {
    self.packages = PBToolchains.shared.catalog;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : self.packages.count;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"资源来源" : @"可选组件";
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"编译核心已随 PocketBuild 安装。加载 PocketBuild-packages.json 后，可选择下载 SDK、头文件和 Logos 构建资源。";
    }
    return PBToolchains.shared.message;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 0;
    if (index.section == 0) {
        if (index.row == 0) {
            cell.textLabel.text = @"资源清单地址";
            cell.detailTextLabel.text = [NSUserDefaults.standardUserDefaults stringForKey:@"PackageManifestURL"] ?: @"填写 HTTPS 或局域网 HTTP 地址";
        } else if (index.row == 1) {
            cell.textLabel.text = @"读取资源清单";
        } else {
            NSDictionary *status = PBToolchains.shared.status;
            cell.textLabel.text = [status[@"compilerBundled"] boolValue] ? @"编译核心已包含在 App 中" :
                [status[@"compilerLoaded"] boolValue] ? @"编译核心已加载" : @"编译核心状态";
            cell.detailTextLabel.text = PBToolchains.shared.busy ?
                [NSString stringWithFormat:@"%@ · %.0f%%", PBToolchains.shared.message, PBToolchains.shared.progress * 100] :
                PBToolchains.shared.message;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else {
        NSDictionary *package = self.packages[index.row];
        cell.textLabel.text = package[@"title"];
        NSString *path = PBInstalledPackage(package[@"id"]);
        NSString *size = package[@"bytes"] ? [NSByteCountFormatter stringFromByteCount:[package[@"bytes"] longLongValue]
            countStyle:NSByteCountFormatterCountStyleFile] : @"";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@", path ? @"已安装" : @"可下载", size];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"工具链" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    PBToolchains *store = PBToolchains.shared;
    if (store.busy || store.buildRunning) {
        [self showMessage:@"请等待当前安装或构建结束"];
        return;
    }
    if (index.section == 0 && index.row == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"资源清单地址"
            message:@"可在 Windows 上解压资源包并启动 HTTP 服务，再填写清单的局域网地址。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = [NSUserDefaults.standardUserDefaults stringForKey:@"PackageManifestURL"];
            field.placeholder = @"http://电脑IPv4:8000/PocketBuild-packages.json";
            field.keyboardType = UIKeyboardTypeURL;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
        }];
        __weak UIAlertController *weak = alert;
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *text = [weak.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            [NSUserDefaults.standardUserDefaults setObject:text forKey:@"PackageManifestURL"];
            [self refresh];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (index.section == 0 && index.row == 1) {
        NSString *text = [NSUserDefaults.standardUserDefaults stringForKey:@"PackageManifestURL"];
        [store loadManifest:[NSURL URLWithString:text ?: @""]];
    } else if (index.section == 1) {
        NSDictionary *package = self.packages[index.row];
        NSString *identifier = package[@"id"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:package[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"下载安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [store install:identifier];
        }]];
        if (PBInstalledPackage(identifier)) {
            [alert addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                NSError *error = nil;
                if (![store remove:identifier error:&error]) [self showMessage:error.localizedDescription];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        alert.popoverPresentationController.sourceView = table;
        alert.popoverPresentationController.sourceRect = [table rectForRowAtIndexPath:index];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end

UIViewController *PBToolsHome(void) {
    return [[PBToolsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
}
