#import "Workspace.h"
#import "Appearance.h"
#import "BuildService.h"
#import "BuildBackground.h"
#import "SourceEditor.h"
#import "../DocumentPresentation.h"

#import "ProjectRecords.h"
#import "Toolchains.h"

static UIViewController *BuildResult(NSString *identifier, BOOL assign);

@interface PBBuildRecordsController : UIViewController
@property UIStackView *activeCard;
@property UILabel *stage;
@property UIProgressView *progress;
@property UIButton *cancel;
@property UIStackView *history;
@property NSString *projectID;
@end

@implementation PBBuildRecordsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.projectID ? @"项目构建" : @"构建";
    self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    UIStackView *content = PBPageContent(self.view, self.view.bottomAnchor);
    self.activeCard = PBCard();
    [self.activeCard addArrangedSubview:PBLabel(PBBuildStateTitle(@"running"), 16, UIFontWeightSemibold, UIColor.labelColor)];
    self.stage = PBLabel(@"", 14, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [self.activeCard addArrangedSubview:self.stage];
    self.progress = [UIProgressView new];
    self.progress.progressTintColor = PBAccent();
    [self.activeCard addArrangedSubview:self.progress];
    self.cancel = PBButton(@"取消构建", @"xmark", NO);
    [self.cancel addTarget:self action:@selector(cancelBuild) forControlEvents:UIControlEventTouchUpInside];
    [self.activeCard addArrangedSubview:self.cancel];
    [content addArrangedSubview:self.activeCard];
    if (!self.projectID) [content addArrangedSubview:PBLabel(@"项目", 13, UIFontWeightMedium, UIColor.secondaryLabelColor)];
    self.history = [UIStackView new];
    self.history.axis = UILayoutConstraintAxisVertical;
    self.history.spacing = 12;
    [content addArrangedSubview:self.history];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(buildEvent:)
        name:PBBuildChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(buildEvent:)
        name:PBBackgroundBuildChanged object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildChanged];
    [self reloadHistory];
}

- (void)cancelBuild {
    [DXBuildService.shared cancelBuild];
    self.cancel.enabled = NO;
}

- (void)buildChanged {
    NSDictionary *job = DXBuildService.shared.latestJob;
    BOOL running = [job[@"state"] isEqual:@"running"] && (!self.projectID || [job[@"project"] isEqual:self.projectID]);
    BOOL wasHidden = self.activeCard.hidden;
    self.activeCard.hidden = !running;
    self.stage.text = job[@"stage"] ?: @"准备编译器…";
    if (PBBackgroundAudioPlaying()) self.stage.text = [self.stage.text stringByAppendingString:@"\n后台辅助运行中"];
    self.progress.progress = [job[@"progress"] floatValue];
    if (!running || wasHidden) self.cancel.enabled = YES;
}

- (void)buildEvent:(NSNotification *)event {
    if (!self.view.window) return;
    [self buildChanged];
    if (event.object && [event.name isEqual:PBBuildChanged]) [self reloadHistory];
}

