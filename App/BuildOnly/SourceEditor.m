#import "SourceEditor.h"
#import "Appearance.h"
#import "BuildService.h"
#import "ProjectRecords.h"
#import "Workspace.h"

@interface PBSourceLayout : NSLayoutManager
@property (nonatomic) NSRange highlightedRange;
@end

@implementation PBSourceLayout
- (void)setHighlightedRange:(NSRange)range {
    NSRange previous = NSIntersectionRange(_highlightedRange, NSMakeRange(0, self.textStorage.length));
    _highlightedRange = range;
    if (previous.length) [self invalidateDisplayForCharacterRange:previous];
    if (range.length) [self invalidateDisplayForCharacterRange:range];
}
- (void)drawBackgroundForGlyphRange:(NSRange)glyphs atPoint:(CGPoint)origin {
    [super drawBackgroundForGlyphRange:glyphs atPoint:origin];
    NSRange marked = NSIntersectionRange(self.highlightedRange, NSMakeRange(0, self.textStorage.length));
    if (!marked.length) return;
    NSRange visible = NSIntersectionRange(glyphs, [self glyphRangeForCharacterRange:marked actualCharacterRange:nil]);
    if (!visible.length) return;
    NSTextContainer *container = [self textContainerForGlyphAtIndex:visible.location effectiveRange:nil];
    [[PBAccent() colorWithAlphaComponent:.24] setFill];
    [self enumerateEnclosingRectsForGlyphRange:visible withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0)
        inTextContainer:container usingBlock:^(CGRect rect, BOOL *stop) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectOffset(rect, origin.x, origin.y) cornerRadius:3] fill];
    }];
}
@end

@interface PBLineNumbers : UIView
@property (weak) UITextView *editor;
@property NSIndexSet *starts;
@end

@implementation PBLineNumbers
- (void)drawRect:(CGRect)rect {
    UITextView *editor = self.editor;
    NSLayoutManager *layout = editor.layoutManager;
    NSTextContainer *container = editor.textContainer;
    CGFloat origin = editor.textContainerInset.top - editor.contentOffset.y;
    CGRect viewport = CGRectMake(0, MAX(0, -origin), container.size.width, CGRectGetHeight(self.bounds));
    NSRange visible = [layout glyphRangeForBoundingRect:viewport inTextContainer:container];
    NSDictionary *style = @{NSFontAttributeName:editor.font, NSForegroundColorAttributeName:UIColor.secondaryLabelColor};
    NSUInteger first = visible.length ? [layout characterIndexForGlyphAtIndex:visible.location] : 0;
    __block NSUInteger line = [self.starts countOfIndexesInRange:NSMakeRange(0, first)];
    void (^draw)(NSUInteger, CGRect) = ^(NSUInteger number, CGRect fragment) {
        NSString *text = [@(number) stringValue];
        CGFloat width = [text sizeWithAttributes:style].width;
        [text drawAtPoint:CGPointMake(CGRectGetWidth(self.bounds) - width - 7,
            origin + CGRectGetMidY(fragment) - editor.font.lineHeight / 2) withAttributes:style];
    };
    [layout enumerateLineFragmentsForGlyphRange:visible usingBlock:
        ^(CGRect fragment, CGRect used, NSTextContainer *owner, NSRange glyphs, BOOL *stop) {
            if ([self.starts containsIndex:[layout characterIndexForGlyphAtIndex:glyphs.location]]) draw(++line, fragment);
        }];
    if (layout.extraLineFragmentTextContainer == container && [self.starts containsIndex:editor.text.length]) {
        draw(self.starts.count, layout.extraLineFragmentRect);
    }
}
@end

@interface PBSourceEditorController : UIViewController <UITextViewDelegate, UITextFieldDelegate>
@property NSString *project, *path, *original;
@property BOOL snapshot, currentAvailable;
@property NSUInteger line, column;
@property NSTextStorage *storage;
@property PBSourceLayout *sourceLayout;
@property UITextView *editor;
@property PBLineNumbers *numbers;
@property NSLayoutConstraint *gutterWidth;
@property UITextField *query;
@property UIStackView *searchRow, *actions;
@property UIButton *saveButton;
@property UILabel *fileStatus;
@end

