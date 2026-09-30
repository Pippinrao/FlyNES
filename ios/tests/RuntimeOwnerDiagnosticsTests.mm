#import <XCTest/XCTest.h>
#import "FlyNesRuntimeBridge.h"

@interface FlyNesRuntimeBridge (OwnerDiagnosticsTest)
+ (NSUInteger)liveRuntimeCount;
@end

@interface RuntimeOwnerDiagnosticsTests : XCTestCase
@end
@implementation RuntimeOwnerDiagnosticsTests
- (void)testRuntimeCountTracksRealAllocationReplacementAndDestruction {
    XCTAssertTrue([FlyNesRuntimeBridge respondsToSelector:@selector(liveRuntimeCount)],
                  @"UI ownership checks must measure runtime allocations, not visible routes");
    if (![FlyNesRuntimeBridge respondsToSelector:@selector(liveRuntimeCount)]) return;
    NSUInteger initial = FlyNesRuntimeBridge.liveRuntimeCount;
    @autoreleasepool {
        FlyNesRuntimeBridge *first = [[FlyNesRuntimeBridge alloc] init];
        FlyNesRuntimeBridge *second = [[FlyNesRuntimeBridge alloc] init];
        XCTAssertTrue([first createRuntime:nil]);
        XCTAssertTrue([second createRuntime:nil]);
        XCTAssertEqual(FlyNesRuntimeBridge.liveRuntimeCount, initial + 2);
        XCTAssertTrue([first createRuntime:nil]);
        XCTAssertEqual(FlyNesRuntimeBridge.liveRuntimeCount, initial + 2);
        [second destroyRuntime]; [second destroyRuntime];
        XCTAssertEqual(FlyNesRuntimeBridge.liveRuntimeCount, initial + 1);
    }
    XCTAssertEqual(FlyNesRuntimeBridge.liveRuntimeCount, initial);
}
@end
