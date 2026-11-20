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
    UIStackView *card=[UIStackView new];card.axis=UILayoutConstraintAxisVertical;card.spacing=11;
    card.layoutMargins=UIEdgeInsetsMake(15,15,15,15);card.layoutMarginsRelativeArrangement=YES;
    card.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;card.layer.cornerRadius=16;
    card.layer.cornerCurve=kCACornerCurveContinuous;return card;
}
UIStackView *PBPageContent(UIView *view, NSLayoutYAxisAnchor *bottom) {
    view.backgroundColor=PBBackground();
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.alwaysBounceVertical=YES;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    [view addSubview:scroll];UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;
    stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:view.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:bottom],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];return stack;
}
UIButton *PBButton(NSString *title, NSString *symbol, BOOL primary) {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config=primary?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.grayButtonConfiguration;
    config.title=title;config.image=[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium]];config.imagePadding=6;
    config.cornerStyle=UIButtonConfigurationCornerStyleMedium;config.contentInsets=NSDirectionalEdgeInsetsMake(10,12,10,12);
    config.titleTextAttributesTransformer=^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attributes){
        NSMutableDictionary *result=[attributes mutableCopy];result[NSFontAttributeName]=PBFont(14,primary?UIFontWeightSemibold:UIFontWeightMedium);return result;
    };
    if(primary)config.baseBackgroundColor=UIColor.labelColor;
    config.baseForegroundColor=primary?UIColor.systemBackgroundColor:UIColor.labelColor;
    button.configuration=config;
    NSLayoutConstraint *touchHeight=[button.heightAnchor constraintGreaterThanOrEqualToConstant:44];
    touchHeight.priority=UILayoutPriorityDefaultHigh;touchHeight.active=YES;return button;
}
UIButton *PBLinkButton(NSString *title, NSString *symbol) {
    UIButton *button = PBButton(title, symbol, NO);
    UIButtonConfiguration *style = button.configuration;
    style.background = UIBackgroundConfiguration.clearConfiguration;
    style.baseForegroundColor = UIColor.labelColor;
    style.contentInsets = NSDirectionalEdgeInsetsMake(8, 0, 8, 0);
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
