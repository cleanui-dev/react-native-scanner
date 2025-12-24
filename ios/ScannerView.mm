#import "ScannerView.h"

#import <react/renderer/components/ScannerViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/ScannerViewSpec/EventEmitters.h>
#import <react/renderer/components/ScannerViewSpec/Props.h>
#import <react/renderer/components/ScannerViewSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

using namespace facebook::react;

@interface ScannerView () <RCTScannerViewViewProtocol>

@end

@implementation ScannerView {
    UIView * _view;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
    return concreteComponentDescriptorProvider<ScannerViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const ScannerViewProps>();
    _props = defaultProps;

    _view = [[UIView alloc] init];

    self.contentView = _view;
  }

  return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
    const auto &oldViewProps = *std::static_pointer_cast<ScannerViewProps const>(_props);
    const auto &newViewProps = *std::static_pointer_cast<ScannerViewProps const>(props);

    // Update background color when frameColor changes (hex string like "#RRGGBB" or "RRGGBB")
    if (oldViewProps.frameColor != newViewProps.frameColor) {
        NSString *colorToConvert = newViewProps.frameColor.empty()
            ? nil
            : [[NSString alloc] initWithUTF8String:newViewProps.frameColor.c_str()];
        UIColor *color = [self hexStringToColor:colorToConvert];
        if (color) {
            [_view setBackgroundColor:color];
        } else {
            // Optionally clear or keep previous color if invalid
            // [_view setBackgroundColor:UIColor.clearColor];
        }
    }

    [super updateProps:props oldProps:oldProps];
}

Class<RCTComponentViewProtocol> ScannerViewCls(void)
{
    return ScannerView.class;
}

- (UIColor *)hexStringToColor:(NSString *)stringToConvert
{
    if (stringToConvert == nil || stringToConvert.length == 0) {
        return nil;
    }

    NSString *noHashString = [stringToConvert stringByReplacingOccurrencesOfString:@"#" withString:@""];

    // Support shorthand like "FFF"
    if (noHashString.length == 3) {
        unichar chars[3];
        [noHashString getCharacters:chars range:NSMakeRange(0, 3)];
        noHashString = [NSString stringWithFormat:@"%C%C%C%C%C%C",
                        chars[0], chars[0], chars[1], chars[1], chars[2], chars[2]];
    }

    if (noHashString.length != 6) {
        return nil;
    }

    unsigned hex = 0;
    NSScanner *stringScanner = [NSScanner scannerWithString:noHashString];
    if (![stringScanner scanHexInt:&hex]) return nil;

    CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 8) & 0xFF) / 255.0;
    CGFloat b = (hex & 0xFF) / 255.0;

    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

@end
