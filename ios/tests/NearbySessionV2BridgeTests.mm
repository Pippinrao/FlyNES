#import <XCTest/XCTest.h>
#import "FlyNesNearbyBridge.h"
#import "FlyNesAppBridge.h"

@interface NearbySessionV2BridgeTests : XCTestCase
@end

@implementation NearbySessionV2BridgeTests

- (void)testRetiredDiscoveryBridgeIsAbsentWhileQrSessionReportsItsRealState
{
    FlyNesAppBridge *oldBridge = [[FlyNesAppBridge alloc] init];
    XCTAssertFalse([oldBridge respondsToSelector:NSSelectorFromString(@"nearbySessionSnapshotV2")]);
    FlyNesNearbyBridge *session = FlyNesNearbyBridge.sharedInstance;
    XCTAssertFalse([session respondsToSelector:NSSelectorFromString(@"configureLocalGameIfNeeded:")]);
    [session cancel];
    NSDictionary<NSString *, id> *snapshot = session.snapshot;
    XCTAssertEqual([snapshot[@"state"] intValue], 0);
}

@end
