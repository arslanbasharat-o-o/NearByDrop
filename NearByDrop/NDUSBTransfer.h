#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// All operations run on one serial queue; cancellation may come from the main thread.
@interface NDUSBTransfer : NSObject
@property(atomic) BOOL cancelRequested;
@property(copy, nullable) void (^progress)(double);
- (nullable NSArray<NSDictionary *> *)devices:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)openDevice:(NSString *)identifier error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)filesInStorage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error;
- (BOOL)upload:(NSURL *)url storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error;
- (nullable NSURL *)download:(uint32_t)item name:(NSString *)name directory:(NSURL *)directory error:(NSError **)error;
- (void)close;
@end
NS_ASSUME_NONNULL_END
