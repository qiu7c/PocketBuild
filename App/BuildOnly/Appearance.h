#import <UIKit/UIKit.h>
UIColor *PBBackground(void);
UIColor *PBAccent(void);
UIFont *PBFont(CGFloat size, UIFontWeight weight);
UILabel *PBLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color);
UIStackView *PBCard(void);
UIStackView *PBPageContent(UIView *view, NSLayoutYAxisAnchor * _Nullable bottom);
UIButton *PBButton(NSString *title, NSString *symbol, BOOL primary);
UIButton *PBLinkButton(NSString *title, NSString *symbol);
UIView *PBFeature(NSString *symbol, NSString *title, NSString *detail);
void PBToast(UIViewController *controller, NSString *text);
void PBShowError(UIViewController *controller, NSString *message);
