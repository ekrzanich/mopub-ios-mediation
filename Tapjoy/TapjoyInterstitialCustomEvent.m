
#import "TapjoyInterstitialCustomEvent.h"
#import <Tapjoy/TJPlacement.h>
#import <Tapjoy/Tapjoy.h>
#if __has_include("MoPub.h")
    #import "MPLogging.h"
    #import "MoPub.h"
#endif
#import "TapjoyAdvancedBiddingConstants.h"

@interface TapjoyInterstitialCustomEvent () <TJPlacementDelegate>
@property (nonatomic, strong) TJPlacement *placement;
@property (nonatomic, assign) BOOL isConnecting;
@property (nonatomic, copy) NSString *placementName;
@end

@implementation TapjoyInterstitialCustomEvent

- (void)setupListeners {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tjcConnectSuccess:)
                                                 name:TJC_CONNECT_SUCCESS
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tjcConnectFail:)
                                                 name:TJC_CONNECT_FAILED
                                               object:nil];
}

- (void)initializeWithCustomNetworkInfo:(NSDictionary *)info {
    // Grab sdkKey and connect flags defined in MoPub dashboard
    NSString *sdkKey = info[@"sdkKey"];
    BOOL enableDebug = [info[@"debugEnabled"] boolValue];

    if (sdkKey) {
        MPLogInfo(@"Connecting to Tapjoy via MoPub dashboard settings");
        NSMutableDictionary *connectOptions = [[NSMutableDictionary alloc] init];
        [connectOptions setObject:@(enableDebug) forKey:TJC_OPTION_ENABLE_LOGGING];
        [self setupListeners];
        
        [Tapjoy connect:sdkKey options:connectOptions];

        self.isConnecting = YES;
    }
    else {
        MPLogInfo(@"Tapjoy interstitial is initialized with empty 'sdkKey'. You must call Tapjoy connect before requesting content.");
        [self.delegate interstitialCustomEvent:self didFailToLoadAdWithError:nil];
    }
}

- (void)requestInterstitialWithCustomEventInfo:(NSDictionary *)info adMarkup:(NSString *)adMarkup {
    // Grab placement name defined in MoPub dashboard as custom event data
    self.placementName = info[@"name"];

    // Adapter is making connect call on behalf of publisher, wait for success before requesting content.
    if (self.isConnecting) {
        return;
    }
    
    // Attempt to establish a connection to Tapjoy
    if (![Tapjoy isConnected]) {
        [self initializeWithCustomNetworkInfo:info];
    }
    // Live connection to Tapjoy already exists; request the ad
    else {
        MPLogInfo(@"Requesting Tapjoy interstitial");
        [self requestPlacementContentWithAdMarkup:adMarkup];
    }
}

- (void)requestPlacementContentWithAdMarkup:(NSString *)adMarkup {
    if (self.placementName) {
        self.placement = [TJPlacement placementWithName:self.placementName mediationAgent:@"mopub" mediationId:nil delegate:self];
        self.placement.adapterVersion = MP_SDK_VERSION;
        
        // Advanced bidding response
        if (adMarkup != nil) {
            // Convert the JSON string into a dictionary.
            NSData * jsonData = [adMarkup dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary * adMarkupJson = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if (adMarkupJson != nil) {
                NSDictionary * auctionData = @{
                                               TJ_AUCTION_DATA: adMarkupJson[kTJBiddingAuctionData],
                                               TJ_AUCTION_ID: adMarkupJson[kTJBiddingAuctionId],
                                               TJ_AUCTION_TYPE: adMarkupJson[kTJBiddingAuctionType],
                                               TJ_AUCTION_CLEARING_PRICE: adMarkupJson[kTJBiddingAuctionClearingPrice]
                                               };
                
                [self.placement setAuctionData:auctionData];
            }
        }

        [self.placement requestContent];
    }
    else {
        MPLogInfo(@"Invalid Tapjoy placement name specified");
        [self.delegate interstitialCustomEvent:self didFailToLoadAdWithError:nil];
    }
}

- (void)showInterstitialFromRootViewController:(UIViewController *)rootViewController {
    MPLogInfo(@"Tapjoy interstitial will be shown");
    [self.placement showContentWithViewController:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _placement.delegate = nil;
}

#pragma mark - TJPlacementtDelegate

- (void)requestDidSucceed:(TJPlacement *)placement {
    if (placement.isContentAvailable) {
        MPLogInfo(@"Tapjoy interstitial request successful");
        [self.delegate interstitialCustomEvent:self didLoadAd:nil];
    }
    else {
        MPLogInfo(@"No Tapjoy interstitials available");
        [self.delegate interstitialCustomEvent:self didFailToLoadAdWithError:nil];
    }
}

- (void)requestDidFail:(TJPlacement *)placement error:(NSError *)error {
    MPLogInfo(@"Tapjoy interstitial request failed");
    [self.delegate interstitialCustomEvent:self didFailToLoadAdWithError:error];
}

- (void)contentDidAppear:(TJPlacement *)placement {
    MPLogInfo(@"Tapjoy interstitial did appear");
    [self.delegate interstitialCustomEventWillAppear:self];
    [self.delegate interstitialCustomEventDidAppear:self];
}

- (void)contentDidDisappear:(TJPlacement *)placement {
    MPLogInfo(@"Tapjoy interstitial did disappear");
    [self.delegate interstitialCustomEventWillDisappear:self];
    [self.delegate interstitialCustomEventDidDisappear:self];
}

- (void)tjcConnectSuccess:(NSNotification*)notifyObj {
    MPLogInfo(@"Tapjoy connect Succeeded");
    self.isConnecting = NO;
    [self fetchMoPubGDPRSettings];
    [self requestPlacementContentWithAdMarkup:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)tjcConnectFail:(NSNotification*)notifyObj {
    MPLogInfo(@"Tapjoy connect Failed");
    self.isConnecting = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Collect latest MoPub GDPR settings and pass them to Tapjoy
-(void)fetchMoPubGDPRSettings {
    // If the GDPR applies setting is unknown, assume it has been skipped/unset
    MPBool gdprApplies = [MoPub sharedInstance].isGDPRApplicable;
    if (gdprApplies != MPBoolUnknown ) {
        //Turn the MPBool into a proper bool
        if(gdprApplies == MPBoolYes) {
            [Tapjoy subjectToGDPR:YES];
            
            NSString *consentString = [[MoPub sharedInstance] canCollectPersonalInfo] ? @"1" : @"0";
            [Tapjoy setUserConsent: consentString];
        } else {
            [Tapjoy subjectToGDPR:NO];
            [Tapjoy setUserConsent:@"-1"];
        }
    }
}

@end
