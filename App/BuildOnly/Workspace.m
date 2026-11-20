#import "Workspace.h"
#import "Appearance.h"
#import "BuildService.h"
#import "Toolchains.h"

UINavigationController *PBNavigation(UIViewController *root) {
    root.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = PBBackground();
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{NSFontAttributeName:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold], NSForegroundColorAttributeName:UIColor.labelColor};
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    navigation.navigationBar.prefersLargeTitles = NO;
    navigation.navigationBar.tintColor = UIColor.labelColor;
    navigation.navigationBar.standardAppearance = appearance;
    navigation.navigationBar.scrollEdgeAppearance = appearance;
    navigation.navigationBar.compactAppearance = appearance;
    return navigation;
}

@interface PBTabButton : UIButton
@property UIImageView *glyph;
@property UILabel *caption;
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol;
@end

@implementation PBTabButton
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = title;
        self.glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium]]];
        self.glyph.contentMode = UIViewContentModeCenter;
        self.caption = [UILabel new];
        self.caption.text = title;
        self.caption.textAlignment = NSTextAlignmentCenter;
        self.caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        self.caption.adjustsFontForContentSizeCategory = YES;
        self.caption.adjustsFontSizeToFitWidth = YES;
        self.caption.minimumScaleFactor = .65;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.glyph, self.caption]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 3;
        stack.userInteractionEnabled = NO;
        stack.accessibilityElementsHidden = YES;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [self.glyph.heightAnchor constraintEqualToConstant:22],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3]
        ]];
    }
    return self;
}
@end

@interface PBWorkspaceController : UIViewController <UINavigationControllerDelegate>
@property NSArray<UINavigationController *> *tabs;
@property NSArray<PBTabButton *> *buttons;
@property UINavigationController *current;
@property UIStackView *bar;
@property NSLayoutConstraint *barHeight;
@property NSLayoutConstraint *navigationBottom;
- (void)showTab:(NSUInteger)index;
@end

@implementation PBWorkspaceController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PBBackground();
    self.tabs = @[PBNavigation(DXBuildHome()), PBNavigation(PBBuildsHome()),
                  PBNavigation(PBToolsHome()), PBNavigation(PBSettingsHome())];
    self.bar = [UIStackView new];
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bar.backgroundColor = UIColor.clearColor;
    self.bar.axis = UILayoutConstraintAxisHorizontal;
    self.bar.distribution = UIStackViewDistributionFillEqually;
    self.bar.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(4, 5, 4, 5);
    self.bar.layoutMarginsRelativeArrangement = YES;
    [self.view addSubview:self.bar];
    self.barHeight = [self.bar.heightAnchor constraintEqualToConstant:66];
    NSLayoutConstraint *barWidth = [self.bar.widthAnchor constraintEqualToConstant:310];
    barWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        self.barHeight, barWidth,
        [self.bar.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-48],
        [self.bar.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-7]
    ]];

    NSArray *names = @[@"工作台", @"构建", @"组件", @"设置"];
    NSArray *symbols = @[@"rectangle.grid.1x2", @"hammer", @"shippingbox", @"gearshape"];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < names.count; index++) {
        PBTabButton *button = [[PBTabButton alloc] initWithTitle:names[index] symbol:symbols[index]];
        button.tag = index;
        [button addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        [self.bar addArrangedSubview:button];
        [buttons addObject:button];
    }
    self.buttons = buttons;
    [self showTab:0];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!self.bar) return;
    if (![previous.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory]) {
        [self updateBar];
    }
}

- (void)select:(UIButton *)button { [self showTab:(NSUInteger)button.tag]; }

- (void)showTab:(NSUInteger)index {
    UINavigationController *next = self.tabs[index];
    UINavigationController *previous = self.current;
    if (previous == next) {
        [next popToRootViewControllerAnimated:YES];
    } else {
        BOOL visible = self.view.window != nil;
        [previous willMoveToParentViewController:nil];
        [self addChildViewController:next];
        next.delegate = self;
        self.current = next;
        if (visible) {
            [previous beginAppearanceTransition:NO animated:NO];
            [next beginAppearanceTransition:YES animated:NO];
        }
        [previous.view removeFromSuperview];
        next.view.translatesAutoresizingMaskIntoConstraints = NO;
        next.view.clipsToBounds = YES;
        [self.view insertSubview:next.view belowSubview:self.bar];
        [NSLayoutConstraint activateConstraints:@[
            [next.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [next.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [next.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
        ]];
        if (visible) {
            [previous endAppearanceTransition];
            [next endAppearanceTransition];
        }
        [previous removeFromParentViewController];
        [next didMoveToParentViewController:self];
    }
    [self updateBar];
}

- (void)updateBar {
    BOOL visible = self.current.viewControllers.count == 1;
    BOOL largeText = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    CGFloat height = largeText ? 74 : 66;
    self.barHeight.constant = height;
    for (PBTabButton *button in self.buttons) {
        BOOL selected = self.tabs[button.tag] == self.current;
        UIColor *tint = selected ? PBAccent() : UIColor.secondaryLabelColor;
        button.caption.textColor = tint;
        button.glyph.tintColor = tint;
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
    self.bar.hidden = !visible;
    self.bar.accessibilityElementsHidden = !visible;
    self.navigationBottom.active = NO;
    NSLayoutYAxisAnchor *bottom = visible ? self.bar.topAnchor : self.view.bottomAnchor;
    self.navigationBottom = [self.current.view.bottomAnchor constraintEqualToAnchor:bottom constant:visible ? -12 : 0];
    self.navigationBottom.active = YES;
}

- (void)navigationController:(UINavigationController *)navigation
       willShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (navigation == self.current && navigation.viewControllers.count > 1) [self updateBar];
}

- (void)navigationController:(UINavigationController *)navigation
       didShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (navigation != self.current) return;
    [self updateBar];
}
@end

UIViewController *PBWorkspace(void) { return [PBWorkspaceController new]; }

BOOL PBOpenComponents(UIViewController *from) {
    UIViewController *workspace = from.navigationController.parentViewController;
    if (![workspace isKindOfClass:PBWorkspaceController.class]) return NO;
    [(PBWorkspaceController *)workspace showTab:2];
    return YES;
}

UIViewController *PBTextPage(NSString *title, NSString *text) {
    UIViewController *controller = [UIViewController new];
    controller.title = title;
    controller.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    controller.view.backgroundColor = PBBackground();
    UITextView *reader = [UITextView new];
    reader.translatesAutoresizingMaskIntoConstraints = NO;
    reader.backgroundColor = UIColor.clearColor;
    reader.editable = NO;
    reader.text = text;
    reader.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    reader.textColor = UIColor.labelColor;
    reader.textContainerInset = UIEdgeInsetsMake(16, 14, 24, 14);
    [controller.view addSubview:reader];
    [NSLayoutConstraint activateConstraints:@[
        [reader.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor],
        [reader.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor],
        [reader.leadingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.leadingAnchor],
        [reader.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor]
    ]];
    return controller;
}