@implementation PBSourceEditorController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.snapshot ? @"源码快照" : @"源码编辑";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.backward"]
        style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"返回";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
        style:UIBarButtonItemStylePlain target:self action:@selector(openSearch)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"在文件内查找";
    self.view.backgroundColor = PBBackground();

    UILabel *path = PBLabel(self.path, 14, UIFontWeightSemibold, UIColor.labelColor);
    path.numberOfLines = 2;
    path.lineBreakMode = NSLineBreakByTruncatingMiddle;
    path.accessibilityLabel = self.path;
    self.fileStatus = PBLabel(@"", 12, UIFontWeightMedium, UIColor.secondaryLabelColor);
    self.fileStatus.numberOfLines = 2;

    self.query = [UITextField new];
    self.query.delegate = self;
    self.query.borderStyle = UITextBorderStyleRoundedRect;
    self.query.placeholder = @"在文件内查找";
    self.query.autocorrectionType = UITextAutocorrectionTypeNo;
    self.query.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.query.returnKeyType = UIReturnKeySearch;
    self.query.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self.query setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    [next setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    next.accessibilityLabel = @"查找下一处";
    [next addTarget:self action:@selector(findNext) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.accessibilityLabel = @"关闭查找";
    [close addTarget:self action:@selector(closeSearch) forControlEvents:UIControlEventTouchUpInside];
    [next.widthAnchor constraintEqualToConstant:44].active = YES;
    [close.widthAnchor constraintEqualToConstant:44].active = YES;
    self.searchRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.query, next, close]];
    self.searchRow.spacing = 4;
    self.searchRow.hidden = YES;
    NSLayoutConstraint *searchHeight = [self.query.heightAnchor constraintGreaterThanOrEqualToConstant:44];
    searchHeight.priority = UILayoutPriorityDefaultHigh;
    searchHeight.active = YES;

    self.storage = [NSTextStorage new];
    self.sourceLayout = [PBSourceLayout new];
    [self.storage addLayoutManager:self.sourceLayout];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(0, CGFLOAT_MAX)];
    container.widthTracksTextView = YES;
    [self.sourceLayout addTextContainer:container];
    self.editor = [[UITextView alloc] initWithFrame:CGRectZero textContainer:container];
    self.editor.text = self.original;
    self.editor.delegate = self;
    self.editor.editable = !self.snapshot;
    self.editor.accessibilityLabel = self.snapshot ? @"只读源码快照" : @"项目源码";
    self.editor.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.editor.textColor = UIColor.labelColor;
    self.editor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.editor.autocorrectionType = UITextAutocorrectionTypeNo;
    self.editor.spellCheckingType = UITextSpellCheckingTypeNo;
    self.editor.smartQuotesType = UITextSmartQuotesTypeNo;
    self.editor.smartDashesType = UITextSmartDashesTypeNo;
    self.editor.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    self.editor.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.editor.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.editor.textContainerInset = UIEdgeInsetsMake(9, 5, 12, 5);
    self.numbers = [PBLineNumbers new];
    self.numbers.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    self.numbers.editor = self.editor;
    self.gutterWidth = [self.numbers.widthAnchor constraintEqualToConstant:40];
    self.gutterWidth.active = YES;
    UIStackView *source = [[UIStackView alloc] initWithArrangedSubviews:@[self.numbers, self.editor]];
    source.layer.cornerRadius = 12;
    source.clipsToBounds = YES;
    [source setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisVertical];

    self.actions = [UIStackView new];
    self.actions.spacing = 8;
    if (!self.snapshot) {
        self.saveButton = PBButton(@"保存", @"checkmark", NO);
        [self.saveButton addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
        UIButton *build = PBButton(@"保存并编译", @"hammer", YES);
        [build addTarget:self action:@selector(build) forControlEvents:UIControlEventTouchUpInside];
        [self.actions addArrangedSubview:self.saveButton];
        [self.actions addArrangedSubview:build];
        UIToolbar *keyboard = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
        keyboard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        keyboard.items = @[
            [[UIBarButtonItem alloc] initWithTitle:@"缩进" style:UIBarButtonItemStylePlain target:self action:@selector(indent)],
            [[UIBarButtonItem alloc] initWithTitle:@"撤销" style:UIBarButtonItemStylePlain target:self action:@selector(undo)],
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
            [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStylePlain target:self action:@selector(save)],
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)]
        ];
        self.editor.inputAccessoryView = keyboard;
    } else if (self.currentAvailable) {
        UIButton *current = PBButton(@"编辑当前源码", @"pencil", YES);
        [current addTarget:self action:@selector(openCurrent) forControlEvents:UIControlEventTouchUpInside];
        [self.actions addArrangedSubview:current];
    } else {
        self.actions.hidden = YES;
    }
    UIStackView *layout = [[UIStackView alloc] initWithArrangedSubviews:@[path, self.fileStatus, self.searchRow, source, self.actions]];
    layout.translatesAutoresizingMaskIntoConstraints = NO;
    layout.axis = UILayoutConstraintAxisVertical;
    layout.spacing = 8;
    [self.view addSubview:layout];
    [NSLayoutConstraint activateConstraints:@[
        [layout.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [layout.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [layout.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [layout.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8]
    ]];
    [self updateFont];
    if (self.line) [self selectLocation:PBSourceLocation(self.original, self.line, self.column)];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Keep swipe-back from discarding an edit, including gestures begun with the keyboard open.
    self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    if (self.line) [self.editor scrollRangeToVisible:self.editor.selectedRange];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    [self dismissKeyboard];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL keyboardVisible = CGRectGetHeight(self.view.keyboardLayoutGuide.layoutFrame) > self.view.safeAreaInsets.bottom;
    BOOL hideActions = keyboardVisible || (self.snapshot && !self.currentAvailable);
    if (self.actions.hidden != hideActions) self.actions.hidden = hideActions;
    [self.numbers setNeedsDisplay];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.editor && ![previous.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory]) [self updateFont];
}
- (void)updateFont {
    self.editor.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular]];
    BOOL large = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    self.actions.axis = large ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.actions.distribution = large ? UIStackViewDistributionFill : UIStackViewDistributionFillEqually;
    [self textViewDidChange:self.editor];
}
- (BOOL)dirty { return !self.snapshot && ![self.editor.text isEqualToString:self.original]; }
- (void)textViewDidChange:(UITextView *)editor {
    NSMutableIndexSet *starts = [NSMutableIndexSet indexSetWithIndex:0];
    NSString *text = editor.text;
    self.sourceLayout.highlightedRange = NSMakeRange(0, 0);
    for (NSUInteger start = 0, end = 0; start < text.length; start = end) {
        NSUInteger contentsEnd = 0;
        [text getLineStart:nil end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(start, 1)];
        if (end > contentsEnd) [starts addIndex:end];
    }
    self.numbers.starts = starts;
    CGFloat digits = [[@(starts.count) stringValue] sizeWithAttributes:@{NSFontAttributeName:editor.font}].width;
    self.gutterWidth.constant = MAX(36, ceil(digits) + 14);
    [self.numbers setNeedsDisplay];
    self.saveButton.enabled = self.dirty;
    if (self.snapshot) {
        self.fileStatus.text = [NSString stringWithFormat:@"本次构建快照 · 第 %lu 行 · 只读", (unsigned long)self.line];
    } else {
        self.fileStatus.text = self.dirty ? @"当前项目 · 有未保存的修改" :
            self.line ? [NSString stringWithFormat:@"当前源码与构建快照一致 · 第 %lu 行", (unsigned long)self.line] : @"当前项目源码";
    }
}
- (void)selectLocation:(NSRange)range {
    self.sourceLayout.highlightedRange = range;
    self.editor.selectedRange = range;
}
- (void)scrollViewDidScroll:(UIScrollView *)scroll { [self.numbers setNeedsDisplay]; }
- (void)indent { [self.editor insertText:@"    "]; }
- (void)undo { [self.editor.undoManager undo]; }
- (void)dismissKeyboard { [self.view endEditing:YES]; }
- (void)openSearch {
    self.searchRow.hidden = NO;
    [self.query becomeFirstResponder];
}
- (void)closeSearch {
    [self.query resignFirstResponder];
    self.searchRow.hidden = YES;
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [self findNext]; return NO; }
- (void)findNext {
    NSString *needle = self.query.text;
    if (!needle.length) return;
    NSString *text = self.editor.text;
    NSUInteger start = MIN(text.length, NSMaxRange(self.editor.selectedRange));
    NSRange hit = [text rangeOfString:needle options:NSCaseInsensitiveSearch range:NSMakeRange(start, text.length - start)];
    if (hit.location == NSNotFound) hit = [text rangeOfString:needle options:NSCaseInsensitiveSearch];
    if (hit.location == NSNotFound) { PBToast(self, @"未找到匹配"); return; }
    if (self.snapshot) [self.query resignFirstResponder]; else [self.editor becomeFirstResponder];
    [self selectLocation:hit];
    [self.editor scrollRangeToVisible:hit];
}
- (BOOL)persist {
    if (!self.dirty) return YES;
    NSError *error = nil;
    NSString *text = self.editor.text;
    if (![DXBuildService.shared saveSource:text forProject:self.project path:self.path expected:self.original error:&error]) {
        PBShowError(self, error.localizedDescription ?: @"无法保存源码。");
        return NO;
    }
    self.original = text;
    self.line = 0;
    [self textViewDidChange:self.editor];
    return YES;
}
- (void)save { if ([self persist]) PBToast(self, @"源码已保存"); }
- (void)build {
    if (![self persist]) return;
    [self dismissKeyboard];
    NSError *error = nil;
    NSDictionary *job = [DXBuildService.shared startProjectBuild:self.project error:&error];
    if (job) [self.navigationController pushViewController:PBBuildResult(job[@"id"]) animated:YES];
    else PBShowError(self, error.localizedDescription ?: @"无法开始构建。");
}
- (void)goBack {
    if (!self.dirty) { [self.navigationController popViewControllerAnimated:YES]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存对源码的修改？"
        message:self.path preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存并返回" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if ([weak persist]) [weak.navigationController popViewControllerAnimated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"放弃修改" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weak.navigationController popViewControllerAnimated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续编辑" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openCurrent { PBOpenProjectFile(self, self.project, self.path); }
@end

void PBOpenProjectFile(UIViewController *from, NSString *project, NSString *path) {
    NSError *error = nil;
    NSString *text = [DXBuildService.shared sourceForProject:project path:path error:&error];
    if (!text) { PBShowError(from, error.localizedDescription); return; }
    PBSourceEditorController *editor = [PBSourceEditorController new];
    editor.project = project;
    editor.path = path;
    editor.original = text;
    [from.navigationController pushViewController:editor animated:YES];
}

void PBOpenBuildSource(UIViewController *from, NSString *project, NSString *build) {
    NSError *error = nil;
    NSDictionary *source = [DXBuildService.shared diagnosticSourceForBuild:build error:&error];
    if (!source) { PBShowError(from, error.localizedDescription); return; }
    PBSourceEditorController *editor = [PBSourceEditorController new];
    editor.project = project;
    editor.path = source[@"path"];
    editor.original = source[@"text"];
    editor.snapshot = [source[@"snapshot"] boolValue];
    editor.currentAvailable = [source[@"currentAvailable"] boolValue];
    editor.line = [source[@"line"] unsignedIntegerValue];
    editor.column = [source[@"column"] unsignedIntegerValue];
    [from.navigationController pushViewController:editor animated:YES];
}

@interface PBSourceFilesController : UITableViewController
@property NSString *project, *prefix;
@property NSArray<NSString *> *rows;
@end

@implementation PBSourceFilesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.prefix.length ? self.prefix.lastPathComponent : @"项目源码";
    self.view.backgroundColor = PBBackground();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"file"];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSMutableSet *folders = [NSMutableSet set];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *path in [DXBuildService.shared sourceFilesForProject:self.project]) {
        if (![path hasPrefix:self.prefix]) continue;
        NSString *relative = [path substringFromIndex:self.prefix.length];
        NSRange slash = [relative rangeOfString:@"/"];
        if (slash.location != NSNotFound) [folders addObject:[relative substringToIndex:NSMaxRange(slash)]];
        else [files addObject:relative];
    }
    self.rows = [[folders.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)]
        arrayByAddingObjectsFromArray:[files sortedArrayUsingSelector:@selector(localizedStandardCompare:)]];
    UILabel *empty = PBLabel(@"此目录还没有文件，可在电脑端导入源码。", 15, UIFontWeightRegular, UIColor.secondaryLabelColor);
    empty.textAlignment = NSTextAlignmentCenter;
    self.tableView.backgroundView = self.rows.count ? nil : empty;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"file" forIndexPath:index];
    NSString *entry = self.rows[index.row];
    UIListContentConfiguration *content = UIListContentConfiguration.cellConfiguration;
    content.text = entry.lastPathComponent;
    content.textProperties.numberOfLines = 0;
    content.image = [UIImage systemImageNamed:[entry hasSuffix:@"/"] ? @"folder" : @"doc.text"];
    content.imageProperties.tintColor = UIColor.secondaryLabelColor;
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    NSString *entry = self.rows[index.row];
    NSString *relative = [self.prefix stringByAppendingString:entry];
    if (![entry hasSuffix:@"/"]) { PBOpenProjectFile(self, self.project, relative); return; }
    PBSourceFilesController *folder = [[PBSourceFilesController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    folder.project = self.project;
    folder.prefix = relative;
    [self.navigationController pushViewController:folder animated:YES];
}
@end

UIViewController *PBProjectSources(NSString *project) {
    PBSourceFilesController *controller = [[PBSourceFilesController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.project = project;
    controller.prefix = @"";
    return controller;
}
