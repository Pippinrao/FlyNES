#ifndef FLYNES_APP_BRIDGE_H
#define FLYNES_APP_BRIDGE_H

#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns one immutable native snapshot; used only on the product serial worker.
@interface FlyNesProductCatalogSnapshot : NSObject
@property(nonatomic, readonly) uint64_t generation;
@property(nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, id> *> *rows;
- (nullable NSDictionary<NSString *, id> *)project:(NSDictionary<NSString *, id> *)query
                                           offset:(uint64_t)offset limit:(uint32_t)limit
                                            error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)itemForCanonicalID:(NSString *)canonicalID;
@end

FOUNDATION_EXPORT NSURL * _Nullable FlyNesLegacyAutosaveURL(NSURL *documentsRoot, NSString *canonicalID);

@interface FlyNesAppBridge : NSObject

+ (instancetype)sharedInstance;

- (BOOL)createWithDataRoot:(NSString *)dataRoot
                 cacheRoot:(NSString *)cacheRoot
                     error:(NSError * _Nullable * _Nullable)error;

- (NSDictionary<NSString *, id> *)settingsGet;
- (BOOL)applySettings:(NSDictionary<NSString *, id> *)settings
                error:(NSError * _Nullable * _Nullable)error;

- (NSString *)controlLayoutGet;
- (BOOL)controlLayoutApply:(NSString *)utf8
                     error:(NSError * _Nullable * _Nullable)error;

- (NSArray<NSDictionary<NSString *, id> *> *)catalogSnapshotGames;
- (nullable FlyNesProductCatalogSnapshot *)productCatalogSnapshot:(NSError * _Nullable * _Nullable)error;
// Nearby peers use manifest keys for bundled games; local saves keep content IDs.
- (nullable NSDictionary<NSString *, id> *)catalogGameForNearbyKey:(NSString *)key NS_SWIFT_NAME(catalogGame(forNearbyKey:));
- (NSString *)nearbyGameKeyForCanonicalID:(NSString *)canonicalID;
- (BOOL)scanFileRecords:(NSArray<NSDictionary<NSString *, id> *> *)records
             sourceUUID:(NSData *)sourceUUID
            sourceScope:(uint32_t)sourceScope
             incomplete:(BOOL)incomplete
                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setFavorite:(BOOL)favorite canonicalID:(NSString *)canonicalID
               error:(NSError * _Nullable * _Nullable)error;
- (BOOL)markPlayedCanonicalID:(NSString *)canonicalID error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeSourceUUID:(NSData *)sourceUUID scope:(uint32_t)scope
                  error:(NSError * _Nullable * _Nullable)error;
- (NSArray<NSDictionary<NSString *, id> *> *)gameCenterFilteredGamesForCategory:(NSString *)category
                                                                          query:(NSString *)query;

- (uint64_t)nearbyNextHostGeneration;
- (uint64_t)nearbyNextJoinAttemptID;
- (BOOL)nearbyHostPublishCode:(NSString *)code generation:(uint64_t)generation
               nowNanoseconds:(uint64_t)nowNanoseconds;
- (BOOL)nearbyHostRegenerateCode:(NSString *)code generation:(uint64_t)generation
                  nowNanoseconds:(uint64_t)nowNanoseconds;
- (BOOL)nearbyHostCancelGeneration:(uint64_t)generation;
- (BOOL)nearbySubmitCode:(NSString *)code attemptID:(uint64_t)attemptID
          nowNanoseconds:(uint64_t)nowNanoseconds;
- (BOOL)nearbyCancelAttempt:(uint64_t)attemptID;
- (void)nearbyTickNanoseconds:(uint64_t)nowNanoseconds;
- (NSDictionary<NSString *, NSNumber *> *)nearbyInviteSnapshot;

- (BOOL)scanBorrowedFd:(int)borrowedFd
          relativePath:(NSString *)relativePath
           displayName:(NSString *)displayName
            sourceUUID:(NSData *)sourceUUID
           sourceScope:(uint32_t)sourceScope
                 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
