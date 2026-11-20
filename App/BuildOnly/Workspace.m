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
    appearance.titleTextAttributes = @{NSFontAttributeName:PBFont(17, UIFontWeightSemibold), NSForegroundColorAttributeName:UIColor.labelColor};
    appearance.largeTitleTextAttributes = @{NSFontAttributeName:PBFont(32, UIFontWeightBold), NSForegroundColorAttributeName:UIColor.labelColor};
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    navigation.navigationBar.prefersLargeTitles = YES;
    navigation.navigationBar.tintColor = UIColor.labelColor;
    navigation.navigationBar.standardAppearance = appearance;
    navigation.navigationBar.scrollEdgeAppearance = appearance;
    navigation.navigationBar.compactAppearance = appearance;
    return navigation;
}

@interface PBWorkspaceController : UIViewController <UINavigationControllerDelegate>
@property NSArray<UINavigationController *> *tabs;
@property NSArray<UIButton *> *buttons;
@property UINavigationController *current;
@property UIVisualEffectView *bar;
@property NSLayoutConstraint *barHeight;
@property NSLayoutConstraint *barWidth;
@property (weak) UIPanGestureRecognizer *observedPan;
@property BOOL collapsed;
@property CGFloat lastOffset;
- (void)showTab:(NSUInteger)index;
@end

@implementation PBWorkspaceController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PBBackground();
    self.tabs = @[PBNavigation(DXBuildHome()), PBNavigation(PBBuildsHome()),
                  PBNavigation(PBToolsHome()), PBNavigation(PBSettingsHome())];
    self.bar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bar.layer.cornerRadius = 29;
    self.bar.layer.cornerCurve = kCACornerCurveContinuous;
    self.bar.clipsToBounds = YES;
    [self.view addSubview:self.bar];
    self.barHeight = [self.bar.heightAnchor constraintEqualToConstant:60];
    self.barWidth = [self.bar.widthAnchor constraintEqualToConstant:372];
    self.barWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        self.barHeight, self.barWidth,
        [self.bar.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-24],
        [self.bar.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];

    UIStackView *row = [UIStackView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 3;
    [self.bar.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.bar.contentView.leadingAnchor constant:6],
        [row.trailingAnchor constraintEqualToAnchor:self.bar.contentView.trailingAnchor constant:-6],
        [row.topAnchor constraintEqualToAnchor:self.bar.contentView.topAnchor constant:4],
        [row.bottomAnchor constraintEqualToAnchor:self.bar.contentView.bottomAnchor constant:-4]
    ]];
    NSArray *names = @[@"工作台", @"构建", @"组件", @"设置"];
    NSArray *symbols = @[@"rectangle.grid.1x2", @"hammer", @"shippingbox", @"gearshape"];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < names.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *configuration = UIButtonConfiguration.plainButtonConfiguration;
        configuration.image = [UIImage systemImageNamed:symbols[index] withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium]];
        configuration.imagePlacement = NSDirectionalRectEdgeTop;
        configuration.imagePadding = 3;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *updated = [attributes mutableCopy];
            updated[NSFontAttributeName] = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
            return updated;
        };
        button.configuration = configuration;
        button.accessibilityLabel = names[index];
        button.tag = index;
        [button addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:button];
        [buttons addObject:button];
    }
    self.buttons = buttons;
    [self showTab:0];
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
        [self.view insertSubview:next.view belowSubview:self.bar];
        [NSLayoutConstraint activateConstraints:@[
            [next.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [next.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
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
    [self updateBar:NO animated:NO];
    [self observeScrolling:next.topViewController];
}

- (void)updateBar:(BOOL)collapsed animated:(BOOL)animated {
    self.collapsed = collapsed;
    BOOL visible = self.current.viewControllers.count == 1;
    self.barHeight.constant = collapsed ? 48 : 60;
    self.barWidth.constant = collapsed ? 260 : 372;
    for (UIButton *button in self.buttons) {
        BOOL selected = self.tabs[button.tag] == self.current;
        UIButtonConfiguration *configuration = button.configuration;
        configuration.title = collapsed ? nil : button.accessibilityLabel;
        configuration.baseForegroundColor = selected ? UIColor.labelColor : UIColor.secondaryLabelColor;
        configuration.background.backgroundColor = selected ? UIColor.tertiarySystemFillColor : UIColor.clearColor;
        button.configuration = configuration;
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
    self.bar.userInteractionEnabled = visible;
    self.bar.accessibilityElementsHidden = !visible;
    [UIView animateWithDuration:animated && !UIAccessibilityIsReduceMotionEnabled() ? .24 : 0 animations:^{
        self.bar.alpha = visible ? 1 : 0;
        self.current.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, visible ? self.barHeight.constant + 14 : 0, 0);
        [self.view layoutIfNeeded];
    }];
}

- (void)observeScrolling:(UIViewController *)controller {
    [self.observedPan removeTarget:self action:@selector(scrolled:)];
    self.observedPan = nil;
    if (self.current.viewControllers.count != 1) return;
    for (UIView *view in controller.view.subviews) {
        if (![view isKindOfClass:UIScrollView.class]) continue;
        self.observedPan = ((UIScrollView *)view).panGestureRecognizer;
        [self.observedPan addTarget:self action:@selector(scrolled:)];
        break;
    }
}

- (void)scrolled:(UIPanGestureRecognizer *)pan {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([[defaults objectForKey:@"PocketBuildCollapseTabs"] isEqual:@NO]) return;
    UIScrollView *scroll = (UIScrollView *)pan.view;
    if (pan.state == UIGestureRecognizerStateBegan) self.lastOffset = [pan translationInView:scroll].y;
    if (pan.state != UIGestureRecognizerStateChanged || scroll.contentSize.height <= scroll.bounds.size.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom) return;
    CGFloat offset = [pan translationInView:scroll].y;
    CGFloat delta = offset - self.lastOffset;
    if (fabs(delta) < 28) return;
    self.lastOffset = offset;
    BOOL collapse = delta < 0 && scroll.contentOffset.y > -scroll.adjustedContentInset.top + 18;
    if (collapse != self.collapsed) [self updateBar:collapse animated:YES];
}

- (void)navigationController:(UINavigationController *)navigation
       willShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (navigation == self.current && navigation.viewControllers.count > 1) [self updateBar:NO animated:animated];
}

- (void)navigationController:(UINavigationController *)navigation
       didShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (navigation != self.current) return;
    [self updateBar:NO animated:animated];
    [self observeScrolling:controller];
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
