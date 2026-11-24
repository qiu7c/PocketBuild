#import "Appearance.h"
UIColor *PBBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle==UIUserInterfaceStyleDark ? [UIColor colorWithWhite:.075 alpha:1] : [UIColor colorWithRed:.966 green:.962 blue:.953 alpha:1];
    }];
}
UIColor *PBAccent(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:.94 green:.62 blue:.46 alpha:1]
            : [UIColor colorWithRed:.64 green:.28 blue:.17 alpha:1];
    }];
}
UIFont *PBFont(CGFloat size, UIFontWeight weight) {
    UIFont *font=[UIFont systemFontOfSize:size weight:weight];
    return [UIFontMetrics.defaultMetrics scaledFontForFont:font];
}
UILabel *PBLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label=[UILabel new];label.text=text;label.font=PBFont(size,weight);label.textColor=color;
    label.numberOfLines=0;label.adjustsFontForContentSizeCategory=YES;return label;
}
UIStackView *PBCard(void) {
    UIStackView *card = [UIStackView new];
    card.axis = UILayoutConstraintAxisVertical;
    card.spacing = 12;
    card.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(16, 16, 16, 16);
    card.layoutMarginsRelativeArrangement = YES;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    return card;
}
UIStackView *PBPageContent(UIView *view, NSLayoutYAxisAnchor *bottom) {
    view.backgroundColor = PBBackground();
    UILayoutGuide *safeArea = view.safeAreaLayoutGuide;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [view addSubview:scroll];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    UILayoutGuide *frame = scroll.frameLayoutGuide;
    UILayoutGuide *content = scroll.contentLayoutGuide;
    NSLayoutConstraint *preferredWidth = [stack.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-32];
    // Keep the viewport width ahead of the arranged views' intrinsic sizes.
    preferredWidth.priority = UILayoutPriorityRequired - 1;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:bottom ?: safeArea.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:frame.widthAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:frame.widthAnchor constant:-32],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:640],
        preferredWidth
    ]];
    return stack;
}
static UIButton *PBConfiguredButton(UIButtonConfiguration *config, NSString *title, NSString *symbol, UIFontWeight weight) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    config.title = title;
    config.image = [UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium]];
    config.imagePadding = 6;
    config.titleLineBreakMode = NSLineBreakByWordWrapping;
    config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
        NSMutableDictionary *result = [attributes mutableCopy];
        result[NSFontAttributeName] = PBFont(14, weight);
        return result;
    };
    button.configuration = config;
    NSLayoutConstraint *touchHeight = [button.heightAnchor constraintGreaterThanOrEqualToConstant:44];
    touchHeight.priority = UILayoutPriorityDefaultHigh;
    touchHeight.active = YES;
    return button;
}
UIButton *PBButton(NSString *title, NSString *symbol, BOOL primary) {
    UIButtonConfiguration *config = primary ? UIButtonConfiguration.filledButtonConfiguration : UIButtonConfiguration.grayButtonConfiguration;
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.contentInsets = NSDirectionalEdgeInsetsMake(10, 12, 10, 12);
    if (primary) config.baseBackgroundColor = UIColor.labelColor;
    config.baseForegroundColor = primary ? UIColor.systemBackgroundColor : UIColor.labelColor;
    return PBConfiguredButton(config, title, symbol, primary ? UIFontWeightSemibold : UIFontWeightMedium);
}
UIButton *PBLinkButton(NSString *title, NSString *symbol) {
    UIButtonConfiguration *style = UIButtonConfiguration.plainButtonConfiguration;
    style.baseForegroundColor = UIColor.labelColor;
    style.contentInsets = NSDirectionalEdgeInsetsMake(8, 0, 8, 0);
    UIButton *button = PBConfiguredButton(style, title, symbol, UIFontWeightRegular);
    UIImage *glyph = style.image;
    CGSize column = CGSizeMake(22, 22);
    CGFloat scale = MIN(1, 20 / MAX(glyph.size.width, glyph.size.height));
    CGSize size = CGSizeMake(glyph.size.width * scale, glyph.size.height * scale);
    CGRect glyphRect = CGRectMake((column.width - size.width) / 2, (column.height - size.height) / 2, size.width, size.height);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:column];
    UIImage *alignedImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [glyph drawInRect:glyphRect];
    }];
    style.image = [alignedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    style.imagePadding = 8;
    button.configuration = style;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    return button;
}
UIView *PBFeature(NSString *symbol, NSString *title, NSString *detail) {
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=10;row.alignment=UIStackViewAlignmentTop;
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium]]];
    icon.tintColor=UIColor.secondaryLabelColor;icon.contentMode=UIViewContentModeCenter;
    [icon.widthAnchor constraintEqualToConstant:20].active=YES;[icon.heightAnchor constraintEqualToConstant:21].active=YES;
    UIStackView *texts=[UIStackView new];texts.axis=UILayoutConstraintAxisVertical;texts.spacing=4;
    [texts addArrangedSubview:PBLabel(title,15,UIFontWeightMedium,UIColor.labelColor)];
    if(detail.length)[texts addArrangedSubview:PBLabel(detail,13,UIFontWeightRegular,UIColor.secondaryLabelColor)];
    [row addArrangedSubview:icon];[row addArrangedSubview:texts];return row;
}
void PBToast(UIViewController *controller, NSString *text) {
    [[controller.view viewWithTag:7181] removeFromSuperview];
    UILabel *label=PBLabel(text,14,UIFontWeightMedium,UIColor.systemBackgroundColor);label.textAlignment=NSTextAlignmentCenter;
    UIView *toast=[UIView new];toast.tag=7181;toast.backgroundColor=UIColor.labelColor;toast.layer.cornerRadius=16;toast.alpha=0;
    toast.translatesAutoresizingMaskIntoConstraints=NO;label.translatesAutoresizingMaskIntoConstraints=NO;[toast addSubview:label];[controller.view addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[[toast.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [toast.widthAnchor constraintLessThanOrEqualToAnchor:controller.view.widthAnchor constant:-48],
        [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:20],[label.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:toast.topAnchor constant:13],[label.bottomAnchor constraintEqualToAnchor:toast.bottomAnchor constant:-13]]];
    [UIView animateWithDuration:.2 animations:^{toast.alpha=1;}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.7*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [UIView animateWithDuration:.2 animations:^{toast.alpha=0;} completion:^(BOOL done){[toast removeFromSuperview];}];
    });
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
void PBShowError(UIViewController *controller, NSString *message) {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"请检查设置" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[controller presentViewController:alert animated:YES completion:nil];
}