- (void)reloadHistory {
    for (UIView *view in self.history.arrangedSubviews) [view removeFromSuperview];
    DXBuildService *service = DXBuildService.shared;
    NSArray<NSDictionary *> *projects = service.projectList;
    NSArray<NSDictionary *> *allJobs = service.recordedBuilds;
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *project in projects) groups[project[@"id"]] = [NSMutableArray array];
    groups[@""] = [NSMutableArray array];
    for (NSDictionary *job in allJobs) {
        NSString *key = job[@"project"] ?: @"";
        [(groups[key] ?: groups[@""]) addObject:job];
    }

    if (self.projectID) {
        NSDictionary *project = nil;
        for (NSDictionary *entry in projects) {
            if ([entry[@"id"] isEqual:self.projectID]) { project = entry; break; }
        }
        if (project) {
            self.title = project[@"name"];
            [self addProjectActions:project jobs:groups[self.projectID]];
        } else {
            self.title = @"未归档";
        }
        NSArray *jobs = groups[self.projectID] ?: @[];
        [self.history addArrangedSubview:PBLabel(@"构建记录", 13, UIFontWeightMedium, UIColor.secondaryLabelColor)];
        for (NSDictionary *job in jobs) {
            if ([job[@"state"] isEqual:@"running"]) continue;
            [self addRecord:job];
        }
        if (!jobs.count) [self.history addArrangedSubview:PBLabel(@"该项目还没有构建记录。", 14, UIFontWeightRegular, UIColor.secondaryLabelColor)];
        return;
    }

    __weak typeof(self) weak = self;
    for (NSDictionary *project in projects) {
        NSString *identifier = project[@"id"];
        NSArray *jobs = groups[identifier];
        NSString *type = [project[@"productType"] isEqual:@"app"] ? @"UIKit App" : @"插件";
        NSString *suffix = [identifier substringFromIndex:identifier.length - 6];
        UIStackView *card = PBCard();
        [card addArrangedSubview:PBFeature(@"folder", project[@"name"],
            [NSString stringWithFormat:@"%@ · %@ · %lu 次构建", type, suffix, (unsigned long)jobs.count])];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[project[@"lastBuildAt"] doubleValue]];
        NSString *lastBuild = jobs.count ? [NSString stringWithFormat:@"%@ · %@", PBBuildStateTitle(jobs.firstObject[@"state"]),
            [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]] :
            @"还没有构建";
        UILabel *detail = PBLabel(lastBuild, 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
        [card addArrangedSubview:detail];
        UIButton *open = PBButton(@"查看项目", @"chevron.right", NO);
        [open addAction:[UIAction actionWithHandler:^(UIAction *action) {
            [weak.navigationController pushViewController:PBProjectBuilds(identifier) animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [card addArrangedSubview:open];
        [self.history addArrangedSubview:card];

        NSString *source = [[PBDocumentsDirectory() stringByAppendingPathComponent:@"Projects"] stringByAppendingPathComponent:identifier];
        NSArray *paths = [[jobs valueForKey:@"buildPath"] arrayByAddingObject:source];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *size = [NSByteCountFormatter stringFromByteCount:PBAllocatedBytes(paths) countStyle:NSByteCountFormatterCountStyleFile];
            dispatch_async(dispatch_get_main_queue(), ^{
                detail.text = [NSString stringWithFormat:@"%@ · 源码与构建占用 %@", lastBuild, size];
            });
        });
    }
    NSUInteger unfiled = [groups[@""] count];
    if (unfiled) {
        UIButton *legacy = PBButton([NSString stringWithFormat:@"未归档 · %lu 条", (unsigned long)unfiled], @"tray", NO);
        [legacy addAction:[UIAction actionWithHandler:^(UIAction *action) {
            [weak.navigationController pushViewController:PBProjectBuilds(@"") animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [self.history addArrangedSubview:legacy];
    }
    if (!projects.count && !unfiled) {
        UIStackView *empty = PBCard();
        [empty addArrangedSubview:PBFeature(@"tray", @"还没有项目", @"在电脑浏览器新建或导入项目，MCP 上传的项目也会显示在这里。")];
        [self.history addArrangedSubview:empty];
    }
}

- (void)addProjectActions:(NSDictionary *)project jobs:(NSArray<NSDictionary *> *)jobs {
    UIStackView *card = PBCard();
    NSString *identifier = project[@"id"];
    NSDictionary *summary = [DXBuildService.shared projectDetails:identifier];
    NSDictionary *issue = summary[@"issue"];
    NSString *product = [(summary[@"productType"] ?: project[@"productType"]) isEqual:@"app"] ? @"UIKit App" : @"插件";
    [card addArrangedSubview:PBLabel(product, 16, UIFontWeightSemibold, UIColor.labelColor)];
    if (summary[@"sdk"]) {
        NSString *sdk = [NSString stringWithFormat:@"iOS %@ SDK · 最低 iOS %@ · %@", summary[@"sdk"], summary[@"minimum"], summary[@"cpu"]];
        NSArray *outputs = summary[@"outputs"];
        [card addArrangedSubview:PBLabel(sdk, 14, UIFontWeightMedium, UIColor.secondaryLabelColor)];
        [card addArrangedSubview:PBLabel(outputs.count ? [outputs componentsJoinedByString:@" / "] : @"未选择产物",
            14, UIFontWeightMedium, UIColor.secondaryLabelColor)];
    }
    [card addArrangedSubview:PBLabel(issue[@"message"] ?: @"所需组件已就绪", 15, UIFontWeightSemibold, UIColor.labelColor)];
    NSDictionary *latest = jobs.firstObject;
    if (latest) [card addArrangedSubview:PBLabel([@"最近一次 · " stringByAppendingString:PBBuildStateTitle(latest[@"state"])],
        13, UIFontWeightMedium, UIColor.secondaryLabelColor)];
    __weak typeof(self) weak = self;
    BOOL missing = [issue[@"kind"] isEqual:@"components"];
    UIButton *rebuild = PBButton(missing ? @"安装缺少的组件" : jobs.count ? @"重新编译" : @"编译项目",
        missing ? @"arrow.down.circle" : @"hammer", YES);
    rebuild.enabled = !PBToolchains.shared.buildRunning && !PBToolchains.shared.busy;
    [rebuild addAction:[UIAction actionWithHandler:^(UIAction *action) {
        if (missing) {
            [weak.navigationController pushViewController:PBToolsForBuildIssue(issue, identifier) animated:YES];
            return;
        }
        NSError *error = nil;
        NSDictionary *job = [DXBuildService.shared startProjectBuild:identifier error:&error];
        if (!job) PBShowError(weak, error.localizedDescription ?: @"无法创建构建。");
        else [weak showBuild:job];
    }] forControlEvents:UIControlEventTouchUpInside];
    [card addArrangedSubview:rebuild];
    UIButton *source = PBButton(@"项目源码", @"folder", NO);
    [source addAction:[UIAction actionWithHandler:^(UIAction *action) {
        [weak.navigationController pushViewController:PBProjectSources(identifier) animated:YES];
    }] forControlEvents:UIControlEventTouchUpInside];
    [card addArrangedSubview:source];
    if ([summary[@"hasManifest"] boolValue]) {
        UIButton *edit = PBButton(@"编辑构建配置", @"pencil", NO);
        [edit addAction:[UIAction actionWithHandler:^(UIAction *action) {
            PBOpenProjectFile(weak, identifier, @"MobileCompiler.json");
        }] forControlEvents:UIControlEventTouchUpInside];
        [card addArrangedSubview:edit];
    }

    NSDictionary *latestSuccess = nil;
    for (NSDictionary *job in jobs) {
        if ([job[@"state"] isEqual:@"succeeded"]) { latestSuccess = job; break; }
    }
    if (latestSuccess) {
        UIButton *open = PBButton(@"最近成功产物", @"shippingbox", NO);
        [open addAction:[UIAction actionWithHandler:^(UIAction *action) { [weak showBuild:latestSuccess]; }]
            forControlEvents:UIControlEventTouchUpInside];
        [card addArrangedSubview:open];
    }
    UIAction *rename = [UIAction actionWithTitle:@"重命名项目" image:[UIImage systemImageNamed:@"pencil"] identifier:nil
        handler:^(UIAction *action) { [weak renameProject:project]; }];
    NSMutableArray *menu = [NSMutableArray arrayWithObject:rename];
    NSArray *old = PBJobsToClean(jobs);
    if (old.count) {
        UIAction *clean = [UIAction actionWithTitle:[NSString stringWithFormat:@"清理 %lu 条旧构建", (unsigned long)old.count]
            image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) { [weak confirmCleanup:identifier]; }];
        clean.attributes = UIMenuElementAttributesDestructive | (PBToolchains.shared.buildRunning ? UIMenuElementAttributesDisabled : 0);
        [menu addObject:clean];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
        menu:[UIMenu menuWithChildren:menu]];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"项目操作";
    [self.history addArrangedSubview:card];
}

- (void)renameProject:(NSDictionary *)project {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名项目" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = project[@"name"]; }];
    __weak UIAlertController *input = alert;
    __weak typeof(self) weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSError *error = nil;
        if (![DXBuildService.shared renameProject:project[@"id"] name:input.textFields.firstObject.text error:&error]) {
            PBShowError(weak, error.localizedDescription ?: @"无法保存名称。");
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmCleanup:(NSString *)identifier {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清理该项目的旧构建？"
        message:@"删除旧构建的快照、日志、内部产物和自动生成的文件副本。保留最近一次成功记录，以及另外分享或保存的文件。"
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error = nil;
        if (![DXBuildService.shared cleanOldBuildsForProject:identifier error:&error]) {
            PBShowError(weak, error.localizedDescription ?: @"清理未完成。");
        } else PBToast(weak, @"旧构建已清理");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addRecord:(NSDictionary *)job {
    NSString *name = job[@"projectName"] ?: @"构建";
    NSString *status = PBBuildStateTitle(job[@"state"]);
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[(job[@"finishedAt"] ?: job[@"startedAt"]) doubleValue]];
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    UIStackView *card = PBCard();
    [card addArrangedSubview:PBFeature(@"doc.text", name, [NSString stringWithFormat:@"%@ · %@", status, timestamp])];
    if (job[@"issue"][@"message"]) {
        UILabel *issue = PBLabel(job[@"issue"][@"message"], 13, UIFontWeightRegular, UIColor.secondaryLabelColor);
        issue.numberOfLines = 2;
        [card addArrangedSubview:issue];
    }
    __weak typeof(self) weak = self;
    UIButton *open = PBButton(@"查看详情", @"chevron.right", NO);
    [open addAction:[UIAction actionWithHandler:^(UIAction *action) { [weak showBuild:job]; }]
        forControlEvents:UIControlEventTouchUpInside];
    [card addArrangedSubview:open];
    [self.history addArrangedSubview:card];
}

- (void)showBuild:(NSDictionary *)job {
    [self.navigationController pushViewController:BuildResult(job[@"id"], [self.projectID isEqual:@""]) animated:YES];
}
@end

@interface PBBuildResultController : UIViewController
@property NSString *buildID, *displayedState;
@property BOOL canAssign;
@property UIStackView *content;
@property UILabel *stage;
@property UIProgressView *progress;
@end

@implementation PBBuildResultController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"构建详情";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.content = PBPageContent(self.view, self.view.bottomAnchor);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:PBBuildChanged object:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)refresh {
    NSDictionary *job = [DXBuildService.shared recordedBuild:self.buildID];
    NSString *state = job[@"state"] ?: @"removed";
    if (![self.displayedState isEqual:state]) {
        self.displayedState = state;
        [self render:job];
    }
    if ([state isEqual:@"running"]) {
        self.stage.text = job[@"stage"] ?: @"正在准备编译器…";
        self.progress.progress = [job[@"progress"] floatValue];
    }
}
- (void)render:(NSDictionary *)job {
    UIStackView *content = self.content;
    for (UIView *child in content.arrangedSubviews) [child removeFromSuperview];
    if (!job) {
        [content addArrangedSubview:PBLabel(@"这次构建记录已移除。", 16, UIFontWeightMedium, UIColor.secondaryLabelColor)];
        return;
    }
    NSString *path = job[@"buildPath"];
    self.title = job[@"projectName"] ?: @"构建详情";
    NSDictionary *report = TMCDocumentJSON([path stringByAppendingPathComponent:@"report.json"]);
    UIViewController *detail = self;
    UIStackView *summary = PBCard();
    NSString *result = PBBuildStateTitle(job[@"state"]);
    [summary addArrangedSubview:PBLabel(result, 19, UIFontWeightSemibold, UIColor.labelColor)];
    if (report[@"sdkVersion"] || job[@"sdk"]) {
        NSString *sdk = [NSString stringWithFormat:@"iOS %@ SDK · %@", report[@"sdkVersion"] ?: job[@"sdk"],
            report[@"cpuArchitecture"] ?: job[@"cpu"] ?: @"arm64"];
        [summary addArrangedSubview:PBLabel(sdk, 14, UIFontWeightMedium, UIColor.secondaryLabelColor)];
    }
    [content addArrangedSubview:summary];
    __weak typeof(self) weakSelf = self;
    if ([job[@"state"] isEqual:@"running"]) {
        self.stage = PBLabel(@"正在准备编译器…", 15, UIFontWeightRegular, UIColor.secondaryLabelColor);
        self.progress = [UIProgressView new];
        self.progress.progressTintColor = PBAccent();
        [summary addArrangedSubview:self.stage];
        [summary addArrangedSubview:self.progress];
        UIButton *stop = PBButton(@"取消编译", @"xmark", NO);
        [stop addAction:[UIAction actionWithHandler:^(UIAction *action) {
            [DXBuildService.shared cancelBuild];
            ((UIControl *)action.sender).enabled = NO;
        }] forControlEvents:UIControlEventTouchUpInside];
        [summary addArrangedSubview:stop];
        return;
    }
    NSDictionary *issue = job[@"issue"];
    if (!issue && [job[@"state"] isEqual:@"failed"]) issue = PBBuildIssue(path);
    NSString *message = issue[@"message"] ?: report[@"packageError"];
    if (message.length) [summary addArrangedSubview:PBLabel(message, 14, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    if (issue[@"file"]) {
        NSMutableArray *parts = [NSMutableArray arrayWithObject:issue[@"file"]];
        if (issue[@"line"]) [parts addObject:[issue[@"line"] stringValue]];
        if (issue[@"column"]) [parts addObject:[issue[@"column"] stringValue]];
        [summary addArrangedSubview:PBLabel([parts componentsJoinedByString:@":"], 13, UIFontWeightSemibold, UIColor.labelColor)];
        NSString *source = [[path stringByAppendingPathComponent:@"snapshot"] stringByAppendingPathComponent:issue[@"file"]];
        BOOL available = TMCRegularDocument(source, NO);
        if (available || job[@"project"]) {
            UIButton *locate = PBButton(available ? @"定位源码" : @"打开当前源码", @"scope", YES);
            [locate addAction:[UIAction actionWithHandler:^(UIAction *action) {
                if (available) PBOpenBuildSource(weakSelf, job[@"project"], job[@"id"]);
                else PBOpenProjectFile(weakSelf, job[@"project"], issue[@"file"]);
            }] forControlEvents:UIControlEventTouchUpInside];
            [summary addArrangedSubview:locate];
        }
    }
    if ([issue[@"kind"] isEqual:@"components"] && job[@"project"]) {
        UIButton *install = PBButton(@"安装缺少的组件", @"arrow.down.circle", YES);
        [install addAction:[UIAction actionWithHandler:^(UIAction *action) {
            [weakSelf.navigationController pushViewController:PBToolsForBuildIssue(issue, job[@"project"]) animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [summary addArrangedSubview:install];
    }

    NSArray<NSString *> *artifacts = PBProductFiles(PBBuildArtifacts(path));
    if (artifacts.count) {
        UIStackView *output = PBCard();
        [output addArrangedSubview:PBLabel([job[@"state"] isEqual:@"succeeded"] ? @"构建产物" : @"已生成文件",
            15, UIFontWeightSemibold, UIColor.labelColor)];
        for (NSString *file in artifacts) {
            [self addShareButtonForFile:file path:path to:output title:@"保存或分享" showName:YES];
        }
        [content addArrangedSubview:output];
    }

    UIStackView *technical = PBCard();
    [technical addArrangedSubview:PBLabel(@"日志与快照", 15, UIFontWeightMedium, UIColor.labelColor)];
    NSString *log = [path stringByAppendingPathComponent:@"build.log"];
    __weak UIViewController *weakDetail = detail;
    if (TMCRegularDocument(log, NO)) {
        UIButton *read = PBButton(@"查看构建日志", @"text.alignleft", NO);
        [read addAction:[UIAction actionWithHandler:^(UIAction *action) {
            NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:log];
            unsigned long long length = 0;
            NSUInteger limit = 256 * 1024;
            BOOL positioned = [file seekToEndReturningOffset:&length error:nil] &&
                [file seekToOffset:length > limit ? length - limit : 0 error:nil];
            NSData *data = positioned ? [file readDataUpToLength:limit error:nil] : nil;
            [file closeAndReturnError:nil];
            NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            if (!text && data.length > 3) {
                for (NSUInteger skip = 1; skip <= 3 && !text; skip++) {
                    text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(skip, data.length - skip)]
                        encoding:NSUTF8StringEncoding];
                }
            }
            if (length > limit && text) text = [@"显示日志末尾，可通过分享导出完整日志。\n\n" stringByAppendingString:text];
            [weakDetail.navigationController pushViewController:PBTextPage(@"构建日志", text ?: @"日志无法读取。") animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [technical addArrangedSubview:read];
    }
    NSString *configuration = [path stringByAppendingPathComponent:@"snapshot/MobileCompiler.json"];
    if (TMCRegularDocument(configuration, NO)) {
        UIButton *viewConfig = PBButton(@"查看该次构建配置", @"doc.text", NO);
        [viewConfig addAction:[UIAction actionWithHandler:^(UIAction *action) {
            NSDictionary *provenance = TMCDocumentJSON([path stringByAppendingPathComponent:@"provenance.json"]);
            NSMutableDictionary *effective = [provenance[@"effectiveConfiguration"] mutableCopy];
            if (report[@"sdkVersion"]) effective[@"sdkVersion"] = report[@"sdkVersion"];
            if (report[@"deploymentTarget"]) effective[@"deploymentTarget"] = report[@"deploymentTarget"];
            NSData *data = effective ? [NSJSONSerialization dataWithJSONObject:effective options:NSJSONWritingPrettyPrinted error:nil] :
                [NSData dataWithContentsOfFile:configuration];
            NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            [weakDetail.navigationController pushViewController:PBTextPage(@"构建配置", text ?: @"配置无法读取。") animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [technical addArrangedSubview:viewConfig];
    }
    NSString *snapshot = [path stringByAppendingPathComponent:@"snapshot"];
    if (TMCRegularDocument(snapshot, YES)) {
        UIButton *viewSource = PBButton(@"查看源码快照", @"folder", NO);
        __weak typeof(self) weak = self;
        [viewSource addAction:[UIAction actionWithHandler:^(UIAction *action) {
            [weak showSnapshot:snapshot from:weakDetail];
        }] forControlEvents:UIControlEventTouchUpInside];
        [technical addArrangedSubview:viewSource];
    }
    if (self.canAssign && DXBuildService.shared.projectList.count) {
        UIButton *assign = PBButton(@"归档到已有项目", @"folder", NO);
        __weak typeof(self) weak = self;
        __weak UIButton *anchor = assign;
        [assign addAction:[UIAction actionWithHandler:^(UIAction *action) {
            [weak chooseProjectForJob:job in:weakDetail anchor:anchor];
        }] forControlEvents:UIControlEventTouchUpInside];
        [technical addArrangedSubview:assign];
    }
    if (TMCRegularDocument(log, NO)) [self addShareButtonForFile:@"build.log" path:path to:technical title:@"分享完整日志" showName:NO];
    if (report.count) [self addShareButtonForFile:@"report.json" path:path to:technical title:@"分享构建报告" showName:NO];
    if (technical.arrangedSubviews.count > 1) [content addArrangedSubview:technical];
}

- (void)addShareButtonForFile:(NSString *)file path:(NSString *)path to:(UIStackView *)card title:(NSString *)title showName:(BOOL)showName {
    if (showName) [card addArrangedSubview:PBLabel(file, 14, UIFontWeightSemibold, UIColor.labelColor)];
    NSString *filePath = [path stringByAppendingPathComponent:file];
    UIButton *share = PBButton(title, @"square.and.arrow.up", showName);
    if (showName) share.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", title, file];
    __weak typeof(self) weak = self;
    __weak UIButton *anchor = share;
    [share addAction:[UIAction actionWithHandler:^(UIAction *action) {
        if (!TMCRegularDocument(filePath, NO)) { PBShowError(weak, @"文件已被移除。"); return; }
        UIActivityViewController *sheet = [[UIActivityViewController alloc]
            initWithActivityItems:@[[NSURL fileURLWithPath:filePath]] applicationActivities:nil];
        sheet.popoverPresentationController.sourceView = anchor;
        sheet.popoverPresentationController.sourceRect = anchor.bounds;
        [weak presentViewController:sheet animated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [card addArrangedSubview:share];
}
- (void)showSnapshot:(NSString *)snapshot from:(UIViewController *)detail {
    UIViewController *page = [UIViewController new];
    page.title = @"源码快照";
    page.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIStackView *content = PBPageContent(page.view, page.view.bottomAnchor);
    NSArray *extensions = @[@"m", @"mm", @"x", @"xm", @"c", @"cpp", @"h", @"hpp"];
    NSMutableArray<NSString *> *sources = [NSMutableArray array];
    for (NSString *relative in [NSFileManager.defaultManager enumeratorAtPath:snapshot]) {
        if (![extensions containsObject:relative.pathExtension.lowercaseString]) continue;
        NSString *file = [snapshot stringByAppendingPathComponent:relative];
        if (TMCRegularDocument(file, NO)) [sources addObject:relative];
    }
    __weak UIViewController *weakPage = page;
    for (NSString *relative in [sources sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        UIButton *open = PBButton(relative, @"doc.text", NO);
        [open addAction:[UIAction actionWithHandler:^(UIAction *action) {
            NSString *file = [snapshot stringByAppendingPathComponent:relative];
            NSString *text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
            [weakPage.navigationController pushViewController:PBTextPage(relative.lastPathComponent, text ?: @"源码无法读取。") animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [content addArrangedSubview:open];
    }
    if (!sources.count) [content addArrangedSubview:PBLabel(@"这次构建没有保存可查看的源码文件。", 14, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [detail.navigationController pushViewController:page animated:YES];
}

- (void)chooseProjectForJob:(NSDictionary *)job in:(UIViewController *)detail anchor:(UIView *)anchor {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"归档到项目"
        message:@"选择这条旧记录实际所属的项目。" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIViewController *weakDetail = detail;
    for (NSDictionary *project in DXBuildService.shared.projectList) {
        NSString *identifier = project[@"id"];
        NSString *title = [NSString stringWithFormat:@"%@ · %@", project[@"name"], [identifier substringFromIndex:identifier.length - 6]];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSError *error = nil;
            if (![DXBuildService.shared assignBuild:job[@"id"] toProject:identifier error:&error]) {
                PBShowError(weakDetail, error.localizedDescription ?: @"无法归档。");
            } else [weakDetail.navigationController popViewControllerAnimated:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = anchor;
    sheet.popoverPresentationController.sourceRect = anchor.bounds;
    [detail presentViewController:sheet animated:YES completion:nil];
}
@end

static UIViewController *BuildResult(NSString *identifier, BOOL assign) {
    PBBuildResultController *controller = [PBBuildResultController new];
    controller.buildID = identifier;
    controller.canAssign = assign;
    return controller;
}
UIViewController *PBBuildResult(NSString *identifier) { return BuildResult(identifier, NO); }

UIViewController *PBProjectBuilds(NSString *identifier) {
    PBBuildRecordsController *controller = [PBBuildRecordsController new];
    controller.projectID = identifier;
    return controller;
}

UIViewController *PBBuildsHome(void) { return [PBBuildRecordsController new]; }
