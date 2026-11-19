#import "Appearance.h"
UIColor *PBBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle==UIUserInterfaceStyleDark ? [UIColor colorWithRed:.055 green:.061 blue:.071 alpha:1] : [UIColor colorWithRed:.96 green:.957 blue:.945 alpha:1];
    }];
}
UIColor *PBAccent(void) { return [UIColor colorWithRed:.86 green:.34 blue:.15 alpha:1]; }
UIFont *PBFont(CGFloat size, UIFontWeight weight) {
    UIFont *font=[UIFont systemFontOfSize:size weight:weight];
    return [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded] size:size]];
}
UILabel *PBLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label=[UILabel new];label.text=text;label.font=PBFont(size,weight);label.textColor=color;
    label.numberOfLines=0;label.adjustsFontForContentSizeCategory=YES;return label;
}
UIStackView *PBCard(void) {
    UIStackView *card=[UIStackView new];card.axis=UILayoutConstraintAxisVertical;card.spacing=14;
    card.layoutMargins=UIEdgeInsetsMake(20,20,20,20);card.layoutMarginsRelativeArrangement=YES;
    card.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;card.layer.cornerRadius=24;
    card.layer.cornerCurve=kCACornerCurveContinuous;return card;
}
UIStackView *PBPageContent(UIView *view, NSLayoutYAxisAnchor *bottom) {
    view.backgroundColor=PBBackground();
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.alwaysBounceVertical=YES;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    [view addSubview:scroll];UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=20;
    stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:view.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:bottom],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];return stack;
}
UIButton *PBButton(NSString *title, NSString *symbol, BOOL primary) {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config=primary?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.tintedButtonConfiguration;
    config.title=title;config.image=[UIImage systemImageNamed:symbol];config.imagePadding=8;
    config.cornerStyle=UIButtonConfigurationCornerStyleLarge;config.contentInsets=NSDirectionalEdgeInsetsMake(14,16,14,16);
    config.titleTextAttributesTransformer=^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attributes){
        NSMutableDictionary *result=[attributes mutableCopy];result[NSFontAttributeName]=PBFont(15,UIFontWeightSemibold);return result;
    };
    config.baseBackgroundColor=UIColor.labelColor;
    config.baseForegroundColor=primary?UIColor.systemBackgroundColor:UIColor.labelColor;
    button.configuration=config;button.titleLabel.font=PBFont(15,UIFontWeightSemibold);return button;
}
UIView *PBFeature(NSString *symbol, NSString *title, NSString *detail) {
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=14;row.alignment=UIStackViewAlignmentTop;
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];icon.tintColor=PBAccent();icon.contentMode=UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:25].active=YES;[icon.heightAnchor constraintEqualToConstant:28].active=YES;
    UIStackView *texts=[UIStackView new];texts.axis=UILayoutConstraintAxisVertical;texts.spacing=5;
    [texts addArrangedSubview:PBLabel(title,16,UIFontWeightSemibold,UIColor.labelColor)];
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
